// ignore_for_file: avoid_print

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_taglib/flutter_taglib.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Directory Benchmark Test', () {
    test('Scan mock music library directory recursively', () async {
      Directory? mockLibDir;
      for (final p in [
        'benchmark_music_library',
        '../benchmark_music_library',
        'example/benchmark_music_library',
        'benchmark_library',
        '../benchmark_library',
        'example/benchmark_library',
      ]) {
        final d = Directory(p);
        if (d.existsSync()) {
          mockLibDir = d;
          break;
        }
      }

      if (mockLibDir == null) {
        print('benchmark_library directory does not exist, skipping directory test');
        return;
      }

      final supportedExtensions = {
        'mp3',
        'flac',
        'm4a',
        'aac',
        'ogg',
        'wav',
        'aiff',
        'ape',
        'mpc',
        'wv',
        'tta',
        'wma',
        'opus',
        'spx',
      };

      final audioFiles = <File>[];
      await for (final entity in mockLibDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          final ext = entity.path.split('.').last.toLowerCase();
          if (supportedExtensions.contains(ext)) {
            audioFiles.add(entity);
          }
        }
      }

      print('\n====================================================');
      print('  Directory Scan Benchmark (mock music library)');
      print('====================================================');
      print('Location:   ${mockLibDir.absolute.path}');
      print('Files:      ${audioFiles.length} audio files found\n');

      final stopwatch = Stopwatch()..start();
      int successCount = 0;
      final formatBreakdown = <String, int>{};

      for (final file in audioFiles) {
        final ext = file.path.split('.').last.toUpperCase();
        formatBreakdown[ext] = (formatBreakdown[ext] ?? 0) + 1;

        final f = TagLibFile.open(file.path);
        if (f != null) {
          final _ = f.title;
          final _ = f.artist;
          final _ = f.album;
          final _ = f.genre;
          final _ = f.comment;
          final _ = f.year;
          final _ = f.track;
          final _ = f.duration;
          final _ = f.bitrate;
          final _ = f.sampleRate;
          final _ = f.channels;
          final _ = f.hasCover;
          f.close();
          successCount++;
        }
      }

      stopwatch.stop();

      final totalMs = stopwatch.elapsedMilliseconds;
      final avgMs = totalMs / audioFiles.length;
      final opsPerSec = (audioFiles.length /
          (stopwatch.elapsedMicroseconds / 1000000.0));

      print('----------------------------------------------------');
      print('           DIRECTORY BENCHMARK RESULTS              ');
      print('----------------------------------------------------');
      print('Total Audio Files:    ${audioFiles.length}');
      print('Successfully Read:    $successCount / ${audioFiles.length}');
      print('Total Time Elapsed:   $totalMs ms');
      print('Average Time / File:  ${avgMs.toStringAsFixed(2)} ms');
      print('Scan Throughput:      ${opsPerSec.toStringAsFixed(2)} files/sec');
      print('Formats Distribution: $formatBreakdown');
      print('====================================================\n');

      expect(successCount, equals(audioFiles.length));
    });
  });
}
