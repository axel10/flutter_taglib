// ignore_for_file: avoid_print

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_taglib/flutter_taglib.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TagLib Metadata Read Performance Benchmark', () {
    test('Read metadata 1,000 times and measure elapsed time', () async {
      const iterations = 1000;

      // Locate test audio asset
      final candidatePaths = [
        '../test/assets/01 TempleOS Hymn Risen (Remix).mp3',
        'test/assets/01 TempleOS Hymn Risen (Remix).mp3',
        'assets/01 TempleOS Hymn Risen (Remix).mp3',
      ];

      String? filePath;
      for (final path in candidatePaths) {
        if (File(path).existsSync()) {
          filePath = path;
          break;
        }
      }

      expect(filePath, isNotNull, reason: 'Test audio file should exist at test/assets/');
      final file = File(filePath!);
      final fileSizeKb = (file.lengthSync() / 1024).toStringAsFixed(2);

      print('\n====================================================');
      print('  Flutter TagLib Performance Benchmark (1,000 Reads)');
      print('====================================================');
      print('Target Audio File: $filePath ($fileSizeKb KB)');
      print('Iterations:        $iterations reads\n');

      // Verify file opening and print sample metadata
      final sample = TagLibFile.open(filePath);
      expect(sample, isNotNull);
      print('Sample Metadata:');
      print('  Title:       ${sample!.title}');
      print('  Artist:      ${sample.artist}');
      print('  Album:       ${sample.album}');
      print('  Duration:    ${sample.duration}');
      print('  Format:      ${sample.sampleRate} Hz, ${sample.channels} ch, ${sample.bitrate} kbps');
      sample.close();
      print('');

      // Warm-up phase (10 reads) to load dynamic library / caches
      for (int i = 0; i < 10; i++) {
        final f = TagLibFile.open(filePath);
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
        }
      }

      // Benchmark execution
      print('Running benchmark ($iterations iterations)...');
      final stopwatch = Stopwatch()..start();

      int successCount = 0;
      for (int i = 0; i < iterations; i++) {
        final f = TagLibFile.open(filePath);
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
      final totalUs = stopwatch.elapsedMicroseconds;
      final avgMs = totalMs / iterations;
      final avgUs = totalUs / iterations;
      final opsPerSec = (iterations / (totalUs / 1000000.0));

      print('----------------------------------------------------');
      print('                 BENCHMARK RESULTS                  ');
      print('----------------------------------------------------');
      print('Successful Reads:     $successCount / $iterations');
      print('Total Time Elapsed:   $totalMs ms (${(totalMs / 1000.0).toStringAsFixed(3)} s)');
      print('Average Time / Read:  ${avgMs.toStringAsFixed(3)} ms (${avgUs.toStringAsFixed(1)} µs)');
      print('Throughput Speed:     ${opsPerSec.toStringAsFixed(2)} reads/sec');
      print('====================================================\n');

      expect(successCount, equals(iterations));
    });
  });
}
