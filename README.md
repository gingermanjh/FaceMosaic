# FaceMosaic

사진에서 얼굴을 자동으로 감지하여 모자이크/블러 처리하는 SwiftUI 멀티플랫폼 앱.

## 주요 기능

- **자동 얼굴 감지** — YOLO11n-face (CoreML) 기반, WIDERFace 데이터셋 학습
- **모자이크 / 블러** — 두 가지 효과 지원, 영역별 개별 스타일 적용 가능
- **수동 영역 추가** — 이미지 위에서 드래그하여 직접 영역 지정
- **영역별 조절** — 강도(프리셋 + 숫자 입력), 크기(딱맞게/보통/넓게) 개별 설정
- **다양한 이미지 소스** — 사진 라이브러리, 파일 열기, 드래그 앤 드롭, 클립보드 붙여넣기
- **안전한 내보내기** — EXIF 메타데이터 제거, JPEG/PNG 저장 및 공유

## 지원 플랫폼

| 플랫폼 | 최소 버전 |
|--------|----------|
| macOS  | 14.0     |
| iOS    | 17.0     |

## 기술 스택

| 영역 | 기술 |
|------|------|
| UI | SwiftUI (Multiplatform) |
| 얼굴 감지 | YOLO11n-face (CoreML) / Apple Vision (교체 가능) |
| 이미지 처리 | Core Image (CIPixellate, CIGaussianBlur, CIBlendWithMask) |
| 사진 선택 | PhotosUI (PhotosPicker) |
| 아키텍처 | MVVM |
| 외부 의존성 | 없음 (Apple 네이티브 프레임워크만 사용) |

## 프로젝트 구조

```
FaceMosaic/
├── FaceMosaicApp.swift              # 앱 진입점
├── Models/
│   ├── DetectedFace.swift           # 감지된 얼굴 공통 모델
│   └── MosaicRegion.swift           # 모자이크 영역 모델
├── Services/
│   ├── FaceDetector.swift           # 얼굴 감지 프로토콜 (교체 가능)
│   ├── VisionFaceDetector.swift     # Apple Vision 구현체
│   ├── YOLOFaceDetector.swift       # YOLO CoreML 구현체 (기본)
│   └── ImageProcessingService.swift # 마스크 기반 합성 파이프라인
├── ViewModels/
│   └── ImageEditorViewModel.swift   # 중앙 상태 관리
├── Views/
│   ├── ContentView.swift            # 사진 선택 화면
│   ├── ImageEditorView.swift        # 메인 편집기
│   ├── MosaicOverlayView.swift      # 영역 오버레이 + 인라인 프리셋
│   └── RegionListView.swift         # 영역 목록 사이드 패널
├── Utilities/
│   ├── PlatformImage.swift          # iOS/macOS 이미지 브릿지
│   └── CGRect+Helpers.swift         # 좌표 변환 유틸
└── Resources/
    ├── YOLOFace.mlpackage           # YOLO11n-face CoreML 모델
    └── FaceMosaic.entitlements      # macOS 샌드박스 권한
```

## 얼굴 감지 엔진

`FaceDetector` 프로토콜로 추상화되어 있어 엔진을 쉽게 교체할 수 있습니다.

```swift
// 기본: YOLO11n-face (높은 정확도)
let vm = ImageEditorViewModel(faceDetector: YOLOFaceDetector())

// Apple Vision으로 전환 (외부 모델 불필요)
let vm = ImageEditorViewModel(faceDetector: VisionFaceDetector())
```

추후 Google ML Kit, MediaPipe 등의 구현체를 추가할 수 있습니다.

## 이미지 처리 방식

마스크 기반 합성(Mask-Based Compositing)을 사용합니다:

1. 원본 이미지 전체에 효과(픽셀화/블러) 적용
2. 처리할 영역을 흰색, 나머지를 검정으로 한 마스크 생성
3. `CIBlendWithMask`로 합성 — 원본 픽셀 데이터가 파괴되므로 복원 불가능

## 보안

- 모자이크/블러는 픽셀 데이터를 파괴하는 방식으로, 레이어를 벗겨내는 것이 불가능
- 내보내기 시 EXIF 메타데이터(GPS, 촬영 정보, 원본 썸네일 등) 완전 제거
- 충분한 강도(모자이크 25px+ / 블러 30+) 사용 시 AI 복원도 불가능

## 빌드

```bash
# XcodeGen 설치 (처음 한 번만)
brew install xcodegen

# 프로젝트 생성
cd FaceMosaic
xcodegen generate

# Xcode에서 열기
open FaceMosaic.xcodeproj
```

## 라이선스

YOLO11n-face 모델: [akanametov/yolo-face](https://github.com/akanametov/yolo-face) (AGPL-3.0)
