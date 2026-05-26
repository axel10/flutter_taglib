import Flutter
import UIKit
import UniformTypeIdentifiers

public class FlutterTaglibPlugin: NSObject, FlutterPlugin, UIDocumentPickerDelegate {
  private static let bookmarkStoreKey = "flutter_taglib.directoryBookmarks"

  private enum PendingPickerAction {
    case directory
    case audioFile
  }

  private var channel: FlutterMethodChannel?
  private var pendingResult: FlutterResult?
  private var pendingPickerAction: PendingPickerAction?
  private var activeUrls = [String: URL]()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_taglib", binaryMessenger: registrar.messenger())
    let instance = FlutterTaglibPlugin()
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pickAudioFile":
      self.pendingResult = result
      self.pendingPickerAction = .audioFile
      let picker = UIDocumentPickerViewController(
        forOpeningContentTypes: [.audio],
        asCopy: false
      )
      picker.delegate = self
      picker.allowsMultipleSelection = false
      if let rootVC = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController {
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
          topVC = presented
        }
        topVC.present(picker, animated: true)
      } else {
        result(FlutterError(code: "NO_VIEW_CONTROLLER", message: "Failed to find key window root view controller", details: nil))
        self.pendingResult = nil
        self.pendingPickerAction = nil
      }

    case "pickAndAuthorizeDirectory":
      self.pendingResult = result
      self.pendingPickerAction = .directory
      let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
      picker.delegate = self
      picker.allowsMultipleSelection = false
      if let rootVC = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController {
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
          topVC = presented
        }
        topVC.present(picker, animated: true)
      } else {
        result(FlutterError(code: "NO_VIEW_CONTROLLER", message: "Failed to find key window root view controller", details: nil))
        self.pendingResult = nil
        self.pendingPickerAction = nil
      }

    case "startAccessingDirectory":
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing path argument", details: nil))
        return
      }

      if let activePath = activeAuthorizedPath(for: path) {
        result(["path": activePath])
      } else if let restoredPath = restoreDirectoryAccess(for: path) {
        result(["path": restoredPath])
      } else {
        result(FlutterError(code: "ACCESS_DENIED", message: "Directory has not been authorized", details: nil))
      }

    case "restoreDirectoryAccess":
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing path argument", details: nil))
        return
      }

      if let activePath = activeAuthorizedPath(for: path) {
        result(["path": activePath])
      } else if let restoredPath = restoreDirectoryAccess(for: path) {
        result(["path": restoredPath])
      } else {
        result(nil)
      }

    case "stopAccessingDirectory":
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing path argument", details: nil))
        return
      }
      
      if let url = activeUrls.removeValue(forKey: path) {
        url.stopAccessingSecurityScopedResource()
      }
      result(nil)

    case "commitPickedFile":
      guard let args = call.arguments as? [String: Any],
            let workingPath = args["workingPath"] as? String,
            let originalPath = args["originalPath"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing workingPath or originalPath", details: nil))
        return
      }

      guard let originalURL = activeUrls[originalPath] else {
        result(FlutterError(code: "ACCESS_DENIED", message: "Original file is not authorized in this session", details: nil))
        return
      }

      let workingURL = URL(fileURLWithPath: workingPath)
      guard FileManager.default.fileExists(atPath: workingURL.path) else {
        result(FlutterError(code: "MISSING_WORKING_FILE", message: "Working file does not exist", details: nil))
        return
      }

      let coordinator = NSFileCoordinator()
      var coordinationError: NSError?
      var commitError: Error?

      coordinator.coordinate(writingItemAt: originalURL, options: [], error: &coordinationError) { coordinatedURL in
        do {
          let data = try Data(contentsOf: workingURL)
          try data.write(to: coordinatedURL)
        } catch {
          commitError = error
        }
      }

      if let coordinationError {
        result(FlutterError(code: "COORDINATION_FAILED", message: coordinationError.localizedDescription, details: nil))
      } else if let commitError {
        result(FlutterError(code: "COMMIT_FAILED", message: commitError.localizedDescription, details: nil))
      } else {
        result(nil)
      }

    case "debugInfo":
      result([
        "plugin": "FlutterTaglibPlugin",
        "activeUrlsCount": activeUrls.count,
        "activePaths": Array(activeUrls.keys).sorted(),
        "bundlePath": Bundle.main.bundlePath,
      ])

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - UIDocumentPickerDelegate
  public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else {
      pendingResult?(nil)
      pendingResult = nil
      pendingPickerAction = nil
      return
    }

    let success = url.startAccessingSecurityScopedResource()
    guard success else {
      pendingResult?(FlutterError(code: "ACCESS_DENIED", message: "Failed to access security-scoped resource", details: nil))
      pendingResult = nil
      pendingPickerAction = nil
      return
    }

    switch pendingPickerAction {
    case .audioFile:
      let workingURL = makeWorkingCopy(for: url) ?? url
      if let existing = activeUrls.removeValue(forKey: url.path) {
        existing.stopAccessingSecurityScopedResource()
      }
      activeUrls[url.path] = url
      pendingResult?([
        "path": workingURL.path,
        "originalPath": url.path,
        "name": url.lastPathComponent,
      ])
    case .directory:
      if let existing = activeUrls.removeValue(forKey: url.path) {
        existing.stopAccessingSecurityScopedResource()
      }
      activeUrls[url.path] = url
      persistBookmark(for: url)
      pendingResult?([
        "path": url.path
      ])
    case .none:
      url.stopAccessingSecurityScopedResource()
      pendingResult?(FlutterError(code: "NO_PENDING_PICKER", message: "No pending picker action found", details: nil))
    }
    pendingResult = nil
    pendingPickerAction = nil
  }

  public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pendingResult?(nil)
    pendingResult = nil
    pendingPickerAction = nil
  }

  private func makeWorkingCopy(for sourceURL: URL) -> URL? {
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("flutter_taglib_working", isDirectory: true)

    do {
      try FileManager.default.createDirectory(
        at: tempDirectory,
        withIntermediateDirectories: true
      )

      let sanitizedName = sourceURL.lastPathComponent.isEmpty
        ? "audio_file"
        : sourceURL.lastPathComponent
      let destinationURL = tempDirectory.appendingPathComponent(
        "\(UUID().uuidString)_\(sanitizedName)"
      )

      try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
      return destinationURL
    } catch {
      return nil
    }
  }

  private func activeAuthorizedPath(for requestedPath: String) -> String? {
    for path in activeUrls.keys.sorted(by: { $0.count > $1.count }) {
      if path == requestedPath || requestedPath.hasPrefix(path + "/") {
        return path
      }
    }
    return nil
  }

  private func persistBookmark(for url: URL) {
    do {
      let bookmarkData = try url.bookmarkData(
        options: [],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      var bookmarks = loadPersistedBookmarks()
      bookmarks[url.path] = bookmarkData.base64EncodedString()
      savePersistedBookmarks(bookmarks)
    } catch {
      // Ignore bookmark persistence failures and keep session access alive.
    }
  }

  private func loadPersistedBookmarks() -> [String: String] {
    UserDefaults.standard.dictionary(forKey: Self.bookmarkStoreKey) as? [String: String] ?? [:]
  }

  private func savePersistedBookmarks(_ bookmarks: [String: String]) {
    UserDefaults.standard.set(bookmarks, forKey: Self.bookmarkStoreKey)
  }

  private func restoreDirectoryAccess(for requestedPath: String) -> String? {
    let bookmarks = loadPersistedBookmarks()
    let candidatePaths = bookmarks.keys
      .filter { $0 == requestedPath || requestedPath.hasPrefix($0 + "/") }
      .sorted { $0.count > $1.count }

    for candidatePath in candidatePaths {
      guard let encoded = bookmarks[candidatePath],
            let data = Data(base64Encoded: encoded) else {
        continue
      }

      var isStale = false
      do {
        let url = try URL(
          resolvingBookmarkData: data,
          options: [.withoutUI],
          relativeTo: nil,
          bookmarkDataIsStale: &isStale
        )

        guard url.startAccessingSecurityScopedResource() else {
          continue
        }

        if let existing = activeUrls.removeValue(forKey: url.path) {
          existing.stopAccessingSecurityScopedResource()
        }
        activeUrls[url.path] = url

        if isStale {
          persistBookmark(for: url)
        }

        return url.path
      } catch {
        continue
      }
    }

    return nil
  }
}
