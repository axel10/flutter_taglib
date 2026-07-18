# flutter_taglib

[![pub package](https://img.shields.io/pub/v/flutter_taglib.svg)](https://pub.dev/packages/flutter_taglib)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

A high-performance, feature-rich Flutter plugin wrapping **TagLib** using Dart FFI and Native Assets. It allows you to read and write audio metadata (including album cover art) and extract technical audio properties across various platforms.

> [!WARNING]
> Versions 1.3.0 and 1.3.1 did not download dynamic libraries locally during the build. Windows and Linux users may encounter a missing dynamic library error when starting the app without an internet connection. Please update to the latest version as soon as possible.

> [!NOTE]
> This package uses a hybrid platform strategy:
> - **Windows/Linux/Android** use prebuilt binaries that are downloaded on demand and cached locally, so host apps do not need to compile TagLib during every build.
> - **iOS/macOS** continue to rely on native platform builds.

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
  - Bitrate (kbps) and Bitrate Mode (`CBR`, `VBR`, or `Unknown`)
  - Sample Rate (Hz)
  - Channels (Mono, Stereo, etc.)
  - Get a structured `AudioInfo` object containing all detailed audio properties.
- **Scoped Storage & SAF Support (Android)**:
  - Open files using Unix File Descriptors (`openFd`) to bypass Scoped Storage restrictions.
  - Reuse persisted SAF tree permissions when a file lives under a selected output directory, so batch writes can stay inside one folder grant instead of prompting per file.
  - Automatically request write permissions using `openAsync` or `requestWriteAccess()` when a direct writable descriptor is not already available.
- **Selectable Platform Support**: Avoid compilation conflicts by selectively enabling or disabling platform builds using a simple YAML configuration file.

---

## Installation

Add `flutter_taglib` to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_taglib: ^1.2.0
```

If you are developing against the local repository, you can keep using a path
dependency during development:

```yaml
dependencies:
  flutter_taglib:
    path: /path/to/flutter_taglib
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
    print('Duration:     ${file.duration}');
    print('Bitrate:      ${file.bitrate} kbps');
    print('Bitrate Mode: ${file.bitrateMode}'); // 'CBR', 'VBR', or 'Unknown'
    print('Sample Rate:  ${file.sampleRate} Hz');
    print('Channels:     ${file.channels}');

    // Or retrieve all detailed audio properties as a structured object
    final audioInfo = file.audioInfo;
    print('Audio Info:   $audioInfo');
  } finally {
    // Always close the file to release native resources!
    file.close();
  }
}
```

### 2. Modifying Metadata

To update metadata, modify the fields and call `save()`.

> [!IMPORTANT]
> On Android, modifying files in Scoped Storage may require write permission. If you pick an output directory through SAF, the persisted tree permission is typically enough for files created inside that directory, so batch metadata writes should avoid per-file prompts.

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

If you need the full embedded picture list, use `file.pictures` and
`file.setPictures(...)`. `setCover(...)` is a convenience wrapper that updates
the first picture only.

### 4. iOS File and Directory Access

On iOS, file and directory access uses Apple's security-scoped resource model.
The plugin wraps that lifecycle in typed helpers so you do not need to work with
raw MethodChannel maps or manage most of the native details yourself.

There are two separate flows:

1. Audio file editing uses a writable working copy.
2. Directory access uses security-scoped bookmarks that can be restored later.

#### Audio File Editing Flow

When you pick an audio file with `TagLibFile.pickAudioFileForEditing()`, the
plugin:

- Presents an iOS document picker.
- Calls `startAccessingSecurityScopedResource()` for the selected file.
- Creates a writable working copy in temporary storage.
- Returns a `PickedAudioFile` with both the working copy path and the original
  file path.

After you edit metadata and call `save()`, call `PickedAudioFile.commit()` to
copy the working copy back to the original file.

```dart
final picked = await TagLibFile.pickAudioFileForEditing();
if (picked != null) {
  final file = await TagLibFile.openAsync(picked.path);
  if (file != null) {
    try {
      file.title = 'Updated Title';
      file.save();
      await picked.commit();
    } finally {
      file.close();
    }
  }
}
```

#### Directory Authorization Flow

When you pick a directory with `TagLibFile.pickAuthorizedDirectory()`, the
plugin:

- Presents an iOS folder picker.
- Calls `startAccessingSecurityScopedResource()` for the selected directory.
- Creates a security-scoped bookmark.
- Stores that bookmark in `UserDefaults` under the key
  `flutter_taglib.directoryBookmarks`.

That means access can be restored later, even after the app restarts, as long
as iOS still accepts the bookmark.

Use the returned `AuthorizedDirectory` as a disposable handle:

```dart
final directory = await TagLibFile.pickAuthorizedDirectory();
if (directory != null) {
  try {
    print('Authorized directory: ${directory.path}');
  } finally {
    await directory.dispose();
  }
}
```

#### Restoring Access

If you need to restore a previously authorized directory later, call
`TagLibFile.restoreAuthorizedDirectory(path)`.

The plugin will:

- Look up the stored bookmark for the path or one of its ancestor directories.
- Resolve the bookmark with `URL(resolvingBookmarkData:)`.
- Call `startAccessingSecurityScopedResource()` again.
- Refresh the bookmark if iOS reports it is stale.

```dart
final restored = await TagLibFile.restoreAuthorizedDirectory(directoryPath);
if (restored != null) {
  try {
    print('Restored access to: ${restored.path}');
  } finally {
    await restored.dispose();
  }
}
```

#### Notes

- `pickAudioFileForEditing()` is for editing individual files, not for
  persistent directory access.
- `pickAuthorizedDirectory()` is the entry point for reusable folder access.
- Always call `dispose()` on `AuthorizedDirectory` when you are done.
- The bookmark data is persisted on-device via `UserDefaults`, not in your Dart
  code.

### 5. Android Scoped Storage & File Descriptors

Android 10+ enforces Scoped Storage. Directly opening a filepath (like `/storage/emulated/0/...`) in C++ write mode will fail unless permissions are handled. `flutter_taglib` offers two ways to handle this:

If you use `file_picker` on Android to choose a target file for writing, use
`PlatformFile.identifier` as the write path. In many cases `file.path` is only
a local filesystem path without write permission, while `identifier` preserves
the `content://` URI that can actually be granted write access.

```dart
final result = await FilePicker.pickFiles(type: FileType.audio);
if (result != null && result.files.isNotEmpty) {
  final file = result.files.single;
  final writePath = file.identifier;
  if (writePath == null || writePath.isEmpty) {
    throw StateError('Android write access requires a file identifier.');
  }

  final tagFile = await TagLibFile.openAsync(writePath, writeAccess: true);
  // ...
}
```

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

### 6. Advanced Metadata Properties (Generic Properties Map)

For advanced metadata management, TagLib supports a generic properties map (`Map<String, List<String>>`) representing key-value pairs of tags. This allows you to read and write tags that are not exposed via standard high-level properties, or handle tags with multiple values (e.g., multiple artists or genres).

Standard keys are defined as constants in the `TagProperties` class (e.g., `TagProperties.albumArtist`, `TagProperties.lyrics`, `TagProperties.bpm`, etc.).

#### Reading Generic Properties

```dart
final file = TagLibFile.open(filePath);
if (file != null) {
  try {
    // Get all properties as a Map<String, List<String>>
    final Map<String, List<String>> props = file.properties;

    // Read standard tags using TagProperties constants
    final artists = props[TagProperties.artist]; // List of artist names
    final albumArtist = props[TagProperties.albumArtist]?.firstOrNull;
    final lyrics = props[TagProperties.lyrics]?.firstOrNull;

    print('Artists: $artists');
    print('Lyrics: $lyrics');
    
    // Print all available properties in the file
    props.forEach((key, values) {
      print('$key: $values');
    });
  } finally {
    file.close();
  }
}
```

#### Writing Generic Properties

```dart
final file = await TagLibFile.openAsync(filePath, writeAccess: true);
if (file != null) {
  try {
    // 1. Prepare properties to set
    final Map<String, List<String>> newProps = {
      TagProperties.artist: ['First Artist', 'Second Artist'], // Multiple values
      TagProperties.albumArtist: ['Various Artists'],
      TagProperties.lyrics: ['Line 1...\nLine 2...\nLine 3...'],
      'CUSTOM_TAG': ['Custom Value'], // You can also use custom tags
    };

    // 2. Set the properties in memory
    // It returns any properties not supported by this file format
    final unsupported = file.setProperties(newProps);
    if (unsupported.isNotEmpty) {
      print('Warning: Some properties are unsupported by the file format: $unsupported');
    }

    // 3. Save to write changes to disk
    final success = file.save();
    if (success) {
      print('Generic properties saved successfully!');
    }
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

Because iOS/macOS still compile native code during the platform build:
- **iOS/macOS**: Requires Xcode.

For **Windows/Linux/Android app builds**, the plugin downloads prebuilt
libraries instead of compiling TagLib locally. Repository maintainers can
refresh those binaries through `.github/workflows/build-native-assets.yml`.

If you maintain the binaries yourself and need to regenerate them from
source, you may still need the necessary build tools/Android NDK toolchain in your build environment.

---

## License

This project is licensed under the Apache 2.0 License. TagLib itself is licensed under LGPL/MPL.
