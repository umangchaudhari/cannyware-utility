import Photos

enum PhotoLibrarySaver {
    static func save(_ data: Data) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw PhotoError.photoAccessDenied }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = "Cannyware-Utility-compressed.jpg"
            request.addResource(with: .photo, data: data, options: options)
        }
    }

    static func save(files: [URL]) async throws {
        guard !files.isEmpty else { throw DocumentError.emptySelection }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw PhotoError.photoAccessDenied }
        try await PHPhotoLibrary.shared().performChanges {
            for url in files {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = url.lastPathComponent
                request.addResource(with: .photo, fileURL: url, options: options)
            }
        }
    }
}
