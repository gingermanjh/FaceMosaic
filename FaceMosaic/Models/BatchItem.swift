import CoreGraphics
import Foundation

enum BatchStatus: String {
    case pending
    case detecting
    case detected
    case edited
    case error
}

struct BatchItem: Identifiable, Hashable {
    static func == (lhs: BatchItem, rhs: BatchItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    let id: UUID
    let sourceData: Data
    var sourceName: String?  // 원본 파일명 (확장자 제외)
    var originalImage: CGImage?      // nil when not editing; loaded on demand
    var thumbnailImage: CGImage?     // always in memory (~200px)
    var processedPreview: CGImage?   // preview-res (~1024px), cached to disk
    var regions: [MosaicRegion]
    var status: BatchStatus
    var faceCount: Int
    var mosaicStyle: MosaicStyle
    var pixelScale: Float
    var errorMessage: String?

    init(id: UUID = UUID(), sourceData: Data) {
        self.id = id
        self.sourceData = sourceData
        self.regions = []
        self.status = .pending
        self.faceCount = 0
        self.mosaicStyle = .blur
        self.pixelScale = MosaicIntensity.medium.blurRadius
    }
}
