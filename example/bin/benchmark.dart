// ignore_for_file: avoid_print

import 'dart:io';
import 'package:flutter_taglib/flutter_taglib.dart';

void main(List<String> args) async {
  print('====================================================');
  print('  Flutter TagLib Metadata Read Performance Benchmark');
  print('====================================================\n');

  // Parse arguments
  int iterations = 1000;
  String? targetFilePath;

  for (int i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith('--iterations=')) {
      iterations = int.tryParse(arg.split('=')[1]) ?? 1000;
    } else if (arg == '-n' && i + 1 < args.length) {
      iterations = int.tryParse(args[++i]) ?? 1000;
    } else if (!arg.startsWith('-')) {
      targetFilePath = arg;
    }
  }

  // Determine target audio file path
  File? audioFile;
  if (targetFilePath != null) {
    audioFile = File(targetFilePath);
  } else {
    // Try candidate paths relative to workspace or example directory
    final candidates = [
      '../test/assets/01 TempleOS Hymn Risen (Remix).mp3',
      'test/assets/01 TempleOS Hymn Risen (Remix).mp3',
      'assets/01 TempleOS Hymn Risen (Remix).mp3',
    ];
    for (final cand in candidates) {
      final f = File(cand);
      if (f.existsSync()) {
        audioFile = f;
        break;
      }
    }
  }

  if (audioFile == null || !audioFile.existsSync()) {
    print('Error: Target audio file not found.');
    print('Usage: dart run example/bin/benchmark.dart [path_to_audio_file] [-n <iterations>]');
    print('Example: dart run example/bin/benchmark.dart ../test/assets/01 TempleOS Hymn Risen (Remix).mp3 -n 1000');
    exit(1);
  }

  final resolvedPath = audioFile.path;
  final fileSizeBytes = audioFile.lengthSync();
  final fileSizeKb = (fileSizeBytes / 1024).toStringAsFixed(2);

  print('Audio File: $resolvedPath ($fileSizeKb KB)');
  print('Iterations: $iterations reads\n');

  // Verify file opens successfully first
  final testOpen = TagLibFile.open(resolvedPath);
  if (testOpen == null) {
    print('Error: Failed to open audio file with TagLibFile.');
    exit(1);
  }
  print('Sample Metadata:');
  print('  Title:       ${testOpen.title}');
  print('  Artist:      ${testOpen.artist}');
  print('  Album:       ${testOpen.album}');
  print('  Format/Rate: ${testOpen.sampleRate} Hz, ${testOpen.channels} ch, ${testOpen.bitrate} kbps');
  print('  Duration:    ${testOpen.duration.inMilliseconds} ms');
  testOpen.close();
  print('');

  // Warm-up phase (10 iterations) to eliminate cold-start / FFI binding setup overhead
  print('Performing warm-up (10 iterations)...');
  for (int i = 0; i < 10; i++) {
    final f = TagLibFile.open(resolvedPath);
    if (f != null) {
      // Touch properties
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
  print('Warm-up completed.\n');

  // Benchmark execution
  print('Running performance test ($iterations iterations)...');
  final stopwatch = Stopwatch()..start();

  int successCount = 0;
  for (int i = 0; i < iterations; i++) {
    final f = TagLibFile.open(resolvedPath);
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
  final totalMicroseconds = stopwatch.elapsedMicroseconds;
  final avgMsPerRead = totalMs / iterations;
  final avgUsPerRead = totalMicroseconds / iterations;
  final readsPerSec = (iterations / (totalMicroseconds / 1000000.0));

  print('----------------------------------------------------');
  print('                 BENCHMARK RESULTS                  ');
  print('----------------------------------------------------');
  print('Successful Reads:     $successCount / $iterations');
  print('Total Time Elapsed:   $totalMs ms (${(totalMs / 1000.0).toStringAsFixed(3)} s)');
  print('Average Time / Read:  ${avgMsPerRead.toStringAsFixed(3)} ms (${avgUsPerRead.toStringAsFixed(1)} µs)');
  print('Throughput Speed:     ${readsPerSec.toStringAsFixed(2)} reads/sec');
  print('====================================================\n');
}
