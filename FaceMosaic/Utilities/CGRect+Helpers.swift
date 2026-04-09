import CoreGraphics

extension CGRect {
    /// Vision 좌표(bottom-left origin) → SwiftUI/일반 좌표(top-left origin) 변환
    func visionToTopLeft() -> CGRect {
        CGRect(
            x: origin.x,
            y: 1.0 - origin.y - height,
            width: width,
            height: height
        )
    }

    /// 정규화 좌표(0~1) → 지정된 크기의 픽셀 좌표로 스케일링
    func scaled(to size: CGSize) -> CGRect {
        CGRect(
            x: origin.x * size.width,
            y: origin.y * size.height,
            width: width * size.width,
            height: height * size.height
        )
    }

    /// top-left 정규화 좌표 → CIImage 좌표(bottom-left 픽셀) 변환
    func topLeftToCIImage(imageSize: CGSize) -> CGRect {
        CGRect(
            x: origin.x * imageSize.width,
            y: (1.0 - origin.y - height) * imageSize.height,
            width: width * imageSize.width,
            height: height * imageSize.height
        )
    }

    /// 값을 0~1 범위로 클램핑
    func clamped() -> CGRect {
        let x = max(0, min(1, origin.x))
        let y = max(0, min(1, origin.y))
        let w = max(0, min(1 - x, width))
        let h = max(0, min(1 - y, height))
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
