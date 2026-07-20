## Unreleased
* Improve `TagLibFile.coverData` performance.
* Added `TagLibFile.format` (and `AudioInfo.format`), reporting the audio format detected from the file contents (`MP3`, `FLAC`, `OPUS`, `AAC`, `ALAC`, `AIFF`, ...), or `null` when it cannot be determined.

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
