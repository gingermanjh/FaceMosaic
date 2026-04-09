import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = ImageEditorViewModel()
    @State private var showFileImporter = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.originalImage != nil {
                    ImageEditorView(viewModel: viewModel)
                } else {
                    welcomeView
                }
            }
            .navigationTitle("FaceMosaic")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onChange(of: viewModel.selectedPhotoItem) { _, _ in
                Task { await viewModel.loadImage() }
            }
            .alert("오류", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("확인") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
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
            // 드래그 앤 드롭: 앱 전체에서 이미지를 받을 수 있음
            .onDrop(of: [.image], isTargeted: nil) { providers in
                viewModel.loadFromDrop(providers: providers)
                return true
            }
            // 키보드 단축키 (macOS)
            #if os(macOS)
            .keyboardShortcut("v", modifiers: .command)
            #endif
        }
    }

    private var welcomeView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "face.dashed")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)

            Text("사진을 선택하면\n얼굴을 자동으로 감지하여 모자이크합니다")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            // 사진 라이브러리에서 선택
            PhotosPicker(
                selection: $viewModel.selectedPhotoItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label("사진 라이브러리", systemImage: "photo.on.rectangle")
                    .font(.headline)
                    .frame(width: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            // 파일에서 열기
            Button {
                #if os(macOS)
                viewModel.openFilePicker()
                #else
                showFileImporter = true
                #endif
            } label: {
                Label("파일에서 열기", systemImage: "folder")
                    .font(.headline)
                    .frame(width: 200)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            // 클립보드에서 붙여넣기
            Button {
                Task { await viewModel.loadFromClipboard() }
            } label: {
                Label("클립보드에서 붙여넣기", systemImage: "doc.on.clipboard")
                    .font(.headline)
                    .frame(width: 200)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            #if os(macOS)
            Text("이미지를 여기에 드래그 앤 드롭할 수도 있습니다")
                .font(.caption)
                .foregroundStyle(.tertiary)
            #endif

            Spacer()
        }
        .padding()
    }
}
