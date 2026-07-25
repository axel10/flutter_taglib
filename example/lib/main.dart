import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_taglib/flutter_taglib.dart';
import 'package:file_picker/file_picker.dart';
import 'package:logging/logging.dart';

void main() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    debugPrint(
      '[${record.level.name}] ${record.loggerName}: ${record.message}',
    );
    if (record.error != null) {
      debugPrint('error=${record.error}');
    }
    if (record.stackTrace != null) {
      debugPrint('${record.stackTrace}');
    }
  });
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TagLib Metadata Editor',
      theme: ThemeData.dark().copyWith(
        primaryColor: const Color(0xFF6366F1),
        scaffoldBackgroundColor: const Color(
          0xFF0F172A,
        ), // Slate 900 equivalent
        cardColor: const Color(0xFF1E293B), // Slate 800 equivalent
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1), // Indigo 500
          secondary: Color(0xFF10B981), // Emerald 500
          surface: Color(0xFF1E293B),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF334155), // Slate 700 equivalent
          labelStyle: TextStyle(color: Colors.grey.shade300),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
          ),
        ),
      ),
      home: const MetadataEditorScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MetadataEditorScreen extends StatefulWidget {
  const MetadataEditorScreen({super.key});

  @override
  State<MetadataEditorScreen> createState() => _MetadataEditorScreenState();
}

class _MetadataEditorScreenState extends State<MetadataEditorScreen> {
  String? _filePath;
  String? _fileName;
  String? _fileDirectoryPath;
  PickedAudioFile? _pickedAudioFile;
  TagLibFile? _tagLibFile;
  String? _errorMessage;
  bool _isSaving = false;
  bool _isCheckingDirectoryAccess = false;
  bool _isAuthorizingDirectory = false;
  bool _hasDirectoryWriteAccess = true;
  AuthorizedDirectory? _authorizedDirectory;

  // Controllers for tag fields
  final titleController = TextEditingController();
  final artistController = TextEditingController();
  final albumController = TextEditingController();
  final genreController = TextEditingController();
  final yearController = TextEditingController();
  final trackController = TextEditingController();

  // Cover Art state
  Uint8List? _customCoverBytes;
  String? _customCoverMimeType;
  bool _coverChanged = false;

  // Benchmark state
  int _benchmarkModeIndex = 0; // 0 = Single File, 1 = Directory Scan
  bool _isBenchmarking = false;
  bool _isGeneratingMockLibrary = false;
  double _benchmarkProgress = 0.0;
  String? _benchmarkCurrentFile;
  int _benchmarkIterations = 1000;
  int _benchmarkIsolateCount = 0;
  TagLibAudioPropertiesStyle _benchmarkAudioPropertiesStyle =
      TagLibAudioPropertiesStyle.average;
  final _mockFileCountController = TextEditingController(text: '50');
  _BenchmarkResult? _benchmarkResult;
  _DirectoryBenchmarkResult? _dirBenchmarkResult;

  @override
  void initState() {
    super.initState();
    // Auto-load test asset if available locally
    _loadDemoAsset();
  }

  @override
  void dispose() {
    unawaited(_releaseDirectoryAccess());
    _tagLibFile?.close();
    titleController.dispose();
    artistController.dispose();
    albumController.dispose();
    genreController.dispose();
    yearController.dispose();
    trackController.dispose();
    _mockFileCountController.dispose();
    super.dispose();
  }

  /// Attempts to find and copy the project's test MP3 file as a default demo
  void _loadDemoAsset() {
    // Relative path to test file when running from the example directory
    final localPath = '../test/assets/01 TempleOS Hymn Risen (Remix).mp3';
    final localFile = File(localPath);
    if (localFile.existsSync()) {
      // Create a temporary copy to avoid editing the shared test assets directly
      try {
        final tempDir = Directory.systemTemp.createTempSync(
          'taglib_demo_flutter',
        );
        final tempMp3File = File('${tempDir.path}/demo_song.mp3');
        localFile.copySync(tempMp3File.path);
        _loadFile(tempMp3File.path);
      } catch (e) {
        debugPrint('Failed to copy default demo asset: $e');
      }
    }
  }

  /// Opens the file using TagLibFile and updates the state controllers
  Future<void> _loadFile(
    String path, {
    String? name,
    PickedAudioFile? pickedAudioFile,
  }) async {
    _tagLibFile?.close();
    debugPrint('TagLib _loadFile start path=$path name=$name');

    TagLibFile.resetSupportCache();

    TagLibFile? file;
    try {
      file = await TagLibFile.openAsync(path);
    } catch (e, stackTrace) {
      final diagnostics = await TagLibFile.collectDiagnostics();
      debugPrint('TagLib openAsync threw: $e');
      debugPrint('$stackTrace');
      debugPrint('TagLib diagnostics: $diagnostics');
      rethrow;
    }

    if (file == null) {
      final diagnostics = await TagLibFile.collectDiagnostics();
      debugPrint('TagLib openAsync returned null. diagnostics=$diagnostics');
      setState(() {
        _filePath = null;
        _fileName = null;
        _fileDirectoryPath = null;
        _pickedAudioFile = null;
        _tagLibFile = null;
        _errorMessage =
            'Failed to open file. The audio format may not be supported by TagLib.';
        _hasDirectoryWriteAccess = true;
        _authorizedDirectory = null;
        _isCheckingDirectoryAccess = false;
      });
      return;
    }
    final openedFile = file;

    final sourcePath = pickedAudioFile?.originalPath ?? path;
    final directoryPath = Platform.isIOS && !sourcePath.startsWith('content://')
        ? File(sourcePath).parent.path
        : null;
    AuthorizedDirectory? restoredDirectoryAccess;

    if (Platform.isIOS && directoryPath != null) {
      try {
        restoredDirectoryAccess = await TagLibFile.restoreAuthorizedDirectory(
          directoryPath,
        );
      } catch (e) {
        debugPrint('Failed to restore directory access for $directoryPath: $e');
      }
    }

    if (_authorizedDirectory != null &&
        directoryPath != null &&
        !_isSameDirectoryOrAncestor(
          _authorizedDirectory!.path,
          directoryPath,
        )) {
      await _releaseDirectoryAccess();
    }

    setState(() {
      _filePath = path;
      _pickedAudioFile = pickedAudioFile;
      _fileName =
          name ??
          (path.startsWith('content://')
              ? 'Android Audio File'
              : File(path).path.split(Platform.pathSeparator).last);
      _fileDirectoryPath = directoryPath;
      _tagLibFile = openedFile;
      _errorMessage = null;
      _coverChanged = false;
      _customCoverBytes = openedFile.coverData;
      _customCoverMimeType = openedFile.coverMimeType;
      _hasDirectoryWriteAccess =
          restoredDirectoryAccess != null ||
          !Platform.isIOS ||
          directoryPath == null;
      _authorizedDirectory = restoredDirectoryAccess;
      _isCheckingDirectoryAccess = Platform.isIOS && directoryPath != null;

      titleController.text = openedFile.title;
      artistController.text = openedFile.artist;
      albumController.text = openedFile.album;
      genreController.text = openedFile.genre;
      yearController.text = openedFile.year == 0
          ? ''
          : openedFile.year.toString();
      trackController.text = openedFile.track == 0
          ? ''
          : openedFile.track.toString();
    });

    if (directoryPath != null) {
      final hasAccess = await _checkDirectoryWriteAccess(directoryPath);
      if (!mounted || _filePath != path) return;
      setState(() {
        _hasDirectoryWriteAccess = hasAccess;
        _isCheckingDirectoryAccess = false;
        if (!hasAccess) {
          _errorMessage = '当前原目录没有编辑权限，请先授权该目录。';
        }
      });
    }
  }

  /// Lets the user select an audio file using FilePicker
  Future<void> _pickAudioFile() async {
    try {
      if (Platform.isIOS) {
        final result = await TagLibFile.pickAudioFileForEditing();
        if (result != null) {
          await _loadFile(
            result.path,
            name: result.name,
            pickedAudioFile: result,
          );
        }
        return;
      }

      final result = await FilePicker.pickFiles(type: FileType.audio);

      if (result != null) {
        final file = result.files.single;
        final path = (Platform.isAndroid && file.identifier != null)
            ? file.identifier!
            : file.path;
        if (path != null) {
          await _loadFile(path, name: file.name);
        }
      }
    } catch (e) {
      final diagnostics = await TagLibFile.collectDiagnostics();
      debugPrint('Error picking file: $e');
      debugPrint('TagLib diagnostics during pick: $diagnostics');
      setState(() {
        _errorMessage = 'Error picking file: $e\n$diagnostics';
      });
    }
  }

  Future<bool> _checkDirectoryWriteAccess(String directoryPath) async {
    if (!Platform.isIOS) return true;

    try {
      final directory = Directory(directoryPath);
      if (!await directory.exists()) return false;

      final probeFile = File(
        '${directory.path}${Platform.pathSeparator}.flutter_taglib_write_probe_${DateTime.now().microsecondsSinceEpoch}',
      );
      await probeFile.writeAsBytes(const <int>[], flush: true);
      await probeFile.delete();
      return true;
    } catch (e) {
      debugPrint('Directory access check failed for $directoryPath: $e');
      return false;
    }
  }

  Future<void> _authorizeOriginalDirectory() async {
    if (!Platform.isIOS || _fileDirectoryPath == null) return;

    setState(() {
      _isAuthorizingDirectory = true;
    });

    try {
      final directoryAccess = await TagLibFile.pickAuthorizedDirectory();
      if (directoryAccess == null) return;

      final authorizedPath = directoryAccess.path;
      if (authorizedPath.isEmpty) {
        throw StateError('未能解析授权目录路径。');
      }

      final matchesOriginalDirectory = _isSameDirectoryOrAncestor(
        authorizedPath,
        _fileDirectoryPath!,
      );

      if (!mounted) return;

      if (!matchesOriginalDirectory) {
        final messenger = ScaffoldMessenger.of(context);
        await directoryAccess.dispose();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('请选择当前文件所在的原目录或其上级目录。'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      await _releaseDirectoryAccess();
      if (!mounted) return;
      setState(() {
        _authorizedDirectory = directoryAccess;
        _hasDirectoryWriteAccess = true;
        _isCheckingDirectoryAccess = false;
        _errorMessage = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('目录授权成功，可以直接保存到原文件。'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('目录授权失败：$e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isAuthorizingDirectory = false;
        });
      }
    }
  }

  bool _isSameDirectoryOrAncestor(
    String candidateDirectory,
    String targetDirectory,
  ) {
    final normalizedCandidate = _normalizeDirectoryPath(candidateDirectory);
    final normalizedTarget = _normalizeDirectoryPath(targetDirectory);

    if (normalizedCandidate == normalizedTarget) {
      return true;
    }

    return normalizedTarget.startsWith(
      '$normalizedCandidate${Platform.pathSeparator}',
    );
  }

  String _normalizeDirectoryPath(String path) {
    var normalized = path.replaceAll('\\', Platform.pathSeparator);
    while (normalized.length > 1 &&
        normalized.endsWith(Platform.pathSeparator)) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  Future<void> _releaseDirectoryAccess() async {
    final directoryAccess = _authorizedDirectory;
    if (directoryAccess == null || !Platform.isIOS) return;

    _authorizedDirectory = null;
    try {
      await directoryAccess.dispose();
    } catch (e) {
      debugPrint(
        'Failed to stop accessing directory ${directoryAccess.path}: $e',
      );
    }
  }

  /// Lets the user pick an image file to set as the album cover art
  Future<void> _pickCoverImage() async {
    if (_tagLibFile == null) return;
    try {
      final result = await FilePicker.pickFiles(type: FileType.image);

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final bytes = await File(path).readAsBytes();

        String mimeType = 'image/jpeg';
        if (path.toLowerCase().endsWith('.png')) {
          mimeType = 'image/png';
        } else if (path.toLowerCase().endsWith('.gif')) {
          mimeType = 'image/gif';
        }

        setState(() {
          _customCoverBytes = bytes;
          _customCoverMimeType = mimeType;
          _coverChanged = true;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error picking image: $e')));
    }
  }

  /// Removes the cover art
  void _removeCoverImage() {
    setState(() {
      _customCoverBytes = null;
      _customCoverMimeType = null;
      _coverChanged = true;
    });
  }

  /// Saves the updated metadata back to the audio file
  Future<void> _saveChanges() async {
    if (_tagLibFile == null) return;

    setState(() {
      _isSaving = true;
    });

    try {
      // Request write access (handles Android permissions and reopens in read-write mode)
      final hasWriteAccess = await _tagLibFile!.requestWriteAccess();
      if (!hasWriteAccess) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save: Write permission denied.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        setState(() {
          _isSaving = false;
        });
        return;
      }

      // Set updated tag fields
      _tagLibFile!.title = titleController.text;
      _tagLibFile!.artist = artistController.text;
      _tagLibFile!.album = albumController.text;
      _tagLibFile!.genre = genreController.text;
      _tagLibFile!.year = int.tryParse(yearController.text) ?? 0;
      _tagLibFile!.track = int.tryParse(trackController.text) ?? 0;

      // Set cover art if modified
      if (_coverChanged) {
        _tagLibFile!.setCover(
          data: _customCoverBytes,
          mimeType: _customCoverMimeType ?? 'image/jpeg',
        );
      }

      final success = _tagLibFile!.save();

      if (!mounted) return;

      if (success) {
        if (Platform.isIOS &&
            _pickedAudioFile != null &&
            _pickedAudioFile!.needsCommit) {
          await _pickedAudioFile!.commit();
          if (!mounted) return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Metadata saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        // Reload metadata to confirm it writes/reads correctly
        await _loadFile(
          _tagLibFile!.path,
          name: _fileName,
          pickedAudioFile: _pickedAudioFile,
        );
      } else {
        if (Platform.isIOS && !_hasDirectoryWriteAccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('当前目录没有写权限，请先授权原目录后再保存。'),
              backgroundColor: Colors.redAccent,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to save metadata.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving changes: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _runBenchmark() async {
    if (_tagLibFile == null && _filePath == null) return;
    final filePath = _filePath ?? _tagLibFile?.path;
    if (filePath == null) return;

    final fileName = _fileName;
    final pickedFile = _pickedAudioFile;

    // Temporarily close the UI file handle so Windows OS file locking doesn't block benchmark open calls
    _tagLibFile?.close();
    _tagLibFile = null;

    setState(() {
      _isBenchmarking = true;
      _benchmarkProgress = 0.0;
      _benchmarkResult = null;
    });

    try {
      final iterations = _benchmarkIterations;

      // Warm up phase (10 reads)
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

      final stopwatch = Stopwatch()..start();
      int successCount = 0;
      final batchSize = (iterations / 20).ceil().clamp(1, 100);

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

        if (i % batchSize == 0 || i == iterations - 1) {
          if (!mounted) return;
          setState(() {
            _benchmarkProgress = (i + 1) / iterations;
          });
          await Future<void>.delayed(Duration.zero);
        }
      }

      stopwatch.stop();

      final totalMs = stopwatch.elapsedMilliseconds;
      final totalUs = stopwatch.elapsedMicroseconds;
      final avgMs = totalMs / iterations;
      final avgUs = totalUs / iterations;
      final opsPerSec = (iterations / (totalUs / 1000000.0));

      if (!mounted) return;

      setState(() {
        _benchmarkResult = _BenchmarkResult(
          iterations: iterations,
          successCount: successCount,
          totalMs: totalMs,
          avgMs: avgMs,
          avgUs: avgUs,
          opsPerSec: opsPerSec,
        );
      });
    } finally {
      // Re-open UI file handle for the editor screen
      await _loadFile(filePath, name: fileName, pickedAudioFile: pickedFile);
      if (mounted) {
        setState(() {
          _isBenchmarking = false;
        });
      }
    }
  }

  Future<void> _runDirectoryBenchmark([
    String? preSelectedDir,
    bool useSafScan = false,
  ]) async {
    String? dirPath = preSelectedDir;
    if (dirPath == null) {
      try {
        if (Platform.isAndroid && useSafScan) {
          dirPath = await TagLibFile.pickSafDirectory();
        } else {
          dirPath = await FilePicker.getDirectoryPath();
        }
      } catch (e) {
        debugPrint('Directory pick error: $e');
      }
    }

    if (dirPath == null || dirPath.isEmpty) return;

    final currentFilePath = _filePath ?? _tagLibFile?.path;
    final currentFileName = _fileName;
    final currentPickedFile = _pickedAudioFile;

    // Temporarily close UI file handle so Windows OS file locks don't interfere
    _tagLibFile?.close();
    _tagLibFile = null;

    setState(() {
      _isBenchmarking = true;
      _benchmarkProgress = 0.0;
      _benchmarkCurrentFile = 'Scanning folder structure...';
      _dirBenchmarkResult = null;
    });

    try {
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

      TagLibFile.resetOpenStats();
      final audioFilePaths = <String>[];
      final String scanModeLabel;
      final listStopwatch = Stopwatch()..start();

      if (Platform.isAndroid && useSafScan) {
        scanModeLabel = 'SAF (DocumentTree)';
        setState(() {
          _benchmarkCurrentFile =
              'Scanning SAF DocumentTree via ContentResolver...';
        });
        final safUris = await TagLibFile.listSafDirectory(dirPath);
        audioFilePaths.addAll(safUris);
      } else if (Platform.isAndroid && !useSafScan) {
        scanModeLabel = 'POSIX (Direct FS)';
        setState(() {
          _benchmarkCurrentFile = 'Checking media storage permissions...';
        });
        final granted = await TagLibFile.requestStoragePermission();
        if (!granted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Media/Storage permission denied for POSIX directory scan.',
                ),
              ),
            );
          }
          return;
        }

        // Convert SAF Uri or SAF relative path to physical path if needed
        String posixPath = dirPath;
        if (!posixPath.startsWith('/storage/')) {
          if (posixPath.contains('primary:')) {
            final rel = posixPath.substring(
              posixPath.indexOf('primary:') + 'primary:'.length,
            );
            posixPath =
                '/storage/emulated/0/${rel.startsWith('/') ? rel.substring(1) : rel}';
          } else if (posixPath.startsWith('/sdcard')) {
            posixPath = '/storage/emulated/0${posixPath.substring(7)}';
          }
        }

        final dir = Directory(posixPath);
        if (!dir.existsSync()) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Selected POSIX directory does not exist: $posixPath',
                ),
              ),
            );
          }
          return;
        }

        await for (final entity
            in dir.list(recursive: true, followLinks: false).handleError((e) {
              debugPrint('Directory list item error: $e');
            })) {
          if (entity is File) {
            final ext = entity.path.split('.').last.toLowerCase();
            if (supportedExtensions.contains(ext)) {
              audioFilePaths.add(entity.path);
            }
          }
        }
      } else {
        scanModeLabel = 'POSIX (Standard)';
        final dir = Directory(dirPath);
        if (!dir.existsSync()) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Selected directory does not exist: $dirPath'),
            ),
          );
          return;
        }

        await for (final entity in dir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is File) {
            final ext = entity.path.split('.').last.toLowerCase();
            if (supportedExtensions.contains(ext)) {
              audioFilePaths.add(entity.path);
            }
          }
        }
      }
      listStopwatch.stop();

      if (audioFilePaths.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No supported audio files found ($scanModeLabel) in: $dirPath',
            ),
          ),
        );
        return;
      }

      final totalFiles = audioFilePaths.length;
      int successCount = 0;
      int failCount = 0;
      final formatBreakdown = <String, int>{};
      final sampleSongs = <ScannedSongMetadata>[];

      final stopwatch = Stopwatch()..start();

      final batchResults = await TagLibFile.readBatchAsync(
        audioFilePaths,
        isolateCount: _benchmarkIsolateCount,
        audioPropertiesStyle: _benchmarkAudioPropertiesStyle,
        onProgress: (processed, total) {
          if (!mounted) return;
          setState(() {
            _benchmarkProgress = processed / total;
            _benchmarkCurrentFile =
                'Multi-Isolate Batch Scanning ($processed / $total)...';
          });
        },
      );

      for (final item in batchResults) {
        final ext = item.path.split('.').last.toUpperCase();
        formatBreakdown[ext] = (formatBreakdown[ext] ?? 0) + 1;

        if (item.success) {
          successCount++;
          if (sampleSongs.length < 10) {
            final fileName = item.path.startsWith('content://')
                ? 'SAF Document'
                : item.path.split(Platform.pathSeparator).last;
            sampleSongs.add(
              ScannedSongMetadata(
                path: item.path,
                fileName: fileName,
                title: item.title.trim().isEmpty ? fileName : item.title,
                artist: item.artist.trim().isEmpty
                    ? 'Unknown Artist'
                    : item.artist,
                album: item.album.trim().isEmpty
                    ? 'Unknown Album'
                    : item.album,
                genre: item.genre.trim().isEmpty
                    ? 'Unknown Genre'
                    : item.genre,
                year: item.year,
                track: item.track,
                duration: item.duration,
                bitrate: item.bitrate,
                sampleRate: item.sampleRate,
                channels: item.channels,
                hasCover: item.hasCover,
              ),
            );
          }
        } else {
          failCount++;
        }
      }

      stopwatch.stop();

      final totalMs = stopwatch.elapsedMilliseconds;
      final avgMs = totalFiles > 0 ? totalMs / totalFiles : 0.0;
      final opsPerSec = stopwatch.elapsedMicroseconds > 0
          ? (totalFiles / (stopwatch.elapsedMicroseconds / 1000000.0))
          : 0.0;

      debugPrint('''
========== [SCAN BENCHMARK DIAGNOSTICS] ==========
Scan Mode: $scanModeLabel
Isolates Count: ${_benchmarkIsolateCount == 0 ? 'Auto (${Platform.numberOfProcessors} Cores)' : _benchmarkIsolateCount}
Audio Properties Mode: ${_benchmarkAudioPropertiesStyle.name}
Target Directory: $dirPath
Total Files Found: $totalFiles

[Timing Breakdown]
- Phase 1 (Directory Listing): ${listStopwatch.elapsedMilliseconds} ms
- Phase 2 (Tag Reading Loop):  $totalMs ms
- Total Combined Time:        ${listStopwatch.elapsedMilliseconds + totalMs} ms

[TagLib Parsing Performance]
- Tag Reading Rate: ${opsPerSec.toStringAsFixed(1)} songs/sec (${avgMs.toStringAsFixed(2)} ms/song)
==================================================
''');

      if (!mounted) return;

      setState(() {
        _dirBenchmarkResult = _DirectoryBenchmarkResult(
          directoryPath: dirPath!,
          totalFilesFound: totalFiles,
          successCount: successCount,
          failCount: failCount,
          totalMs: totalMs,
          avgMsPerFile: avgMs,
          opsPerSec: opsPerSec,
          formatBreakdown: formatBreakdown,
          firstSongs: sampleSongs,
          scanMode: scanModeLabel,
        );
      });
    } catch (e) {
      debugPrint('Directory benchmark error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Directory benchmark failed: $e')),
        );
      }
    } finally {
      if (currentFilePath != null) {
        await _loadFile(
          currentFilePath,
          name: currentFileName,
          pickedAudioFile: currentPickedFile,
        );
      }
      if (mounted) {
        setState(() {
          _isBenchmarking = false;
        });
      }
    }
  }

  Future<void> _generateAndScanMockLibrary() async {
    final count = int.tryParse(_mockFileCountController.text) ?? 50;
    if (count <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid song count (> 0).')),
      );
      return;
    }

    setState(() {
      _isGeneratingMockLibrary = true;
      _isBenchmarking = true;
      _benchmarkProgress = 0.0;
      _benchmarkCurrentFile = 'Checking ffmpeg availability...';
    });

    try {
      final ffmpegCheck = await Process.run('ffmpeg', ['-version']);
      if (ffmpegCheck.exitCode != 0) {
        throw Exception('ffmpeg error');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGeneratingMockLibrary = false;
        _isBenchmarking = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'ffmpeg is not available in system PATH. Please install ffmpeg to generate test songs.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    try {
      if (!mounted) return;
      setState(() {
        _benchmarkCurrentFile =
            'Generating $count mock audio files via ffmpeg...';
      });

      final targetDirName = 'benchmark_music_library';
      final rootDir = Directory.current.path.endsWith('example')
          ? File(Directory.current.path).parent.path
          : Directory.current.path;

      final scriptPath =
          '$rootDir${Platform.pathSeparator}example${Platform.pathSeparator}bin${Platform.pathSeparator}generate_benchmark_library.dart';

      final process = await Process.start('dart', [
        'run',
        scriptPath,
        '--dir=$targetDirName',
        '--count=$count',
      ], workingDirectory: rootDir);

      final RegExp lineRegex = RegExp(r'\[(\d+)/(\d+)\] Created:\s*(.*)');
      final stderrBuffer = StringBuffer();

      process.stderr
          .transform(utf8.decoder)
          .listen((data) => stderrBuffer.write(data));

      final stdoutLines = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in stdoutLines) {
        final match = lineRegex.firstMatch(line);
        if (match != null) {
          final current = int.tryParse(match.group(1) ?? '') ?? 0;
          final total = int.tryParse(match.group(2) ?? '') ?? count;
          final fullPath = match.group(3) ?? '';
          final fileName = fullPath
              .split('(')
              .first
              .trim()
              .split(Platform.pathSeparator)
              .last;
          if (mounted) {
            setState(() {
              _benchmarkProgress = (current / total).clamp(0.0, 1.0);
              _benchmarkCurrentFile =
                  '[$current/$total] Generating $fileName...';
            });
          }
        } else if (line.contains('Generating cover art assets')) {
          if (mounted) {
            setState(() {
              _benchmarkCurrentFile = 'Generating cover art assets...';
            });
          }
        }
      }

      final exitCode = await process.exitCode;
      if (exitCode != 0) {
        debugPrint('Generator error output: $stderrBuffer');
        throw Exception('Generation script failed: $stderrBuffer');
      }

      String? mockLibPath;
      for (final p in [
        'benchmark_music_library',
        '../benchmark_music_library',
        'example/benchmark_music_library',
      ]) {
        if (Directory(p).existsSync()) {
          mockLibPath = p;
          break;
        }
      }

      if (mockLibPath != null) {
        await _runDirectoryBenchmark(mockLibPath);
      }
    } catch (e) {
      debugPrint('Generation error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate mock library: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingMockLibrary = false;
          _isBenchmarking = false;
        });
      }
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String threeDigits(int n) => n.toString().padLeft(3, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    final milliseconds = threeDigits(duration.inMilliseconds.remainder(1000));
    return '$minutes:$seconds.$milliseconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TagLib Metadata Editor'),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'Open Audio File',
            onPressed: _pickAudioFile,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top banner or warning
            if (_errorMessage != null)
              Container(
                color: Colors.redAccent.withAlpha(51),
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                width: double.infinity,
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  ],
                ),
              ),

            Expanded(
              child: _tagLibFile == null
                  ? _buildEmptyState()
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFileInfoBanner(),
                          const SizedBox(height: 16),
                          _buildDirectoryAuthorizationBanner(),
                          const SizedBox(height: 24),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              if (constraints.maxWidth > 700) {
                                // Side-by-side layout for large screens
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: _buildCoverArtSection(),
                                    ),
                                    const SizedBox(width: 32),
                                    Expanded(
                                      flex: 3,
                                      child: _buildFormSection(),
                                    ),
                                  ],
                                );
                              } else {
                                // Vertical layout for small screens
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Center(
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 300,
                                        ),
                                        child: SizedBox(
                                          width: double.infinity,
                                          child: _buildCoverArtSection(),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 32),
                                    _buildFormSection(),
                                  ],
                                );
                              }
                            },
                          ),
                          const SizedBox(height: 24),
                          _buildAudioPropertiesSection(),
                          const SizedBox(height: 24),
                          _buildBenchmarkSection(),
                          const SizedBox(
                            height: 100,
                          ), // Padding for the floating save button
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: _tagLibFile != null
          ? FloatingActionButton.extended(
              onPressed: _isSaving ? null : _saveChanges,
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.save),
              label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
            )
          : null,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF334155), width: 2),
            ),
            child: Icon(
              Icons.music_note,
              size: 72,
              color: Colors.indigo.shade400,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'No Audio File Loaded',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Select a music file (MP3, FLAC, M4A, WAV, OGG) to view and edit metadata.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _pickAudioFile,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.folder_open),
            label: const Text(
              'Select Audio File',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileInfoBanner() {
    final fileName = _fileName ?? '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 520;

          final fileDetails = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fileName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                _pickedAudioFile?.originalPath ?? _filePath ?? '',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                overflow: TextOverflow.fade,
              ),
            ],
          );

          final actionButton = TextButton.icon(
            onPressed: _pickAudioFile,
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('Change File'),
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.audio_file,
                      color: Colors.indigo.shade300,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: fileDetails),
                  ],
                ),
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: actionButton),
              ],
            );
          }

          return Row(
            children: [
              Icon(Icons.audio_file, color: Colors.indigo.shade300, size: 28),
              const SizedBox(width: 16),
              Expanded(child: fileDetails),
              const SizedBox(width: 12),
              actionButton,
            ],
          );
        },
      ),
    );
  }

  Widget _buildDirectoryAuthorizationBanner() {
    if (!Platform.isIOS || _fileDirectoryPath == null) {
      return const SizedBox.shrink();
    }

    if (_isCheckingDirectoryAccess) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('正在检查原目录权限...'),
          ],
        ),
      );
    }

    if (_hasDirectoryWriteAccess) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF3B1D1D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB91C1C)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline, color: Color(0xFFF87171)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '当前原目录没有编辑权限',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFCA5A5),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '文件所在目录：$_fileDirectoryPath\n先授权这个目录，才能直接保存回原文件。',
                  style: TextStyle(
                    color: Colors.red.shade100,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _isAuthorizingDirectory
                      ? null
                      : _authorizeOriginalDirectory,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF97316),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: _isAuthorizingDirectory
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.folder_shared),
                  label: Text(_isAuthorizingDirectory ? '正在授权...' : '授权原目录'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverArtSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Cover Image
            AspectRatio(
              aspectRatio: 1.0,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: _customCoverBytes != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          _customCoverBytes!,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.album,
                            size: 80,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No Cover Art',
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 20),
            if (_customCoverBytes != null) ...[
              Text(
                'Mime-Type: ${_customCoverMimeType ?? "Unknown"}',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
              ),
              Text(
                'Size: ${(_customCoverBytes!.length / 1024).toStringAsFixed(1)} KB',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
              ),
              const SizedBox(height: 12),
            ],
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton.icon(
                  onPressed: _pickCoverImage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF334155),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.image, size: 18),
                  label: const Text('Change Art'),
                ),
                if (_customCoverBytes != null)
                  OutlinedButton.icon(
                    onPressed: _removeCoverImage,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Remove'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Metadata Info',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF818CF8),
              ),
            ),
            const Divider(color: Color(0xFF334155), height: 24),
            TextFormField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Song Title',
                prefixIcon: Icon(Icons.title),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: artistController,
              decoration: const InputDecoration(
                labelText: 'Artist',
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: albumController,
              decoration: const InputDecoration(
                labelText: 'Album',
                prefixIcon: Icon(Icons.album),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: genreController,
              decoration: const InputDecoration(
                labelText: 'Genre',
                prefixIcon: Icon(Icons.category),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: yearController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Year',
                      prefixIcon: Icon(Icons.calendar_today),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: trackController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Track #',
                      prefixIcon: Icon(Icons.music_note),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioPropertiesSection() {
    if (_tagLibFile == null) return const SizedBox.shrink();

    final props = [
      _AudioPropertyItem(
        label: 'Duration',
        value: _formatDuration(_tagLibFile!.duration),
        icon: Icons.timer_outlined,
      ),
      _AudioPropertyItem(
        label: 'Bitrate',
        value: '${_tagLibFile!.bitrate} kbps',
        icon: Icons.speed_outlined,
      ),
      _AudioPropertyItem(
        label: 'Sample Rate',
        value: '${(_tagLibFile!.sampleRate / 1000).toStringAsFixed(1)} kHz',
        icon: Icons.graphic_eq_outlined,
      ),
      _AudioPropertyItem(
        label: 'Channels',
        value: _tagLibFile!.channels == 2
            ? 'Stereo (2ch)'
            : _tagLibFile!.channels == 1
            ? 'Mono (1ch)'
            : '${_tagLibFile!.channels} ch',
        icon: Icons.hearing_outlined,
      ),
    ];

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Technical Properties',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF34D399),
              ),
            ),
            const Divider(color: Color(0xFF334155), height: 24),
            LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 360;

                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: isCompact ? constraints.maxWidth : 220,
                    mainAxisExtent: 80,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                  ),
                  itemCount: props.length,
                  itemBuilder: (context, index) {
                    final prop = props[index];
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            prop.icon,
                            color: const Color(0xFF34D399),
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  prop.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.grey.shade400,
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  prop.value,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBenchmarkSection() {
    if (_tagLibFile == null) return const SizedBox.shrink();

    // Check if generated benchmark_library exists
    String? localMockLibPath;
    for (final path in [
      'benchmark_music_library',
      '../benchmark_music_library',
      'example/benchmark_music_library',
    ]) {
      if (Directory(path).existsSync()) {
        localMockLibPath = path;
        break;
      }
    }

    final singleResult = _benchmarkResult;
    final dirResult = _dirBenchmarkResult;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 500;

            final modeSelector = SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  label: Text('Single File'),
                  icon: Icon(Icons.audio_file, size: 16),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('Directory Scan'),
                  icon: Icon(Icons.folder_copy, size: 16),
                ),
              ],
              selected: {_benchmarkModeIndex},
              onSelectionChanged: _isBenchmarking
                  ? null
                  : (newSelection) {
                      setState(() {
                        _benchmarkModeIndex = newSelection.first;
                      });
                    },
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Mode selector row / column
                if (isCompact) ...[
                  const Row(
                    children: [
                      Icon(Icons.speed, color: Color(0xFF6366F1), size: 24),
                      SizedBox(width: 8),
                      Text(
                        'Performance Benchmark',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF818CF8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, child: modeSelector),
                ] else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.speed, color: Color(0xFF6366F1), size: 24),
                          SizedBox(width: 8),
                          Text(
                            'Performance Benchmark',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF818CF8),
                            ),
                          ),
                        ],
                      ),
                      modeSelector,
                    ],
                  ),
                ],
                const Divider(color: Color(0xFF334155), height: 24),

                if (_benchmarkModeIndex == 0) ...[
                  // Single file benchmark UI
                  if (isCompact) ...[
                    Text(
                      'Repeatedly open, parse metadata, and close the current song $_benchmarkIterations times to benchmark raw single-file throughput.',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButton<int>(
                      value: _benchmarkIterations,
                      dropdownColor: const Color(0xFF1E293B),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(value: 100, child: Text('100 Reads')),
                        DropdownMenuItem(
                          value: 1000,
                          child: Text('1,000 Reads'),
                        ),
                        DropdownMenuItem(
                          value: 5000,
                          child: Text('5,000 Reads'),
                        ),
                      ],
                      onChanged: _isBenchmarking
                          ? null
                          : (val) {
                              if (val != null) {
                                setState(() {
                                  _benchmarkIterations = val;
                                });
                              }
                            },
                    ),
                  ] else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Repeatedly open, parse metadata, and close the current song $_benchmarkIterations times to benchmark raw single-file throughput.',
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        DropdownButton<int>(
                          value: _benchmarkIterations,
                          dropdownColor: const Color(0xFF1E293B),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                          underline: const SizedBox.shrink(),
                          items: const [
                            DropdownMenuItem(
                              value: 100,
                              child: Text('100 Reads'),
                            ),
                            DropdownMenuItem(
                              value: 1000,
                              child: Text('1,000 Reads'),
                            ),
                            DropdownMenuItem(
                              value: 5000,
                              child: Text('5,000 Reads'),
                            ),
                          ],
                          onChanged: _isBenchmarking
                              ? null
                              : (val) {
                                  if (val != null) {
                                    setState(() {
                                      _benchmarkIterations = val;
                                    });
                                  }
                                },
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (_isBenchmarking) ...[
                    LinearProgressIndicator(
                      value: _benchmarkProgress,
                      backgroundColor: const Color(0xFF334155),
                      color: const Color(0xFF6366F1),
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Running benchmark: ${(_benchmarkProgress * 100).toStringAsFixed(0)}% (${(_benchmarkProgress * _benchmarkIterations).toInt()} / $_benchmarkIterations)',
                      style: TextStyle(
                        color: Colors.indigo.shade200,
                        fontSize: 13,
                      ),
                    ),
                  ] else ...[
                    ElevatedButton.icon(
                      onPressed: _runBenchmark,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.play_arrow, size: 20),
                      label: Text(
                        'Run Benchmark ($_benchmarkIterations Reads)',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                  if (singleResult != null && !_isBenchmarking) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Benchmark Results (Single File)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Color(0xFF10B981),
                            ),
                          ),
                          const SizedBox(height: 12),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: isCompact ? 140 : 200,
                                  mainAxisExtent: 64,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                ),
                            itemCount: 3,
                            itemBuilder: (context, index) {
                              switch (index) {
                                case 0:
                                  return _buildMetricTile(
                                    'Total Time',
                                    '${singleResult.totalMs} ms',
                                    Icons.timer,
                                  );
                                case 1:
                                  return _buildMetricTile(
                                    'Avg Time / Read',
                                    '${singleResult.avgMs.toStringAsFixed(3)} ms',
                                    Icons.av_timer,
                                  );
                                case 2:
                                default:
                                  return _buildMetricTile(
                                    'Throughput',
                                    '${singleResult.opsPerSec.toStringAsFixed(0)} / sec',
                                    Icons.flash_on,
                                  );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ] else ...[
                  // Directory benchmark UI
                  Text(
                    'Recursively scan a directory tree containing music files of various formats (MP3, FLAC, M4A, WAV, etc.) and cover sizes.',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  if (_isBenchmarking) ...[
                    LinearProgressIndicator(
                      value: _benchmarkProgress,
                      backgroundColor: const Color(0xFF334155),
                      color: const Color(0xFF10B981),
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Scanning directory: ${(_benchmarkProgress * 100).toStringAsFixed(0)}% ${_benchmarkCurrentFile ?? ""}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFA7F3D0),
                        fontSize: 13,
                      ),
                    ),
                  ] else ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            SizedBox(
                              width: isCompact ? double.infinity : 130,
                              child: TextFormField(
                                controller: _mockFileCountController,
                                keyboardType: TextInputType.number,
                                enabled: !_isBenchmarking,
                                decoration: const InputDecoration(
                                  labelText: 'Mock Songs',
                                  hintText: '50',
                                  prefixIcon: Icon(Icons.numbers, size: 18),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: isCompact ? double.infinity : 150,
                              child: DropdownButtonFormField<int>(
                                initialValue: _benchmarkIsolateCount,
                                decoration: const InputDecoration(
                                  labelText: '并发 Isolates',
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                ),
                                items: [0, 1, 2, 4, 8, 16].map((count) {
                                  final label = count == 0
                                      ? 'Auto (${Platform.numberOfProcessors}核)'
                                      : '$count Isolates';
                                  return DropdownMenuItem<int>(
                                    value: count,
                                    child: Text(label),
                                  );
                                }).toList(),
                                onChanged: _isBenchmarking
                                    ? null
                                    : (val) {
                                        if (val != null) {
                                          setState(() {
                                            _benchmarkIsolateCount = val;
                                          });
                                        }
                                      },
                              ),
                            ),
                            SizedBox(
                              width: isCompact ? double.infinity : 150,
                              child:
                                  DropdownButtonFormField<
                                    TagLibAudioPropertiesStyle
                                  >(
                                    initialValue:
                                        _benchmarkAudioPropertiesStyle,
                                    decoration: const InputDecoration(
                                      labelText: 'TagLib 模式',
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                    ),
                                    items: TagLibAudioPropertiesStyle.values
                                        .map((style) {
                                          return DropdownMenuItem<
                                            TagLibAudioPropertiesStyle
                                          >(
                                            value: style,
                                            child: Text(
                                              style.name.toUpperCase(),
                                            ),
                                          );
                                        })
                                        .toList(),
                                    onChanged: _isBenchmarking
                                        ? null
                                        : (val) {
                                            if (val != null) {
                                              setState(() {
                                                _benchmarkAudioPropertiesStyle =
                                                    val;
                                              });
                                            }
                                          },
                                  ),
                            ),
                            ElevatedButton.icon(
                              onPressed: _isBenchmarking
                                  ? null
                                  : _generateAndScanMockLibrary,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: _isGeneratingMockLibrary
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.auto_mode, size: 18),
                              label: Text(
                                _isGeneratingMockLibrary
                                    ? 'Generating...'
                                    : 'Generate & Scan Mock Library',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            if (Platform.isAndroid) ...[
                              ElevatedButton.icon(
                                onPressed: () =>
                                    _runDirectoryBenchmark(null, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0284C7),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                icon: const Icon(Icons.folder_open, size: 18),
                                label: const Text(
                                  'SAF 目录扫描',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: () =>
                                    _runDirectoryBenchmark(null, false),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                icon: const Icon(Icons.security, size: 18),
                                label: const Text(
                                  'POSIX 权限扫描',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ] else ...[
                              ElevatedButton.icon(
                                onPressed: () => _runDirectoryBenchmark(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                icon: const Icon(Icons.folder_open, size: 18),
                                label: const Text(
                                  'Select Any Local Folder...',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                            if (localMockLibPath != null)
                              OutlinedButton.icon(
                                onPressed: () =>
                                    _runDirectoryBenchmark(localMockLibPath),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF34D399),
                                  side: const BorderSide(
                                    color: Color(0xFF34D399),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                icon: const Icon(Icons.bolt, size: 18),
                                label: const Text('Scan Existing Mock Library'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ],
                  if (dirResult != null && !_isBenchmarking) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'Directory Scan Results',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: Color(0xFF10B981),
                                    ),
                                  ),
                                  if (dirResult.scanMode != null) ...[
                                    const SizedBox(width: 8),
                                    Chip(
                                      label: Text(
                                        dirResult.scanMode!,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      backgroundColor: const Color(0xFF0284C7),
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                    ),
                                  ],
                                ],
                              ),
                              Text(
                                '${dirResult.successCount} passed / ${dirResult.failCount} failed',
                                style: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            dirResult.directoryPath,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 16),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: isCompact ? 140 : 180,
                                  mainAxisExtent: 64,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                ),
                            itemCount: 4,
                            itemBuilder: (context, index) {
                              switch (index) {
                                case 0:
                                  return _buildMetricTile(
                                    'Total Files',
                                    '${dirResult.totalFilesFound}',
                                    Icons.library_music,
                                  );
                                case 1:
                                  return _buildMetricTile(
                                    'Total Time',
                                    '${dirResult.totalMs} ms',
                                    Icons.timer,
                                  );
                                case 2:
                                  return _buildMetricTile(
                                    'Avg / File',
                                    '${dirResult.avgMsPerFile.toStringAsFixed(2)} ms',
                                    Icons.av_timer,
                                  );
                                case 3:
                                default:
                                  return _buildMetricTile(
                                    'Scan Speed',
                                    '${dirResult.opsPerSec.toStringAsFixed(0)} / sec',
                                    Icons.flash_on,
                                  );
                              }
                            },
                          ),
                          if (dirResult.formatBreakdown.isNotEmpty) ...[
                            const Divider(color: Color(0xFF334155), height: 24),
                            const Text(
                              'Format Distribution:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: dirResult.formatBreakdown.entries.map((
                                entry,
                              ) {
                                return Chip(
                                  label: Text(
                                    '${entry.key}: ${entry.value}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white,
                                    ),
                                  ),
                                  backgroundColor: const Color(0xFF1E293B),
                                  side: const BorderSide(
                                    color: Color(0xFF475569),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                );
                              }).toList(),
                            ),
                          ],
                          if (dirResult.firstSongs.isNotEmpty)
                            _buildScannedSongsList(dirResult.firstSongs),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildScannedSongsList(List<ScannedSongMetadata> songs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: Color(0xFF334155), height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Top ${songs.length} Scanned Songs Metadata',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF818CF8),
              ),
            ),
            Text(
              'First 10 items preview',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: songs.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final song = songs[index];
            final ext = song.fileName.contains('.')
                ? song.fileName.split('.').last.toUpperCase()
                : 'AUDIO';
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '#${index + 1}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: const Color(0xFF818CF8),
                        ),
                        onPressed: () {
                          _loadFile(song.path, name: song.fileName);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Loaded "${song.title}" into Metadata Editor',
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        icon: const Icon(Icons.edit, size: 14),
                        label: const Text(
                          'Edit',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.person, size: 13, color: Colors.grey.shade400),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${song.artist} • ${song.album}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade300,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _buildChip(ext, const Color(0xFF0284C7)),
                      _buildChip(
                        _formatDuration(song.duration),
                        const Color(0xFF334155),
                      ),
                      _buildChip(
                        '${song.bitrate} kbps',
                        const Color(0xFF334155),
                      ),
                      _buildChip(
                        '${(song.sampleRate / 1000).toStringAsFixed(1)} kHz',
                        const Color(0xFF334155),
                      ),
                      _buildChip(
                        song.channels == 2 ? 'Stereo' : '${song.channels}ch',
                        const Color(0xFF334155),
                      ),
                      if (song.genre != 'Unknown Genre')
                        _buildChip(song.genre, const Color(0xFF10B981)),
                      if (song.year > 0)
                        _buildChip('${song.year}', const Color(0xFF475569)),
                      if (song.hasCover)
                        _buildChip('🎨 Cover', const Color(0xFF8B5CF6)),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildMetricTile(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF10B981), size: 20),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ],
    );
  }
}

class _AudioPropertyItem {
  final String label;
  final String value;
  final IconData icon;

  _AudioPropertyItem({
    required this.label,
    required this.value,
    required this.icon,
  });
}

class _BenchmarkResult {
  final int iterations;
  final int successCount;
  final int totalMs;
  final double avgMs;
  final double avgUs;
  final double opsPerSec;

  _BenchmarkResult({
    required this.iterations,
    required this.successCount,
    required this.totalMs,
    required this.avgMs,
    required this.avgUs,
    required this.opsPerSec,
  });
}

class ScannedSongMetadata {
  final String path;
  final String fileName;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final int year;
  final int track;
  final Duration duration;
  final int bitrate;
  final int sampleRate;
  final int channels;
  final bool hasCover;

  ScannedSongMetadata({
    required this.path,
    required this.fileName,
    required this.title,
    required this.artist,
    required this.album,
    required this.genre,
    required this.year,
    required this.track,
    required this.duration,
    required this.bitrate,
    required this.sampleRate,
    required this.channels,
    required this.hasCover,
  });
}

class _DirectoryBenchmarkResult {
  final String directoryPath;
  final int totalFilesFound;
  final int successCount;
  final int failCount;
  final int totalMs;
  final double avgMsPerFile;
  final double opsPerSec;
  final Map<String, int> formatBreakdown;
  final List<ScannedSongMetadata> firstSongs;
  final String? scanMode;

  _DirectoryBenchmarkResult({
    required this.directoryPath,
    required this.totalFilesFound,
    required this.successCount,
    required this.failCount,
    required this.totalMs,
    required this.avgMsPerFile,
    required this.opsPerSec,
    required this.formatBreakdown,
    this.firstSongs = const [],
    this.scanMode,
  });
}
