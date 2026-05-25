# flutter_taglib

[![pub package](https://img.shields.io/pub/v/flutter_taglib.svg)](https://pub.dev/packages/flutter_taglib)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

A high-performance, feature-rich Flutter plugin wrapping **TagLib** using Dart FFI and Native Assets. It allows you to read and write audio metadata (including album cover art) and extract technical audio properties across various platforms.

> [!NOTE]
> This package uses Flutter's modern **Native Assets** feature. The native TagLib C++ code is compiled directly during your application build process, ensuring seamless compilation and optimization without requiring precompiled binaries.

---

## Features

- **Wide Format Support**: Read and write tags for `MP3`, `FLAC`, `M4A` (AAC/ALAC), `WAV`, `OGG` (Vorbis), and other formats supported by TagLib.
- **Full Tag Editing**: Read and modify standard tag fields: Title, Artist, Album, Genre, Year, Track Number, and Comment.
- **Album Art (Cover) Management**:
  - Check if a file contains cover art (`hasCover`).
  - Retrieve cover art bytes (`coverData`) and its MIME type (`coverMimeType`).
  - Set or update cover art, or remove it entirely.
- **Audio Technical Properties**: Extract read-only properties:
  - Duration (as Dart `Duration`)
  - Bitrate (kbps)
  - Sample Rate (Hz)
  - Channels (Mono, Stereo, etc.)
- **Scoped Storage & SAF Support (Android)**:
  - Open files using Unix File Descriptors (`openFd`) to bypass Scoped Storage restrictions.
  - Automatically request write permissions using `openAsync` or `requestWriteAccess()`.
- **Selectable Platform Support**: Avoid compilation conflicts by selectively enabling or disabling platform builds using a simple YAML configuration file.

---

## Installation

Add `flutter_taglib` to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_taglib:
    path: /path/to/flutter_taglib # Use path dependency or pub version when published
```

---

## Usage Guide

### 1. Basic Reading

Open an audio file and retrieve its metadata and technical properties:

```dart
import 'package:flutter_taglib/flutter_taglib.dart';

void readMetadata(String filePath) {
  // Check if the native library is loaded and supported on this platform
  if (!TagLibFile.isSupported) {
    print('TagLib is not supported on this platform.');
    return;
  }

  // Open the file
  final file = TagLibFile.open(filePath);
  if (file == null) {
    print('Failed to open file: $filePath');
    return;
  }

  try {
    // Read tag fields
    print('Title:       ${file.title}');
    print('Artist:      ${file.artist}');
    print('Album:       ${file.album}');
    print('Genre:       ${file.genre}');
    print('Year:        ${file.year}');
    print('Track:       ${file.track}');
    print('Comment:     ${file.comment}');

    // Read audio properties
    print('Duration:    ${file.duration}');
    print('Bitrate:     ${file.bitrate} kbps');
    print('Sample Rate: ${file.sampleRate} Hz');
    print('Channels:    ${file.channels}');
  } finally {
    // Always close the file to release native resources!
    file.close();
  }
}
```

### 2. Modifying Metadata

To update metadata, modify the fields and call `save()`.

> [!IMPORTANT]
> On Android, modifying files in Scoped Storage may require write permission. You must request write access before making changes.

```dart
import 'package:flutter_taglib/flutter_taglib.dart';

Future<void> updateMetadata(String filePath) async {
  // Use openAsync with writeAccess: true to automatically request permissions on Android
  final file = await TagLibFile.openAsync(filePath, writeAccess: true);
  if (file == null) {
    print('Failed to open file or permission denied.');
    return;
  }

  try {
    // Edit tag fields
    file.title = 'My New Song Title';
    file.artist = 'Famous Artist';
    file.album = 'New Album';
    file.year = 2026;
    file.track = 3;

    // Save changes back to the file
    final success = file.save();
    if (success) {
      print('Metadata saved successfully!');
    } else {
      print('Failed to save metadata.');
    }
  } finally {
    file.close();
  }
}
```

### 3. Cover Art (Album Art)

Extract, update, or remove cover art:

```dart
import 'dart:typed_data';
import 'package:flutter_taglib/flutter_taglib.dart';

void handleCoverArt(TagLibFile file, Uint8List? newCoverBytes) {
  // 1. Read Cover Art
  if (file.hasCover) {
    final Uint8List? coverBytes = file.coverData;
    final String? mimeType = file.coverMimeType;
    print('Cover found! MIME type: $mimeType, Size: ${coverBytes?.length} bytes');
  } else {
    print('No cover art found.');
  }

  // 2. Set or Update Cover Art
  if (newCoverBytes != null) {
    file.setCover(data: newCoverBytes, mimeType: 'image/jpeg');
    file.save();
  }

  // 3. Remove Cover Art
  file.setCover(data: null); // Pass null to delete the cover art
  file.save();
}
```

### 4. Android Scoped Storage & File Descriptors

Android 10+ enforces Scoped Storage. Directly opening a filepath (like `/storage/emulated/0/...`) in C++ write mode will fail unless permissions are handled. `flutter_taglib` offers two ways to handle this:

#### Option A: Automatic Permission Requests (`openAsync` & `requestWriteAccess`)
Use `openAsync` with `writeAccess: true` to trigger the system prompt when necessary. If you already have a `TagLibFile` open in read-only mode, you can request write access before saving:

```dart
final file = TagLibFile.open(path);
// ... do some read operations ...

// Reopens the file natively with write permissions
final hasWriteAccess = await file.requestWriteAccess();
if (hasWriteAccess) {
  file.title = 'New Title';
  file.save();
}
file.close();
```

#### Option B: Opening File Descriptors (`openFd`)
If you obtain a file descriptor through the Android Storage Access Framework (SAF) or MediaStore, you can pass the file descriptor directly to `TagLibFile.openFd`:

```dart
// E.g., obtained via MethodChannel or a document picker in Android
int fd = androidFileDescriptor; 
final file = TagLibFile.openFd(fd, path: filePath);

if (file != null) {
  try {
    print(file.title);
    file.title = 'Updated Title via FD';
    file.save();
  } finally {
    file.close();
  }
}
```

---

## Configuration: Selectable Platform Support

If your project only targets specific platforms or you want to avoid native compilation conflicts with other libraries, you can selectively enable or disable platforms by adding a configuration file named `flutter_taglib.yaml` in your **host project's root directory**.

Create a `flutter_taglib.yaml` file:

```yaml
# flutter_taglib.yaml
platforms:
  android: true
  ios: false
  macos: true
  windows: true
  linux: true
```

- **`true` (Default)**: Compilation is enabled for the platform.
- **`false`**: Native compilation is skipped for the platform, and calling `TagLibFile` methods on that platform will throw an `UnsupportedError` (or you can verify via `TagLibFile.isSupported` which returns `false`).

---

## Native Assets Compilation Requirements

Because this plugin compiles TagLib from source using Native Assets:
- **Android**: Requires NDK configured in your local environment.
- **iOS/macOS**: Requires Xcode.
- **Windows**: Requires Visual Studio with C++ build tools.
- **Linux**: Requires `cmake`, `pkg-config`, and compiler tools (`gcc`/`g++`).

---

## License

This project is licensed under the MIT License. TagLib itself is licensed under LGPL/MPL.
