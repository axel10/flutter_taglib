#include "flutter_taglib.h"
#include <fileref.h>
#include <tfilestream.h>
#include <tag.h>
#include <audioproperties.h>
#include <tvariant.h>
#include <tbytevector.h>
#include <tstring.h>
#include <mpegfile.h>
#include <mpegproperties.h>
#include <xingheader.h>
#include <flacfile.h>
#include <ogg/vorbis/vorbisfile.h>
#include <ogg/opus/opusfile.h>
#include <mp4/mp4file.h>
#include <riff/wav/wavfile.h>
#include <tpropertymap.h>

#include <string>
#include <vector>
#include <map>
#include <cstring>

#include <cstdio>
#include <iostream>

#ifdef __ANDROID__
#include <jni.h>
#include <unistd.h>
#include <android/log.h>

#define LOG_TAG "FlutterTaglib"
#define LOGI(...) do {} while(0) // Disable info logs to optimize performance
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

static JavaVM* g_vm = nullptr;
static jobject g_context = nullptr;

static JNIEnv* get_jni_env() {
    if (!g_vm) return nullptr;
    JNIEnv* env = nullptr;
    jint res = g_vm->GetEnv((void**)&env, JNI_VERSION_1_6);
    if (res == JNI_EDETACHED) {
        #ifdef __ANDROID__
        res = g_vm->AttachCurrentThread(&env, nullptr);
        #else
        res = g_vm->AttachCurrentThread((void**)&env, nullptr);
        #endif
        if (res != JNI_OK) {
            return nullptr;
        }
    }
    return env;
}

static void check_and_clear_jni_exception(JNIEnv* env, const char* context) {
    if (env->ExceptionCheck()) {
        jthrowable exc = env->ExceptionOccurred();
        if (exc) {
            env->ExceptionClear();
            jclass excClass = env->GetObjectClass(exc);
            jmethodID toStringMethod = env->GetMethodID(excClass, "toString", "()Ljava/lang/String;");
            if (toStringMethod) {
                jstring jstr = (jstring)env->CallObjectMethod(exc, toStringMethod);
                if (jstr) {
                    const char* str = env->GetStringUTFChars(jstr, nullptr);
                    LOGE("[%s] JNI Exception: %s", context, str);
                    env->ReleaseStringUTFChars(jstr, str);
                    env->DeleteLocalRef(jstr);
                } else {
                    LOGE("[%s] JNI Exception occurred, but toString failed", context);
                }
            } else {
                LOGE("[%s] JNI Exception occurred, but toString method not found", context);
            }
            env->DeleteLocalRef(excClass);
            env->DeleteLocalRef(exc);
        } else {
            env->ExceptionClear();
            LOGE("[%s] ExceptionCheck was true, but ExceptionOccurred returned null", context);
        }
    }
}

static int open_content_uri_fd(const char* uri_str, const char* mode_str) {
    JNIEnv* env = get_jni_env();
    if (!env) {
        LOGE("open_content_uri_fd: JNI env is null");
        return -1;
    }
    if (!g_context) {
        LOGE("open_content_uri_fd: g_context is null");
        return -1;
    }

    // Get ContentResolver
    jclass contextClass = env->GetObjectClass(g_context);
    jmethodID getContentResolverMethod = env->GetMethodID(contextClass, "getContentResolver", "()Landroid/content/ContentResolver;");
    if (!getContentResolverMethod) {
        LOGE("open_content_uri_fd: getContentResolver method not found");
        return -1;
    }
    jobject resolver = env->CallObjectMethod(g_context, getContentResolverMethod);
    if (env->ExceptionCheck()) {
        check_and_clear_jni_exception(env, "getContentResolver");
        return -1;
    }
    if (!resolver) {
        LOGE("open_content_uri_fd: ContentResolver is null");
        return -1;
    }

    // Parse Uri
    jclass uriClass = env->FindClass("android/net/Uri");
    if (!uriClass) {
        LOGE("open_content_uri_fd: Uri class not found");
        return -1;
    }
    jmethodID parseMethod = env->GetStaticMethodID(uriClass, "parse", "(Ljava/lang/String;)Landroid/net/Uri;");
    if (!parseMethod) {
        LOGE("open_content_uri_fd: Uri.parse method not found");
        return -1;
    }
    jstring juri_str = env->NewStringUTF(uri_str);
    jobject uri = env->CallStaticObjectMethod(uriClass, parseMethod, juri_str);
    env->DeleteLocalRef(juri_str);
    if (env->ExceptionCheck()) {
        check_and_clear_jni_exception(env, "Uri.parse");
        return -1;
    }
    if (!uri) {
        LOGE("open_content_uri_fd: Uri parsing returned null");
        return -1;
    }

    // Call resolver.openFileDescriptor(uri, mode)
    jclass resolverClass = env->GetObjectClass(resolver);
    jmethodID openFileDescriptorMethod = env->GetMethodID(resolverClass, "openFileDescriptor", "(Landroid/net/Uri;Ljava/lang/String;)Landroid/os/ParcelFileDescriptor;");
    if (!openFileDescriptorMethod) {
        LOGE("open_content_uri_fd: openFileDescriptor method not found");
        return -1;
    }
    jstring jmode_str = env->NewStringUTF(mode_str);
    jobject pfd = env->CallObjectMethod(resolver, openFileDescriptorMethod, uri, jmode_str);
    env->DeleteLocalRef(jmode_str);
    if (env->ExceptionCheck()) {
        check_and_clear_jni_exception(env, "openFileDescriptor");
        return -1;
    }
    if (!pfd) {
        LOGE("open_content_uri_fd: openFileDescriptor returned null");
        return -1;
    }

    // Get raw fd and detach it
    jclass pfdClass = env->GetObjectClass(pfd);
    jmethodID detachFdMethod = env->GetMethodID(pfdClass, "detachFd", "()I");
    if (!detachFdMethod) {
        LOGE("open_content_uri_fd: detachFd method not found");
        env->DeleteLocalRef(pfd);
        return -1;
    }
    int fd = env->CallIntMethod(pfd, detachFdMethod);
    if (env->ExceptionCheck()) {
        check_and_clear_jni_exception(env, "detachFd");
        env->DeleteLocalRef(pfd);
        return -1;
    }
    env->DeleteLocalRef(pfd);

    return fd;
}
#else
#define LOGI(...) do {} while(0) // Disable info logs on desktop to optimize performance
#define LOGW(...) do { fprintf(stderr, "[FlutterTaglib WARN] "); fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); } while(0)
#define LOGE(...) do { fprintf(stderr, "[FlutterTaglib ERROR] "); fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); } while(0)
#endif

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
    std::string cachedBitrateMode;
};

struct TagLibBridgePictures {
    TagLib::List<TagLib::VariantMap> pictures;
    std::vector<TagLib::VariantMap> cachedPictures;
    std::vector<std::string> cachedMimeTypes;
    std::vector<std::string> cachedDescriptions;
    std::vector<std::string> cachedPictureTypes;

    void refreshCache() {
        cachedPictures.clear();
        cachedMimeTypes.clear();
        cachedDescriptions.clear();
        cachedPictureTypes.clear();

        for (const auto& picture : pictures) {
            cachedPictures.push_back(picture);

            auto mimeVar = picture["mimeType"];
            cachedMimeTypes.push_back(
                mimeVar.isEmpty() ? std::string() : mimeVar.toString().to8Bit(true)
            );

            auto descVar = picture["description"];
            cachedDescriptions.push_back(
                descVar.isEmpty() ? std::string() : descVar.toString().to8Bit(true)
            );

            auto typeVar = picture["pictureType"];
            cachedPictureTypes.push_back(
                typeVar.isEmpty() ? std::string() : typeVar.toString().to8Bit(true)
            );
        }
    }
};

static TagLib::List<TagLib::VariantMap> read_picture_list(TagLibBridgeFile* file) {
    if (!file || !file->fileRef || file->fileRef->isNull()) {
        return TagLib::List<TagLib::VariantMap>();
    }
    return file->fileRef->complexProperties("PICTURE");
}

static const TagLib::VariantMap* picture_at(const TagLibBridgePictures* pictures, int index) {
    if (!pictures || index < 0 || index >= static_cast<int>(pictures->cachedPictures.size())) {
        return nullptr;
    }
    return &pictures->cachedPictures[static_cast<size_t>(index)];
}

static TagLib::VariantMap build_picture_map(
    const uint8_t* data,
    uint32_t size,
    const char* mime_type,
    const char* picture_type,
    const char* description
) {
    TagLib::VariantMap picMap;
    picMap["data"] = TagLib::ByteVector(reinterpret_cast<const char*>(data), size);
    picMap["mimeType"] = TagLib::String(mime_type ? mime_type : "image/jpeg", TagLib::String::UTF8);
    picMap["pictureType"] = TagLib::String(picture_type ? picture_type : "Front Cover", TagLib::String::UTF8);
    if (description && *description != '\0') {
        picMap["description"] = TagLib::String(description, TagLib::String::UTF8);
    }
    return picMap;
}

extern "C" {

#ifdef __ANDROID__
JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void* reserved) {
    g_vm = vm;
    return JNI_VERSION_1_6;
}

JNIEXPORT void JNICALL Java_com_axel10_flutter_1taglib_FlutterTaglibPlugin_setNativeContext(JNIEnv* env, jobject thiz, jobject context) {
    if (g_context) {
        env->DeleteGlobalRef(g_context);
    }
    g_context = env->NewGlobalRef(context);
}

JNIEXPORT void JNICALL Java_com_axel10_flutter_1taglib_FlutterTaglibPlugin_clearNativeContext(JNIEnv* env, jobject thiz) {
    if (g_context) {
        env->DeleteGlobalRef(g_context);
        g_context = nullptr;
    }
}
#endif

TagLibBridgeFile* taglib_bridge_open(const char* filepath) {
    if (!filepath) {
        LOGE("taglib_bridge_open: filepath is null");
        return nullptr;
    }

#ifdef __ANDROID__
    if (std::strncmp(filepath, "content://", 10) == 0) {
        LOGI("taglib_bridge_open: opening content URI: %s", filepath);
        int fd = open_content_uri_fd(filepath, "rw");
        if (fd == -1) {
            LOGW("taglib_bridge_open: failed to open content URI in 'rw' mode, falling back to 'r' (read-only) mode");
            fd = open_content_uri_fd(filepath, "r");
        }
        if (fd != -1) {
            return taglib_bridge_open_fd(fd);
        }
        LOGE("taglib_bridge_open: failed to open content URI fd for: %s", filepath);
        return nullptr;
    }
#endif

    LOGI("taglib_bridge_open: opening file path: %s", filepath);
    try {
#ifdef _WIN32
        TagLib::String pathStr(filepath, TagLib::String::UTF8);
        TagLib::FileName filename(pathStr.toWString().c_str());
#else
        TagLib::FileName filename = filepath;
#endif
        auto fileRef = new TagLib::FileRef(filename);
        if (fileRef->isNull()) {
            LOGE("taglib_bridge_open: fileRef is null (invalid file or format) for: %s", filepath);
            delete fileRef;
            return nullptr;
        }

        auto bridge = new TagLibBridgeFile();
        bridge->stream = nullptr;
        bridge->fileRef = fileRef;
        LOGI("taglib_bridge_open: successfully opened file: %s", filepath);
        return bridge;
    } catch (const std::exception& e) {
        LOGE("taglib_bridge_open: std::exception caught for %s: %s", filepath, e.what());
        return nullptr;
    } catch (...) {
        LOGE("taglib_bridge_open: unknown exception caught for %s", filepath);
        return nullptr;
    }
}

TagLibBridgeFile* taglib_bridge_open_fd(int fd) {
    LOGI("taglib_bridge_open_fd: opening fd: %d", fd);
    try {
        // TagLib::FileStream is an IOStream wrapping fd.
        // First try read/write (false), then read-only (true).
        auto stream = new TagLib::FileStream(fd, false);
        if (!stream->isOpen()) {
            LOGW("taglib_bridge_open_fd: fd %d cannot be opened as read-write, trying read-only", fd);
            delete stream;
            stream = new TagLib::FileStream(fd, true);
        }
        if (!stream->isOpen()) {
            LOGE("taglib_bridge_open_fd: fd %d failed to open stream", fd);
            delete stream;
            return nullptr;
        }

        if (stream->readOnly()) {
            LOGW("taglib_bridge_open_fd: fd %d is opened in READ-ONLY mode. Metadata changes will not be saved!", fd);
        } else {
            LOGI("taglib_bridge_open_fd: fd %d opened successfully in read-write mode", fd);
        }

        // FileRef does not take ownership of stream.
        auto fileRef = new TagLib::FileRef(stream);
        if (fileRef->isNull()) {
            LOGE("taglib_bridge_open_fd: fileRef is null (invalid file or format) for fd: %d", fd);
            delete fileRef;
            delete stream;
            return nullptr;
        }

        auto bridge = new TagLibBridgeFile();
        bridge->stream = stream;
        bridge->fileRef = fileRef;
        return bridge;
    } catch (const std::exception& e) {
        LOGE("taglib_bridge_open_fd: std::exception caught: %s", e.what());
        return nullptr;
    } catch (...) {
        LOGE("taglib_bridge_open_fd: unknown exception caught");
        return nullptr;
    }
}

int taglib_bridge_save(TagLibBridgeFile* file) {
    if (!file) {
        LOGE("taglib_bridge_save: file pointer is NULL");
        return 0;
    }
    if (!file->fileRef) {
        LOGE("taglib_bridge_save: fileRef is NULL");
        return 0;
    }
    if (file->fileRef->isNull()) {
        LOGE("taglib_bridge_save: fileRef is null (invalid file)");
        return 0;
    }
    if (file->fileRef->file()) {
        if (file->fileRef->file()->readOnly()) {
            LOGE("taglib_bridge_save: TagLib::File is read-only. Cannot save metadata updates!");
            return 0;
        }
    } else {
        LOGW("taglib_bridge_save: TagLib::File is NULL");
    }

    try {
        bool success = file->fileRef->save();
        if (success) {
            LOGI("taglib_bridge_save: metadata saved successfully");
            return 1;
        } else {
            LOGE("taglib_bridge_save: fileRef->save() returned false");
            return 0;
        }
    } catch (const std::exception& e) {
        LOGE("taglib_bridge_save: std::exception caught while saving: %s", e.what());
        return 0;
    } catch (...) {
        LOGE("taglib_bridge_save: unknown exception caught while saving");
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
        return file->fileRef->audioProperties()->lengthInMilliseconds();
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

const char* taglib_bridge_get_bitrate_mode(TagLibBridgeFile* file) {
    if (!file || !file->fileRef || file->fileRef->isNull() || !file->fileRef->audioProperties()) return "";
    try {
        auto audioProps = file->fileRef->audioProperties();
        auto filePtr = file->fileRef->file();
        
        if (auto mpegFile = dynamic_cast<TagLib::MPEG::File*>(filePtr)) {
            auto mpegProps = dynamic_cast<TagLib::MPEG::Properties*>(audioProps);
            if (mpegProps) {
                auto xing = mpegProps->xingHeader();
                if (xing && xing->isValid()) {
                    if (xing->type() == TagLib::MPEG::XingHeader::Xing || xing->type() == TagLib::MPEG::XingHeader::VBRI) {
                        file->cachedBitrateMode = "VBR";
                    } else {
                        file->cachedBitrateMode = "CBR";
                    }
                } else {
                    file->cachedBitrateMode = "CBR";
                }
            } else {
                file->cachedBitrateMode = "Unknown";
            }
        } else if (auto flacFile = dynamic_cast<TagLib::FLAC::File*>(filePtr)) {
            file->cachedBitrateMode = "VBR";
        } else if (auto vorbisFile = dynamic_cast<TagLib::Ogg::Vorbis::File*>(filePtr)) {
            file->cachedBitrateMode = "VBR";
        } else if (auto opusFile = dynamic_cast<TagLib::Ogg::Opus::File*>(filePtr)) {
            file->cachedBitrateMode = "VBR";
        } else if (auto wavFile = dynamic_cast<TagLib::RIFF::WAV::File*>(filePtr)) {
            file->cachedBitrateMode = "CBR";
        } else {
            file->cachedBitrateMode = "Unknown";
        }
        return file->cachedBitrateMode.c_str();
    } catch (...) {
        return "";
    }
}

int taglib_bridge_has_cover(TagLibBridgeFile* file) {
    if (!file || !file->fileRef || file->fileRef->isNull()) return 0;
    try {
        auto pictures = read_picture_list(file);
        return !pictures.isEmpty() ? 1 : 0;
    } catch (...) {
        return 0;
    }
}

uint32_t taglib_bridge_get_cover_data_size(TagLibBridgeFile* file) {
    if (!file || !file->fileRef || file->fileRef->isNull()) return 0;
    try {
        auto pictures = read_picture_list(file);
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
        auto pictures = read_picture_list(file);
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
        auto pictures = read_picture_list(file);
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
            pictures.append(build_picture_map(data, size, mime_type, "Front Cover", nullptr));
        }
        return file->fileRef->setComplexProperties("PICTURE", pictures) ? 1 : 0;
    } catch (...) {
        return 0;
    }
}

TagLibBridgePictures* taglib_bridge_pictures_create() {
    return new TagLibBridgePictures();
}

void taglib_bridge_pictures_free(TagLibBridgePictures* pictures) {
    if (pictures) delete pictures;
}

TagLibBridgePictures* taglib_bridge_pictures_get(TagLibBridgeFile* file) {
    if (!file || !file->fileRef || file->fileRef->isNull()) return nullptr;
    try {
        auto* bridgePictures = new TagLibBridgePictures();
        bridgePictures->pictures = read_picture_list(file);
        bridgePictures->refreshCache();
        return bridgePictures;
    } catch (...) {
        return nullptr;
    }
}

int taglib_bridge_pictures_set(TagLibBridgeFile* file, TagLibBridgePictures* pictures) {
    if (!file || !file->fileRef || file->fileRef->isNull() || !pictures) return 0;
    try {
        return file->fileRef->setComplexProperties("PICTURE", pictures->pictures) ? 1 : 0;
    } catch (...) {
        return 0;
    }
}

int taglib_bridge_pictures_size(TagLibBridgePictures* pictures) {
    if (!pictures) return 0;
    return static_cast<int>(pictures->cachedPictures.size());
}

uint32_t taglib_bridge_pictures_data_size(TagLibBridgePictures* pictures, int index) {
    const auto* picture = picture_at(pictures, index);
    if (!picture) return 0;
    auto dataVar = (*picture)["data"];
    if (dataVar.isEmpty()) return 0;
    return static_cast<uint32_t>(dataVar.toByteVector().size());
}

int taglib_bridge_pictures_data(TagLibBridgePictures* pictures, int index, uint8_t* buffer, uint32_t buffer_size) {
    if (!pictures || !buffer || buffer_size == 0) return 0;
    const auto* picture = picture_at(pictures, index);
    if (!picture) return 0;
    auto dataVar = (*picture)["data"];
    if (dataVar.isEmpty()) return 0;
    auto byteVector = dataVar.toByteVector();
    uint32_t toCopy = byteVector.size() < buffer_size ? byteVector.size() : buffer_size;
    std::memcpy(buffer, byteVector.data(), toCopy);
    return 1;
}

const char* taglib_bridge_pictures_mime_type(TagLibBridgePictures* pictures, int index) {
    if (!pictures || index < 0 || index >= static_cast<int>(pictures->cachedMimeTypes.size())) return "";
    return pictures->cachedMimeTypes[static_cast<size_t>(index)].c_str();
}

const char* taglib_bridge_pictures_description(TagLibBridgePictures* pictures, int index) {
    if (!pictures || index < 0 || index >= static_cast<int>(pictures->cachedDescriptions.size())) return "";
    return pictures->cachedDescriptions[static_cast<size_t>(index)].c_str();
}

const char* taglib_bridge_pictures_picture_type(TagLibBridgePictures* pictures, int index) {
    if (!pictures || index < 0 || index >= static_cast<int>(pictures->cachedPictureTypes.size())) return "";
    return pictures->cachedPictureTypes[static_cast<size_t>(index)].c_str();
}

void taglib_bridge_pictures_add(
    TagLibBridgePictures* pictures,
    const uint8_t* data,
    uint32_t size,
    const char* mime_type,
    const char* picture_type,
    const char* description
) {
    if (!pictures || !data || size == 0) return;
    try {
        pictures->pictures.append(
            build_picture_map(data, size, mime_type, picture_type, description)
        );
        pictures->refreshCache();
    } catch (...) {
    }
}

struct TagLibBridgeProperties {
    TagLib::PropertyMap properties;
    std::vector<std::string> keys;
    std::map<std::string, std::vector<std::string>> values;

    void refreshCache() {
        keys.clear();
        values.clear();
        for (auto it = properties.begin(); it != properties.end(); ++it) {
            std::string keyStr = it->first.to8Bit(true);
            keys.push_back(keyStr);
            
            std::vector<std::string> valStrs;
            for (auto const& val : it->second) {
                valStrs.push_back(val.to8Bit(true));
            }
            values[keyStr] = valStrs;
        }
    }
};

TagLibBridgeProperties* taglib_bridge_properties_create() {
    return new TagLibBridgeProperties();
}

void taglib_bridge_properties_free(TagLibBridgeProperties* props) {
    if (props) delete props;
}

TagLibBridgeProperties* taglib_bridge_properties_get(TagLibBridgeFile* file) {
    if (!file || !file->fileRef || file->fileRef->isNull()) return nullptr;
    try {
        auto* bridgeProps = new TagLibBridgeProperties();
        bridgeProps->properties = file->fileRef->properties();
        bridgeProps->refreshCache();
        return bridgeProps;
    } catch (...) {
        return nullptr;
    }
}

TagLibBridgeProperties* taglib_bridge_properties_set(TagLibBridgeFile* file, TagLibBridgeProperties* props) {
    if (!file || !file->fileRef || file->fileRef->isNull() || !props) return nullptr;
    try {
        TagLib::PropertyMap unsupported = file->fileRef->setProperties(props->properties);
        
        auto* bridgeUnsupported = new TagLibBridgeProperties();
        bridgeUnsupported->properties = unsupported;
        bridgeUnsupported->refreshCache();
        return bridgeUnsupported;
    } catch (...) {
        return nullptr;
    }
}

int taglib_bridge_properties_size(TagLibBridgeProperties* props) {
    if (!props) return 0;
    return props->keys.size();
}

const char* taglib_bridge_properties_key(TagLibBridgeProperties* props, int index) {
    if (!props || index < 0 || index >= (int)props->keys.size()) return "";
    return props->keys[index].c_str();
}

int taglib_bridge_properties_value_count(TagLibBridgeProperties* props, const char* key) {
    if (!props || !key) return 0;
    auto it = props->values.find(key);
    if (it == props->values.end()) return 0;
    return it->second.size();
}

const char* taglib_bridge_properties_value(TagLibBridgeProperties* props, const char* key, int value_index) {
    if (!props || !key || value_index < 0) return "";
    auto it = props->values.find(key);
    if (it == props->values.end() || value_index >= (int)it->second.size()) return "";
    return it->second[value_index].c_str();
}

void taglib_bridge_properties_add(TagLibBridgeProperties* props, const char* key, const char* value) {
    if (!props || !key || !value) return;
    TagLib::String tKey(key, TagLib::String::UTF8);
    TagLib::String tVal(value, TagLib::String::UTF8);
    props->properties[tKey].append(tVal);
    props->refreshCache();
}

} // extern "C"
