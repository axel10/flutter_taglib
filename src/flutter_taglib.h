#ifndef FLUTTER_TAGLIB_H
#define FLUTTER_TAGLIB_H

#include <stdint.h>

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Opaque struct pointer for TagLib File bridge
typedef struct TagLibBridgeFile TagLibBridgeFile;

// Open a file by file path. Returns NULL if failed.
FFI_PLUGIN_EXPORT TagLibBridgeFile* taglib_bridge_open(const char* filepath);

// Open a file by File Descriptor (FD). Returns NULL if failed.
FFI_PLUGIN_EXPORT TagLibBridgeFile* taglib_bridge_open_fd(int fd);

// Save changes to the file. Returns 1 on success, 0 on failure.
FFI_PLUGIN_EXPORT int taglib_bridge_save(TagLibBridgeFile* file);

// Close and free resources.
FFI_PLUGIN_EXPORT void taglib_bridge_close(TagLibBridgeFile* file);

// Read string properties. The returned strings are managed by the bridge and must NOT be freed.
FFI_PLUGIN_EXPORT const char* taglib_bridge_get_title(TagLibBridgeFile* file);
FFI_PLUGIN_EXPORT const char* taglib_bridge_get_artist(TagLibBridgeFile* file);
FFI_PLUGIN_EXPORT const char* taglib_bridge_get_album(TagLibBridgeFile* file);
FFI_PLUGIN_EXPORT const char* taglib_bridge_get_genre(TagLibBridgeFile* file);
FFI_PLUGIN_EXPORT const char* taglib_bridge_get_comment(TagLibBridgeFile* file);

// Read integer properties
FFI_PLUGIN_EXPORT uint32_t taglib_bridge_get_year(TagLibBridgeFile* file);
FFI_PLUGIN_EXPORT uint32_t taglib_bridge_get_track(TagLibBridgeFile* file);

// Write string properties
FFI_PLUGIN_EXPORT void taglib_bridge_set_title(TagLibBridgeFile* file, const char* title);
FFI_PLUGIN_EXPORT void taglib_bridge_set_artist(TagLibBridgeFile* file, const char* artist);
FFI_PLUGIN_EXPORT void taglib_bridge_set_album(TagLibBridgeFile* file, const char* album);
FFI_PLUGIN_EXPORT void taglib_bridge_set_genre(TagLibBridgeFile* file, const char* genre);
FFI_PLUGIN_EXPORT void taglib_bridge_set_comment(TagLibBridgeFile* file, const char* comment);

// Write integer properties
FFI_PLUGIN_EXPORT void taglib_bridge_set_year(TagLibBridgeFile* file, uint32_t year);
FFI_PLUGIN_EXPORT void taglib_bridge_set_track(TagLibBridgeFile* file, uint32_t track);

// Read audio properties
FFI_PLUGIN_EXPORT int taglib_bridge_get_duration(TagLibBridgeFile* file); // seconds
FFI_PLUGIN_EXPORT int taglib_bridge_get_bitrate(TagLibBridgeFile* file);  // kbps
FFI_PLUGIN_EXPORT int taglib_bridge_get_samplerate(TagLibBridgeFile* file); // Hz
FFI_PLUGIN_EXPORT int taglib_bridge_get_channels(TagLibBridgeFile* file);

// Album Art / Picture APIs
FFI_PLUGIN_EXPORT int taglib_bridge_has_cover(TagLibBridgeFile* file);
FFI_PLUGIN_EXPORT uint32_t taglib_bridge_get_cover_data_size(TagLibBridgeFile* file);
FFI_PLUGIN_EXPORT int taglib_bridge_get_cover_data(TagLibBridgeFile* file, uint8_t* buffer, uint32_t buffer_size);
FFI_PLUGIN_EXPORT const char* taglib_bridge_get_cover_mime_type(TagLibBridgeFile* file);

// Write album art. mime_type can be "image/jpeg" or "image/png". Pass data=NULL, size=0 to remove cover.
FFI_PLUGIN_EXPORT int taglib_bridge_set_cover(TagLibBridgeFile* file, const char* mime_type, const uint8_t* data, uint32_t size);

#ifdef __cplusplus
}
#endif

#endif // FLUTTER_TAGLIB_H
