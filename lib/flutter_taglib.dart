import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:logging/logging.dart';
import 'flutter_taglib_bindings_generated.dart' as bindings;

final Logger _logger = Logger('flutter_taglib');

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

  static bool? _isSupportedCached;
  static Object? _lastSupportProbeError;
  static StackTrace? _lastSupportProbeStackTrace;

  static void resetSupportCache() {
    _isSupportedCached = null;
    _lastSupportProbeError = null;
    _lastSupportProbeStackTrace = null;
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
  /// requires user approval. This method triggers the Android system permission request dialog
  /// and returns the URI that has write permission granted, or `null` if permission was denied.
  /// On other platforms, it immediately returns the original URI.
  static Future<String?> requestWritePermission(String uri) async {
    if (!Platform.isAndroid) return uri;
    if (!isSupported) {
      throw UnsupportedError(
        'flutter_taglib is not supported or has been disabled on this platform.',
      );
    }
    try {
      return await _channel.invokeMethod<String>('requestWritePermission', {
        'uri': uri,
      });
    } catch (e) {
      _logger.warning('requestWritePermission failed: $e');
      return null;
    }
  }

  ffi.Pointer<bindings.TagLibBridgeFile> _handle;
  final String path;
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
    if (!isSupported) {
      throw UnsupportedError(
        'flutter_taglib is not supported or has been disabled on this platform.',
      );
    }
    String targetPath = path;
    if (writeAccess && Platform.isAndroid) {
      final grantedUri = await requestWritePermission(path);
      if (grantedUri == null) {
        _logger.warning('Write permission denied for $path');
        return null;
      }
      targetPath = grantedUri;
    }

    final pathPtr = targetPath.toNativeUtf8();
    try {
      final handle = bindings.taglib_bridge_open(pathPtr.cast<ffi.Char>());
      if (handle == ffi.nullptr) {
        _logger.severe(
          'Failed to open path "$targetPath". Check native/platform logs for details.',
        );
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

    // Close current native handle
    bindings.taglib_bridge_close(_handle);

    // Open new native handle in read-write mode
    final pathPtr = grantedUri.toNativeUtf8();
    try {
      final newHandle = bindings.taglib_bridge_open(pathPtr.cast<ffi.Char>());
      if (newHandle == ffi.nullptr) {
        _logger.severe('Failed to reopen path "$grantedUri" in write mode.');
        return false;
      }
      _handle = newHandle;
      return true;
    } finally {
      malloc.free(pathPtr);
    }
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
    final seconds = bindings.taglib_bridge_get_duration(_handle);
    return Duration(seconds: seconds);
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

  /// Retrieves the cover art image bytes as a [Uint8List].
  ///
  /// Returns `null` if the file has no cover art.
  Uint8List? get coverData {
    _checkClosed();
    final size = bindings.taglib_bridge_get_cover_data_size(_handle);
    if (size == 0) return null;

    final buffer = malloc<ffi.Uint8>(size);
    try {
      final success = bindings.taglib_bridge_get_cover_data(
        _handle,
        buffer,
        size,
      );
      if (success == 1) {
        final list = buffer.asTypedList(size);
        return Uint8List.fromList(list);
      }
      return null;
    } finally {
      malloc.free(buffer);
    }
  }

  /// Mime-type of the cover art (e.g. `image/jpeg` or `image/png`).
  ///
  /// Returns `null` if the file has no cover art.
  String? get coverMimeType {
    _checkClosed();
    if (!hasCover) return null;
    final ptr = bindings.taglib_bridge_get_cover_mime_type(_handle);
    if (ptr == ffi.nullptr) return null;
    final str = ptr.cast<Utf8>().toDartString();
    return str.isEmpty ? null : str;
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
      return bindings.taglib_bridge_set_cover(
            _handle,
            ffi.nullptr,
            ffi.nullptr,
            0,
          ) ==
          1;
    }

    final mimePtr = mimeType.toNativeUtf8();
    final dataPtr = malloc<ffi.Uint8>(data.length);
    try {
      final list = dataPtr.asTypedList(data.length);
      list.setAll(0, data);
      return bindings.taglib_bridge_set_cover(
            _handle,
            mimePtr.cast<ffi.Char>(),
            dataPtr,
            data.length,
          ) ==
          1;
    } finally {
      malloc.free(mimePtr);
      malloc.free(dataPtr);
    }
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
}

/// Represents a picked audio file on iOS.
///
/// On iOS, the plugin gives you a writable working copy path together with the
/// original file path. Call [commit] after saving metadata to copy the working
/// copy back to the original file.
class PickedAudioFile {
  final String path;
  final String originalPath;
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
