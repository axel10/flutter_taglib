import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_taglib/flutter_taglib.dart';
import 'package:file_picker/file_picker.dart';

void main() {
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
        scaffoldBackgroundColor: const Color(0xFF0F172A), // Slate 900 equivalent
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
  TagLibFile? _tagLibFile;
  String? _errorMessage;
  bool _isSaving = false;

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

  @override
  void initState() {
    super.initState();
    // Auto-load test asset if available locally
    _loadDemoAsset();
  }

  @override
  void dispose() {
    _tagLibFile?.close();
    titleController.dispose();
    artistController.dispose();
    albumController.dispose();
    genreController.dispose();
    yearController.dispose();
    trackController.dispose();
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
        final tempDir = Directory.systemTemp.createTempSync('taglib_demo_flutter');
        final tempMp3File = File('${tempDir.path}/demo_song.mp3');
        localFile.copySync(tempMp3File.path);
        _loadFile(tempMp3File.path);
      } catch (e) {
        debugPrint('Failed to copy default demo asset: $e');
      }
    }
  }

  /// Opens the file using TagLibFile and updates the state controllers
  void _loadFile(String path, {String? name}) {
    _tagLibFile?.close();

    final file = TagLibFile.open(path);
    if (file == null) {
      setState(() {
        _filePath = null;
        _fileName = null;
        _tagLibFile = null;
        _errorMessage = 'Failed to open file. The audio format may not be supported by TagLib.';
      });
      return;
    }

    setState(() {
      _filePath = path;
      _fileName = name ?? (path.startsWith('content://') ? 'Android Audio File' : File(path).path.split(Platform.pathSeparator).last);
      _tagLibFile = file;
      _errorMessage = null;
      _coverChanged = false;
      _customCoverBytes = file.coverData;
      _customCoverMimeType = file.coverMimeType;

      titleController.text = file.title;
      artistController.text = file.artist;
      albumController.text = file.album;
      genreController.text = file.genre;
      yearController.text = file.year == 0 ? '' : file.year.toString();
      trackController.text = file.track == 0 ? '' : file.track.toString();
    });
  }

  /// Lets the user select an audio file using FilePicker
  Future<void> _pickAudioFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (result != null) {
        final file = result.files.single;
        final path = (Platform.isAndroid && file.identifier != null)
            ? file.identifier!
            : file.path;
        if (path != null) {
          _loadFile(path, name: file.name);
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error picking file: $e';
      });
    }
  }

  /// Lets the user pick an image file to set as the album cover art
  Future<void> _pickCoverImage() async {
    if (_tagLibFile == null) return;
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e')),
      );
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
      var targetPath = _filePath!;

      // Request write permission on Android for content URIs / storage paths
      if (Platform.isAndroid && _filePath != null) {
        final grantedUri = await TagLibFile.requestWritePermission(_filePath!);
        if (grantedUri == null) {
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
        targetPath = grantedUri;
      }

      // Close the existing read-only file and reopen in write mode
      _tagLibFile?.close();
      final writableFile = TagLibFile.open(targetPath);
      if (writableFile == null) {
        throw Exception('Failed to reopen file in write mode.');
      }
      _tagLibFile = writableFile;

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Metadata saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        // Reload metadata to confirm it writes/reads correctly
        if (_filePath != null) {
          _loadFile(_filePath!, name: _fileName);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save metadata.'),
            backgroundColor: Colors.redAccent,
          ),
        );
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

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
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
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                width: double.infinity,
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent))),
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
                          const SizedBox(height: 24),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              if (constraints.maxWidth > 700) {
                                // Side-by-side layout for large screens
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 2, child: _buildCoverArtSection()),
                                    const SizedBox(width: 32),
                                    Expanded(flex: 3, child: _buildFormSection()),
                                  ],
                                );
                              } else {
                                // Vertical layout for small screens
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Center(child: SizedBox(width: 300, child: _buildCoverArtSection())),
                                    const SizedBox(height: 32),
                                    _buildFormSection(),
                                  ],
                                );
                              }
                            },
                          ),
                          const SizedBox(height: 24),
                          _buildAudioPropertiesSection(),
                          const SizedBox(height: 100), // Padding for the floating save button
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
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
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
            child: Icon(Icons.music_note, size: 72, color: Colors.indigo.shade400),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.folder_open),
            label: const Text('Select Audio File', style: TextStyle(fontWeight: FontWeight.bold)),
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
      child: Row(
        children: [
          Icon(Icons.audio_file, color: Colors.indigo.shade300, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _filePath ?? '',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                  overflow: TextOverflow.fade,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: _pickAudioFile,
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('Change File'),
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
                          Icon(Icons.album, size: 80, color: Colors.grey.shade600),
                          const SizedBox(height: 12),
                          Text('No Cover Art', style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _pickCoverImage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF334155),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF818CF8)),
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
      _AudioPropertyItem(label: 'Duration', value: _formatDuration(_tagLibFile!.duration), icon: Icons.timer_outlined),
      _AudioPropertyItem(label: 'Bitrate', value: '${_tagLibFile!.bitrate} kbps', icon: Icons.speed_outlined),
      _AudioPropertyItem(label: 'Sample Rate', value: '${(_tagLibFile!.sampleRate / 1000).toStringAsFixed(1)} kHz', icon: Icons.graphic_eq_outlined),
      _AudioPropertyItem(label: 'Channels', value: _tagLibFile!.channels == 2 ? 'Stereo (2ch)' : _tagLibFile!.channels == 1 ? 'Mono (1ch)' : '${_tagLibFile!.channels} ch', icon: Icons.hearing_outlined),
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
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF34D399)),
            ),
            const Divider(color: Color(0xFF334155), height: 24),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 2.8,
              ),
              itemCount: props.length,
              itemBuilder: (context, index) {
                final prop = props[index];
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Row(
                    children: [
                      Icon(prop.icon, color: const Color(0xFF34D399), size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(prop.label, style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                            const SizedBox(height: 2),
                            Text(prop.value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioPropertyItem {
  final String label;
  final String value;
  final IconData icon;

  _AudioPropertyItem({required this.label, required this.value, required this.icon});
}
