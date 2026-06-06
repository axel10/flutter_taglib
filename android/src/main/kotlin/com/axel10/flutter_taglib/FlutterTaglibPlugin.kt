package com.axel10.flutter_taglib

import android.app.Activity
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class FlutterTaglibPlugin: FlutterPlugin, MethodCallHandler, ActivityAware, PluginRegistry.ActivityResultListener {
    private var channel: MethodChannel? = null
    private var context: Context? = null
    private var activity: Activity? = null
    private var pendingResult: Result? = null
    private var resolvedUriString: String? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    companion object {
        private const val TAG = "FlutterTaglibPlugin"
        private const val REQUEST_WRITE_PERMISSION = 1045
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "flutter_taglib")
        channel?.setMethodCallHandler(this)
        Log.d(TAG, "onAttachedToEngine: Plugin registered")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = null
        channel?.setMethodCallHandler(null)
        channel = null
        Log.d(TAG, "onDetachedFromEngine: Plugin unregistered")
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        if (call.method == "requestWritePermission") {
            val uriStr = call.argument<String>("uri")
            if (uriStr == null) {
                result.error("INVALID_ARGUMENT", "URI is null", null)
                return
            }
            Log.d(TAG, "onMethodCall requestWritePermission: uri=$uriStr")
            // Run on a background thread to prevent blocking main thread when MediaScanner synchronously awaits callbacks.
            Thread {
                handleRequestWritePermission(uriStr, result)
            }.start()
        } else if (call.method == "openWritableFileDescriptor") {
            val uriStr = call.argument<String>("uri")
            if (uriStr == null) {
                result.error("INVALID_ARGUMENT", "URI is null", null)
                return
            }
            Log.d(TAG, "onMethodCall openWritableFileDescriptor: uri=$uriStr")
            handleOpenFileDescriptor(uriStr, "rw", result)
        } else if (call.method == "openFileDescriptor") {
            val uriStr = call.argument<String>("uri")
            val mode = call.argument<String>("mode") ?: "r"
            if (uriStr == null) {
                result.error("INVALID_ARGUMENT", "URI is null", null)
                return
            }
            Log.d(TAG, "onMethodCall openFileDescriptor: uri=$uriStr mode=$mode")
            handleOpenFileDescriptor(uriStr, mode, result)
        } else {
            result.notImplemented()
        }
    }

    private fun handleRequestWritePermission(uriStr: String, result: Result) {
        val safeContext = context ?: run {
            Log.e(TAG, "handleRequestWritePermission: context is null")
            mainHandler.post {
                result.error("INTERNAL_ERROR", "Context is null", null)
            }
            return
        }

        val originalUri = Uri.parse(uriStr)
        Log.d(TAG, "handleRequestWritePermission: originalUri=$originalUri, authority=${originalUri.authority}")
        
        val isContentUri = originalUri.toString().startsWith("content://")
        
        if (!isContentUri) {
            val filePath = originalUri.toString()
            try {
                val file = java.io.File(filePath)
                val writable = file.exists() && file.canWrite()
                Log.d(TAG, "handleRequestWritePermission: local file path=$filePath, writable=$writable")
                if (writable) {
                    mainHandler.post {
                        result.success(filePath)
                    }
                    return
                }
            } catch (e: Exception) {
                Log.e(TAG, "handleRequestWritePermission: failed checking local file: ${e.message}")
            }
        }

        // Prefer the already granted tree/document permission. This is the path
        // we want for SAF-selected output directories so we do not trigger a
        // per-file confirmation flow when writing many files in the same folder.
        if (isContentUri) {
            try {
                safeContext.contentResolver.openFileDescriptor(originalUri, "rw")?.use {
                    Log.d(TAG, "handleRequestWritePermission: direct rw open succeeded for $originalUri")
                    mainHandler.post {
                        result.success(originalUri.toString())
                    }
                    return
                }
            } catch (e: android.app.RecoverableSecurityException) {
                Log.w(
                    TAG,
                    "handleRequestWritePermission: direct rw open hit RecoverableSecurityException for $originalUri: ${e.message}",
                )
            } catch (e: SecurityException) {
                Log.w(TAG, "handleRequestWritePermission: direct rw open denied for $originalUri: ${e.message}")
            } catch (e: Exception) {
                Log.w(TAG, "handleRequestWritePermission: direct rw open failed for $originalUri: ${e.message}")
            }

            // SAF tree URIs are expected to be writable through the selected folder's
            // persisted permission. If the direct open failed, do not escalate to a
            // per-file write request and instead return null so the caller can fail
            // fast rather than showing a confirmation dialog for each file.
            val isTreeUri = originalUri.authority == "com.android.externalstorage.documents" &&
                    originalUri.pathSegments.let { it.size >= 2 && it[0] == "tree" }
            if (isTreeUri) {
                Log.w(
                    TAG,
                    "handleRequestWritePermission: refusing per-file write request for SAF tree uri=$originalUri",
                )
                mainHandler.post {
                    result.success(null)
                }
                return
            }
        }

        val targetUri = if (isContentUri) {
            resolveToMediaStoreUri(safeContext, originalUri) ?: originalUri
        } else {
            val filePath = originalUri.toString()
            resolvePathToMediaStoreUri(safeContext, filePath) ?: scanFileSynchronously(safeContext, filePath)
        }

        if (targetUri == null) {
            Log.w(TAG, "handleRequestWritePermission: targetUri could not be resolved, returning null")
            mainHandler.post {
                result.success(null)
            }
            return
        }

        val targetUriStr = targetUri.toString()
        Log.d(TAG, "handleRequestWritePermission: resolved targetUri=$targetUriStr")

        // Switch to the main thread to safely run permission checks and start intent activities.
        mainHandler.post {
            // First try to check uri permission directly.
            if (checkUriPermission(targetUri, Intent.FLAG_GRANT_WRITE_URI_PERMISSION)) {
                Log.d(TAG, "handleRequestWritePermission: Already has write permission for $targetUriStr")
                result.success(targetUriStr)
                return@post
            }

            // Try opening the descriptor in "rw" mode to see if we already have write permission.
            try {
                safeContext.contentResolver.openFileDescriptor(targetUri, "rw")?.use {
                    Log.d(TAG, "handleRequestWritePermission: Successfully opened openFileDescriptor in 'rw' mode, returning $targetUriStr")
                    result.success(targetUriStr)
                    return@post
                }
            } catch (e: android.app.RecoverableSecurityException) {
                Log.d(TAG, "handleRequestWritePermission: RecoverableSecurityException caught, launching userAction intent")
                val safeActivity = activity ?: run {
                    Log.e(TAG, "handleRequestWritePermission: activity is null for RecoverableSecurityException")
                    result.error("NO_ACTIVITY", "Activity is null, cannot request write permission", null)
                    return@post
                }
                pendingResult = result
                resolvedUriString = targetUriStr
                try {
                    safeActivity.startIntentSenderForResult(
                        e.userAction.actionIntent.intentSender,
                        REQUEST_WRITE_PERMISSION,
                        null,
                        0,
                        0,
                        0
                    )
                } catch (launchError: Exception) {
                    pendingResult = null
                    resolvedUriString = null
                    Log.e(TAG, "handleRequestWritePermission: failed launching RecoverableSecurityException intent: ${launchError.message}")
                    result.error("WRITE_PERMISSION_FAILED", launchError.message, null)
                }
                return@post
            } catch (e: SecurityException) {
                Log.w(TAG, "handleRequestWritePermission: SecurityException during 'rw' open check: ${e.message}")
            } catch (e: Exception) {
                Log.w(TAG, "handleRequestWritePermission: Exception during 'rw' open check: ${e.message}")
            }

            // Android 11+ (API 30+) MediaStore.createWriteRequest (only for MediaStore URIs)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && targetUri.authority == "media") {
                Log.d(TAG, "handleRequestWritePermission: API 30+, using MediaStore.createWriteRequest")
                val safeActivity = activity ?: run {
                    Log.e(TAG, "handleRequestWritePermission: activity is null for MediaStore.createWriteRequest")
                    result.error("NO_ACTIVITY", "Activity is null, cannot request write permission", null)
                    return@post
                }
                try {
                    val uris = listOf(targetUri)
                    val pendingIntent = MediaStore.createWriteRequest(safeContext.contentResolver, uris)
                    pendingResult = result
                    resolvedUriString = targetUriStr
                    safeActivity.startIntentSenderForResult(
                        pendingIntent.intentSender,
                        REQUEST_WRITE_PERMISSION,
                        null,
                        0,
                        0,
                        0
                    )
                } catch (e: Exception) {
                    Log.e(TAG, "handleRequestWritePermission: MediaStore.createWriteRequest failed: ${e.message}")
                    result.error("WRITE_PERMISSION_FAILED", e.message, null)
                }
            } else {
                Log.w(TAG, "handleRequestWritePermission: Not a media store URI or SDK < 30, and open check failed. No permission available.")
                // If it is not a media store URI or SDK < R, we cannot ask for write permission via createWriteRequest.
                // But we can check if we already have it. If not, return null.
                if (checkUriPermission(targetUri, Intent.FLAG_GRANT_WRITE_URI_PERMISSION)) {
                    result.success(targetUriStr)
                } else {
                    result.success(null)
                }
            }
        }
    }

    private fun handleOpenFileDescriptor(uriStr: String, mode: String, result: Result) {
        val safeContext = context ?: run {
            Log.e(TAG, "handleOpenFileDescriptor: context is null")
            result.error("INTERNAL_ERROR", "Context is null", null)
            return
        }

        val targetUri = Uri.parse(uriStr)
        Log.d(TAG, "handleOpenFileDescriptor: targetUri=$targetUri mode=$mode")

        try {
            safeContext.contentResolver.openFileDescriptor(targetUri, mode)?.use { pfd ->
                val fd = pfd.detachFd()
                Log.d(
                    TAG,
                    "handleOpenFileDescriptor: opened fd=$fd for $uriStr",
                )
                result.success(fd)
                return
            }
            Log.e(
                TAG,
                "handleOpenFileDescriptor: openFileDescriptor returned null for $uriStr",
            )
            result.error("OPEN_FAILED", "openFileDescriptor returned null for $uriStr", null)
        } catch (e: Exception) {
            Log.e(
                TAG,
                "handleOpenFileDescriptor: failed to open fd for $uriStr: ${e.message}",
                e,
            )
            result.error("OPEN_FAILED", "failed to open fd for $uriStr: ${e.message}", e.toString())
        }
    }

    private fun resolveToMediaStoreUri(context: Context, uri: Uri): Uri? {
        if (uri.authority == "media") {
            return uri
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT && android.provider.DocumentsContract.isDocumentUri(context, uri)) {
            val docId = android.provider.DocumentsContract.getDocumentId(uri)
            Log.d(TAG, "resolveToMediaStoreUri: isDocumentUri, docId=$docId")
            if (docId != null) {
                val parts = docId.split(":")
                if (parts.size == 2) {
                    val type = parts[0]
                    val id = parts[1].toLongOrNull()
                    if (id != null) {
                        Log.d(TAG, "resolveToMediaStoreUri: docId matches specific MediaStore ID type=$type, id=$id")
                        if (type.equals("audio", ignoreCase = true)) {
                            return ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id)
                        } else if (type.equals("video", ignoreCase = true)) {
                            return ContentUris.withAppendedId(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, id)
                        } else if (type.equals("image", ignoreCase = true)) {
                            return ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id)
                        }
                    }
                }
                
                // Fallback for ExternalStorageProvider URIs (e.g., primary:Music/song.mp3)
                if (docId.startsWith("primary:", ignoreCase = true)) {
                    val relPath = docId.substring("primary:".length)
                    val fullPath = "/storage/emulated/0/$relPath"
                    Log.d(TAG, "resolveToMediaStoreUri: primary storage path relPath=$relPath, fullPath=$fullPath")
                    
                    // 1. Try scanning synchronously
                    Log.d(TAG, "resolveToMediaStoreUri: Scanning file: $fullPath")
                    val scannedUri = scanFileSynchronously(context, fullPath)
                    if (scannedUri != null) {
                        Log.d(TAG, "resolveToMediaStoreUri: Scanned successfully. Scanned URI: $scannedUri")
                        return scannedUri
                    }
                    
                    // 2. Try querying MediaStore as a fallback
                    Log.d(TAG, "resolveToMediaStoreUri: Scanning returned null, querying MediaStore fallback for $fullPath")
                    val queriedUri = resolvePathToMediaStoreUri(context, fullPath)
                    Log.d(TAG, "resolveToMediaStoreUri: Query returned URI: $queriedUri")
                    return queriedUri
                }
            }
        }
        return null
    }

    private fun scanFileSynchronously(context: Context, filePath: String): Uri? {
        val latch = CountDownLatch(1)
        var resultUri: Uri? = null
        try {
            MediaScannerConnection.scanFile(
                context,
                arrayOf(filePath),
                null
            ) { path, uri ->
                Log.d(TAG, "scanFile Callback: path=$path, uri=$uri")
                resultUri = uri
                latch.countDown()
            }
            val completed = latch.await(3, TimeUnit.SECONDS)
            if (!completed) {
                Log.w(TAG, "scanFileSynchronously: Media scanner timed out for $filePath")
            }
        } catch (e: Exception) {
            Log.e(TAG, "scanFileSynchronously error: ${e.message}", e)
        }
        return resultUri
    }

    private fun resolvePathToMediaStoreUri(context: Context, filePath: String): Uri? {
        val projection = arrayOf(MediaStore.Audio.Media._ID)
        val selection = "${MediaStore.Audio.Media.DATA} = ?"
        val selectionArgs = arrayOf(filePath)
        try {
            context.contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                projection,
                selection,
                selectionArgs,
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val idIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
                    val id = cursor.getLong(idIndex)
                    return ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "resolvePathToMediaStoreUri: failed querying audio MediaStore: ${e.message}")
        }

        // Try general Files MediaStore query
        try {
            val fileProjection = arrayOf(MediaStore.Files.FileColumns._ID)
            val fileSelection = "${MediaStore.Files.FileColumns.DATA} = ?"
            val fileSelectionArgs = arrayOf(filePath)
            val externalUri = MediaStore.Files.getContentUri("external")
            context.contentResolver.query(
                externalUri,
                fileProjection,
                fileSelection,
                fileSelectionArgs,
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val idIndex = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns._ID)
                    val id = cursor.getLong(idIndex)
                    return ContentUris.withAppendedId(externalUri, id)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "resolvePathToMediaStoreUri: failed querying files MediaStore: ${e.message}")
        }
        return null
    }

    private fun checkUriPermission(uri: Uri, modeFlags: Int): Boolean {
        val safeContext = context ?: return false
        return try {
            safeContext.checkUriPermission(
                uri,
                android.os.Process.myPid(),
                android.os.Process.myUid(),
                modeFlags
            ) == android.content.pm.PackageManager.PERMISSION_GRANTED
        } catch (e: Exception) {
            false
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == REQUEST_WRITE_PERMISSION) {
            val result = pendingResult
            val uriStr = resolvedUriString
            pendingResult = null
            resolvedUriString = null
            Log.d(TAG, "onActivityResult: requestCode=$requestCode, resultCode=$resultCode (Activity.RESULT_OK=${Activity.RESULT_OK})")
            if (result != null) {
                if (resultCode == Activity.RESULT_OK) {
                    Log.d(TAG, "onActivityResult: Permission GRANTED, returning $uriStr")
                    result.success(uriStr)
                } else {
                    Log.w(TAG, "onActivityResult: Permission DENIED, returning null")
                    result.success(null)
                }
                return true
            }
        }
        return false
    }

    // ActivityAware implementation
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
        Log.d(TAG, "onAttachedToActivity: Activity attached")
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
        Log.d(TAG, "onDetachedFromActivityForConfigChanges")
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
        Log.d(TAG, "onReattachedToActivityForConfigChanges")
    }

    override fun onDetachedFromActivity() {
        activity = null
        Log.d(TAG, "onDetachedFromActivity: Activity detached")
    }

}
