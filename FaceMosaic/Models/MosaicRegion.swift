import Foundation

enum RegionSource: String {
    case autoDetected
    case manual
}

struct MosaicRegion: Identifiable {
    let id: UUID
    /// 정규화 좌표 (top-left origin, 0~1 범위)
    var normalizedRect: CGRect
    var source: RegionSource
    var isEnabled: Bool
    /// 개별 효과 스타일 (nil이면 글로벌 설정 사용)
    var style: MosaicStyle?
    /// 개별 모자이크 강도 (nil이면 글로벌 설정 사용)
    var pixelScale: Float?
    /// 영역 크기 배율 (1.0 = 감지된 크기 그대로, 1.5 = 50% 확대)
    var sizeMultiplier: Float

    init(
        id: UUID = UUID(),
        normalizedRect: CGRect,
        source: RegionSource,
        isEnabled: Bool = true,
        style: MosaicStyle? = nil,
        pixelScale: Float? = nil,
        sizeMultiplier: Float = 1.0
    ) {
        self.id = id
        self.normalizedRect = normalizedRect
        self.source = source
        self.isEnabled = isEnabled
        self.style = style
        self.pixelScale = pixelScale
        self.sizeMultiplier = sizeMultiplier
    }

    /// sizeMultiplier가 적용된 실제 영역
    var effectiveRect: CGRect {
        let cx = normalizedRect.midX
        let cy = normalizedRect.midY
        let newW = normalizedRect.width * CGFloat(sizeMultiplier)
        let newH = normalizedRect.height * CGFloat(sizeMultiplier)
        return CGRect(
            x: cx - newW / 2,
            y: cy - newH / 2,
            width: newW,
            height: newH
        ).clamped()
    }
}
