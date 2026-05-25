import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'flutter_taglib_bindings_generated.dart' as bindings;

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
  final ffi.Pointer<bindings.TagLibBridgeFile> _handle;
  bool _isClosed = false;

  TagLibFile._(this._handle);

  /// Opens an audio file by path.
  ///
  /// Returns `null` if the file could not be opened or is invalid.
  static TagLibFile? open(String path) {
    final pathPtr = path.toNativeUtf8();
    try {
      final handle = bindings.taglib_bridge_open(pathPtr.cast<ffi.Char>());
      if (handle == ffi.nullptr) return null;
      return TagLibFile._(handle);
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
  static TagLibFile? openFd(int fd) {
    final handle = bindings.taglib_bridge_open_fd(fd);
    if (handle == ffi.nullptr) return null;
    return TagLibFile._(handle);
  }

  /// Saves any changes made to the file metadata.
  ///
  /// Returns `true` on success, `false` on failure.
  bool save() {
    _checkClosed();
    return bindings.taglib_bridge_save(_handle) == 1;
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
      final success = bindings.taglib_bridge_get_cover_data(_handle, buffer, size);
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
      ) == 1;
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
      ) == 1;
    } finally {
      malloc.free(mimePtr);
      malloc.free(dataPtr);
    }
  }
}
