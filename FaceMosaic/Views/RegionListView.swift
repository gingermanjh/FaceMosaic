import SwiftUI

struct RegionListView: View {
    @ObservedObject var viewModel: ImageEditorViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack {
                Text("모자이크 영역")
                    .font(.headline)
                Spacer()
                Button("완료") { isPresented = false }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(12)

            Divider()

            // 목록
            ScrollView {
                LazyVStack(spacing: 12) {
                    if viewModel.regions.isEmpty {
                        ContentUnavailableView(
                            "영역 없음",
                            systemImage: "rectangle.dashed",
                            description: Text("감지된 얼굴이나 수동 영역이 없습니다.")
                        )
                    } else {
                        ForEach(Array(viewModel.regions.enumerated()), id: \.element.id) { index, region in
                            RegionRow(region: region, number: index + 1, viewModel: viewModel)
                        }
                    }
                }
                .padding()
            }
        }
    }
}

// MARK: - Region Row
private struct RegionRow: View {
    let region: MosaicRegion
    let number: Int
    let viewModel: ImageEditorViewModel

    @State private var intensityText: String = ""
    @State private var sizeText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 헤더: 아이콘 + 이름 + 토글 + 삭제
            HStack {
                Text("\(number)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(
                        region.source == .autoDetected ? Color.blue : Color.green,
                        in: Circle()
                    )

                Image(systemName: region.source == .autoDetected
                      ? "face.dashed" : "hand.draw")
                    .foregroundStyle(region.source == .autoDetected ? .blue : .green)
                    .font(.caption)

                Text(region.source == .autoDetected ? "감지된 얼굴" : "수동 영역")
                    .font(.headline)

                Spacer()

                Button(role: .destructive) {
                    viewModel.removeRegion(id: region.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                Toggle("", isOn: Binding(
                    get: { region.isEnabled },
                    set: { _ in viewModel.toggleRegion(id: region.id) }
                ))
                .labelsHidden()
            }

            if region.isEnabled {
                // 영역별 스타일 토글
                Picker("효과", selection: Binding(
                    get: { region.style ?? viewModel.mosaicStyle },
                    set: {
                        viewModel.setRegionStyle(id: region.id, style: $0)
                        intensityText = "\(Int(MosaicIntensity.medium.value(for: $0)))"
                    }
                )) {
                    ForEach(MosaicStyle.allCases, id: \.self) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                // 강도: 프리셋 + 숫자 입력
                VStack(alignment: .leading, spacing: 6) {
                    Text("강도")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        ForEach(MosaicIntensity.allCases, id: \.self) { preset in
                            let regionStyle = region.style ?? viewModel.mosaicStyle
                            let value = Int(preset.value(for: regionStyle))
                            let scale = preset.value(for: regionStyle)
                            PresetButton(
                                label: preset.rawValue,
                                detail: "\(value)",
                                isActive: isActiveIntensity(preset)
                            ) {
                                viewModel.updateRegionScale(id: region.id, pixelScale: scale)
                                viewModel.reprocessImage()
                                intensityText = "\(value)"
                            }
                        }

                        Divider().frame(height: 28)

                        TextField("px", text: $intensityText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 55)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .onSubmit { commitIntensity() }
                    }
                }

                // 크기: 프리셋 + 숫자 입력
                VStack(alignment: .leading, spacing: 6) {
                    Text("영역 크기")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        ForEach(RegionSize.allCases, id: \.self) { preset in
                            PresetButton(
                                label: preset.rawValue,
                                detail: String(format: "%.1fx", preset.multiplier),
                                isActive: isActiveSize(preset)
                            ) {
                                viewModel.updateRegionSize(id: region.id, multiplier: preset.multiplier)
                                viewModel.reprocessImage()
                                sizeText = String(format: "%.1f", preset.multiplier)
                            }
                        }

                        Divider().frame(height: 28)

                        TextField("배율", text: $sizeText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 55)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .onSubmit { commitSize() }
                    }
                }
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        .onAppear {
            intensityText = "\(Int(region.pixelScale ?? viewModel.pixelScale))"
            sizeText = String(format: "%.1f", region.sizeMultiplier)
        }
    }

    private func commitIntensity() {
        guard let value = Float(intensityText),
              (1...200).contains(value) else {
            intensityText = "\(Int(region.pixelScale ?? viewModel.pixelScale))"
            return
        }
        viewModel.updateRegionScale(id: region.id, pixelScale: value)
        viewModel.reprocessImage()
    }

    private func commitSize() {
        guard let value = Float(sizeText),
              (0.5...2.5).contains(value) else {
            sizeText = String(format: "%.1f", region.sizeMultiplier)
            return
        }
        viewModel.updateRegionSize(id: region.id, multiplier: value)
        viewModel.reprocessImage()
    }

    private func isActiveIntensity(_ intensity: MosaicIntensity) -> Bool {
        let current = region.pixelScale ?? viewModel.pixelScale
        let regionStyle = region.style ?? viewModel.mosaicStyle
        return abs(current - intensity.value(for: regionStyle)) < 3
    }

    private func isActiveSize(_ size: RegionSize) -> Bool {
        return abs(region.sizeMultiplier - size.multiplier) < 0.15
    }
}

// MARK: - Preset Button
private struct PresetButton: View {
    let label: String
    let detail: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(label)
                    .font(.caption)
                    .fontWeight(isActive ? .bold : .regular)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(isActive ? .white.opacity(0.8) : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isActive ? Color.accentColor : Color.secondary.opacity(0.15))
            .foregroundStyle(isActive ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}
