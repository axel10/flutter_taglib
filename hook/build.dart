import 'dart:io';
import 'package:code_assets/code_assets.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:logging/logging.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final targetOSStr = input.config.code.targetOS.toString().split('.').last.toLowerCase();
    if (!_isPlatformEnabled(targetOSStr)) {
      print('flutter_taglib: Building for $targetOSStr is disabled via flutter_taglib.yaml. Skipping compilation.');
      return;
    }

    final packageName = input.packageName;

    // --- Online Fetch TagLib 2.3 & utfcpp ---
    final taglibVersion = '2.3';
    final utfcppVersion = '4.0.9';

    final cacheDir = Directory('.dart_tool/flutter_taglib');
    final taglibExtractedDir = Directory('${cacheDir.path}/taglib-$taglibVersion');
    final targetUtfcppDir = Directory('${taglibExtractedDir.path}/3rdparty/utfcpp');

    if (!taglibExtractedDir.existsSync() || !File('${targetUtfcppDir.path}/source/utf8.h').existsSync()) {
      print('flutter_taglib: TagLib 2.3 or utfcpp missing in cache. Downloading sources...');
      cacheDir.createSync(recursive: true);

      // 1. Download TagLib 2.3
      final taglibZip = File('${cacheDir.path}/taglib.zip');
      final taglibUrl = 'https://github.com/taglib/taglib/archive/refs/tags/v$taglibVersion.zip';
      print('Downloading TagLib from $taglibUrl...');
      await _downloadFile(taglibUrl, taglibZip);

      // 2. Download utfcpp
      final utfcppZip = File('${cacheDir.path}/utfcpp.zip');
      final utfcppUrl = 'https://github.com/nemtrif/utfcpp/archive/refs/tags/v$utfcppVersion.zip';
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

      final utfcppExtractedDir = Directory('${cacheDir.path}/utfcpp-$utfcppVersion');
      if (utfcppExtractedDir.existsSync()) {
        await _moveDirectory(utfcppExtractedDir, targetUtfcppDir);
        utfcppExtractedDir.deleteSync(recursive: true);
      }

      // Cleanup ZIPs
      if (taglibZip.existsSync()) taglibZip.deleteSync();
      if (utfcppZip.existsSync()) utfcppZip.deleteSync();
      print('flutter_taglib: Online sources fetched successfully.');
    }

    final sources = <String>[
      'src/flutter_taglib.cpp',
    ];

    final includes = <String>[
      'src',
      taglibExtractedDir.path,
      '${taglibExtractedDir.path}/taglib',
      '${taglibExtractedDir.path}/3rdparty/utfcpp/source',
    ];

    // Find all .cpp files in taglib/taglib recursively and group them by subdirectory
    // Also find all subdirectories in taglib/taglib and add to includes
    final taglibSubDir = Directory('${taglibExtractedDir.path}/taglib');
    final List<String> taglibLibraries = [];

    if (targetOSStr == 'windows') {
      final dirToCppFiles = <String, List<String>>{};
      if (taglibSubDir.existsSync()) {
        for (final entity in taglibSubDir.listSync(recursive: true)) {
          if (entity is File && entity.path.endsWith('.cpp')) {
            final parentDir = entity.parent.path;
            dirToCppFiles.putIfAbsent(parentDir, () => []).add(entity.path);
          } else if (entity is Directory) {
            includes.add(entity.path);
          }
        }
      }

      // Compile each directory's C++ files into its own static library
      for (final entry in dirToCppFiles.entries) {
        final dirPath = entry.key;
        final cppFiles = entry.value;

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

        final libName = 'taglib_$suffix';
        taglibLibraries.add(libName);

        // Clean up any existing .obj files in the output directory
        // to prevent them from being packaged into the static library
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
          sources: cppFiles,
          includes: includes,
          defines: {
            'HAVE_CONFIG_H': '1',
            'TAGLIB_STATIC': '1',
          },
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
    } else {
      // For other platforms, compile all .cpp files directly
      if (taglibSubDir.existsSync()) {
        for (final entity in taglibSubDir.listSync(recursive: true)) {
          if (entity is File && entity.path.endsWith('.cpp')) {
            sources.add(entity.path);
          } else if (entity is Directory) {
            includes.add(entity.path);
          }
        }
      }
    }

    final cbuilder = CBuilder.library(
      name: packageName,
      assetName: '${packageName}_bindings_generated.dart',
      sources: sources,
      includes: includes,
      defines: {
        'HAVE_CONFIG_H': '1',
        'TAGLIB_STATIC': '1',
      },
      std: 'c++17',
      language: Language.cpp,
      cppLinkStdLib: input.config.code.targetOS.toString().contains('android') ? 'c++_static' : null,
      flags: [
        if (!input.config.code.targetOS.toString().contains('windows'))
          '-fvisibility=hidden',
      ],
      libraries: [
        if (targetOSStr == 'windows') ...taglibLibraries,
        if (input.config.code.targetOS.toString().contains('android') ||
            input.config.code.targetOS.toString().contains('linux'))
          'm',
        if (input.config.code.targetOS.toString().contains('android'))
          'log',
      ],
      libraryDirectories: [
        if (targetOSStr == 'windows') '.',
      ],
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
  final result = await Process.run('tar', ['-xf', zipFile.path, '-C', destDir.path]);
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

bool _isPlatformEnabled(String targetOS) {
  // Check for configuration file in current directory or parent directory
  File? configFile;
  final pathsToCheck = [
    Directory.current.uri.resolve('flutter_taglib.yaml').toFilePath(),
    if (Directory.current.parent.existsSync())
      Directory.current.parent.uri.resolve('flutter_taglib.yaml').toFilePath(),
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
    print('flutter_taglib hook/build.dart: error reading/parsing flutter_taglib.yaml: $e');
  }

  return true; // Default to enabled on error or if not found in config
}
