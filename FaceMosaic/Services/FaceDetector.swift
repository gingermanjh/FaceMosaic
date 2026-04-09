import CoreGraphics

/// 얼굴 인식 엔진 프로토콜
/// 구현체를 교체하면 다른 엔진(ML Kit, MediaPipe 등)으로 전환 가능
protocol FaceDetector {
    var name: String { get }
    func detectFaces(in image: CGImage) async throws -> [DetectedFace]
}
