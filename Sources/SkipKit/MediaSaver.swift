// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception
#if !SKIP_BRIDGE
import Foundation
#if !SKIP
import Photos
#else
import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.compose.ui.platform.LocalContext
#endif

/// Errors that can occur when saving media to the gallery
public enum MediaSaveError: Error {
    case fileNotFound
    case writeFailed
    case permissionDenied
}

/// Utility for saving images and videos to the device photo library/gallery
public enum MediaSaver {
    /// Save image to device photo library/gallery
    /// - Parameter url: Local file URL of the image to save
    /// - Throws: MediaSaveError if the save fails
    public static func saveImageToGallery(url: URL) async throws {
        #if !SKIP
        try await saveToPhotoLibrary(url: url, isVideo: false)
        #else
        let context = ProcessInfo.processInfo.androidContext
        try saveToMediaStore(context: context, url: url, isVideo: false)
        #endif
    }

    /// Save video to device photo library/gallery
    /// - Parameter url: Local file URL of the video to save
    /// - Throws: MediaSaveError if the save fails
    public static func saveVideoToGallery(url: URL) async throws {
        #if !SKIP
        try await saveToPhotoLibrary(url: url, isVideo: true)
        #else
        let context = ProcessInfo.processInfo.androidContext
        try saveToMediaStore(context: context, url: url, isVideo: false)
        #endif
    }

    #if !SKIP
    private static func saveToPhotoLibrary(url: URL, isVideo: Bool) async throws {
        // Check if file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MediaSaveError.fileNotFound
        }

        // Check permission
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .denied || status == .restricted {
            throw MediaSaveError.permissionDenied
        }

        // Request permission if needed
        if status == .notDetermined {
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            if newStatus == .denied || newStatus == .restricted {
                throw MediaSaveError.permissionDenied
            }
        }

        // Save to photo library
        try await PHPhotoLibrary.shared().performChanges {
            if isVideo {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } else {
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
            }
        }
    }
    #else
    private static func saveToMediaStore(context: Context, url: URL, isVideo: Bool) throws {
        let filePath = url.path
        let sourceFile = java.io.File(filePath)

        // Check if source file exists
        if !sourceFile.exists() {
            throw MediaSaveError.fileNotFound
        }

        // Determine file name and MIME type
        let fileName = sourceFile.getName()
        let mimeType: String
        let contentUri: android.net.Uri

        if isVideo {
            mimeType = getMimeType(fileName: fileName, defaultType: "video/mp4")
            contentUri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        } else {
            mimeType = getMimeType(fileName: fileName, defaultType: "image/jpeg")
            contentUri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }

        // Create content values
        let contentValues = ContentValues()
        contentValues.put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
        contentValues.put(MediaStore.MediaColumns.MIME_TYPE, mimeType)

        // Set relative path for Android 10+ (scoped storage)
        if Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q {
            let relativePath = isVideo
                ? Environment.DIRECTORY_MOVIES + "/SkipKit"
                : Environment.DIRECTORY_PICTURES + "/SkipKit"
            contentValues.put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            contentValues.put(MediaStore.MediaColumns.IS_PENDING, 1)
        }

        // Insert into MediaStore
        let contentResolver = context.contentResolver
        guard let insertUri = contentResolver.insert(contentUri, contentValues) else {
            throw MediaSaveError.writeFailed
        }

        // Copy file content
        do {
            guard let outputStream = contentResolver.openOutputStream(insertUri) else {
                contentResolver.delete(insertUri, nil, nil)
                throw MediaSaveError.writeFailed
            }

            let inputStream = java.io.FileInputStream(sourceFile)
            let buffer = ByteArray(8192)
            var bytesRead: Int
            while (inputStream.read(buffer).also { bytesRead = $0 }) != -1 {
                outputStream.write(buffer, 0, bytesRead)
            }
            outputStream.flush()
            outputStream.close()
            inputStream.close()

            // Mark as complete for Android 10+
            if Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q {
                contentValues.clear()
                contentValues.put(MediaStore.MediaColumns.IS_PENDING, 0)
                contentResolver.update(insertUri, contentValues, nil, nil)
            }

            logger.log("MediaSaver: Saved \(filePath) to gallery")
        } catch {
            // Clean up on failure
            contentResolver.delete(insertUri, nil, nil)
            logger.error("MediaSaver: Error saving to gallery: \(error)")
            throw MediaSaveError.writeFailed
        }
    }

    private static func getMimeType(fileName: String, defaultType: String) -> String {
        let extension_ = fileName.substringAfterLast(".", "")
        if extension_.isEmpty {
            return defaultType
        }
        let mimeType = android.webkit.MimeTypeMap.getSingleton()
            .getMimeTypeFromExtension(extension_.lowercased())
        return mimeType ?? defaultType
    }
    #endif
}
#endif
