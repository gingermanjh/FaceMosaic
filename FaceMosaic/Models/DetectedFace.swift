import CoreGraphics

struct FaceLandmarks {
    let leftEye: CGPoint?
    let rightEye: CGPoint?
    let nose: CGPoint?
    let mouth: CGPoint?
}

struct DetectedFace {
    /// 정규화 좌표 (top-left origin, 0~1 범위)
    let boundingBox: CGRect
    /// 신뢰도 (0~1)
    let confidence: Float
    /// 얼굴 랜드마크 (지원하는 엔진만 제공)
    let landmarks: FaceLandmarks?
}
