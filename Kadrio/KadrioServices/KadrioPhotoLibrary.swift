import Foundation
import Photos

struct KadrioPhotoLibrary {
    static func authorize() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw KadrioError.photoAccess }
    }

    static func save(_ url: URL, recordIdentifier: (@Sendable (String) -> Void)? = nil) async throws {
        try await authorize()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, fileURL: url, options: nil)
                if let identifier = request.placeholderForCreatedAsset?.localIdentifier {
                    recordIdentifier?(identifier)
                }
            } completionHandler: { success, error in
                if success { continuation.resume() }
                else { continuation.resume(throwing: error ?? KadrioError.storage) }
            }
        }
    }

    static func containsAsset(with identifier: String) -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return false }
        return PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject != nil
    }
}
