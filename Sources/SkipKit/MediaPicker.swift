// Copyright 2025–2026 Skip
// SPDX-License-Identifier: MPL-2.0
#if !SKIP_BRIDGE
import Foundation
import SwiftUI
#if !SKIP
import UniformTypeIdentifiers
#endif

#if SKIP
import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.result.contract.ActivityResultContracts.GetContent
import androidx.activity.result.contract.ActivityResultContracts.TakePicture
import androidx.activity.result.PickVisualMediaRequest
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat.startActivity
#endif

public enum MediaPickerType {
    case camera, library
}

public enum MediaPickerMediaType {
    case imagesOnly
    case videosOnly
    case imagesAndVideos
}

#if SKIP
// https://stackoverflow.com/questions/51640154/android-view-contextthemewrapper-cannot-be-cast-to-android-app-activity/63360115#63360115
extension Context {
    func asActivity() -> Activity {
        if let activity = self as? Activity {
            return activity
        } else if let wrapper = self as? android.content.ContextWrapper {
            return wrapper.baseContext.asActivity()
        } else {
            fatalError("could not extract activity from: \(self)")
        }
    }
}

/// Copies content from a content:// URI to a local file and returns the file path
func copyContentToLocalFile(context: Context, uri: android.net.Uri) -> String? {
    let contentResolver = context.contentResolver

    // Get the file extension from MIME type
    let mimeType = contentResolver.getType(uri)
    let extension_: String
    if let mimeType = mimeType {
        extension_ = MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType) ?? "tmp"
    } else {
        extension_ = "tmp"
    }

    // Try to get the original filename
    var fileName = "media_\(java.util.UUID.randomUUID().toString()).\(extension_)"
    let cursor = contentResolver.query(uri, nil, nil, nil, nil)
    if let cursor = cursor {
        if cursor.moveToFirst() {
            let nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if nameIndex >= 0 {
                let name = cursor.getString(nameIndex)
                if let name = name, !name.isEmpty {
                    fileName = name
                }
            }
        }
        cursor.close()
    }

    // Create destination file in cache directory
    let cacheDir = context.cacheDir
    let destFile = java.io.File(cacheDir, fileName)

    do {
        // Open input stream from content URI
        guard let inputStream = contentResolver.openInputStream(uri) else {
            logger.error("copyContentToLocalFile: Failed to open input stream for \(uri)")
            return nil
        }

        // Copy to output file
        let outputStream = java.io.FileOutputStream(destFile)
        let buffer = ByteArray(8192)
        var bytesRead: Int
        while (inputStream.read(buffer).also { bytesRead = $0 }) != -1 {
            outputStream.write(buffer, 0, bytesRead)
        }
        outputStream.flush()
        outputStream.close()
        inputStream.close()

        logger.log("copyContentToLocalFile: Copied \(uri) to \(destFile.absolutePath)")
        return destFile.absolutePath
    } catch {
        logger.error("copyContentToLocalFile: Error copying file: \(error)")
        return nil
    }
}
#endif

extension View {
    /// Enables a media picker interface for the camera or photo library can be activated through the `isPresented` binding, and which returns the selected media through the `selectedMediaURL` binding.
    ///
    /// On iOS, this camera selector will be presented in a `fullScreenCover` view, whereas the media library browser will be presented in a `sheet`.
    /// On Android, the camera and library browser will be activated through Intents after querying for the necessary permissions.
    ///
    /// - Parameters:
    ///   - type: Whether to use the camera or photo library
    ///   - mediaType: The type of media to pick (images only, videos only, or both). Defaults to `.imagesOnly` for backward compatibility.
    ///   - isPresented: Binding to control picker presentation
    ///   - selectedMediaURL: Binding that receives the selected media URL
    @ViewBuilder public func withMediaPicker(type: MediaPickerType, mediaType: MediaPickerMediaType = .imagesOnly, isPresented: Binding<Bool>, selectedMediaURL: Binding<URL?>) -> some View {
        switch type {
        case .library:
            #if !SKIP
            #if os(iOS)
            sheet(isPresented: isPresented) {
                PhotoLibraryPicker(sourceType: .photoLibrary, mediaType: mediaType, selectedMediaURL: selectedMediaURL)
                    .presentationDetents([.medium])
            }
            #endif
            #else
            let context = LocalContext.current
            let pickMediaLauncher = rememberLauncherForActivityResult(contract: ActivityResultContracts.PickVisualMedia()) { uri in
                // uri e.g.: content://media/picker/0/com.android.providers.media.photopicker/media/1000000025
                isPresented.wrappedValue = false // clear the presented bit
                logger.log("pickMediaLauncher: \(uri)")
                if let uri = uri {
                    // Copy content to local file since content:// URIs can't be read directly with Data(contentsOf:)
                    if let localPath = copyContentToLocalFile(context: context, uri: uri) {
                        selectedMediaURL.wrappedValue = URL(fileURLWithPath: localPath)
                    } else {
                        logger.error("pickMediaLauncher: Failed to copy content to local file")
                    }
                }
            }

            return onChange(of: isPresented.wrappedValue) { presented in
                if presented == true {
                    switch mediaType {
                    case .imagesOnly:
                        pickMediaLauncher.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                    case .videosOnly:
                        pickMediaLauncher.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.VideoOnly))
                    case .imagesAndVideos:
                        pickMediaLauncher.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageAndVideo))
                    }
                }
            }
            #endif

        case .camera:
            #if !SKIP
            #if os(iOS)
            fullScreenCover(isPresented: isPresented) {
                PhotoLibraryPicker(sourceType: .camera, mediaType: mediaType, selectedMediaURL: selectedMediaURL)
            }
            #endif
            #else
            // SKIP INSERT:
            // var imageURLString by rememberSaveable { mutableStateOf<String?>(null) }

            // alternatively, we could use TakePicturePreview, which returns a Bitmap
            let takePictureLauncher = rememberLauncherForActivityResult(contract: ActivityResultContracts.TakePicture()) { success in
                // uri e.g.: content://media/picker/0/com.android.providers.media.photopicker/media/1000000025
                isPresented.wrappedValue = false // clear the presented bit
                logger.log("takePictureLauncher: success: \(success) from \(imageURLString)")
                if success == true, let imageURLString {
                    selectedMediaURL.wrappedValue = URL(string: imageURLString)
                }
            }

            // FIXME: 05-20 20:29:41.435  8964  8964 E AndroidRuntime: java.lang.SecurityException: Permission Denial: starting Intent { act=android.media.action.IMAGE_CAPTURE flg=0x3 cmp=com.android.camera2/com.android.camera.CaptureActivity clip={text/uri-list hasLabel(0) {}} (has extras) } from ProcessRecord{c5fb1f 8964:skip.photo.chat/u0a190} (pid=8964, uid=10190) with revoked permission android.permission.CAMERA

            let context = LocalContext.current

            let PERM_REQUEST_CAMERA = 642

            return onChange(of: isPresented.wrappedValue) { presented in
                if presented == true {
                    var perms = listOf(Manifest.permission.CAMERA).toTypedArray()
                    if ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED {
                        logger.log("takePictureLauncher: requesting Manifest.permission.CAMERA permission")
                        ActivityCompat.requestPermissions(context.asActivity(), perms, PERM_REQUEST_CAMERA)
                        isPresented.wrappedValue = false
                    } else {
                        let storageDir = context.getExternalFilesDir(android.os.Environment.DIRECTORY_PICTURES)
                        let ext = ".jpg"
                        let tmpFile = java.io.File.createTempFile("SkipKit_\(UUID().uuidString)", ext, storageDir)
                        logger.log("takePictureLauncher: create tmpFile: \(tmpFile)")

                        imageURLString = androidx.core.content.FileProvider.getUriForFile(context.asActivity(), context.getPackageName() + ".fileprovider", tmpFile).kotlin().toString()
                        logger.log("takePictureLauncher: takePictureLauncher.launch: \(imageURLString)")

                        takePictureLauncher.launch(android.net.Uri.parse(imageURLString))
                    }
                }
            }
            #endif
        }
    }

    /// Backward-compatible overload that uses `selectedImageURL` parameter name.
    /// Prefer using `withMediaPicker(type:mediaType:isPresented:selectedMediaURL:)` for new code.
    @ViewBuilder public func withMediaPicker(type: MediaPickerType, isPresented: Binding<Bool>, selectedImageURL: Binding<URL?>) -> some View {
        withMediaPicker(type: type, mediaType: .imagesOnly, isPresented: isPresented, selectedMediaURL: selectedImageURL)
    }
}

#if !SKIP
#if os(iOS)
struct PhotoLibraryPicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let mediaType: MediaPickerMediaType
    @Binding var selectedMediaURL: URL?
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let imagePicker = UIImagePickerController()
        imagePicker.delegate = context.coordinator
        imagePicker.sourceType = sourceType

        // Set media types based on mediaType parameter
        switch mediaType {
        case .imagesOnly:
            imagePicker.mediaTypes = [UTType.image.identifier]
        case .videosOnly:
            imagePicker.mediaTypes = [UTType.movie.identifier]
        case .imagesAndVideos:
            imagePicker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        }

        return imagePicker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {

    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: PhotoLibraryPicker

        init(_ parent: PhotoLibraryPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            logger.info("didFinishPickingMediaWithInfo: \(info)")

            // Check for video first
            if let mediaURL = info[.mediaURL] as? URL {
                logger.info("imagePickerController: selected video mediaURL: \(mediaURL)")
                parent.selectedMediaURL = mediaURL
            } else if let imageURL = info[.imageURL] as? URL {
                // for the media picker, it provided direct access to the image URL
                logger.info("imagePickerController: selected imageURL: \(imageURL)")
                parent.selectedMediaURL = imageURL
            } else if let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage {
                logger.info("imagePickerController: selected editedImage: \(image)")
                // need to save to a temporary URL so it can be loaded
                if let imageData = image.pngData() {
                    let imageURL = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
                    logger.info("imagePickerController: saving image to: \(imageURL.path)")
                    do {
                        try imageData.write(to: imageURL)
                        parent.selectedMediaURL = imageURL
                    } catch {
                        logger.warning("imagePickerController: error writing image to \(imageURL.path): \(error)")
                    }
                } else {
                    logger.warning("imagePickerController: error extracting PNG data from image: \(image)")
                }
            } else {
                logger.info("imagePickerController: no media found in keys: \(info.keys)")
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            logger.info("imagePickerControllerDidCancel")
            parent.dismiss()
        }
    }
}
#endif
#endif
#endif
