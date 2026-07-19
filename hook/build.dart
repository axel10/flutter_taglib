// ignore_for_file: avoid_print

import 'dart:io';
import 'package:code_assets/code_assets.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:logging/logging.dart';
import 'package:hooks/hooks.dart';

const String _prebuiltReleaseTag = 'desktop-binaries-v1.4.0';
const String _githubDownloadBaseUrl =
    'https://github.com/axel10/flutter_taglib/releases/download/$_prebuiltReleaseTag';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final targetOSStr = input.config.code.targetOS
        .toString()
        .split('.')
        .last
        .toLowerCase();
    if (!_isPlatformEnabled(targetOSStr)) {
      print(
        'flutter_taglib: Building for $targetOSStr is disabled via flutter_taglib.yaml. Skipping compilation.',
      );
      return;
    }

    final buildDesktopFromSource = _shouldBuildDesktopFromSource();
    if ((targetOSStr == 'windows' || targetOSStr == 'linux') &&
        !buildDesktopFromSource) {
      final archStr = input.config.code.targetArchitecture
          .toString()
          .split('.')
          .last
          .toLowerCase();
      if (archStr == 'x64') {
        final remoteFileName = targetOSStr == 'windows'
            ? 'flutter_taglib_windows_x64.dll'
            : 'libflutter_taglib_linux_x64.so';
        final localFileName = targetOSStr == 'windows'
            ? 'flutter_taglib_native.dll'
            : 'libflutter_taglib_native.so';

        final cacheDir = Directory.fromUri(
          input.packageRoot.resolve('.dart_tool/flutter_taglib/prebuilt/'),
        );
        if (!cacheDir.existsSync()) {
          cacheDir.createSync(recursive: true);
        }

        final prebuiltFile = File.fromUri(
          cacheDir.uri.resolve(localFileName),
        );
        if (!prebuiltFile.existsSync()) {
          final url = '$_githubDownloadBaseUrl/$remoteFileName';
          print('flutter_taglib: Downloading prebuilt binary from $url...');
          await _downloadFile(url, prebuiltFile);
        } else {
          print('flutter_taglib: Using cached prebuilt binary at ${prebuiltFile.path}');
        }

        output.assets.code.add(
          CodeAsset(
            package: input.packageName,
            name: '${input.packageName}_bindings_generated.dart',
            linkMode: DynamicLoadingBundled(),
            file: prebuiltFile.uri,
          ),
        );
        print('flutter_taglib: Bundled prebuilt binary for $targetOSStr $archStr');
        return;
      } else {
        throw UnsupportedError(
          'flutter_taglib prebuilt binaries are only supported on x64 architecture. Please build from source for $archStr.',
        );
      }
    }

    final packageName = input.packageName;
    final nativeLibraryName = '${packageName}_native';

    final buildAndroidFromSource = _shouldBuildAndroidFromSource();
    if (targetOSStr == 'android' && !buildAndroidFromSource) {
      final archStr = input.config.code.targetArchitecture
          .toString()
          .split('.')
          .last
          .toLowerCase();
      final abi = _mapArchitectureToAndroidAbi(archStr);
      if (abi != null && abi != 'x86') {
        final remoteFileName = 'libflutter_taglib_android_$abi.so';
        final localFileName = 'libflutter_taglib_native_$abi.so';

        final cacheDir = Directory.fromUri(
          input.packageRoot.resolve('.dart_tool/flutter_taglib/prebuilt/'),
        );
        if (!cacheDir.existsSync()) {
          cacheDir.createSync(recursive: true);
        }

        final prebuiltFile = File.fromUri(
          cacheDir.uri.resolve(localFileName),
        );
        if (!prebuiltFile.existsSync()) {
          final url = '$_githubDownloadBaseUrl/$remoteFileName';
          print('flutter_taglib: Downloading prebuilt Android binary from $url...');
          await _downloadFile(url, prebuiltFile);
        } else {
          print('flutter_taglib: Using cached prebuilt Android binary at ${prebuiltFile.path}');
        }

        output.assets.code.add(
          CodeAsset(
            package: packageName,
            name: '${packageName}_bindings_generated.dart',
            linkMode: DynamicLoadingBundled(),
            file: prebuiltFile.uri,
          ),
        );
        print('flutter_taglib: Bundled prebuilt binary for Android $archStr ($abi)');
        return;
      } else {
        print(
          'flutter_taglib: No prebuilt Android binary for architecture: $archStr ($abi). Falling back to source build.',
        );
      }
    }

    // --- Online Fetch TagLib 2.3 & utfcpp ---
    final taglibVersion = '2.3';
    final utfcppVersion = '4.0.9';

    final cacheDir = Directory('.dart_tool/flutter_taglib');
    final taglibExtractedDir = Directory(
      '${cacheDir.path}/taglib-$taglibVersion',
    );
    final targetUtfcppDir = Directory(
      '${taglibExtractedDir.path}/3rdparty/utfcpp',
    );

    if (!taglibExtractedDir.existsSync() ||
        !File('${targetUtfcppDir.path}/source/utf8.h').existsSync()) {
      print(
        'flutter_taglib: TagLib 2.3 or utfcpp missing in cache. Downloading sources...',
      );
      cacheDir.createSync(recursive: true);

      // 1. Download TagLib 2.3
      final taglibZip = File('${cacheDir.path}/taglib.zip');
      final taglibUrl =
          'https://github.com/taglib/taglib/archive/refs/tags/v$taglibVersion.zip';
      print('Downloading TagLib from $taglibUrl...');
      await _downloadFile(taglibUrl, taglibZip);

      // 2. Download utfcpp
      final utfcppZip = File('${cacheDir.path}/utfcpp.zip');
      final utfcppUrl =
          'https://github.com/nemtrif/utfcpp/archive/refs/tags/v$utfcppVersion.zip';
      print('Downloading utfcpp from $utfcppUrl...');
      await _downloadFile(utfcppUrl, utfcppZip);

      // 3. Extract TagLib
      print('Extracting TagLib...');
      await _extractZip(taglibZip, cacheDir);

      // 4. Extract utfcpp
      print('Extracting utfcpp...');
      await _extractZip(utfcppZip, cacheDir);

      // 5. Setup utfcpp dependency inside taglib-2.3/3rdparty/utfcpp
      print('Setting up utfcpp dependency...');
      if (targetUtfcppDir.existsSync()) {
        targetUtfcppDir.deleteSync(recursive: true);
      }
      targetUtfcppDir.createSync(recursive: true);

      final utfcppExtractedDir = Directory(
        '${cacheDir.path}/utfcpp-$utfcppVersion',
      );
      if (utfcppExtractedDir.existsSync()) {
        await _moveDirectory(utfcppExtractedDir, targetUtfcppDir);
        utfcppExtractedDir.deleteSync(recursive: true);
      }

      // Cleanup ZIPs
      if (taglibZip.existsSync()) taglibZip.deleteSync();
      if (utfcppZip.existsSync()) utfcppZip.deleteSync();
      print('flutter_taglib: Online sources fetched successfully.');
    }

    final sources = <String>['src/flutter_taglib.cpp'];

    final includes = <String>[
      'src',
      taglibExtractedDir.path,
      '${taglibExtractedDir.path}/taglib',
      '${taglibExtractedDir.path}/3rdparty/utfcpp/source',
    ];

    // TagLib headers often use sibling-relative includes such as `tfile.h`
    // or `oggfile.h`. On non-Windows desktop builds we can safely include all
    // TagLib subdirectories to satisfy those transitive includes.
    if (targetOSStr != 'windows') {
      final discoveredIncludeDirs = <String>{};
      final taglibRoot = Directory('${taglibExtractedDir.path}/taglib');
      if (taglibRoot.existsSync()) {
        for (final entity in taglibRoot.listSync(recursive: true)) {
          if (entity is File &&
              (entity.path.endsWith('.h') || entity.path.endsWith('.hpp'))) {
            discoveredIncludeDirs.add(entity.parent.path);
          }
        }
      }
      final sortedIncludeDirs = discoveredIncludeDirs.toList()..sort();
      includes.addAll(sortedIncludeDirs);
    }

    if (targetOSStr == 'windows') {
      final flattenedIncludeDir = Directory(
        '${cacheDir.path}/taglib_flattened_headers',
      );
      _prepareFlattenedWindowsHeaders(
        taglibRoot: Directory('${taglibExtractedDir.path}/taglib'),
        flattenedIncludeDir: flattenedIncludeDir,
      );
      includes.add(flattenedIncludeDir.path);
    }

    // Find all .cpp files in taglib/taglib recursively and group them by
    // subdirectory. We intentionally keep the include list short on Windows
    // because adding every subdirectory can push cl.exe over the command line
    // limit in CI.
    final taglibSubDir = Directory('${taglibExtractedDir.path}/taglib');
    final List<String> taglibLibraries = [];

    if (targetOSStr == 'windows') {
      final dirToCppFiles = <String, List<String>>{};
      if (taglibSubDir.existsSync()) {
        for (final entity in taglibSubDir.listSync(recursive: true)) {
          if (entity is File && entity.path.endsWith('.cpp')) {
            final parentDir = entity.parent.path;
            dirToCppFiles.putIfAbsent(parentDir, () => []).add(entity.path);
          }
        }
      }

      // Compile each directory's C++ files into small static libraries so the
      // generated cl.exe command line stays below Windows limits.
      for (final entry in dirToCppFiles.entries) {
        final dirPath = entry.key;
        final cppFiles = [...entry.value]..sort();

        final normalizedPath = dirPath.replaceAll('\\', '/');
        final pathParts = normalizedPath.split('/');
        final taglibIndex = pathParts.indexOf('taglib');
        String suffix;
        if (taglibIndex != -1 && taglibIndex < pathParts.length - 1) {
          suffix = pathParts.sublist(taglibIndex + 1).join('_');
        } else {
          suffix = pathParts.last;
        }
        if (suffix.isEmpty) {
          suffix = 'root';
        }

        final batches = _chunkFiles(cppFiles, 4);
        for (var index = 0; index < batches.length; index++) {
          final libName = 'taglib_${suffix}_$index';
          taglibLibraries.add(libName);

          // Clean up any existing .obj files in the output directory
          // to prevent them from being packaged into the static library.
          final outDirFile = Directory(input.outputDirectory.toFilePath());
          if (outDirFile.existsSync()) {
            for (final file in outDirFile.listSync()) {
              if (file is File && file.path.endsWith('.obj')) {
                try {
                  file.deleteSync();
                } catch (_) {}
              }
            }
          }

          final staticBuilder = CBuilder.library(
            name: libName,
            assetName: null, // Do not expose as native asset to Flutter
            sources: batches[index],
            includes: includes,
            defines: {'HAVE_CONFIG_H': '1', 'TAGLIB_STATIC': '1'},
            std: 'c++17',
            language: Language.cpp,
            linkModePreference: LinkModePreference.static,
          );

          await staticBuilder.run(
            input: input,
            output: output,
            logger: Logger('')
              ..level = Level.ALL
              ..onRecord.listen((record) => print(record.message)),
          );
        }
      }
    } else {
      // For other platforms, compile all .cpp files directly
      if (taglibSubDir.existsSync()) {
        for (final entity in taglibSubDir.listSync(recursive: true)) {
          if (entity is File && entity.path.endsWith('.cpp')) {
            sources.add(entity.path);
          }
        }
      }
    }

    final cbuilder = CBuilder.library(
      // Avoid colliding with the CocoaPods plugin framework name on iOS/macOS.
      // The asset id still points at the generated Dart bindings, but the
      // produced dynamic library/framework gets its own distinct basename.
      name: nativeLibraryName,
      assetName: '${packageName}_bindings_generated.dart',
      sources: sources,
      includes: includes,
      defines: {'HAVE_CONFIG_H': '1', 'TAGLIB_STATIC': '1'},
      std: 'c++17',
      language: Language.cpp,
      cppLinkStdLib: input.config.code.targetOS.toString().contains('android')
          ? 'c++_static'
          : null,
      flags: [
        if (!input.config.code.targetOS.toString().contains('windows'))
          '-fvisibility=hidden',
      ],
      libraries: [
        if (targetOSStr == 'windows') ...taglibLibraries,
        if (input.config.code.targetOS.toString().contains('android') ||
            input.config.code.targetOS.toString().contains('linux'))
          'm',
        if (input.config.code.targetOS.toString().contains('android')) 'log',
      ],
      libraryDirectories: [if (targetOSStr == 'windows') '.'],
    );

    await cbuilder.run(
      input: input,
      output: output,
      logger: Logger('')
        ..level = Level.ALL
        ..onRecord.listen((record) => print(record.message)),
    );
  });
}

void _prepareFlattenedWindowsHeaders({
  required Directory taglibRoot,
  required Directory flattenedIncludeDir,
}) {
  if (!taglibRoot.existsSync()) {
    return;
  }

  if (flattenedIncludeDir.existsSync()) {
    flattenedIncludeDir.deleteSync(recursive: true);
  }
  flattenedIncludeDir.createSync(recursive: true);

  final seenHeaderNames = <String, String>{};
  const allowedExtensions = <String>{'.h', '.hpp', '.tcc', '.inl', '.inc'};

  for (final entity in taglibRoot.listSync(recursive: true)) {
    if (entity is! File) continue;
    final extension = _extensionOf(entity.path).toLowerCase();
    if (!allowedExtensions.contains(extension)) continue;

    final headerName = entity.uri.pathSegments.last;
    final existingPath = seenHeaderNames[headerName];
    if (existingPath != null && existingPath != entity.path) {
      throw StateError(
        'Duplicate TagLib header name detected for Windows flattened includes: '
        '$headerName\n- $existingPath\n- ${entity.path}',
      );
    }
    seenHeaderNames[headerName] = entity.path;

    final targetFile = File('${flattenedIncludeDir.path}/$headerName');
    entity.copySync(targetFile.path);
  }
}

String _extensionOf(String filePath) {
  final slashIndex = filePath.lastIndexOf(RegExp(r'[\\/]'));
  final fileName = slashIndex == -1
      ? filePath
      : filePath.substring(slashIndex + 1);
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex <= 0 || dotIndex == fileName.length - 1) {
    return '';
  }
  return fileName.substring(dotIndex);
}

bool _shouldBuildDesktopFromSource() {
  if (Platform.environment['FLUTTER_TAGLIB_BUILD_DESKTOP_FROM_SOURCE'] ==
      'true') {
    return true;
  }

  const markerName = '.flutter_taglib_build_desktop_from_source';
  final markerPaths = [
    Directory.current.uri.resolve(markerName).toFilePath(),
    if (Directory.current.parent.existsSync())
      Directory.current.parent.uri.resolve(markerName).toFilePath(),
    if (Directory.current.parent.existsSync() &&
        Directory.current.parent.parent.existsSync())
      Directory.current.parent.parent.uri.resolve(markerName).toFilePath(),
  ];

  for (final path in markerPaths) {
    if (File(path).existsSync()) {
      return true;
    }
  }

  return false;
}

bool _shouldBuildAndroidFromSource() {
  if (Platform.environment['FLUTTER_TAGLIB_BUILD_ANDROID_FROM_SOURCE'] ==
      'true') {
    return true;
  }

  const markerName = '.flutter_taglib_build_android_from_source';
  final markerPaths = [
    Directory.current.uri.resolve(markerName).toFilePath(),
    if (Directory.current.parent.existsSync())
      Directory.current.parent.uri.resolve(markerName).toFilePath(),
    if (Directory.current.parent.existsSync() &&
        Directory.current.parent.parent.existsSync())
      Directory.current.parent.parent.uri.resolve(markerName).toFilePath(),
  ];

  for (final path in markerPaths) {
    if (File(path).existsSync()) {
      return true;
    }
  }

  return false;
}

String? _mapArchitectureToAndroidAbi(String archStr) {
  switch (archStr) {
    case 'arm64':
      return 'arm64-v8a';
    case 'arm':
      return 'armeabi-v7a';
    case 'x64':
      return 'x86_64';
    case 'ia32':
    case 'x86':
      return 'x86';
    default:
      return null;
  }
}

Future<void> _downloadFile(String url, File targetFile) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw Exception('Failed to download from $url: ${response.statusCode}');
    }
    final bytes = await response.fold<List<int>>([], (p, e) => p..addAll(e));
    await targetFile.writeAsBytes(bytes);
  } finally {
    client.close();
  }
}

Future<void> _extractZip(File zipFile, Directory destDir) async {
  ProcessResult result;
  if (Platform.isWindows) {
    result = await Process.run('tar', [
      '-xf',
      zipFile.path,
      '-C',
      destDir.path,
    ]);
  } else {
    result = await Process.run('unzip', [
      '-o',
      '-q',
      zipFile.path,
      '-d',
      destDir.path,
    ]);
  }
  if (result.exitCode != 0) {
    throw Exception('Failed to extract ${zipFile.path}: ${result.stderr}');
  }
}

Future<void> _moveDirectory(Directory source, Directory destination) async {
  for (final entity in source.listSync()) {
    final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (entity is File) {
      entity.renameSync('${destination.path}/$name');
    } else if (entity is Directory) {
      final newDir = Directory('${destination.path}/$name');
      newDir.createSync(recursive: true);
      await _moveDirectory(entity, newDir);
    }
  }
}

List<List<String>> _chunkFiles(List<String> files, int chunkSize) {
  final chunks = <List<String>>[];
  for (var start = 0; start < files.length; start += chunkSize) {
    final end = start + chunkSize > files.length
        ? files.length
        : start + chunkSize;
    chunks.add(files.sublist(start, end));
  }
  return chunks;
}

bool _isPlatformEnabled(String targetOS) {
  // Check for configuration file in current directory or parent directory
  File? configFile;
  final pathsToCheck = [
    Directory.current.uri.resolve('flutter_taglib.yaml').toFilePath(),
    if (Directory.current.parent.existsSync())
      Directory.current.parent.uri.resolve('flutter_taglib.yaml').toFilePath(),
    if (Directory.current.parent.existsSync() &&
        Directory.current.parent.parent.existsSync())
      Directory.current.parent.parent.uri
          .resolve('flutter_taglib.yaml')
          .toFilePath(),
  ];

  for (final path in pathsToCheck) {
    final file = File(path);
    if (file.existsSync()) {
      configFile = file;
      break;
    }
  }

  if (configFile == null) {
    return true; // Default to enabled if no config file is found
  }

  try {
    final lines = configFile.readAsLinesSync();
    bool inPlatformsBlock = false;
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      if (line.startsWith('platforms:')) {
        inPlatformsBlock = true;
        continue;
      }

      // If we hit another top-level key, exit the platforms block
      if (inPlatformsBlock && line.endsWith(':') && !line.startsWith(' ')) {
        inPlatformsBlock = false;
      }

      if (inPlatformsBlock) {
        final parts = line.split(':');
        if (parts.length == 2) {
          final key = parts[0].trim().toLowerCase();
          final val = parts[1].trim().toLowerCase();
          if (key == targetOS.toLowerCase()) {
            return val == 'true';
          }
        }
      }
    }
  } catch (e) {
    print(
      'flutter_taglib hook/build.dart: error reading/parsing flutter_taglib.yaml: $e',
    );
  }

  return true; // Default to enabled on error or if not found in config
}
