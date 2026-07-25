// ignore_for_file: avoid_print

import 'dart:io';

void main(List<String> args) async {
  print('====================================================');
  print('  Mock Music Library Generator for Performance Test ');
  print('====================================================\n');

  // Parse CLI args
  String outputDirName = 'benchmark_music_library';
  int targetFileCount = 50;

  for (int i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '-h' || arg == '--help') {
      print('Usage:');
      print('  dart run example/bin/generate_benchmark_library.dart [count] [--count=N] [--dir=DIR_PATH]\n');
      print('Examples:');
      print('  dart run example/bin/generate_benchmark_library.dart 100          # Generate 100 songs');
      print('  dart run example/bin/generate_benchmark_library.dart --count=500  # Generate 500 songs');
      print('  dart run example/bin/generate_benchmark_library.dart --dir=my_lib --count=200\n');
      exit(0);
    } else if (arg.startsWith('--dir=')) {
      outputDirName = arg.split('=')[1];
    } else if (arg.startsWith('--count=')) {
      targetFileCount = int.tryParse(arg.split('=')[1]) ?? 50;
    } else if (arg == '-c' && i + 1 < args.length) {
      targetFileCount = int.tryParse(args[++i]) ?? 50;
    } else if (int.tryParse(arg) != null) {
      targetFileCount = int.parse(arg);
    } else if (!arg.startsWith('-')) {
      outputDirName = arg;
    }
  }

  // Verify ffmpeg exists
  try {
    final checkFfmpeg = await Process.run('ffmpeg', ['-version']);
    if (checkFfmpeg.exitCode != 0) {
      print('Error: ffmpeg check failed.');
      exit(1);
    }
  } catch (e) {
    print('Error: ffmpeg is not available in system PATH: $e');
    print('Please install ffmpeg and ensure it is accessible from command line.');
    exit(1);
  }

  final outDir = Directory(outputDirName);
  if (outDir.existsSync()) {
    print('Cleaning previous mock library directory at ${outDir.path}...');
    try {
      outDir.deleteSync(recursive: true);
    } catch (e) {
      print('Warning: Could not clean directory: $e');
    }
  }
  outDir.createSync(recursive: true);

  print('Output Directory: ${outDir.absolute.path}');
  print('Target File Count: $targetFileCount audio files\n');

  // Pre-generate temporary cover art images of varying dimensions
  final tempCoverDir = Directory.systemTemp.createTempSync('taglib_covers');
  final coverConfigs = [
    {'name': 'cover_150.jpg', 'size': '150x150', 'format': 'mjpeg'},
    {'name': 'cover_300.jpg', 'size': '300x300', 'format': 'mjpeg'},
    {'name': 'cover_500.jpg', 'size': '500x500', 'format': 'mjpeg'},
    {'name': 'cover_800.jpg', 'size': '800x800', 'format': 'mjpeg'},
    {'name': 'cover_1200.jpg', 'size': '1200x1200', 'format': 'mjpeg'},
    {'name': 'cover_1400.jpg', 'size': '1400x1400', 'format': 'mjpeg'},
  ];

  print('Generating cover art assets...');
  final generatedCovers = <String, String>{}; // sizeKey -> filePath
  for (final conf in coverConfigs) {
    final name = conf['name']!;
    final size = conf['size']!;
    final format = conf['format']!;
    final coverPath = '${tempCoverDir.path}/$name';

    final res = await Process.run('ffmpeg', [
      '-y',
      '-f',
      'lavfi',
      '-i',
      'testsrc=s=$size',
      '-vframes',
      '1',
      '-c:v',
      format,
      coverPath,
    ]);

    if (res.exitCode == 0 && File(coverPath).existsSync()) {
      generatedCovers[size] = coverPath;
    }
  }
  print('Generated ${generatedCovers.length} cover images.\n');

  // Library templates: Genres, Artists, Albums, Formats
  final libraryTemplates = [
    {
      'genre': 'Pop',
      'artist': 'Taylor Swift',
      'album': '1989',
      'year': '2014',
      'tracks': ['Welcome to New York', 'Blank Space', 'Style', 'Out of the Woods', 'Shake It Off', 'I Wish You Would', 'Bad Blood'],
    },
    {
      'genre': 'Pop',
      'artist': 'Ed Sheeran',
      'album': 'Divide',
      'year': '2017',
      'tracks': ['Eraser', 'Castle on the Hill', 'Dive', 'Shape of You', 'Perfect', 'Galway Girl', 'Happier'],
    },
    {
      'genre': 'Rock',
      'artist': 'Queen',
      'album': 'A Night at the Opera',
      'year': '1975',
      'tracks': ['Death on Two Legs', 'Lazing on a Sunday Afternoon', 'I\'m in Love with My Car', 'You\'re My Best Friend', '39', 'Sweet Lady', 'Bohemian Rhapsody'],
    },
    {
      'genre': 'Rock',
      'artist': 'AC_DC',
      'album': 'Back in Black',
      'year': '1980',
      'tracks': ['Hells Bells', 'Shoot to Thrill', 'What Do You Do for Money Honey', 'Given the Dog a Bone', 'Let Me Put My Love into You', 'Back in Black'],
    },
    {
      'genre': 'Classical',
      'artist': 'Beethoven',
      'album': 'Symphony No. 5',
      'year': '1808',
      'tracks': ['Allegro con brio', 'Andante con moto', 'Scherzo. Allegro', 'Allegro'],
    },
    {
      'genre': 'Jazz',
      'artist': 'Miles Davis',
      'album': 'Kind of Blue',
      'year': '1959',
      'tracks': ['So What', 'Freddie Freeloader', 'Blue in Green', 'All Blues', 'Flamenco Sketches'],
    },
    {
      'genre': 'Electronic',
      'artist': 'Daft Punk',
      'album': 'Random Access Memories',
      'year': '2013',
      'tracks': ['Give Life Back to Music', 'The Game of Love', 'Giorgio by Moroder', 'Within', 'Instant Crush', 'Lose Yourself to Dance', 'Get Lucky'],
    },
    {
      'genre': 'Soundtrack',
      'artist': 'Hans Zimmer',
      'album': 'Inception',
      'year': '2010',
      'tracks': ['Half Remembered Dream', 'We Built Our Own World', 'Dream Is Collapsing', 'Radical Notion', 'Old Souls', 'Time'],
    },
  ];

  final formats = [
    {'ext': 'mp3', 'codec': 'libmp3lame', 'bitrate': '192k'},
    {'ext': 'flac', 'codec': 'flac', 'bitrate': null},
    {'ext': 'm4a', 'codec': 'aac', 'bitrate': '256k'},
    {'ext': 'ogg', 'codec': 'libvorbis', 'bitrate': '160k'},
    {'ext': 'wav', 'codec': 'pcm_s16le', 'bitrate': null},
    {'ext': 'aiff', 'codec': 'pcm_s16be', 'bitrate': null},
  ];

  final coverSizes = ['150x150', '300x300', '500x500', '800x800', '1200x1200', '1400x1400', 'none'];

  int generatedCount = 0;

  print('Generating audio files in hierarchy...');

  while (generatedCount < targetFileCount) {
    final tIndex = generatedCount % libraryTemplates.length;
    final template = libraryTemplates[tIndex];
    final genre = template['genre'] as String;
    final artist = template['artist'] as String;
    final album = template['album'] as String;
    final year = template['year'] as String;
    final tracks = template['tracks'] as List<String>;
    final trackTitle = tracks[(generatedCount ~/ libraryTemplates.length) % tracks.length];

    final formatConf = formats[generatedCount % formats.length];
    final ext = formatConf['ext'] as String;
    final codec = formatConf['codec'] as String;
    final bitrate = formatConf['bitrate'];

    final coverSize = coverSizes[generatedCount % coverSizes.length];
    final coverPath = coverSize != 'none' ? generatedCovers[coverSize] : null;

    final trackNum = (generatedCount % 12) + 1;
    final trackNumStr = trackNum.toString().padLeft(2, '0');

    // Folder structure: genre/artist/album/
    final subFolder = Directory('${outDir.path}/$genre/$artist/$album');
    if (!subFolder.existsSync()) {
      subFolder.createSync(recursive: true);
    }

    final outFilePath = '${subFolder.path}/$trackNumStr $trackTitle.$ext';

    // Construct ffmpeg arguments
    final durationSeconds = 1 + (generatedCount % 3); // 1 to 3 seconds audio
    final ffmpegArgs = <String>[
      '-y',
      '-f',
      'lavfi',
      '-i',
      'sine=f=${220 + (generatedCount * 10)}:d=$durationSeconds',
    ];

    if (coverPath != null && (ext == 'mp3' || ext == 'flac' || ext == 'm4a')) {
      ffmpegArgs.addAll(['-i', coverPath, '-map', '0:a', '-map', '1:v']);
    }

    ffmpegArgs.addAll(['-c:a', codec]);
    if (bitrate != null) {
      ffmpegArgs.addAll(['-b:a', bitrate]);
    }

    if (coverPath != null && (ext == 'mp3' || ext == 'flac' || ext == 'm4a')) {
      ffmpegArgs.addAll(['-c:v', 'copy', '-disposition:v:0', 'attached_pic']);
    }

    // Add metadata
    ffmpegArgs.addAll([
      '-metadata', 'title=$trackTitle',
      '-metadata', 'artist=$artist',
      '-metadata', 'album=$album',
      '-metadata', 'genre=$genre',
      '-metadata', 'date=$year',
      '-metadata', 'track=$trackNum',
      '-metadata', 'comment=Synthetic test song $generatedCount ($coverSize)',
    ]);

    if (ext == 'mp3') {
      ffmpegArgs.addAll(['-id3v2_version', '3']);
    }

    ffmpegArgs.add(outFilePath);

    final res = await Process.run('ffmpeg', ffmpegArgs);
    if (res.exitCode == 0 && File(outFilePath).existsSync()) {
      generatedCount++;
      final fileSizeKb = (File(outFilePath).lengthSync() / 1024).toStringAsFixed(1);
      final coverInfo = coverSize != 'none' ? 'Cover: $coverSize' : 'No Cover';
      print('[$generatedCount/$targetFileCount] Created: $outFilePath ($fileSizeKb KB, $coverInfo)');
    } else {
      print('Failed to generate file $outFilePath: ${res.stderr}');
    }
  }

  // Cleanup temp cover directory
  try {
    tempCoverDir.deleteSync(recursive: true);
  } catch (_) {}

  print('\n====================================================');
  print('  Successfully generated $generatedCount realistic music files!');
  print('  Location: ${outDir.absolute.path}');
  print('====================================================\n');
}
