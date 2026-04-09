import SwiftUI

#if os(iOS)
import UIKit
public typealias PlatformImage = UIImage
#elseif os(macOS)
import AppKit
public typealias PlatformImage = NSImage
#endif

extension PlatformImage {
    var asCGImage: CGImage? {
        #if os(iOS)
        return cgImage
        #elseif os(macOS)
        return cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
    }
}

extension CGImage {
    var asPlatformImage: PlatformImage {
        #if os(iOS)
        return UIImage(cgImage: self)
        #elseif os(macOS)
        return NSImage(cgImage: self, size: NSSize(width: width, height: height))
        #endif
    }

    func pngData() -> Data? {
        #if os(iOS)
        return UIImage(cgImage: self).pngData()
        #elseif os(macOS)
        let nsImage = NSImage(cgImage: self, size: NSSize(width: width, height: height))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
        #endif
    }

    /// JPEG로 내보내기 (품질 0.92 — 거의 무손실에 가까운 수준, EXIF 제거)
    func jpegData(quality: CGFloat = 0.92) -> Data? {
        guard let mutableData = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(
                  mutableData, "public.jpeg" as CFString, 1, nil
              ) else { return nil }

        // EXIF/메타데이터 없이 픽셀 데이터만 저장
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, self, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }

    /// PNG로 내보내기 (EXIF 제거)
    func pngDataStripped() -> Data? {
        guard let mutableData = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(
                  mutableData, "public.png" as CFString, 1, nil
              ) else { return nil }

        CGImageDestinationAddImage(destination, self, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }
}
