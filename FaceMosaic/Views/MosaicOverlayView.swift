import SwiftUI

struct MosaicOverlayView: View {
    @ObservedObject var viewModel: ImageEditorViewModel
    let imageSize: CGSize

    @State private var dragStart: CGPoint? = nil
    @State private var dragCurrent: CGPoint? = nil

    var body: some View {
        ZStack {
            // 기존 영역 표시
            ForEach(Array(viewModel.regions.enumerated()), id: \.element.id) { index, region in
                let rect = region.effectiveRect.scaled(to: imageSize)
                let isSelected = viewModel.selectedRegionId == region.id
                let number = index + 1

                RegionRectangle(region: region, rect: rect, isSelected: isSelected, number: number)

                // 선택된 영역에 인라인 프리셋 표시
                if isSelected {
                    InlineRegionControls(region: region, rect: rect, viewModel: viewModel)
                }
            }

            // 드래그 중인 사각형 미리보기
            if let start = dragStart, let current = dragCurrent {
                let rect = dragRect(from: start, to: current)
                Rectangle()
                    .stroke(Color.green, lineWidth: 2)
                    .background(Color.green.opacity(0.15))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(tapGesture)
        .gesture(drawGesture)
    }

    // 탭: 영역 선택/해제
    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                let normalized = CGPoint(
                    x: value.location.x / imageSize.width,
                    y: value.location.y / imageSize.height
                )
                viewModel.selectRegion(at: normalized)
            }
    }

    // 드래그: 새 영역 그리기
    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                if dragStart == nil {
                    // 드래그 시작 시 선택 해제
                    viewModel.selectedRegionId = nil
                    dragStart = value.startLocation
                }
                dragCurrent = value.location
            }
            .onEnded { value in
                guard let start = dragStart else { return }
                let rect = dragRect(from: start, to: value.location)
                let normalized = CGRect(
                    x: rect.origin.x / imageSize.width,
                    y: rect.origin.y / imageSize.height,
                    width: rect.width / imageSize.width,
                    height: rect.height / imageSize.height
                )
                viewModel.addManualRegion(normalizedRect: normalized)
                dragStart = nil
                dragCurrent = nil
            }
    }

    private func dragRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
}

// MARK: - 영역 사각형
private struct RegionRectangle: View {
    let region: MosaicRegion
    let rect: CGRect
    let isSelected: Bool
    let number: Int

    var borderColor: Color {
        if isSelected { return .yellow }
        if !region.isEnabled { return .gray }
        return region.source == .autoDetected ? .blue : .green
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .stroke(borderColor, lineWidth: isSelected ? 2 : 1)
                .background(borderColor.opacity(region.isEnabled ? 0.05 : 0.02))

            // 번호 뱃지
            Text("\(number)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(borderColor, in: Circle())
                .offset(x: -6, y: -6)
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
    }
}

// MARK: - 인라인 프리셋 컨트롤
private struct InlineRegionControls: View {
    let region: MosaicRegion
    let rect: CGRect
    @ObservedObject var viewModel: ImageEditorViewModel

    var body: some View {
        VStack(spacing: 5) {
            // 영역별 스타일 토글
            Picker("", selection: Binding(
                get: { region.style ?? viewModel.mosaicStyle },
                set: { viewModel.setRegionStyle(id: region.id, style: $0) }
            )) {
                ForEach(MosaicStyle.allCases, id: \.self) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 120)

            // 강도 프리셋
            HStack(spacing: 4) {
                ForEach(MosaicIntensity.allCases, id: \.self) { intensity in
                    let regionStyle = region.style ?? viewModel.mosaicStyle
                    let presetValue = intensity.value(for: regionStyle)
                    let isActive = isActiveIntensity(intensity)
                    Button {
                        viewModel.setRegionIntensity(id: region.id, intensity: intensity)
                    } label: {
                        Text("\(intensity.rawValue) \(Int(presetValue))")
                            .font(.caption2)
                            .fontWeight(isActive ? .bold : .regular)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(isActive ? Color.accentColor : Color.secondary.opacity(0.3))
                            .foregroundStyle(isActive ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            // 크기 프리셋 + 삭제
            HStack(spacing: 4) {
                ForEach(RegionSize.allCases, id: \.self) { size in
                    let isActive = isActiveSize(size)
                    Button {
                        viewModel.setRegionSize(id: region.id, size: size)
                    } label: {
                        Text("\(size.rawValue)")
                            .font(.caption2)
                            .fontWeight(isActive ? .bold : .regular)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(isActive ? Color.orange : Color.secondary.opacity(0.3))
                            .foregroundStyle(isActive ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    viewModel.removeRegion(id: region.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .position(
            x: rect.midX,
            y: max(rect.minY - 45, 45)
        )
    }

    private func isActiveIntensity(_ intensity: MosaicIntensity) -> Bool {
        let current = region.pixelScale ?? viewModel.pixelScale
        let regionStyle = region.style ?? viewModel.mosaicStyle
        let presetValue = intensity.value(for: regionStyle)
        return abs(current - presetValue) < 3
    }

    private func isActiveSize(_ size: RegionSize) -> Bool {
        return abs(region.sizeMultiplier - size.multiplier) < 0.15
    }
}
