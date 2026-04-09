import Vision
import CoreGraphics

/// Apple Vision 프레임워크 기반 얼굴 인식 구현체
struct VisionFaceDetector: FaceDetector {
    let name = "Apple Vision"

    func detectFaces(in cgImage: CGImage) async throws -> [DetectedFace] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectFaceRectanglesRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let faces = (request.results as? [VNFaceObservation])?.map { observation in
                    DetectedFace(
                        boundingBox: observation.boundingBox.visionToTopLeft(),
                        confidence: observation.confidence,
                        landmarks: nil
                    )
                } ?? []

                continuation.resume(returning: faces)
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
