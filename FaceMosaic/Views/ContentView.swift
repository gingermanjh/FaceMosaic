import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var batchViewModel = BatchViewModel()

    var body: some View {
        NavigationStack {
            BatchGridView(viewModel: batchViewModel)
                .navigationTitle("FaceMosaic")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        }
        // 개별 편집: 선택된 아이템이 있으면 에디터로 전환
        .sheet(item: $batchViewModel.selectedItemForEditing) { item in
            BatchEditorWrapper(batchItem: item, batchViewModel: batchViewModel)
                #if os(macOS)
                .frame(minWidth: 800, minHeight: 600)
                #endif
        }
    }
}

/// BatchItem → ImageEditorView 연결 래퍼
struct BatchEditorWrapper: View {
    let batchItem: BatchItem
    var batchViewModel: BatchViewModel
    @StateObject private var editorViewModel: ImageEditorViewModel
    @Environment(\.dismiss) private var dismiss

    init(batchItem: BatchItem, batchViewModel: BatchViewModel) {
        self.batchItem = batchItem
        self.batchViewModel = batchViewModel
        self._editorViewModel = StateObject(wrappedValue: ImageEditorViewModel(batchItem: batchItem))
    }

    var body: some View {
        NavigationStack {
            ImageEditorView(viewModel: editorViewModel)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("완료") {
                            batchViewModel.finishEditing(
                                updatedRegions: editorViewModel.regions,
                                style: editorViewModel.mosaicStyle,
                                pixelScale: editorViewModel.pixelScale
                            )
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소") {
                            batchViewModel.cancelEditing()
                            dismiss()
                        }
                    }
                }
        }
    }
}
