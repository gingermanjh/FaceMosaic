import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct BatchGridView: View {
    var viewModel: BatchViewModel
    @State private var selectedPickerItems: [PhotosPickerItem] = []
    @State private var showFileImporter = false


    var body: some View {
        VStack(spacing: 0) {
            // 상단 툴바
            batchToolbar

            Divider()

            if viewModel.items.isEmpty {
                emptyState
            } else {
                // 그리드 (LazyVGrid 대신 수동 레이아웃으로 렌더링 문제 해결)
                ScrollView {
                    let items = viewModel.items
                    let chunkSize = 4
                    VStack(spacing: 12) {
                        ForEach(0..<((items.count + chunkSize - 1) / chunkSize), id: \.self) { row in
                            HStack(spacing: 12) {
                                ForEach(0..<chunkSize, id: \.self) { col in
                                    let index = row * chunkSize + col
                                    if index < items.count {
                                        BatchThumbnailCell(itemId: items[index].id, viewModel: viewModel)
                                            .frame(minWidth: 150, maxWidth: 200)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding()
                }
            }

            // 하단: Export All
            if !viewModel.items.isEmpty {
                Divider()
                bottomBar
            }
        }
        .onDrop(of: [.image], isTargeted: nil) { providers in
            viewModel.addFromDrop(providers: providers)
            return true
        }
        .onChange(of: selectedPickerItems) { _, newItems in
            viewModel.addFromPicker(items: newItems)
            selectedPickerItems = []
        }
        #if os(iOS)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                viewModel.addFromFiles(urls: urls)
            }
        }
        #endif
    }

    // MARK: - Toolbar
    private var batchToolbar: some View {
        HStack {
            PhotosPicker(
                selection: $selectedPickerItems,
                maxSelectionCount: BatchViewModel.maxItems - viewModel.items.count,
                matching: .images
            ) {
                Label("사진 추가", systemImage: "plus.circle")
            }

            Button {
                #if os(macOS)
                openFilePicker()
                #else
                showFileImporter = true
                #endif
            } label: {
                Label("파일 추가", systemImage: "folder.badge.plus")
            }

            Spacer()

            if viewModel.isProcessing {
                ProgressView()
                    .controlSize(.small)
                Text("\(viewModel.processedCount)/\(viewModel.items.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let status = viewModel.statusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !viewModel.items.isEmpty {
                Button(role: .destructive) {
                    viewModel.removeAll()
                } label: {
                    Label("전체 삭제", systemImage: "trash")
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "photo.stack")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("사진을 추가하면\n자동으로 얼굴을 감지하여 모자이크합니다")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("드래그 앤 드롭으로도 추가할 수 있습니다")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    // MARK: - Bottom Bar
    private var bottomBar: some View {
        HStack {
            Text("\(viewModel.items.count)장")
                .font(.headline)

            let readyCount = viewModel.items.filter {
                $0.status == .detected || $0.status == .edited
            }.count
            Text("(\(readyCount)장 준비됨)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if viewModel.isExporting {
                ProgressView(value: viewModel.exportProgress)
                    .frame(width: 100)
            }

            Button {
                Task { await viewModel.exportAll() }
            } label: {
                Label("전체 내보내기", systemImage: "square.and.arrow.up.on.square")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isExporting || readyCount == 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - macOS File Picker
    private func openFilePicker() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK else { return }
            viewModel.addFromFiles(urls: panel.urls)
        }
        #endif
    }
}

// MARK: - Thumbnail Cell (index 기반으로 viewModel에서 직접 읽음)
private struct BatchThumbnailCell: View {
    let itemId: UUID
    var viewModel: BatchViewModel

    private var item: BatchItem? {
        viewModel.items.first { $0.id == itemId }
    }

    var body: some View {
        if let item {
            // 이미지 + 뱃지
            ZStack {
                Group {
                    if let preview = item.processedPreview {
                        Image(decorative: preview, scale: 1.0)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else if let thumbnail = item.thumbnailImage {
                        Image(decorative: thumbnail, scale: 1.0)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(.quaternary)
                            .overlay {
                                if item.status == .pending || item.status == .detecting {
                                    ProgressView()
                                }
                            }
                    }
                }

                // 상태 뱃지 (우상단)
                VStack {
                    HStack {
                        Spacer()
                        statusBadge(for: item.status)
                    }
                    Spacer()
                    // 얼굴 수 (우하단)
                    if item.faceCount > 0 {
                        HStack {
                            Spacer()
                            Text("\(item.faceCount)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.6), in: Capsule())
                        }
                    }
                }
                .padding(6)
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onTapGesture {
                if item.status == .error {
                    viewModel.retryItem(id: itemId)
                } else if item.status == .detected || item.status == .edited {
                    viewModel.beginEditing(id: itemId)
                }
            }
            .contextMenu {
                if item.status == .error {
                    Button("다시 시도") { viewModel.retryItem(id: itemId) }
                }
                Button("삭제", role: .destructive) { viewModel.removeItem(id: itemId) }
            }
        }
    }

    @ViewBuilder
    private func statusBadge(for status: BatchStatus) -> some View {
        switch status {
        case .pending:
            EmptyView()
        case .detecting:
            ProgressView()
                .controlSize(.mini)
                .padding(4)
                .background(.ultraThinMaterial, in: Circle())
        case .detected:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
        case .edited:
            Image(systemName: "pencil.circle.fill")
                .foregroundStyle(.yellow)
                .font(.title3)
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.title3)
        }
    }
}
