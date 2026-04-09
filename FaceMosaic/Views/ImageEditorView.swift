import SwiftUI
import PhotosUI
#if os(macOS)
import AppKit
#endif

struct ImageEditorView: View {
    @ObservedObject var viewModel: ImageEditorViewModel
    @State private var showRegionList = false
    @State private var showFileImporter = false
    @State private var pixelScaleText: String = "25"

    var body: some View {
        VStack(spacing: 0) {
            // 상태 메시지 배너
            if let status = viewModel.statusMessage {
                HStack {
                    Image(systemName: "info.circle")
                    Text(status)
                        .font(.caption)
                    Spacer()
                    Button {
                        viewModel.statusMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(.ultraThinMaterial)
            }

            // 이미지 + 오버레이
            GeometryReader { geometry in
                if let cgImage = viewModel.processedImage ?? viewModel.originalImage {
                    let displaySize = imageDisplaySize(
                        imageWidth: CGFloat(cgImage.width),
                        imageHeight: CGFloat(cgImage.height),
                        containerSize: geometry.size
                    )

                    ZStack {
                        Image(decorative: cgImage, scale: 1.0)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: displaySize.width, height: displaySize.height)

                        MosaicOverlayView(
                            viewModel: viewModel,
                            imageSize: displaySize
                        )
                        .frame(width: displaySize.width, height: displaySize.height)

                        // 로딩 오버레이
                        if viewModel.isDetectingFaces || viewModel.isProcessing {
                            ProgressView()
                                .controlSize(.large)
                                .frame(width: 60, height: 60)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            Divider()

            // 툴바
            toolbarView
        }
        .inspector(isPresented: $showRegionList) {
            RegionListView(viewModel: viewModel, isPresented: $showRegionList)
                .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await viewModel.loadFromFile(url: url) }
            }
        }
        .onDrop(of: [.image], isTargeted: nil) { providers in
            viewModel.loadFromDrop(providers: providers)
            return true
        }
    }

    // MARK: - Toolbar
    private var toolbarView: some View {
        VStack(spacing: 12) {
            // 효과 종류 + 강도
            HStack(spacing: 6) {
                // 모자이크 / 블러 전환
                Picker("", selection: $viewModel.mosaicStyle) {
                    ForEach(MosaicStyle.allCases, id: \.self) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
                .onChange(of: viewModel.mosaicStyle) { _, _ in
                    viewModel.reprocessImage()
                }
                ForEach(MosaicIntensity.allCases, id: \.self) { preset in
                    let presetValue = preset.value(for: viewModel.mosaicStyle)
                    let isActive = abs(viewModel.pixelScale - presetValue) < 3
                    Button {
                        viewModel.pixelScale = presetValue
                        pixelScaleText = "\(Int(presetValue))"
                        viewModel.reprocessImage()
                    } label: {
                        Text("\(preset.rawValue)\n\(Int(presetValue))")
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(isActive ? Color.accentColor : Color.secondary.opacity(0.15))
                            .foregroundStyle(isActive ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                TextField("", text: $pixelScaleText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 55)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .onSubmit {
                        if let v = Float(pixelScaleText), (1...200).contains(v) {
                            viewModel.pixelScale = v
                            viewModel.reprocessImage()
                        } else {
                            pixelScaleText = "\(Int(viewModel.pixelScale))"
                        }
                    }
            }
            .onAppear { pixelScaleText = "\(Int(viewModel.pixelScale))" }
            .onChange(of: viewModel.mosaicStyle) { _, newStyle in
                // 스타일 전환 시 기본값으로 리셋
                let defaultValue = MosaicIntensity.medium.value(for: newStyle)
                viewModel.pixelScale = defaultValue
                pixelScaleText = "\(Int(defaultValue))"
            }

            // 액션 버튼
            HStack(spacing: 12) {
                // 영역 목록
                Button {
                    showRegionList.toggle()
                } label: {
                    Label("\(viewModel.regions.count)", systemImage: "list.bullet")
                }

                Spacer()

                // 새 사진: 라이브러리
                PhotosPicker(
                    selection: $viewModel.selectedPhotoItem,
                    matching: .images
                ) {
                    Label("사진", systemImage: "photo")
                }
                .onChange(of: viewModel.selectedPhotoItem) { _, _ in
                    Task { await viewModel.loadImage() }
                }

                // 새 사진: 파일
                Button {
                    #if os(macOS)
                    viewModel.openFilePicker()
                    #else
                    showFileImporter = true
                    #endif
                } label: {
                    Label("파일", systemImage: "folder")
                }

                // 클립보드
                Button {
                    Task { await viewModel.loadFromClipboard() }
                } label: {
                    Label("붙여넣기", systemImage: "doc.on.clipboard")
                }

                // 공유
                if let url = viewModel.exportToTemporaryFile() {
                    ShareLink(item: url) {
                        Label("공유", systemImage: "square.and.arrow.up")
                    }
                }

                // 저장
                Button {
                    Task { await viewModel.saveToPhotos() }
                } label: {
                    Label("저장", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    // MARK: - Helpers
    private func imageDisplaySize(
        imageWidth: CGFloat,
        imageHeight: CGFloat,
        containerSize: CGSize
    ) -> CGSize {
        let imageAspect = imageWidth / imageHeight
        let containerAspect = containerSize.width / containerSize.height

        if imageAspect > containerAspect {
            let w = containerSize.width
            return CGSize(width: w, height: w / imageAspect)
        } else {
            let h = containerSize.height
            return CGSize(width: h * imageAspect, height: h)
        }
    }
}
