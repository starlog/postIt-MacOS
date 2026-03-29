# PostItNotes for macOS

macOS 네이티브 포스트잇 메모 애플리케이션

가볍고 빠른 macOS 전용 포스트잇 앱. 데스크탑에 항상 떠 있는 메모로 생산성을 높이세요. AI 어시스턴트, 마크다운 미리보기, 이미지 드래그 & 드롭까지 지원합니다.

## 주요 기능

### 메모 관리
- 다중 포스트잇 노트 생성/편집/삭제
- 5가지 색상 선택 (Yellow, Green, Cyan, Magenta, Orange)
- 플로팅 윈도우 (항상 위에 표시, 모든 데스크탑 스페이스)
- 드래그 이동 및 리사이즈
- JSON 기반 자동 저장
- 데이터 폴더 변경 가능

### 텍스트 편집
- 리치 텍스트 지원 (Cmd+B 볼드, Cmd+I 이탈릭, Cmd+U 밑줄)
- 한국어 폰트 선택 (Apple SD 고딕 Neo, 나눔고딕, 나눔명조, 나눔바른고딕, D2 코딩, Apple 명조, 나눔손글씨 펜)
- 폰트 크기 조절 (A-/A+ 버튼)
- 기본 폰트 및 크기 설정 (Settings 메뉴)

### 마크다운 미리보기
- MD 버튼으로 마크다운 렌더링/편집 모드 전환
- 헤더, 볼드, 이탈릭, 코드블록, 인라인 코드 지원
- 테이블 렌더링 지원
- 블록인용, 리스트 (순서/비순서), 수평선 지원
- 이미지 렌더링 (로컬 파일 경로)
- 링크 렌더링
- 마크다운 미리보기에서도 폰트/크기/색상 변경 적용

### 이미지 지원
- 이미지 파일 드래그 & 드롭 (빈 노트에서도 가능)
- 편집 모드: 이미지 첨부로 삽입
- 마크다운 모드: `![image](경로)` 마크다운 문법으로 삽입
- 원본 파일 경로 사용 (복사 없음)
- 이미지 위에 마우스 호버 시 삭제(X) 버튼 및 리사이즈 핸들 표시
- 우측 하단 핸들 드래그로 이미지 크기 조절 (비율 유지)
- 이미지 크기 자동 저장 및 복원
- 이미지 경로를 AI 프롬프트에 자동 포함
- 지원 포맷: PNG, JPG, JPEG, GIF, BMP, TIFF, WebP, HEIC

### AI 어시스턴트
- 노트별 AI 버튼으로 Claude CLI 연동
- 멀티라인 프롬프트 입력 다이얼로그
- 노트 내용 + 프롬프트를 함께 전송 (이미지 경로 포함)
- AI 응답을 노트에 자동 추가
- 로컬 `claude` CLI 사용 (API 키 불필요)

### 단축키 및 설정
- 글로벌 핫키로 노트 표시/숨기기 토글 (기본: Cmd+Shift+N)
- 핫키 커스터마이징 (Settings > Set Hotkey)
- 핫키 초기화 (Reset to Default) 버튼
- Dock 아이콘 클릭으로 노트 표시/숨기기 토글
- 메뉴바 상태 아이콘으로 빠른 접근

### 메뉴
- **상단 메뉴바**: PostItNotes, Edit, Settings
- **Settings 메뉴**: Set Hotkey, Set Default Font, Data Folder
- **상태바 메뉴**: New Note, Show/Hide Notes, Data Folder, Hotkey Settings, Quit

## 빌드

Xcode에서 `PostItNotes.xcodeproj`를 열고 빌드하거나:

```bash
xcodebuild -project PostItNotes.xcodeproj -scheme PostItNotes -configuration Release build
```

## 요구사항

- macOS 13.0+
- Xcode 15+
- Claude CLI (AI 기능 사용 시)

## 라이선스

Copyright 2024. All rights reserved.
