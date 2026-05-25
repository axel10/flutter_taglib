import 'dart:io';
import 'dart:typed_data';
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
        
        expect(file.title, isNotEmpty);
        expect(file.artist, isNotEmpty);
        expect(file.duration.inSeconds, greaterThan(0));
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
        expect(file.title, isNotEmpty);
        expect(file.artist, isNotEmpty);
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
        expect(file.title, isNotEmpty);
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
  });
}
