import Foundation

/// 효과 종류
enum MosaicStyle: String, CaseIterable, Hashable {
    case pixelate = "모자이크"
    case blur = "블러"
}

/// 모자이크 강도 프리셋
enum MosaicIntensity: String, CaseIterable {
    case light = "약하게"
    case medium = "보통"
    case strong = "강하게"

    var pixelScale: Float {
        switch self {
        case .light: return 12
        case .medium: return 25
        case .strong: return 50
        }
    }

    var blurRadius: Float {
        switch self {
        case .light: return 15
        case .medium: return 30
        case .strong: return 60
        }
    }

    func value(for style: MosaicStyle) -> Float {
        style == .blur ? blurRadius : pixelScale
    }
}

/// 영역 크기 프리셋
enum RegionSize: String, CaseIterable {
    case tight = "딱맞게"
    case normal = "보통"
    case wide = "넓게"

    var multiplier: Float {
        switch self {
        case .tight: return 1.0
        case .normal: return 1.3
        case .wide: return 1.8
        }
    }
}
