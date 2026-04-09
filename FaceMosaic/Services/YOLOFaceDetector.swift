import Vision
import CoreGraphics
import CoreML

/// YOLO11n-face CoreML 모델 기반 얼굴 인식 구현체
/// VNCoreMLModel을 캐싱하여 배치 처리 시 1회만 로드
final class YOLOFaceDetector: FaceDetector {
    let name = "YOLO11n-face"

    private var cachedModel: VNCoreMLModel?

    private func getModel() throws -> VNCoreMLModel {
        if let cached = cachedModel { return cached }

        let config = MLModelConfiguration()
        config.computeUnits = .all

        guard let modelURL = Bundle.main.url(forResource: "YOLOFace", withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: "YOLOFace", withExtension: "mlpackage") else {
            throw FaceDetectionError.modelNotFound
        }

        let mlModel = try MLModel(contentsOf: modelURL, configuration: config)
        let vnModel = try VNCoreMLModel(for: mlModel)
        cachedModel = vnModel
        return vnModel
    }

    func detectFaces(in cgImage: CGImage) async throws -> [DetectedFace] {
        let vnModel = try getModel()

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNCoreMLRequest(model: vnModel) { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let faces = (request.results as? [VNRecognizedObjectObservation])?.map { obs in
                    DetectedFace(
                        boundingBox: obs.boundingBox.visionToTopLeft(),
                        confidence: obs.confidence,
                        landmarks: nil
                    )
                } ?? []

                continuation.resume(returning: faces)
            }

            request.imageCropAndScaleOption = .scaleFill

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

enum FaceDetectionError: LocalizedError {
    case modelNotFound

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "YOLOFace.mlpackage 모델 파일을 찾을 수 없습니다."
        }
    }
}
