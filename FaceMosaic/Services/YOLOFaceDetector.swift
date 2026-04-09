import Vision
import CoreGraphics
import CoreML

/// YOLO11n-face CoreML 모델 기반 얼굴 인식 구현체
/// Apple Vision보다 높은 정확도 (WIDERFace 데이터셋 학습)
struct YOLOFaceDetector: FaceDetector {
    let name = "YOLO11n-face"

    func detectFaces(in cgImage: CGImage) async throws -> [DetectedFace] {
        let config = MLModelConfiguration()
        config.computeUnits = .all // Neural Engine + GPU + CPU 자동 선택

        guard let modelURL = Bundle.main.url(forResource: "YOLOFace", withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: "YOLOFace", withExtension: "mlpackage") else {
            throw FaceDetectionError.modelNotFound
        }

        let mlModel = try MLModel(contentsOf: modelURL, configuration: config)
        let vnModel = try VNCoreMLModel(for: mlModel)

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

            // YOLO 모델의 입력 크기에 맞게 이미지 스케일링
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
