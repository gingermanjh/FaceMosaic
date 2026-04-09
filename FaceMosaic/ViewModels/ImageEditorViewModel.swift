import SwiftUI
import PhotosUI
import Photos
import UniformTypeIdentifiers

@MainActor
final class ImageEditorViewModel: ObservableObject {
    // MARK: - Published State
    @Published var selectedPhotoItem: PhotosPickerItem? = nil
    @Published var originalImage: CGImage? = nil
    @Published var processedImage: CGImage? = nil
    @Published var regions: [MosaicRegion] = []
    @Published var pixelScale: Float = 30.0
    @Published var mosaicStyle: MosaicStyle = .blur
    @Published var isDetectingFaces = false
    @Published var isProcessing = false
    @Published var errorMessage: String? = nil
    @Published var statusMessage: String? = nil
    @Published var selectedRegionId: UUID? = nil

    // MARK: - Preview image (축소 이미지로 빠른 편집)
    private var previewImage: CGImage? = nil
    private static let previewMaxSize: CGFloat = 1024

    // MARK: - Services
    private let faceDetector: FaceDetector
    private let imageProcessor = ImageProcessingService()
    private var processingTask: Task<Void, Never>?

    init(faceDetector: FaceDetector = YOLOFaceDetector()) {
        self.faceDetector = faceDetector
    }

    /// BatchItem에서 편집기 진입 시 사용. detectFaces() 생략 (이미 감지됨).
    init(batchItem: BatchItem) {
        self.faceDetector = YOLOFaceDetector()
        if let platformImage = PlatformImage(data: batchItem.sourceData),
           let cgImage = platformImage.asCGImage {
            self.originalImage = cgImage
            self.previewImage = Self.createPreview(from: cgImage)
        }
        self.regions = batchItem.regions
        self.mosaicStyle = batchItem.mosaicStyle
        self.pixelScale = batchItem.pixelScale
        // 즉시 프리뷰 렌더링 (감지 생략)
        Task { @MainActor in
            self.reprocessImage()
        }
    }

    // MARK: - Photo Loading
    func loadImage() async {
        guard let item = selectedPhotoItem else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let platformImage = PlatformImage(data: data),
                  let cgImage = platformImage.asCGImage else {
                errorMessage = "이미지를 불러올 수 없습니다."
                return
            }
            await setImage(cgImage)
        } catch {
            errorMessage = "이미지 로드 실패: \(error.localizedDescription)"
        }
    }

    func loadFromFile(url: URL) async {
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "파일에 접근할 수 없습니다."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url),
              let platformImage = PlatformImage(data: data),
              let cgImage = platformImage.asCGImage else {
            errorMessage = "이미지를 불러올 수 없습니다."
            return
        }
        await setImage(cgImage)
    }

    func openFilePicker() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await self.loadFromFile(url: url) }
        }
        #endif
    }

    func loadFromDrop(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
            Task { @MainActor in
                guard let data, error == nil,
                      let platformImage = PlatformImage(data: data),
                      let cgImage = platformImage.asCGImage else {
                    self.errorMessage = "드롭된 이미지를 불러올 수 없습니다."
                    return
                }
                await self.setImage(cgImage)
            }
        }
    }

    func loadFromClipboard() async {
        #if os(iOS)
        guard UIPasteboard.general.hasImages,
              let uiImage = UIPasteboard.general.image,
              let cgImage = uiImage.cgImage else {
            errorMessage = "클립보드에 이미지가 없습니다."
            return
        }
        await setImage(cgImage)
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        guard let data = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png),
              let nsImage = NSImage(data: data),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            errorMessage = "클립보드에 이미지가 없습니다."
            return
        }
        await setImage(cgImage)
        #endif
    }

    private func setImage(_ cgImage: CGImage) async {
        originalImage = cgImage
        previewImage = Self.createPreview(from: cgImage)
        regions = []
        processedImage = cgImage
        selectedRegionId = nil
        await detectFaces()
    }

    /// 편집용 축소 이미지 생성 (최대 1024px)
    private static func createPreview(from cgImage: CGImage) -> CGImage? {
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        let maxDim = max(w, h)
        guard maxDim > previewMaxSize else { return cgImage }

        let scale = previewMaxSize / maxDim
        let newW = Int(w * scale)
        let newH = Int(h * scale)

        guard let context = CGContext(
            data: nil, width: newW, height: newH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return cgImage }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return context.makeImage()
    }

    // MARK: - Face Detection
    func detectFaces() async {
        guard let cgImage = originalImage else { return }
        isDetectingFaces = true
        defer { isDetectingFaces = false }

        do {
            let faces = try await faceDetector.detectFaces(in: cgImage)
            let faceRegions = faces.map {
                MosaicRegion(normalizedRect: $0.boundingBox, source: .autoDetected)
            }
            regions.append(contentsOf: faceRegions)

            if faces.isEmpty {
                statusMessage = "얼굴이 감지되지 않았습니다. 수동으로 영역을 추가할 수 있습니다."
            } else {
                statusMessage = "\(faces.count)개의 얼굴이 감지되었습니다."
            }
            reprocessImage()
        } catch {
            errorMessage = "얼굴 감지 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - Region Management
    func addManualRegion(normalizedRect: CGRect) {
        let clamped = normalizedRect.clamped()
        guard clamped.width > 0.01, clamped.height > 0.01 else { return }
        regions.append(MosaicRegion(normalizedRect: clamped, source: .manual))
        reprocessImage()
    }

    func toggleRegion(id: UUID) {
        guard let index = regions.firstIndex(where: { $0.id == id }) else { return }
        regions[index].isEnabled.toggle()
        reprocessImage()
    }

    func removeRegion(id: UUID) {
        regions.removeAll { $0.id == id }
        if selectedRegionId == id { selectedRegionId = nil }
        reprocessImage()
    }

    /// 영역별 스타일 변경
    func setRegionStyle(id: UUID, style: MosaicStyle) {
        guard let index = regions.firstIndex(where: { $0.id == id }) else { return }
        regions[index].style = style
        // 스타일 전환 시 강도를 해당 스타일의 기본값으로 리셋
        regions[index].pixelScale = MosaicIntensity.medium.value(for: style)
        reprocessImage()
    }

    /// 프리셋으로 모자이크 강도 변경 (영역의 스타일에 맞는 값 적용)
    func setRegionIntensity(id: UUID, intensity: MosaicIntensity) {
        guard let index = regions.firstIndex(where: { $0.id == id }) else { return }
        let regionStyle = regions[index].style ?? mosaicStyle
        regions[index].pixelScale = intensity.value(for: regionStyle)
        reprocessImage()
    }

    /// 프리셋으로 영역 크기 변경
    func setRegionSize(id: UUID, size: RegionSize) {
        guard let index = regions.firstIndex(where: { $0.id == id }) else { return }
        regions[index].sizeMultiplier = size.multiplier
        reprocessImage()
    }

    /// 드래그 중: 값만 변경 (이미지 재처리 안 함)
    func updateRegionScale(id: UUID, pixelScale: Float?) {
        guard let index = regions.firstIndex(where: { $0.id == id }) else { return }
        regions[index].pixelScale = pixelScale
    }

    /// 드래그 중: 값만 변경 (이미지 재처리 안 함)
    func updateRegionSize(id: UUID, multiplier: Float) {
        guard let index = regions.firstIndex(where: { $0.id == id }) else { return }
        regions[index].sizeMultiplier = multiplier
    }

    /// 이미지 위에서 탭한 좌표로 영역 선택
    func selectRegion(at normalizedPoint: CGPoint) {
        // 탭 위치에 해당하는 영역 찾기 (effectiveRect 기준)
        let tapped = regions.first { region in
            region.isEnabled && region.effectiveRect.contains(normalizedPoint)
        }
        selectedRegionId = tapped?.id
    }

    // MARK: - Image Processing (백그라운드 스레드 + 프리뷰 이미지)
    func reprocessImage() {
        processingTask?.cancel()
        let preview = self.previewImage ?? self.originalImage
        let regions = self.regions
        let scale = self.pixelScale
        let style = self.mosaicStyle
        let processor = self.imageProcessor

        processingTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            guard let preview else { return }

            let result = await Task.detached(priority: .userInitiated) {
                processor.applyEffect(
                    to: preview, regions: regions, globalPixelScale: scale, style: style
                )
            }.value

            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                self?.processedImage = result ?? preview
            }
        }
    }

    func updatePixelScale(_ newValue: Float) {
        pixelScale = newValue
        reprocessImage()
    }

    // MARK: - Export (내보내기 시에만 원본 해상도)
    func renderFullResolution() -> CGImage? {
        guard let original = originalImage else { return nil }
        return imageProcessor.applyEffect(
            to: original, regions: regions, globalPixelScale: pixelScale, style: mosaicStyle
        )
    }

    func exportToTemporaryFile() -> URL? {
        guard let cgImage = renderFullResolution(),
              let data = cgImage.jpegData() else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FaceMosaic_\(Date.now.timeIntervalSince1970).jpg")
        try? data.write(to: url)
        return url
    }

    func saveToPhotos() async {
        guard let cgImage = renderFullResolution() else { return }

        #if os(iOS)
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            errorMessage = "사진 라이브러리 접근이 거부되었습니다."
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                if let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.92) {
                    request.addResource(with: .photo, data: data, options: nil)
                }
            }
            statusMessage = "사진이 저장되었습니다."
        } catch {
            errorMessage = "저장 실패: \(error.localizedDescription)"
        }
        #elseif os(macOS)
        guard let data = cgImage.jpegData() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.jpeg, .png]
        panel.nameFieldStringValue = "FaceMosaic_export.jpg"
        let response = panel.runModal()
        if response == .OK, let url = panel.url {
            do {
                // 확장자에 따라 포맷 결정
                let exportData: Data?
                if url.pathExtension.lowercased() == "png" {
                    exportData = cgImage.pngDataStripped()
                } else {
                    exportData = cgImage.jpegData()
                }
                if let exportData {
                    try exportData.write(to: url)
                    statusMessage = "저장 완료: \(url.lastPathComponent)"
                }
            } catch {
                errorMessage = "저장 실패: \(error.localizedDescription)"
            }
        }
        #endif
    }
}
