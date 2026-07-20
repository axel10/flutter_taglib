// ignore_for_file: avoid_print

import 'dart:io';
import 'package:test/test.dart';
import 'package:flutter_taglib/flutter_taglib.dart';

void main() {
  group('TagLib Basic Reading', () {
    test('Read MP3 metadata', () {
      final file = TagLibFile.open('test/assets/01 TempleOS Hymn Risen (Remix).mp3');
      expect(file, isNotNull);
      if (file != null) {
        print('MP3 Title: "${file.title}"');
        print('MP3 Artist: "${file.artist}"');
        print('MP3 Album: "${file.album}"');
        print('MP3 Duration: ${file.duration}');
        print('MP3 Bitrate: ${file.bitrate} kbps');
        print('MP3 SampleRate: ${file.sampleRate} Hz');
        print('MP3 Channels: ${file.channels}');
        
        print('MP3 BitrateMode: ${file.bitrateMode}');
        print('MP3 AudioInfo: ${file.audioInfo}');
        
        expect(file.title, isNotEmpty);
        expect(file.artist, isNotEmpty);
        expect(file.duration.inSeconds, greaterThan(0));
        expect(file.bitrateMode, anyOf('CBR', 'VBR'));
        expect(file.audioInfo.duration, equals(file.duration));
        expect(file.audioInfo.bitrate, equals(file.bitrate));
        expect(file.audioInfo.bitrateMode, equals(file.bitrateMode));
        file.close();
      }
    });

    test('Read FLAC metadata', () {
      final file = TagLibFile.open('test/assets/01 TempleOS Hymn Risen (Remix).flac');
      expect(file, isNotNull);
      if (file != null) {
        print('FLAC Title: "${file.title}"');
        print('FLAC Artist: "${file.artist}"');
        print('FLAC Duration: ${file.duration}');
        print('FLAC BitrateMode: ${file.bitrateMode}');
        print('FLAC AudioInfo: ${file.audioInfo}');
        expect(file.title, isNotEmpty);
        expect(file.artist, isNotEmpty);
        expect(file.bitrateMode, equals('VBR'));
        expect(file.audioInfo.bitrateMode, equals('VBR'));
        file.close();
      }
    });

    test('Read M4A metadata', () {
      final file = TagLibFile.open('test/assets/01 TempleOS Hymn Risen (Remix).m4a');
      expect(file, isNotNull);
      if (file != null) {
        print('M4A Title: "${file.title}"');
        print('M4A Artist: "${file.artist}"');
        expect(file.title, isNotEmpty);
        file.close();
      }
    });

    test('Read OGG metadata', () {
      final file = TagLibFile.open('test/assets/01 TempleOS Hymn Risen (Remix).ogg');
      expect(file, isNotNull);
      if (file != null) {
        print('OGG Title: "${file.title}"');
        expect(file.title, isNotEmpty);
        file.close();
      }
    });

    test('Read WAV metadata', () {
      final file = TagLibFile.open('test/assets/01 TempleOS Hymn Risen (Remix).wav');
      expect(file, isNotNull);
      if (file != null) {
        print('WAV Title: "${file.title}"');
        print('WAV BitrateMode: ${file.bitrateMode}');
        print('WAV AudioInfo: ${file.audioInfo}');
        expect(file.title, isNotEmpty);
        expect(file.bitrateMode, equals('CBR'));
        expect(file.audioInfo.bitrateMode, equals('CBR'));
        file.close();
      }
    });

    test('Read APE metadata', () {
      final file = TagLibFile.open('test/assets/01 TempleOS Hymn Risen (Remix).ape');
      expect(file, isNotNull);
      if (file != null) {
        print('APE Title: "${file.title}"');
        print('APE Artist: "${file.artist}"');
        print('APE Album: "${file.album}"');
        print('APE Duration: ${file.duration}');
        print('APE SampleRate: ${file.sampleRate} Hz');
        print('APE Channels: ${file.channels}');
        expect(file.title, equals('TempleOS Hymn Risen (Remix)'));
        expect(file.artist, equals('Terry A. Davis'));
        expect(file.album, equals('TempleOS Hymns'));
        expect(file.genre, equals('Electronic'));
        expect(file.year, equals(2020));
        expect(file.track, equals(1));
        expect(file.duration.inSeconds, equals(3));
        expect(file.sampleRate, equals(44100));
        expect(file.channels, equals(2));
        file.close();
      }
    });

    test('Read AIFF metadata', () {
      final file = TagLibFile.open('test/assets/01 TempleOS Hymn Risen (Remix).aiff');
      expect(file, isNotNull);
      if (file != null) {
        print('AIFF Title: "${file.title}"');
        print('AIFF Artist: "${file.artist}"');
        print('AIFF Album: "${file.album}"');
        print('AIFF Duration: ${file.duration}');
        print('AIFF SampleRate: ${file.sampleRate} Hz');
        print('AIFF Channels: ${file.channels}');
        expect(file.title, equals('TempleOS Hymn Risen (Remix)'));
        expect(file.artist, equals('Terry A. Davis'));
        expect(file.album, equals('TempleOS Hymns'));
        expect(file.genre, equals('Electronic'));
        expect(file.year, equals(2020));
        expect(file.track, equals(1));
        expect(file.duration.inSeconds, equals(3));
        expect(file.sampleRate, equals(44100));
        expect(file.channels, equals(2));
        file.close();
      }
    });
  });

  group('TagLib Format Detection', () {
    final expectedFormats = <String, Object>{
      'mp3': 'MP3',
      'flac': 'FLAC',
      'ogg': 'VORBIS',
      'opus': 'OPUS',
      'wav': 'WAV',
      'aiff': 'AIFF',
      // The container reports its codec, which depends on how the asset was encoded.
      'm4a': anyOf('AAC', 'ALAC', 'MP4'),
    };

    for (final entry in expectedFormats.entries) {
      test('Detect ${entry.key.toUpperCase()} format', () {
        final path =
            'test/assets/01 TempleOS Hymn Risen (Remix).${entry.key}';
        if (!File(path).existsSync()) {
          markTestSkipped('Missing asset: $path');
          return;
        }

        final file = TagLibFile.open(path);
        expect(file, isNotNull);
        if (file != null) {
          print('${entry.key.toUpperCase()} Format: ${file.format}');
          expect(file.format, entry.value);
          expect(file.audioInfo.format, equals(file.format));
          file.close();
        }
      });
    }
  });

  group('TagLib Front Cover', () {
    test('frontCover matches the picture list result', () {
      final file = TagLibFile.open(
        'test/assets/01 TempleOS Hymn Risen (Remix).mp3',
      );
      expect(file, isNotNull);
      if (file != null) {
        final frontCover = file.coverData;
        final pictures = file.pictures;

        if (pictures.isEmpty) {
          expect(frontCover, isNull);
        } else {
          expect(frontCover, isNotNull);
          print('Front cover: ${frontCover!.length} bytes');
          final expected = pictures.firstWhere(
            (picture) => picture.pictureType == 'Front Cover',
            orElse: () => pictures.first,
          );
          expect(frontCover, equals(expected.bytes));
        }
        file.close();
      }
    });

    test('frontCover is repeatable', () {
      final file = TagLibFile.open(
        'test/assets/01 TempleOS Hymn Risen (Remix).flac',
      );
      expect(file, isNotNull);
      if (file != null) {
        // The native side caches then releases the bytes per call, so a second
        // read must return the same data rather than null or a truncated buffer.
        expect(file.coverData, equals(file.coverData));
        file.close();
      }
    });
  });

  group('TagLib Metadata Modifying', () {
    late Directory tempDir;
    late File tempFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('taglib_test');
      final original = File('test/assets/01 TempleOS Hymn Risen (Remix).mp3');
      tempFile = File('${tempDir.path}/temp_test.mp3');
      original.copySync(tempFile.path);
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (e) {
        print('Failed to delete temp dir: $e');
      }
    });

    test('Write and read back metadata fields', () {
      final file = TagLibFile.open(tempFile.path);
      expect(file, isNotNull);

      file!.title = 'Modified Title FFI';
      file.artist = 'Modified Artist FFI';
      file.album = 'Modified Album FFI';
      file.genre = 'Electronic';
      file.comment = 'Test Comment for FFI';
      file.year = 2026;
      file.track = 12;

      final saved = file.save();
      expect(saved, isTrue);
      file.close();

      // Read back to verify
      final file2 = TagLibFile.open(tempFile.path);
      expect(file2, isNotNull);
      expect(file2!.title, equals('Modified Title FFI'));
      expect(file2.artist, equals('Modified Artist FFI'));
      expect(file2.album, equals('Modified Album FFI'));
      expect(file2.genre, equals('Electronic'));
      expect(file2.comment, equals('Test Comment for FFI'));
      expect(file2.year, equals(2026));
      expect(file2.track, equals(12));
      file2.close();
    });

    test('Write, read and remove cover art', () {
      final file = TagLibFile.open(tempFile.path);
      expect(file, isNotNull);

      final coverBytes = File('test/assets/cover.jpg').readAsBytesSync();
      
      // Write cover
      final success = file!.setCover(data: coverBytes, mimeType: 'image/jpeg');
      expect(success, isTrue);
      
      final saved = file.save();
      expect(saved, isTrue);
      file.close();

      // Read back
      final file2 = TagLibFile.open(tempFile.path);
      expect(file2, isNotNull);
      expect(file2!.hasCover, isTrue);
      expect(file2.coverMimeType, equals('image/jpeg'));
      
      final readBytes = file2.coverData;
      expect(readBytes, isNotNull);
      expect(readBytes!.length, equals(coverBytes.length));
      expect(readBytes[0], equals(coverBytes[0])); // Verify header bytes match

      // Remove cover
      final removeSuccess = file2.setCover(data: null);
      expect(removeSuccess, isTrue);
      final saved2 = file2.save();
      expect(saved2, isTrue);
      file2.close();

      // Check that cover is gone
      final file3 = TagLibFile.open(tempFile.path);
      expect(file3, isNotNull);
      expect(file3!.hasCover, isFalse);
      expect(file3.coverData, isNull);
      file3.close();
    });

    test('Write and read back multiple embedded pictures', () {
      final tempMultiPic = File('${tempDir.path}/temp_multi_pic.mp3');
      File('test/assets/01 TempleOS Hymn Risen (Remix).mp3').copySync(
        tempMultiPic.path,
      );

      final file = TagLibFile.open(tempMultiPic.path);
      expect(file, isNotNull);
      if (file != null) {
        final coverBytes = File('test/assets/cover.jpg').readAsBytesSync();
        final saved = file.setPictures([
          Picture(
            bytes: coverBytes,
            mimeType: 'image/jpeg',
            pictureType: 'Front Cover',
            description: 'front',
          ),
          Picture(
            bytes: coverBytes,
            mimeType: 'image/jpeg',
            pictureType: 'Back Cover',
            description: 'back',
          ),
        ]);
        expect(saved, isTrue);
        expect(file.save(), isTrue);
        file.close();

        final file2 = TagLibFile.open(tempMultiPic.path);
        expect(file2, isNotNull);
        if (file2 != null) {
          expect(file2.pictures.length, equals(2));
          expect(file2.pictures.first.pictureType, equals('Front Cover'));
          expect(file2.pictures.first.description, equals('front'));
          expect(file2.pictures.last.pictureType, equals('Back Cover'));
          expect(file2.pictures.last.description, equals('back'));
          file2.close();
        }
      }
    });

    test('Write and read back metadata fields for APE', () {
      final tempApe = File('${tempDir.path}/temp_test.ape');
      File('test/assets/01 TempleOS Hymn Risen (Remix).ape').copySync(tempApe.path);

      final file = TagLibFile.open(tempApe.path);
      expect(file, isNotNull);
      if (file != null) {
        expect(file.duration.inSeconds, equals(3));
        expect(file.sampleRate, equals(44100));

        file.title = 'APE Modified Title';
        file.artist = 'APE Modified Artist';
        file.album = 'APE Modified Album';

        final saved = file.save();
        expect(saved, isTrue);
        file.close();

        // Read back to verify
        final file2 = TagLibFile.open(tempApe.path);
        expect(file2, isNotNull);
        if (file2 != null) {
          expect(file2.title, equals('APE Modified Title'));
          expect(file2.artist, equals('APE Modified Artist'));
          expect(file2.album, equals('APE Modified Album'));
          file2.close();
        }
      }
    });

    test('Write and read back metadata fields for AIFF', () {
      final tempAiff = File('${tempDir.path}/temp_test.aiff');
      File('test/assets/01 TempleOS Hymn Risen (Remix).aiff').copySync(tempAiff.path);

      final file = TagLibFile.open(tempAiff.path);
      expect(file, isNotNull);
      if (file != null) {
        expect(file.duration.inSeconds, equals(3));
        expect(file.sampleRate, equals(44100));

        file.title = 'AIFF Modified Title';
        file.artist = 'AIFF Modified Artist';
        file.album = 'AIFF Modified Album';

        final saved = file.save();
        expect(saved, isTrue);
        file.close();

        // Read back to verify
        final file2 = TagLibFile.open(tempAiff.path);
        expect(file2, isNotNull);
        if (file2 != null) {
          expect(file2.title, equals('AIFF Modified Title'));
          expect(file2.artist, equals('AIFF Modified Artist'));
          expect(file2.album, equals('AIFF Modified Album'));
          file2.close();
        }
      }
    });

    test('Read, write and read back properties (PropertyMap)', () {
      final file = TagLibFile.open(tempFile.path);
      expect(file, isNotNull);

      // Read current properties
      final initialProps = file!.properties;
      expect(initialProps, isNotEmpty);
      expect(initialProps.containsKey(TagProperties.title), isTrue);

      // Set new properties
      final unsupported = file.setProperties({
        TagProperties.albumArtist: ['Custom Album Artist'],
        TagProperties.composer: ['Custom Composer'],
      });
      // MP3 should support ALBUMARTIST and COMPOSER via ID3v2
      expect(unsupported, isEmpty);

      final saved = file.save();
      expect(saved, isTrue);
      file.close();

      // Read back to verify
      final file2 = TagLibFile.open(tempFile.path);
      expect(file2, isNotNull);
      final newProps = file2!.properties;
      expect(newProps[TagProperties.albumArtist], equals(['Custom Album Artist']));
      expect(newProps[TagProperties.composer], equals(['Custom Composer']));
      file2.close();
    });
  });
}
