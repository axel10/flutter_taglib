/// A high-performance, feature-rich Flutter plugin wrapping TagLib using Dart FFI and Native Assets.
library;

import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:logging/logging.dart';
import 'src/flutter_taglib_bindings.dart' as bindings;

final Logger _logger = Logger('flutter_taglib');

/// Embedded picture metadata in an audio file.
class Picture {
  const Picture({
    required this.bytes,
    required this.mimeType,
    this.pictureType = 'Front Cover',
    this.description,
  });

  final Uint8List bytes;
  final String mimeType;
  final String pictureType;
  final String? description;
}

/// High-level API for reading and writing music metadata using TagLib.
///
/// Under the hood, this uses Native Assets to compile and link TagLib natively.
///
/// Example:
/// ```dart
/// final file = TagLibFile.open('path/to/song.mp3');
/// if (file != null) {
///   print('Title: ${file.title}');
///   print('Artist: ${file.artist}');
///   print('Duration: ${file.duration}');
///
///   file.title = 'New Title';
///   file.save();
///   file.close();
/// }
/// ```
class TagLibFile {
  static const MethodChannel _channel = MethodChannel('flutter_taglib');

  /// Tracks the most recent failure message during opening, writing permission, or saving.
  static String? lastError;

  static bool? _isSupportedCached;
  static Object? _lastSupportProbeError;
  static StackTrace? _lastSupportProbeStackTrace;

  /// Resets the cached platform support check state.
  ///
  /// This causes the next call to [isSupported] to re-probe the native library.
  static void resetSupportCache() {
    _isSupportedCached = null;
    _lastSupportProbeError = null;
    _lastSupportProbeStackTrace = null;
  }

  /// Overrides the desktop binary download source used on Windows and Linux.
  ///
  /// Call this before [prepareDesktopLibrary], [openAsync], or [isSupported].
  static void configureDesktopBinarySource({String? baseUrl, String? version}) {
    bindings.configureDesktopBinarySource(baseUrl: baseUrl, version: version);
    resetSupportCache();
  }

  /// Downloads and loads the prebuilt desktop binary when running on Windows
  /// or Linux. Other platforms return immediately.
  static Future<void> prepareDesktopLibrary() async {
    await bindings.ensureDesktopLibraryReady();
    resetSupportCache();
  }

  /// Returns `true` if the native TagLib library is supported and successfully loaded.
  static bool get isSupported {
    if (_isSupportedCached != null) return _isSupportedCached!;
    try {
      // `taglib_bridge_close(nullptr)` is a no-op in the native bridge, so this
      // lets us verify symbol availability without depending on filesystem access.
      bindings.taglib_bridge_close(ffi.nullptr);
      _isSupportedCached = true;
      _lastSupportProbeError = null;
      _lastSupportProbeStackTrace = null;
    } catch (e, stackTrace) {
      _logger.warning('flutter_taglib support probe failed: $e');
      _lastSupportProbeError = e;
      _lastSupportProbeStackTrace = stackTrace;
      _isSupportedCached = false;
    }
    return _isSupportedCached!;
  }

  /// Collects runtime diagnostics to help debug platform support issues.
  static Future<Map<String, String>> collectDiagnostics() async {
    final diagnostics = <String, String>{
      'platform': Platform.operatingSystem,
      'platformVersion': Platform.operatingSystemVersion,
      'isSupportedCached': '$_isSupportedCached',
      'usesDownloadedDesktopBinary': '${bindings.usesDownloadedDesktopBinary}',
    };

    final supported = isSupported;
    diagnostics['isSupported'] = '$supported';

    if (_lastSupportProbeError != null) {
      diagnostics['supportProbeError'] = _lastSupportProbeError.toString();
    }
    if (_lastSupportProbeStackTrace != null) {
      final lines = _lastSupportProbeStackTrace
          .toString()
          .split('\n')
          .take(8)
          .join('\n');
      diagnostics['supportProbeStack'] = lines;
    }
    if (bindings.loadedDesktopBinaryPath != null) {
      diagnostics['desktopBinaryPath'] = bindings.loadedDesktopBinaryPath!;
    }
    if (bindings.desktopBinaryError != null) {
      diagnostics['desktopBinaryError'] = bindings.desktopBinaryError!;
    }

    try {
      final pluginInfo = await _channel.invokeMapMethod<String, dynamic>(
        'debugInfo',
      );
      if (pluginInfo != null) {
        diagnostics['pluginDebugInfo'] = pluginInfo.toString();
      } else {
        diagnostics['pluginDebugInfo'] = 'null';
      }
    } catch (e) {
      diagnostics['pluginDebugInfoError'] = e.toString();
    }

    return diagnostics;
  }

  /// Requests write permission for the given URI on Android.
  ///
  /// For Scoped Storage (Android 10+), modifying files from public directories
  /// may require user approval. This method first tries to reuse any existing
  /// writable access, including SAF tree permissions for files inside a picked
  /// directory, and only falls back to a system permission request when needed.
  /// It returns the URI that has write permission granted, or `null` if permission was denied.
  /// On other platforms, it immediately returns the original URI.
  static Future<String?> requestWritePermission(String uri) async {
    if (!Platform.isAndroid) return uri;
    if (!isSupported) {
      lastError = 'flutter_taglib is not supported or has been disabled on this platform.';
      throw UnsupportedError(
        'flutter_taglib is not supported or has been disabled on this platform.',
      );
    }
    try {
      final result = await _channel.invokeMethod<String>('requestWritePermission', {
        'uri': uri,
      });
      if (result == null) {
        lastError = 'requestWritePermission returned null (permission denied or directory not write-authorized) for $uri';
        debugPrint('[flutter_taglib] $lastError');
      }
      return result;
    } catch (e) {
      _logger.warning('requestWritePermission failed: $e');
      lastError = 'requestWritePermission failed: $e';
      debugPrint('[flutter_taglib] $lastError');
      return null;
    }
  }

  ffi.Pointer<bindings.TagLibBridgeFile> _handle;

  /// The filesystem path or content URI of the opened audio file.
  String path;
  bool _isClosed = false;

  TagLibFile._(this._handle, this.path);

  /// Opens an audio file by path.
  ///
  /// Returns `null` if the file could not be opened or is invalid.
  static TagLibFile? open(String path) {
    if (!isSupported) {
      throw UnsupportedError(
        'flutter_taglib is not supported or has been disabled on this platform.',
      );
    }
    final pathPtr = path.toNativeUtf8();
    try {
      final handle = bindings.taglib_bridge_open(pathPtr.cast<ffi.Char>());
      if (handle == ffi.nullptr) {
        _logger.severe(
          'Failed to open path "$path". Check native/platform logs for details.',
        );
        return null;
      }
      return TagLibFile._(handle, path);
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// Opens an audio file by path asynchronously.
  ///
  /// On Android, if [writeAccess] is `true`, this method will automatically request
  /// write permissions for Scoped Storage if needed before opening the file.
  static Future<TagLibFile?> openAsync(
    String path, {
    bool writeAccess = false,
  }) async {
    lastError = null;
    if (Platform.isWindows || Platform.isLinux) {
      await prepareDesktopLibrary();
    }
    if (!isSupported) {
      lastError = 'flutter_taglib is not supported or has been disabled on this platform.';
      throw UnsupportedError(
        'flutter_taglib is not supported or has been disabled on this platform.',
      );
    }
    String targetPath = path;
    if (writeAccess && Platform.isAndroid) {
      final grantedUri = await requestWritePermission(path);
      if (grantedUri == null) {
        _logger.warning('Write permission denied for $path');
        lastError ??= 'Write permission denied for $path';
        debugPrint('[flutter_taglib] $lastError');
        return null;
      }
      targetPath = grantedUri;
    }

    if (Platform.isAndroid && targetPath.startsWith('content://')) {
      final fd = await _openAndroidFileDescriptor(
        targetPath,
        mode: writeAccess ? 'rw' : 'r',
      );
      if (fd == null) {
        _logger.warning(
          'Failed to open Android file descriptor for $targetPath',
        );
        lastError ??= 'Failed to open Android file descriptor for $targetPath';
        debugPrint('[flutter_taglib] $lastError');
        return null;
      }
      return TagLibFile.openFd(fd, path: targetPath);
    }

    final pathPtr = targetPath.toNativeUtf8();
    try {
      final handle = bindings.taglib_bridge_open(pathPtr.cast<ffi.Char>());
      if (handle == ffi.nullptr) {
        _logger.severe(
          'Failed to open path "$targetPath". Check native/platform logs for details.',
        );
        lastError = 'Failed to open path via TagLib bridge for "$targetPath". File might be corrupted or not exist.';
        debugPrint('[flutter_taglib] $lastError');
        return null;
      }
      return TagLibFile._(handle, targetPath);
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// Opens an audio file by its Unix File Descriptor (FD).
  ///
  /// This is particularly useful on Android to bypass Scoped Storage limitations,
  /// allowing you to pass the file descriptor of a file opened via Storage Access Framework
  /// or MediaStore.
  ///
  /// Returns `null` if the file could not be opened.
  static TagLibFile? openFd(int fd, {String path = ''}) {
    if (!isSupported) {
      throw UnsupportedError(
        'flutter_taglib is not supported or has been disabled on this platform.',
      );
    }
    final handle = bindings.taglib_bridge_open_fd(fd);
    if (handle == ffi.nullptr) {
      _logger.severe(
        'Failed to open FD $fd. Check native/platform logs for details.',
      );
      return null;
    }
    return TagLibFile._(handle, path);
  }

  /// Requests Android write permission for this file, and if granted,
  /// reopens the file stream in read-write mode internally.
  ///
  /// This must be called **before** modifying metadata fields, as reopening the file
  /// will discard any unsaved in-memory changes.
  /// Returns `true` if write access is obtained, or `false` otherwise.
  Future<bool> requestWriteAccess() async {
    if (!Platform.isAndroid) return true;
    _checkClosed();

    final grantedUri = await TagLibFile.requestWritePermission(path);
    if (grantedUri == null) return false;

    TagLibFile? reopened;
    if (grantedUri.startsWith('content://')) {
      final fd = await _openAndroidFileDescriptor(grantedUri, mode: 'rw');
      if (fd == null) return false;
      reopened = TagLibFile.openFd(fd, path: path);
    } else {
      reopened = TagLibFile.open(grantedUri);
    }

    if (reopened == null) {
      return false;
    }

    bindings.taglib_bridge_close(_handle);
    _handle = reopened._handle;
    reopened._isClosed = true;
    return true;
  }

  /// Saves any changes made to the file metadata.
  ///
  /// Returns `true` on success, `false` on failure.
  bool save() {
    _checkClosed();
    final success = bindings.taglib_bridge_save(_handle) == 1;
    if (!success) {
      _logger.severe(
        'Failed to save metadata changes. Check native/platform logs for details.',
      );
      lastError = 'Failed to save metadata changes via native TagLib taglib_bridge_save.';
      debugPrint('[flutter_taglib] $lastError');
    }
    return success;
  }

  /// Closes the file and releases native resources.
  ///
  /// Any methods called on this object after [close] will throw a [StateError].
  void close() {
    if (!_isClosed) {
      bindings.taglib_bridge_close(_handle);
      _isClosed = true;
    }
  }

  void _checkClosed() {
    if (_isClosed) {
      throw StateError('TagLibFile is closed.');
    }
  }

  // --- Getters / Setters ---

  /// The song title.
  String get title {
    _checkClosed();
    final ptr = bindings.taglib_bridge_get_title(_handle);
    return ptr.cast<Utf8>().toDartString();
  }

  set title(String value) {
    _checkClosed();
    final ptr = value.toNativeUtf8();
    try {
      bindings.taglib_bridge_set_title(_handle, ptr.cast<ffi.Char>());
    } finally {
      malloc.free(ptr);
    }
  }

  /// The artist name.
  String get artist {
    _checkClosed();
    final ptr = bindings.taglib_bridge_get_artist(_handle);
    return ptr.cast<Utf8>().toDartString();
  }

  set artist(String value) {
    _checkClosed();
    final ptr = value.toNativeUtf8();
    try {
      bindings.taglib_bridge_set_artist(_handle, ptr.cast<ffi.Char>());
    } finally {
      malloc.free(ptr);
    }
  }

  /// The album name.
  String get album {
    _checkClosed();
    final ptr = bindings.taglib_bridge_get_album(_handle);
    return ptr.cast<Utf8>().toDartString();
  }

  set album(String value) {
    _checkClosed();
    final ptr = value.toNativeUtf8();
    try {
      bindings.taglib_bridge_set_album(_handle, ptr.cast<ffi.Char>());
    } finally {
      malloc.free(ptr);
    }
  }

  /// The genre name.
  String get genre {
    _checkClosed();
    final ptr = bindings.taglib_bridge_get_genre(_handle);
    return ptr.cast<Utf8>().toDartString();
  }

  set genre(String value) {
    _checkClosed();
    final ptr = value.toNativeUtf8();
    try {
      bindings.taglib_bridge_set_genre(_handle, ptr.cast<ffi.Char>());
    } finally {
      malloc.free(ptr);
    }
  }

  /// The comment.
  String get comment {
    _checkClosed();
    final ptr = bindings.taglib_bridge_get_comment(_handle);
    return ptr.cast<Utf8>().toDartString();
  }

  set comment(String value) {
    _checkClosed();
    final ptr = value.toNativeUtf8();
    try {
      bindings.taglib_bridge_set_comment(_handle, ptr.cast<ffi.Char>());
    } finally {
      malloc.free(ptr);
    }
  }

  /// The release year.
  int get year {
    _checkClosed();
    return bindings.taglib_bridge_get_year(_handle);
  }

  set year(int value) {
    _checkClosed();
    bindings.taglib_bridge_set_year(_handle, value);
  }

  /// The track number.
  int get track {
    _checkClosed();
    return bindings.taglib_bridge_get_track(_handle);
  }

  set track(int value) {
    _checkClosed();
    bindings.taglib_bridge_set_track(_handle, value);
  }

  // --- Audio Properties ---

  /// Duration of the audio file.
  Duration get duration {
    _checkClosed();
    final milliseconds = bindings.taglib_bridge_get_duration(_handle);
    return Duration(milliseconds: milliseconds);
  }

  /// Bitrate in kbps.
  int get bitrate {
    _checkClosed();
    return bindings.taglib_bridge_get_bitrate(_handle);
  }

  /// Sample rate in Hz.
  int get sampleRate {
    _checkClosed();
    return bindings.taglib_bridge_get_samplerate(_handle);
  }

  /// Number of channels.
  int get channels {
    _checkClosed();
    return bindings.taglib_bridge_get_channels(_handle);
  }

  /// Bitrate mode (e.g. 'CBR', 'VBR', or 'Unknown').
  String get bitrateMode {
    _checkClosed();
    final ptr = bindings.taglib_bridge_get_bitrate_mode(_handle);
    if (ptr == ffi.nullptr) return 'Unknown';
    return ptr.cast<Utf8>().toDartString();
  }

  /// Detailed audio properties of the file.
  AudioInfo get audioInfo {
    _checkClosed();
    return AudioInfo(
      duration: duration,
      bitrate: bitrate,
      bitrateMode: bitrateMode,
      sampleRate: sampleRate,
      channels: channels,
    );
  }

  // --- Album Art / Cover APIs ---

  /// Returns `true` if this file has cover art.
  bool get hasCover {
    _checkClosed();
    return bindings.taglib_bridge_has_cover(_handle) == 1;
  }

  /// Returns all embedded pictures in the file.
  ///
  /// The first picture is typically the front cover.
  List<Picture> get pictures {
    _checkClosed();
    final picturesHandle = bindings.taglib_bridge_pictures_get(_handle);
    if (picturesHandle == ffi.nullptr) return const <Picture>[];

    final result = <Picture>[];
    try {
      final count = bindings.taglib_bridge_pictures_size(picturesHandle);
      for (var index = 0; index < count; index++) {
        final dataSize = bindings.taglib_bridge_pictures_data_size(
          picturesHandle,
          index,
        );
        if (dataSize == 0) {
          continue;
        }

        final buffer = malloc<ffi.Uint8>(dataSize);
        try {
          final copied = bindings.taglib_bridge_pictures_data(
            picturesHandle,
            index,
            buffer,
            dataSize,
          );
          if (copied != 1) {
            continue;
          }

          final bytes = Uint8List.fromList(buffer.asTypedList(dataSize));
          final mimeType =
              _pointerToString(
                bindings.taglib_bridge_pictures_mime_type(
                  picturesHandle,
                  index,
                ),
              ) ??
              'image/jpeg';
          final pictureType =
              _pointerToString(
                bindings.taglib_bridge_pictures_picture_type(
                  picturesHandle,
                  index,
                ),
              ) ??
              'Front Cover';
          final description = _pointerToString(
            bindings.taglib_bridge_pictures_description(picturesHandle, index),
          );

          result.add(
            Picture(
              bytes: bytes,
              mimeType: mimeType,
              pictureType: pictureType,
              description: description,
            ),
          );
        } finally {
          malloc.free(buffer);
        }
      }
    } finally {
      bindings.taglib_bridge_pictures_free(picturesHandle);
    }

    return result;
  }

  /// Retrieves the cover art image bytes as a [Uint8List].
  ///
  /// Returns `null` if the file has no cover art.
  Uint8List? get coverData {
    _checkClosed();
    return pictures.isEmpty ? null : pictures.first.bytes;
  }

  /// Mime-type of the cover art (e.g. `image/jpeg` or `image/png`).
  ///
  /// Returns `null` if the file has no cover art.
  String? get coverMimeType {
    _checkClosed();
    if (pictures.isEmpty) return null;
    final mime = pictures.first.mimeType.trim();
    return mime.isEmpty ? null : mime;
  }

  /// Replaces all embedded pictures in the file.
  ///
  /// Pass an empty list to remove all pictures.
  bool setPictures(List<Picture> pictures) {
    _checkClosed();
    final picturesHandle = bindings.taglib_bridge_pictures_create();
    try {
      for (final picture in pictures) {
        if (picture.bytes.isEmpty) {
          continue;
        }

        final mimePtr = picture.mimeType.toNativeUtf8();
        final typePtr = picture.pictureType.toNativeUtf8();
        final descPtr = picture.description?.toNativeUtf8();
        final dataPtr = malloc<ffi.Uint8>(picture.bytes.length);
        try {
          final list = dataPtr.asTypedList(picture.bytes.length);
          list.setAll(0, picture.bytes);
          bindings.taglib_bridge_pictures_add(
            picturesHandle,
            dataPtr,
            picture.bytes.length,
            mimePtr.cast<ffi.Char>(),
            typePtr.cast<ffi.Char>(),
            descPtr == null ? ffi.nullptr : descPtr.cast<ffi.Char>(),
          );
        } finally {
          malloc.free(mimePtr);
          malloc.free(typePtr);
          if (descPtr != null) malloc.free(descPtr);
          malloc.free(dataPtr);
        }
      }

      return bindings.taglib_bridge_pictures_set(_handle, picturesHandle) == 1;
    } finally {
      bindings.taglib_bridge_pictures_free(picturesHandle);
    }
  }

  /// Sets or updates the cover art of the file.
  ///
  /// Pass `data: null` to remove the cover art.
  /// [mimeType] defaults to `image/jpeg`.
  ///
  /// Returns `true` on success, `false` on failure.
  bool setCover({required Uint8List? data, String mimeType = 'image/jpeg'}) {
    _checkClosed();
    if (data == null || data.isEmpty) {
      return setPictures(const <Picture>[]);
    }

    return setPictures([Picture(bytes: data, mimeType: mimeType)]);
  }

  /// (iOS only) Lets the user pick an audio file for editing.
  ///
  /// The returned object tracks the working copy and can commit changes back
  /// to the original file with [PickedAudioFile.commit].
  static Future<PickedAudioFile?> pickAudioFileForEditing() async {
    if (!Platform.isIOS) {
      throw UnsupportedError(
        'pickAudioFileForEditing is only supported on iOS.',
      );
    }

    final result = await _channel.invokeMapMethod<String, String>(
      'pickAudioFile',
    );
    if (result == null) return null;

    final path = result['path'];
    final originalPath = result['originalPath'];
    if (path == null ||
        path.isEmpty ||
        originalPath == null ||
        originalPath.isEmpty) {
      return null;
    }

    return PickedAudioFile._(
      path: path,
      originalPath: originalPath,
      name: result['name'],
    );
  }

  static String? _pointerToString(ffi.Pointer<ffi.Char> ptr) {
    if (ptr == ffi.nullptr) return null;
    final text = ptr.cast<Utf8>().toDartString().trim();
    return text.isEmpty ? null : text;
  }

  static Future<int?> _openAndroidFileDescriptor(
    String uri, {
    String mode = 'r',
  }) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<int>('openFileDescriptor', {
        'uri': uri,
        'mode': mode,
      });
    } catch (e) {
      _logger.warning('openFileDescriptor failed: $e');
      lastError = 'openFileDescriptor failed for $uri with mode $mode: $e';
      debugPrint('[flutter_taglib] $lastError');
      return null;
    }
  }

  /// (iOS only) Lets the user pick a directory and returns a handle that can
  /// be disposed to stop security-scoped access.
  ///
  /// The plugin already starts access for the selected directory before this
  /// method returns.
  static Future<AuthorizedDirectory?> pickAuthorizedDirectory() async {
    if (!Platform.isIOS) {
      throw UnsupportedError(
        'pickAuthorizedDirectory is only supported on iOS.',
      );
    }

    final result = await _channel.invokeMapMethod<String, String>(
      'pickAndAuthorizeDirectory',
    );
    final path = result?['path'];
    if (path == null || path.isEmpty) return null;

    return AuthorizedDirectory._(path);
  }

  /// (iOS only) Restores a previously authorized directory bookmark for [path]
  /// or one of its ancestor directories.
  static Future<AuthorizedDirectory?> restoreAuthorizedDirectory(
    String path,
  ) async {
    if (!Platform.isIOS) return null;

    final result = await _channel.invokeMapMethod<String, dynamic>(
      'restoreDirectoryAccess',
      {'path': path},
    );
    final authorizedPath = result?['path'] as String?;
    if (authorizedPath == null || authorizedPath.isEmpty) return null;

    return AuthorizedDirectory._(authorizedPath);
  }

  /// Retrieves a copy of all properties (metadata fields) as a map of keys to lists of values.
  /// Standard keys include 'TITLE', 'ARTIST', 'ALBUM', 'GENRE', 'ALBUMARTIST', 'COMPOSER', etc.
  Map<String, List<String>> get properties {
    _checkClosed();
    final propsHandle = bindings.taglib_bridge_properties_get(_handle);
    if (propsHandle == ffi.nullptr) return {};

    final result = <String, List<String>>{};
    try {
      final size = bindings.taglib_bridge_properties_size(propsHandle);
      for (var i = 0; i < size; i++) {
        final keyPtr = bindings.taglib_bridge_properties_key(propsHandle, i);
        if (keyPtr == ffi.nullptr) continue;
        final key = keyPtr.cast<Utf8>().toDartString();

        final valCount = bindings.taglib_bridge_properties_value_count(
          propsHandle,
          keyPtr,
        );
        final valList = <String>[];
        for (var j = 0; j < valCount; j++) {
          final valPtr = bindings.taglib_bridge_properties_value(
            propsHandle,
            keyPtr,
            j,
          );
          if (valPtr == ffi.nullptr) continue;
          valList.add(valPtr.cast<Utf8>().toDartString());
        }
        result[key] = valList;
      }
    } finally {
      bindings.taglib_bridge_properties_free(propsHandle);
    }
    return result;
  }

  /// Sets/updates properties of the file in memory.
  /// Call [save] afterwards to commit these changes to disk.
  ///
  /// Returns a map of properties that were not supported by the file format and could not be set.
  Map<String, List<String>> setProperties(
    Map<String, List<String>> propertiesMap,
  ) {
    _checkClosed();

    final propsHandle = bindings.taglib_bridge_properties_create();
    try {
      propertiesMap.forEach((key, values) {
        final keyPtr = key.toNativeUtf8();
        try {
          for (final val in values) {
            final valPtr = val.toNativeUtf8();
            try {
              bindings.taglib_bridge_properties_add(
                propsHandle,
                keyPtr.cast<ffi.Char>(),
                valPtr.cast<ffi.Char>(),
              );
            } finally {
              malloc.free(valPtr);
            }
          }
        } finally {
          malloc.free(keyPtr);
        }
      });

      final unsupportedHandle = bindings.taglib_bridge_properties_set(
        _handle,
        propsHandle,
      );
      if (unsupportedHandle == ffi.nullptr) return {};

      final unsupportedResult = <String, List<String>>{};
      try {
        final size = bindings.taglib_bridge_properties_size(unsupportedHandle);
        for (var i = 0; i < size; i++) {
          final keyPtr = bindings.taglib_bridge_properties_key(
            unsupportedHandle,
            i,
          );
          if (keyPtr == ffi.nullptr) continue;
          final key = keyPtr.cast<Utf8>().toDartString();

          final valCount = bindings.taglib_bridge_properties_value_count(
            unsupportedHandle,
            keyPtr,
          );
          final valList = <String>[];
          for (var j = 0; j < valCount; j++) {
            final valPtr = bindings.taglib_bridge_properties_value(
              unsupportedHandle,
              keyPtr,
              j,
            );
            if (valPtr == ffi.nullptr) continue;
            valList.add(valPtr.cast<Utf8>().toDartString());
          }
          unsupportedResult[key] = valList;
        }
      } finally {
        bindings.taglib_bridge_properties_free(unsupportedHandle);
      }
      return unsupportedResult;
    } finally {
      bindings.taglib_bridge_properties_free(propsHandle);
    }
  }
}

/// Represents a picked audio file on iOS.
///
/// On iOS, the plugin gives you a writable working copy path together with the
/// original file path. Call [commit] after saving metadata to copy the working
/// copy back to the original file.
class PickedAudioFile {
  /// The local file path of the temporary writable copy.
  final String path;

  /// The original picked file path or resource URI.
  final String originalPath;

  /// The original filename or display name, if available.
  final String? name;

  PickedAudioFile._({
    required this.path,
    required this.originalPath,
    required this.name,
  });

  /// Returns `true` when the working copy differs from the original file path.
  bool get needsCommit => path != originalPath;

  /// Commits the working copy back to the original picked file.
  Future<void> commit() {
    return TagLibFile._channel.invokeMethod<void>('commitPickedFile', {
      'workingPath': path,
      'originalPath': originalPath,
    });
  }
}

/// Represents a security-scoped directory access handle on iOS.
///
/// Dispose this object when the directory is no longer needed to stop
/// security-scoped access.
class AuthorizedDirectory {
  /// The path of the authorized security-scoped directory.
  final String path;
  bool _isDisposed = false;

  AuthorizedDirectory._(this.path);

  /// Stops accessing the authorized directory.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await TagLibFile._channel.invokeMethod<void>('stopAccessingDirectory', {
      'path': path,
    });
  }
}

/// Represents detailed audio properties of a file.
class AudioInfo {
  /// The duration of the audio.
  final Duration duration;

  /// The bitrate in kbps.
  final int bitrate;

  /// The bitrate mode (e.g., 'CBR', 'VBR', or 'Unknown').
  final String bitrateMode;

  /// The sample rate in Hz.
  final int sampleRate;

  /// The number of channels.
  final int channels;

  /// Creates an [AudioInfo] instance representing detailed audio properties.
  AudioInfo({
    required this.duration,
    required this.bitrate,
    required this.bitrateMode,
    required this.sampleRate,
    required this.channels,
  });

  @override
  String toString() =>
      'AudioInfo(duration: $duration, bitrate: $bitrate kbps, bitrateMode: $bitrateMode, sampleRate: $sampleRate Hz, channels: $channels)';
}

/// Dummy class used by Flutter platform registration for Dart-only FFI platforms
/// (macOS, Windows, Linux) to prevent CocoaPods/CMake errors while ensuring
/// pub.dev correctly lists them as supported.
class FlutterTaglib {
  /// Registers this plugin with the platform-specific build system.
  static void registerWith() {}
}

/// Commonly used standard property key constants in the TagLib properties dictionary.
/// Used with [TagLibFile.properties] and [TagLibFile.setProperties].
///
/// Although using these predefined constants is recommended for IDE autocomplete support,
/// you can still use any custom string as a property key.
abstract final class TagProperties {
  /// The song title (TITLE).
  static const String title = 'TITLE';

  /// The main artist/performer (ARTIST).
  static const String artist = 'ARTIST';

  /// The album name (ALBUM).
  static const String album = 'ALBUM';

  /// The track number (TRACKNUMBER).
  static const String trackNumber = 'TRACKNUMBER';

  /// The total number of tracks on the album (TRACKTOTAL).
  static const String trackTotal = 'TRACKTOTAL';

  /// The release year (YEAR).
  static const String year = 'YEAR';

  /// The release date, typically in YYYY-MM-DD format (DATE).
  static const String date = 'DATE';

  /// The genre (GENRE).
  static const String genre = 'GENRE';

  /// Comments or notes (COMMENT).
  static const String comment = 'COMMENT';

  /// The album artist, often used for compilations (ALBUMARTIST).
  static const String albumArtist = 'ALBUMARTIST';

  /// The composer (COMPOSER).
  static const String composer = 'COMPOSER';

  /// The disc/CD number (DISCNUMBER).
  static const String discNumber = 'DISCNUMBER';

  /// The total number of discs (DISCTOTAL).
  static const String discTotal = 'DISCTOTAL';

  /// Embedded lyrics, typically unsynchronized (LYRICS).
  static const String lyrics = 'LYRICS';

  /// Beats per minute (BPM).
  static const String bpm = 'BPM';

  /// The software or tool used for encoding (ENCODER).
  static const String encoder = 'ENCODER';

  /// The record label or publisher (LABEL).
  static const String label = 'LABEL';

  /// The conductor (CONDUCTOR).
  static const String conductor = 'CONDUCTOR';

  /// The arranger (ARRANGER).
  static const String arranger = 'ARRANGER';

  /// The performer (PERFORMER).
  static const String performer = 'PERFORMER';

  /// The remixer (REMIXER).
  static const String remixer = 'REMIXER';

  /// International Standard Recording Code (ISRC).
  static const String isrc = 'ISRC';

  /// The barcode (BARCODE).
  static const String barcode = 'BARCODE';

  /// The copyright notice (COPYRIGHT).
  static const String copyright = 'COPYRIGHT';

  /// The related URL (URL).
  static const String url = 'URL';
}
