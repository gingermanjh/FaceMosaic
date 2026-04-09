import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

struct ImageProcessingService {
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    /// 영역별 개별 스타일/강도를 지원하는 마스크 기반 합성
    func applyEffect(
        to cgImage: CGImage,
        regions: [MosaicRegion],
        globalPixelScale: Float,
        style globalStyle: MosaicStyle
    ) -> CGImage? {
        let ciImage = CIImage(cgImage: cgImage)
        let imageSize = ciImage.extent.size

        let enabledRegions = regions.filter(\.isEnabled)
        guard !enabledRegions.isEmpty else { return cgImage }

        // (스타일, 강도) 조합으로 그룹핑 — 같은 효과끼리 한 번에 처리
        let grouped = Dictionary(grouping: enabledRegions) { region -> EffectKey in
            EffectKey(
                style: region.style ?? globalStyle,
                scale: region.pixelScale ?? globalPixelScale
            )
        }

        var result = ciImage

        for (key, regionsInGroup) in grouped {
            // 1. 효과 적용된 이미지 생성
            guard let effected = applyFilter(
                to: ciImage, style: key.style, scale: key.scale
            ) else { continue }

            // 2. 마스크 생성
            var mask = CIImage(color: .black).cropped(to: ciImage.extent)
            let white = CIImage(color: .white)
            for region in regionsInGroup {
                let pixelRect = region.effectiveRect.topLeftToCIImage(imageSize: imageSize)
                mask = white.cropped(to: pixelRect).composited(over: mask)
            }

            // 3. 블렌딩
            let blendFilter = CIFilter.blendWithMask()
            blendFilter.inputImage = effected
            blendFilter.backgroundImage = result
            blendFilter.maskImage = mask

            if let blended = blendFilter.outputImage {
                result = blended
            }
        }

        return context.createCGImage(result, from: ciImage.extent)
    }

    private func applyFilter(to image: CIImage, style: MosaicStyle, scale: Float) -> CIImage? {
        switch style {
        case .pixelate:
            let filter = CIFilter.pixellate()
            filter.inputImage = image
            filter.scale = scale
            return filter.outputImage
        case .blur:
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = image
            filter.radius = scale
            return filter.outputImage?.cropped(to: image.extent)
        }
    }
}

/// 그룹핑 키: 같은 스타일+강도의 영역은 한 번에 처리
private struct EffectKey: Hashable {
    let style: MosaicStyle
    let scale: Float
}
