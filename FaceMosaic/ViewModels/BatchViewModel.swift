import SwiftUI
import PhotosUI
import Photos
import UniformTypeIdentifiers
import os

private let logger = Logger(subsystem: "FaceMosaic", category: "Batch")

@MainActor
@Observable
final class BatchViewModel {
    // MARK: - State
    var items: [BatchItem] = []
    var isProcessing = false
    var processedCount = 0
    var isExporting = false
    var exportProgress: Double = 0
    var statusMessage: String? = nil
    var selectedItemForEditing: BatchItem? = nil

    // MARK: - Services
    private let faceDetector: FaceDetector
    private let imageProcessor = ImageProcessingService()
    private var processingTask: Task<Void, Never>?

    static let maxItems = 30
    private static let previewMaxSize: CGFloat = 1024
    private static let thumbnailSize: CGFloat = 200

    init(faceDetector: FaceDetector = YOLOFaceDetector()) {
        self.faceDetector = faceDetector
    }

    // MARK: - Add Photos (PhotosPicker)
    func addFromPicker(items pickerItems: [PhotosPickerItem]) {
        Task {
            var addedCount = 0
            for item in pickerItems {
                guard self.items.count < Self.maxItems else {
                    statusMessage = "최대 \(Self.maxItems)장까지 선택할 수 있습니다."
                    break
                }
                if let data = try? await item.loadTransferable(type: Data.self) {
                    self.items.append(BatchItem(sourceData: data))
                    addedCount += 1
                }
            }
            if addedCount > 0 {
                startProcessingIfNeeded()
            }
        }
    }

    // MARK: - Add Photos (Drag & Drop)
    func addFromDrop(providers: [NSItemProvider]) {
        for provider in providers {
            guard items.count < Self.maxItems else {
                statusMessage = "최대 \(Self.maxItems)장까지 선택할 수 있습니다."
                break
            }
            // 파일 URL에서 이름을 가져온 뒤 데이터를 읽음
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                guard let url else { return }
                guard let data = try? Data(contentsOf: url) else { return }
                let baseName = (url.deletingPathExtension().lastPathComponent)
                Task { @MainActor in
                    var item = BatchItem(sourceData: data)
                    if !baseName.isEmpty {
                        item.sourceName = baseName
                    }
                    self.items.append(item)
                    self.startProcessingIfNeeded()
                }
            }
        }
    }

    // MARK: - Add Photos (File Picker / macOS)
    func addFromFiles(urls: [URL]) {
        for url in urls {
            guard items.count < Self.maxItems else {
                statusMessage = "최대 \(Self.maxItems)장까지 선택할 수 있습니다."
                break
            }
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            if let data = try? Data(contentsOf: url) {
                var item = BatchItem(sourceData: data)
                item.sourceName = url.deletingPathExtension().lastPathComponent
                items.append(item)
            }
        }
        if !items.isEmpty { startProcessingIfNeeded() }
    }

    // MARK: - Remove
    func removeItem(id: UUID) {
        items.removeAll { $0.id == id }
    }

    func removeAll() {
        processingTask?.cancel()
        items.removeAll()
        processedCount = 0
        isProcessing = false
    }

    // MARK: - Processing Pipeline (serial queue)
    /// 이미 처리 중이면 무시. 새 pending 아이템이 있을 때만 시작.
    func startProcessingIfNeeded() {
        guard !isProcessing else {
            return
        }
        processingTask = Task { [weak self] in
            guard let self else { return }
            self.isProcessing = true

            // while 루프: 나중에 추가된 아이템도 처리
            while let i = self.items.firstIndex(where: { $0.status == .pending }) {
                self.items[i].status = .detecting

                do {
                    // 1. Load image
                    guard let platformImage = PlatformImage(data: self.items[i].sourceData),
                          let cgImage = platformImage.asCGImage else {
                        self.items[i].status = .error
                        self.items[i].errorMessage = "이미지를 불러올 수 없습니다."
                        continue
                    }

                    // 2. Generate thumbnail
                    let thumbnail = Self.generateThumbnail(from: cgImage)
                    self.items[i].thumbnailImage = thumbnail

                    // 3. Face detection
                    let faces = try await self.faceDetector.detectFaces(in: cgImage)
                    let regions = faces.map {
                        MosaicRegion(normalizedRect: $0.boundingBox, source: .autoDetected)
                    }
                    self.items[i].regions = regions
                    self.items[i].faceCount = faces.count

                    // 4. Generate preview with mosaic
                    let preview = Self.generatePreview(from: cgImage)
                    if let preview {
                        let processed = self.imageProcessor.applyEffect(
                            to: preview,
                            regions: regions,
                            globalPixelScale: self.items[i].pixelScale,
                            style: self.items[i].mosaicStyle
                        )
                        self.items[i].processedPreview = processed ?? preview
                    }

                    self.items[i].status = .detected
                    self.items[i].originalImage = nil
                    self.processedCount += 1

                } catch {
                    if !Task.isCancelled {
                        self.items[i].status = .error
                        self.items[i].errorMessage = error.localizedDescription
                    }
                }
            }

            self.isProcessing = false
            let detected = self.items.filter { $0.status == .detected || $0.status == .edited }.count
            let errors = self.items.filter { $0.status == .error }.count
            if errors > 0 {
                self.statusMessage = "\(detected)장 처리 완료, \(errors)장 실패"
            } else {
                self.statusMessage = "\(detected)장 처리 완료"
            }
        }
    }

    // MARK: - Retry Failed
    func retryItem(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = .pending
        items[index].errorMessage = nil
        isProcessing = false // allow restart
        startProcessingIfNeeded()
    }

    // MARK: - Edit Integration
    func beginEditing(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        // Load original image for editing
        if let platformImage = PlatformImage(data: items[index].sourceData),
           let cgImage = platformImage.asCGImage {
            items[index].originalImage = cgImage
        }
        selectedItemForEditing = items[index]
    }

    func finishEditing(updatedRegions: [MosaicRegion], style: MosaicStyle, pixelScale: Float) {
        guard let editingItem = selectedItemForEditing,
              let index = items.firstIndex(where: { $0.id == editingItem.id }) else { return }

        items[index].regions = updatedRegions
        items[index].faceCount = updatedRegions.count
        items[index].mosaicStyle = style
        items[index].pixelScale = pixelScale
        items[index].status = .edited
        items[index].originalImage = nil // release

        // Re-generate preview
        if let platformImage = PlatformImage(data: items[index].sourceData),
           let cgImage = platformImage.asCGImage {
            let preview = Self.generatePreview(from: cgImage)
            if let preview {
                items[index].processedPreview = imageProcessor.applyEffect(
                    to: preview,
                    regions: updatedRegions,
                    globalPixelScale: pixelScale,
                    style: style
                )
            }
        }

        selectedItemForEditing = nil
    }

    func cancelEditing() {
        if let editingItem = selectedItemForEditing,
           let index = items.firstIndex(where: { $0.id == editingItem.id }) {
            items[index].originalImage = nil
        }
        selectedItemForEditing = nil
    }

    // MARK: - Export All
    func exportAll() async {
        let exportableItems = items.filter { $0.status == .detected || $0.status == .edited }
        guard !exportableItems.isEmpty else {
            statusMessage = "내보낼 사진이 없습니다."
            return
        }

        isExporting = true
        exportProgress = 0

        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "폴더 선택"
        panel.message = "\(exportableItems.count)장의 사진을 저장할 폴더를 선택하세요."

        let response = panel.runModal()
        guard response == .OK, let folder = panel.url else {
            isExporting = false
            return
        }

        var savedCount = 0
        for (i, item) in exportableItems.enumerated() {
            guard let platformImage = PlatformImage(data: item.sourceData),
                  let original = platformImage.asCGImage else { continue }

            let processed = imageProcessor.applyEffect(
                to: original,
                regions: item.regions,
                globalPixelScale: item.pixelScale,
                style: item.mosaicStyle
            )

            if let data = processed?.jpegData() {
                let baseName = item.sourceName ?? "photo_\(i + 1)"
                var filename = "\(baseName)_mosaic.jpg"
                var targetURL = folder.appendingPathComponent(filename)
                // 중복 파일명 처리: name_mosaic_2.jpg, name_mosaic_3.jpg ...
                var counter = 2
                while FileManager.default.fileExists(atPath: targetURL.path) {
                    filename = "\(baseName)_mosaic_\(counter).jpg"
                    targetURL = folder.appendingPathComponent(filename)
                    counter += 1
                }
                try? data.write(to: targetURL)
                savedCount += 1
            }

            exportProgress = Double(i + 1) / Double(exportableItems.count)
        }

        statusMessage = "\(savedCount)장 저장 완료: \(folder.lastPathComponent)/"
        #elseif os(iOS)
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            statusMessage = "사진 라이브러리 접근이 거부되었습니다."
            isExporting = false
            return
        }

        var savedCount = 0
        for (i, item) in exportableItems.enumerated() {
            guard let platformImage = PlatformImage(data: item.sourceData),
                  let original = platformImage.asCGImage else { continue }

            let processed = imageProcessor.applyEffect(
                to: original,
                regions: item.regions,
                globalPixelScale: item.pixelScale,
                style: item.mosaicStyle
            )

            if let cgImage = processed,
               let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.92) {
                try? await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: data, options: nil)
                }
                savedCount += 1
            }

            exportProgress = Double(i + 1) / Double(exportableItems.count)
        }

        statusMessage = "\(savedCount)장 사진 라이브러리에 저장 완료"
        #endif

        isExporting = false
    }

    // MARK: - Thumbnail / Preview Generation
    private static func generateThumbnail(from cgImage: CGImage) -> CGImage? {
        return resize(cgImage, maxSize: thumbnailSize)
    }

    private static func generatePreview(from cgImage: CGImage) -> CGImage? {
        return resize(cgImage, maxSize: previewMaxSize)
    }

    private static func resize(_ cgImage: CGImage, maxSize: CGFloat) -> CGImage? {
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        let maxDim = max(w, h)
        guard maxDim > maxSize else { return cgImage }

        let scale = maxSize / maxDim
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
}
