// ignore_for_file: non_constant_identifier_names

library;

import 'dart:ffi' as ffi;
import '../flutter_taglib_bindings_generated.dart' as generated;

typedef TagLibBridgeFile = generated.TagLibBridgeFile;
typedef TagLibBridgePictures = generated.TagLibBridgePictures;
typedef TagLibBridgeProperties = generated.TagLibBridgeProperties;

bool get usesDownloadedDesktopBinary => false;
String? get loadedDesktopBinaryPath => null;
String? get desktopBinaryError => null;

void configureDesktopBinarySource({String? baseUrl, String? version}) {}
Future<void> ensureDesktopLibraryReady() => Future.value();

ffi.Pointer<TagLibBridgeFile> taglib_bridge_open(
  ffi.Pointer<ffi.Char> filepath,
) {
  return generated.taglib_bridge_open(filepath);
}

ffi.Pointer<TagLibBridgeFile> taglib_bridge_open_fd(int fd) {
  return generated.taglib_bridge_open_fd(fd);
}

int taglib_bridge_save(ffi.Pointer<TagLibBridgeFile> file) {
  return generated.taglib_bridge_save(file);
}

void taglib_bridge_close(ffi.Pointer<TagLibBridgeFile> file) {
  generated.taglib_bridge_close(file);
}

ffi.Pointer<ffi.Char> taglib_bridge_get_title(
  ffi.Pointer<TagLibBridgeFile> file,
) {
  return generated.taglib_bridge_get_title(file);
}

ffi.Pointer<ffi.Char> taglib_bridge_get_artist(
  ffi.Pointer<TagLibBridgeFile> file,
) {
  return generated.taglib_bridge_get_artist(file);
}

ffi.Pointer<ffi.Char> taglib_bridge_get_album(
  ffi.Pointer<TagLibBridgeFile> file,
) {
  return generated.taglib_bridge_get_album(file);
}

ffi.Pointer<ffi.Char> taglib_bridge_get_genre(
  ffi.Pointer<TagLibBridgeFile> file,
) {
  return generated.taglib_bridge_get_genre(file);
}

ffi.Pointer<ffi.Char> taglib_bridge_get_comment(
  ffi.Pointer<TagLibBridgeFile> file,
) {
  return generated.taglib_bridge_get_comment(file);
}

int taglib_bridge_get_year(ffi.Pointer<TagLibBridgeFile> file) {
  return generated.taglib_bridge_get_year(file);
}

int taglib_bridge_get_track(ffi.Pointer<TagLibBridgeFile> file) {
  return generated.taglib_bridge_get_track(file);
}

void taglib_bridge_set_title(
  ffi.Pointer<TagLibBridgeFile> file,
  ffi.Pointer<ffi.Char> title,
) {
  generated.taglib_bridge_set_title(file, title);
}

void taglib_bridge_set_artist(
  ffi.Pointer<TagLibBridgeFile> file,
  ffi.Pointer<ffi.Char> artist,
) {
  generated.taglib_bridge_set_artist(file, artist);
}

void taglib_bridge_set_album(
  ffi.Pointer<TagLibBridgeFile> file,
  ffi.Pointer<ffi.Char> album,
) {
  generated.taglib_bridge_set_album(file, album);
}

void taglib_bridge_set_genre(
  ffi.Pointer<TagLibBridgeFile> file,
  ffi.Pointer<ffi.Char> genre,
) {
  generated.taglib_bridge_set_genre(file, genre);
}

void taglib_bridge_set_comment(
  ffi.Pointer<TagLibBridgeFile> file,
  ffi.Pointer<ffi.Char> comment,
) {
  generated.taglib_bridge_set_comment(file, comment);
}

void taglib_bridge_set_year(ffi.Pointer<TagLibBridgeFile> file, int year) {
  generated.taglib_bridge_set_year(file, year);
}

void taglib_bridge_set_track(ffi.Pointer<TagLibBridgeFile> file, int track) {
  generated.taglib_bridge_set_track(file, track);
}

int taglib_bridge_get_duration(ffi.Pointer<TagLibBridgeFile> file) {
  return generated.taglib_bridge_get_duration(file);
}

int taglib_bridge_get_bitrate(ffi.Pointer<TagLibBridgeFile> file) {
  return generated.taglib_bridge_get_bitrate(file);
}

int taglib_bridge_get_samplerate(ffi.Pointer<TagLibBridgeFile> file) {
  return generated.taglib_bridge_get_samplerate(file);
}

int taglib_bridge_get_channels(ffi.Pointer<TagLibBridgeFile> file) {
  return generated.taglib_bridge_get_channels(file);
}

ffi.Pointer<ffi.Char> taglib_bridge_get_bitrate_mode(
  ffi.Pointer<TagLibBridgeFile> file,
) {
  return generated.taglib_bridge_get_bitrate_mode(file);
}

ffi.Pointer<ffi.Char> taglib_bridge_get_format(
  ffi.Pointer<TagLibBridgeFile> file,
) {
  return generated.taglib_bridge_get_format(file);
}

int taglib_bridge_has_cover(ffi.Pointer<TagLibBridgeFile> file) {
  return generated.taglib_bridge_has_cover(file);
}

ffi.Pointer<TagLibBridgePictures> taglib_bridge_pictures_create() {
  return generated.taglib_bridge_pictures_create();
}

void taglib_bridge_pictures_free(ffi.Pointer<TagLibBridgePictures> pictures) {
  generated.taglib_bridge_pictures_free(pictures);
}

ffi.Pointer<TagLibBridgePictures> taglib_bridge_pictures_get(
  ffi.Pointer<TagLibBridgeFile> file,
) {
  return generated.taglib_bridge_pictures_get(file);
}

int taglib_bridge_pictures_set(
  ffi.Pointer<TagLibBridgeFile> file,
  ffi.Pointer<TagLibBridgePictures> pictures,
) {
  return generated.taglib_bridge_pictures_set(file, pictures);
}

int taglib_bridge_pictures_size(ffi.Pointer<TagLibBridgePictures> pictures) {
  return generated.taglib_bridge_pictures_size(pictures);
}

int taglib_bridge_pictures_data_size(
  ffi.Pointer<TagLibBridgePictures> pictures,
  int index,
) {
  return generated.taglib_bridge_pictures_data_size(pictures, index);
}

int taglib_bridge_pictures_data(
  ffi.Pointer<TagLibBridgePictures> pictures,
  int index,
  ffi.Pointer<ffi.Uint8> buffer,
  int bufferSize,
) {
  return generated.taglib_bridge_pictures_data(
    pictures,
    index,
    buffer,
    bufferSize,
  );
}

ffi.Pointer<ffi.Char> taglib_bridge_pictures_mime_type(
  ffi.Pointer<TagLibBridgePictures> pictures,
  int index,
) {
  return generated.taglib_bridge_pictures_mime_type(pictures, index);
}

ffi.Pointer<ffi.Char> taglib_bridge_pictures_description(
  ffi.Pointer<TagLibBridgePictures> pictures,
  int index,
) {
  return generated.taglib_bridge_pictures_description(pictures, index);
}

ffi.Pointer<ffi.Char> taglib_bridge_pictures_picture_type(
  ffi.Pointer<TagLibBridgePictures> pictures,
  int index,
) {
  return generated.taglib_bridge_pictures_picture_type(pictures, index);
}

void taglib_bridge_pictures_add(
  ffi.Pointer<TagLibBridgePictures> pictures,
  ffi.Pointer<ffi.Uint8> data,
  int size,
  ffi.Pointer<ffi.Char> mimeType,
  ffi.Pointer<ffi.Char> pictureType,
  ffi.Pointer<ffi.Char> description,
) {
  generated.taglib_bridge_pictures_add(
    pictures,
    data,
    size,
    mimeType,
    pictureType,
    description,
  );
}

ffi.Pointer<TagLibBridgeProperties> taglib_bridge_properties_create() {
  return generated.taglib_bridge_properties_create();
}

void taglib_bridge_properties_free(
  ffi.Pointer<TagLibBridgeProperties> properties,
) {
  generated.taglib_bridge_properties_free(properties);
}

ffi.Pointer<TagLibBridgeProperties> taglib_bridge_properties_get(
  ffi.Pointer<TagLibBridgeFile> file,
) {
  return generated.taglib_bridge_properties_get(file);
}

ffi.Pointer<TagLibBridgeProperties> taglib_bridge_properties_set(
  ffi.Pointer<TagLibBridgeFile> file,
  ffi.Pointer<TagLibBridgeProperties> properties,
) {
  return generated.taglib_bridge_properties_set(file, properties);
}

int taglib_bridge_properties_size(
  ffi.Pointer<TagLibBridgeProperties> properties,
) {
  return generated.taglib_bridge_properties_size(properties);
}

ffi.Pointer<ffi.Char> taglib_bridge_properties_key(
  ffi.Pointer<TagLibBridgeProperties> properties,
  int index,
) {
  return generated.taglib_bridge_properties_key(properties, index);
}

int taglib_bridge_properties_value_count(
  ffi.Pointer<TagLibBridgeProperties> properties,
  ffi.Pointer<ffi.Char> key,
) {
  return generated.taglib_bridge_properties_value_count(properties, key);
}

ffi.Pointer<ffi.Char> taglib_bridge_properties_value(
  ffi.Pointer<TagLibBridgeProperties> properties,
  ffi.Pointer<ffi.Char> key,
  int valueIndex,
) {
  return generated.taglib_bridge_properties_value(
    properties,
    key,
    valueIndex,
  );
}

void taglib_bridge_properties_add(
  ffi.Pointer<TagLibBridgeProperties> properties,
  ffi.Pointer<ffi.Char> key,
  ffi.Pointer<ffi.Char> value,
) {
  generated.taglib_bridge_properties_add(properties, key, value);
}
