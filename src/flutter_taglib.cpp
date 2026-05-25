#include "flutter_taglib.h"
#include <fileref.h>
#include <tfilestream.h>
#include <tag.h>
#include <audioproperties.h>
#include <tvariant.h>
#include <tbytevector.h>
#include <tstring.h>

#include <string>
#include <vector>
#include <cstring>

struct TagLibBridgeFile {
    TagLib::IOStream* stream;
    TagLib::FileRef* fileRef;

    // String cache for FFI lifetime safety
    std::string cachedTitle;
    std::string cachedArtist;
    std::string cachedAlbum;
    std::string cachedGenre;
    std::string cachedComment;
    std::string cachedCoverMime;
};

extern "C" {

TagLibBridgeFile* taglib_bridge_open(const char* filepath) {
    if (!filepath) return nullptr;
    try {
#ifdef _WIN32
        TagLib::String pathStr(filepath, TagLib::String::UTF8);
        TagLib::FileName filename(pathStr.toWString().c_str());
#else
        TagLib::FileName filename = filepath;
#endif
        auto fileRef = new TagLib::FileRef(filename);
        if (fileRef->isNull()) {
            delete fileRef;
            return nullptr;
        }

        auto bridge = new TagLibBridgeFile();
        bridge->stream = nullptr;
        bridge->fileRef = fileRef;
        return bridge;
    } catch (...) {
        return nullptr;
    }
}

TagLibBridgeFile* taglib_bridge_open_fd(int fd) {
    try {
        // TagLib::FileStream is an IOStream wrapping fd.
        // First try read/write (false), then read-only (true).
        auto stream = new TagLib::FileStream(fd, false);
        if (!stream->isOpen()) {
            delete stream;
            stream = new TagLib::FileStream(fd, true);
        }
        if (!stream->isOpen()) {
            delete stream;
            return nullptr;
        }

        // FileRef does not take ownership of stream.
        auto fileRef = new TagLib::FileRef(stream);
        if (fileRef->isNull()) {
            delete fileRef;
            delete stream;
            return nullptr;
        }

        auto bridge = new TagLibBridgeFile();
        bridge->stream = stream;
        bridge->fileRef = fileRef;
        return bridge;
    } catch (...) {
        return nullptr;
    }
}

int taglib_bridge_save(TagLibBridgeFile* file) {
    if (!file || !file->fileRef || file->fileRef->isNull()) return 0;
    try {
        return file->fileRef->save() ? 1 : 0;
    } catch (...) {
        return 0;
    }
}

void taglib_bridge_close(TagLibBridgeFile* file) {
    if (!file) return;
    try {
        if (file->fileRef) {
            delete file->fileRef;
        }
        if (file->stream) {
            // Delete stream after fileRef, as required by TagLib API
            delete file->stream;
        }
        delete file;
    } catch (...) {
    }
}

const char* taglib_bridge_get_title(TagLibBridgeFile* file) {
    if (!file || !file->fileRef || file->fileRef->isNull() || !file->fileRef->tag()) return "";
    try {
        file->cachedTitle = file->fileRef->tag()->title().to8Bit(true);
        return file->cachedTitle.c_str();
    } catch (...) {
        return "";
    }
}

const char* taglib_bridge_get_artist(TagLibBridgeFile* file) {
    if (!file || !file->fileRef || file->fileRef->isNull() || !file->fileRef->tag()) return "";
    try {
        file->cachedArtist = file->fileRef->tag()->artist().to8Bit(true);
        return file->cachedArtist.c_str();
    } catch (...) {
        return "";
    }
}

const char* taglib_bridge_get_album(TagLibBridgeFile* file) {
    if (!file || !file->fileRef || file->fileRef->isNull() || !file->fileRef->tag()) return "";
    try {
        file->cachedAlbum = file->fileRef->tag()->album().to8Bit(true);
        return file->cachedAlbum.c_str();
    } catch (...) {
        return "";
    }
}

const char* taglib_bridge_get_genre(TagLibBridgeFile* file) {
    if (!file || !file->fileRef || file->fileRef->isNull() || !file->fileRef->tag()) return "";
    try {
        file->cachedGenre = file->fileRef->tag()->genre().to8Bit(true);
        return file->cachedGenre.c_str();
    } catch (...) {
        return "";
    }
}

const char* taglib_bridge_get_comment(TagLibBridgeFile* file) {
    if (!file || !file->fileRef || file->fileRef->isNull() || !file->fileRef->tag()) return "";
    try {
        file->cachedComment = file->fileRef->tag()->comment().to8Bit(true);
        return file->cachedComment.c_str();
    } catch (...) {
        return "";
    }
}

uint32_t taglib_bridge_get_year(TagLibBridgeFile* file) {
    if (!file || !file->fileRef || file->fileRef->isNull() || !file->fileRef->tag()) return 0;
    try {
        return file->fileRef->tag()->year();
    } catch (...) {
        return 0;
    }
}

uint32_t taglib_bridge_get_track(TagLibBridgeFile* file) {
    if (!file || !file->fileRef || file->fileRef->isNull() || !file->fileRef->tag()) return 0;
    try {
        return file->fileRef->tag()->track();
    } catch (...) {
        return 0;
    }
}

void taglib_bridge_set_title(TagLibBridgeFile* file, const char* title) {
    if (!file || !file->fileRef || file->fileRef->isNull() || !file->fileRef->tag()) return;
    try {
        file->fileRef->tag()->setTitle(TagLib::String(title ? title : "", TagLib::String::UTF8));
    } catch (...) {}
}

void taglib_bridge_set_artist(TagLibBridgeFile* file, const char* artist) {
    if (!file || !file->fileRef || file->fileRef->isNull() || !file->fileRef->tag()) return;
    try {
        file->fileRef->tag()->setArtist(TagLib::String(artist ? artist : "", TagLib::String::UTF8));
    } catch (...) {}
}

void taglib_bridge_set_album(TagLibBridgeFile* file, const char* album) {
    if (!file || !file->fileRef || file->fileRef->isNull() || !file->fileRef->tag()) return;
    try {
        file->fileRef->tag()->setAlbum(TagLib::String(album ? album : "", TagLib::String::UTF8));
    } catch (...) {}
}

void taglib_bridge_set_genre(TagLibBridgeFile* file, const char* genre) {
    if (!file || !file->fileRef || file->fileRef->isNull() || !file->fileRef->tag()) return;
    try {
        file->fileRef->tag()->setGenre(TagLib::String(genre ? genre : "", TagLib::String::UTF8));
    } catch (...) {}
}

void taglib_bridge_set_comment(TagLibBridgeFile* file, const char* comment) {
    if (!file || !file->fileRef || file->fileRef->isNull() || !file->fileRef->tag()) return;
    try {
        file->fileRef->tag()->setComment(TagLib::String(comment ? comment : "", TagLib::String::UTF8));
    } catch (...) {}
}

void taglib_bridge_set_year(TagLibBridgeFile* file, uint32_t year) {
    if (!file || !file->fileRef || file->fileRef->isNull() || !file->fileRef->tag()) return;
    try {
        file->fileRef->tag()->setYear(year);
    } catch (...) {}
}

void taglib_bridge_set_track(TagLibBridgeFile* file, uint32_t track) {
    if (!file || !file->fileRef || file->fileRef->isNull() || !file->fileRef->tag()) return;
    try {
        file->fileRef->tag()->setTrack(track);
    } catch (...) {}
}

int taglib_bridge_get_duration(TagLibBridgeFile* file) {
    if (!file || !file->fileRef || file->fileRef->isNull() || !file->fileRef->audioProperties()) return 0;
    try {
        return file->fileRef->audioProperties()->lengthInSeconds();
    } catch (...) {
        return 0;
    }
}

int taglib_bridge_get_bitrate(TagLibBridgeFile* file) {
    if (!file || !file->fileRef || file->fileRef->isNull() || !file->fileRef->audioProperties()) return 0;
    try {
        return file->fileRef->audioProperties()->bitrate();
    } catch (...) {
        return 0;
    }
}

int taglib_bridge_get_samplerate(TagLibBridgeFile* file) {
    if (!file || !file->fileRef || file->fileRef->isNull() || !file->fileRef->audioProperties()) return 0;
    try {
        return file->fileRef->audioProperties()->sampleRate();
    } catch (...) {
        return 0;
    }
}

int taglib_bridge_get_channels(TagLibBridgeFile* file) {
    if (!file || !file->fileRef || file->fileRef->isNull() || !file->fileRef->audioProperties()) return 0;
    try {
        return file->fileRef->audioProperties()->channels();
    } catch (...) {
        return 0;
    }
}

int taglib_bridge_has_cover(TagLibBridgeFile* file) {
    if (!file || !file->fileRef || file->fileRef->isNull()) return 0;
    try {
        auto pictures = file->fileRef->complexProperties("PICTURE");
        return !pictures.isEmpty() ? 1 : 0;
    } catch (...) {
        return 0;
    }
}

uint32_t taglib_bridge_get_cover_data_size(TagLibBridgeFile* file) {
    if (!file || !file->fileRef || file->fileRef->isNull()) return 0;
    try {
        auto pictures = file->fileRef->complexProperties("PICTURE");
        if (pictures.isEmpty()) return 0;
        auto dataVar = pictures.front()["data"];
        if (dataVar.isEmpty()) return 0;
        return dataVar.toByteVector().size();
    } catch (...) {
        return 0;
    }
}

int taglib_bridge_get_cover_data(TagLibBridgeFile* file, uint8_t* buffer, uint32_t buffer_size) {
    if (!file || !file->fileRef || file->fileRef->isNull() || !buffer || buffer_size == 0) return 0;
    try {
        auto pictures = file->fileRef->complexProperties("PICTURE");
        if (pictures.isEmpty()) return 0;
        auto dataVar = pictures.front()["data"];
        if (dataVar.isEmpty()) return 0;
        auto byteVector = dataVar.toByteVector();
        uint32_t toCopy = byteVector.size() < buffer_size ? byteVector.size() : buffer_size;
        std::memcpy(buffer, byteVector.data(), toCopy);
        return 1;
    } catch (...) {
        return 0;
    }
}

const char* taglib_bridge_get_cover_mime_type(TagLibBridgeFile* file) {
    if (!file || !file->fileRef || file->fileRef->isNull()) return "";
    try {
        auto pictures = file->fileRef->complexProperties("PICTURE");
        if (pictures.isEmpty()) return "";
        auto mimeVar = pictures.front()["mimeType"];
        if (mimeVar.isEmpty()) return "";
        file->cachedCoverMime = mimeVar.toString().to8Bit(true);
        return file->cachedCoverMime.c_str();
    } catch (...) {
        return "";
    }
}

int taglib_bridge_set_cover(TagLibBridgeFile* file, const char* mime_type, const uint8_t* data, uint32_t size) {
    if (!file || !file->fileRef || file->fileRef->isNull()) return 0;
    try {
        TagLib::List<TagLib::VariantMap> pictures;
        if (size > 0 && data != nullptr) {
            TagLib::VariantMap picMap;
            picMap["data"] = TagLib::ByteVector((const char*)data, size);
            picMap["mimeType"] = TagLib::String(mime_type ? mime_type : "image/jpeg", TagLib::String::UTF8);
            picMap["pictureType"] = TagLib::String("Front Cover");
            pictures.append(picMap);
        }
        return file->fileRef->setComplexProperties("PICTURE", pictures) ? 1 : 0;
    } catch (...) {
        return 0;
    }
}

} // extern "C"
