# postIt-MacOS

macOS 네이티브 포스트잇 메모 애플리케이션

## 기능

- 다중 포스트잇 노트 생성/편집/삭제
- 5가지 색상 (Yellow, Green, Cyan, Magenta, Orange)
- 플로팅 윈도우 (항상 위에 표시)
- 드래그 이동 및 리사이즈
- 리치 텍스트 지원 (Cmd+B/I/U)
- 글로벌 단축키 (Cmd+Shift+N) 토글
- JSON 기반 자동 저장
- 데이터 폴더 변경 가능

## 빌드

Xcode에서 `PostItNotes.xcodeproj`를 열고 빌드하거나:

```bash
xcodebuild -project PostItNotes.xcodeproj -scheme PostItNotes -configuration Release build
```

## 요구사항

- macOS 13.0+
- Xcode 15+
