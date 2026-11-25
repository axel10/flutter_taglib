## 1.7.0
* Added audio bit depth extraction (`bitDepth` on `TagLibFile`, `AudioInfo`, and `BatchTagMetadata`) for lossless formats including FLAC, WAV, AIFF, APE, WavPack, ALAC, TrueAudio, DSF, and DSDIFF.
* Added normalized song rating support (`rating` on `TagLibFile` and `BatchTagMetadata`, plus `TagProperties.rating`).
* Added embedded lyrics extraction (`lyrics` on `BatchTagMetadata`, reading `LYRICS` / `UNSYNCEDLYRICS`), supporting remote HTTP Range streams without full file downloads.
* Added HTTP stream read-error tracking (`hadReadError` on `TagLibFile` and `readError` on `BatchTagMetadata`) to distinguish empty tags from truncated/failed reads.
* Improved HTTP Range streaming performance by coalescing large reads (>=128KB) into single range requests with a 1-time retry on transient failures.
* Fixed iOS Security-Scoped bookmark persistence using `.minimalBookmark` and cleaned up temporary working copies after `commitTagChanges` succeeds.
* Updated prebuilt native binary versions.

## 1.6.0
* Added remote HTTP/HTTPS stream tag reading support with `TagLib.openUrl` and `TagLib.openUrlAsync`.
* Implemented cross-platform native HTTP streaming with HTTP Range support (Apple URLSession, Android HttpURLConnection, Windows WinHttp, Linux libcurl) to read tags without full file downloads.
* Added 16KB page size alignment for Android dynamic libraries (Android 15+ compatibility).
* Isolated prebuilt binary download cache directories by ABI/arch to prevent collisions during multi-ABI (`--split-per-abi`) builds.
* Implemented atomic downloads with non-empty validation for native prebuilt assets.
* Improved `isSupported` probe logic to prevent permanently caching `false` before native library initialization.
* Fixed Linux native build header paths and cURL symbol collision.

## 1.5.2
* readBatchAsync enables image extraction option

## 1.5.1
* fix(android): remove dangerous JNI FindClass call in C++ taglib_bridge_open

## 1.5.0
* Supports TagLib AudioPropertiesStyle settings
* Added batch read functionality and multi-isolate support
* Metadata read performance optimization
* Support physical path SAF URI resolution and FD fallback
* Added performance benchmark test to the example

## 1.4.2
* Added `TagLibFile.format` to detect audio file formats (e.g. MP3, FLAC).
* Added `TagLibFile.isLossless` to check if an audio file is lossless.
* Improved `TagLibFile.coverData` for extracting cover art bytes.
* Updated prebuilt native binary download URLs.

## 1.4.1
* Eliminate analyze info prompt

## 1.4.0
* Song duration accurate to milliseconds.
* Deprecated unsupported interfaces.
* Android uses online pre-built artifacts

## 1.3.3
* Lower the Dart SDK requirements to 3.11.0

## 1.3.2
* Remove redundant logs
* Fixes the issue of Windows and Linux dynamic libraries not being downloaded during the build process.

## 1.3.1
* Update readme

## 1.3.0
* Using pre-built artifacts for taglibs in Windows, Linux, and Android
* Fixing Android permission issues

## 1.2.0
* Supports Android content://media format links

## 1.1.1
* Update document

## 1.1.0
* Support PropertyMap

## 1.0.3
* Support SPM

## 1.0.2
* Upgrade dependencies

## 1.0.1
* Adapted to pub.dev

## 1.0.0

* Initial release of flutter_taglib.
