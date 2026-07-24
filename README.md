# PostItNotes for macOS

macOS 네이티브 포스트잇 메모 애플리케이션

가볍고 빠른 macOS 전용 포스트잇 앱. 데스크탑에 항상 떠 있는 메모로 생산성을 높이세요. AI 어시스턴트, 마크다운 미리보기, 이미지 드래그 & 드롭까지 지원합니다.

## 주요 기능

### 메모 관리
- 다중 포스트잇 노트 생성/편집/삭제
- **닫기(✕)**: 메모를 화면에서만 숨김 (데이터는 유지, 언제든 다시 열기 가능)
- **삭제(🗑)**: 확인 후 메모를 영구 삭제 (되돌릴 수 없음)
- **Closed Notes 메뉴**: 닫은 메모 목록에서 클릭하여 다시 열기 (Reopen All 지원)
  - View 메뉴와 메뉴바 아이콘 양쪽에서 접근 가능
- 5가지 색상 선택 (Yellow, Green, Cyan, Magenta, Orange)
- 플로팅 윈도우 (항상 위에 표시, 모든 데스크탑 스페이스)
- 드래그 이동 및 리사이즈
- JSON 기반 자동 저장
- 데이터 폴더 변경 가능

### 탭 모드 (Tab Mode)
- 모든 메모를 하나의 창에 탭으로 모아서 보는 모드
- 탭 라벨은 메모 제목 사용 (제목이 없으면 본문 첫 줄에서 자동 생성)
- 탭 색상은 각 메모의 색상을 그대로 반영 (선택된 탭은 진하게 강조)
- View 메뉴 또는 상태바 메뉴의 **Tab Mode**로 전환 (단축키: Cmd+Shift+T)
- 탭이 많으면 탭 영역을 좌우 스크롤 (마우스 휠/트랙패드)
- 탭 우클릭으로 Close Tab(숨기기) / Delete Note(영구 삭제) 선택
- 모든 탭을 닫으면 빈 화면 안내 표시 (+ 또는 Closed Notes로 복귀)
- 탭 바 우측 `+` 새 메모, `–` 창 숨기기
- 창 위치/크기와 마지막 사용 모드는 자동 저장되어 다음 실행 시 복원
- 창 모드와 탭 모드는 같은 데이터를 공유 (전환해도 메모는 그대로 유지)

**탭 모드 단축키**
- `Cmd+1` ~ `Cmd+9`: 해당 번호의 탭으로 이동
- `Cmd+Shift+]` / `Cmd+Shift+[`: 다음/이전 탭

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
- **상단 메뉴바**: PostItNotes, Edit, View, Settings
- **View 메뉴**: Tab Mode (Cmd+Shift+T)
- **Settings 메뉴**: Set Hotkey, Set Default Font, Data Folder
- **상태바 메뉴**: New Note, Tab Mode, Show/Hide Notes, Data Folder, Hotkey Settings, Quit

## 빌드

Xcode에서 `PostItNotes.xcodeproj`를 열고 빌드하거나:

```bash
xcodebuild -project PostItNotes.xcodeproj -scheme PostItNotes -configuration Release SYMROOT=$PWD/build build
```

빌드 결과물: `build/Release/PostItNotes.app`

## 설치

```bash
# 실행 중인 앱 종료 후 교체
osascript -e 'quit app "PostItNotes"'
rm -rf /Applications/PostItNotes.app
cp -R build/Release/PostItNotes.app /Applications/
open /Applications/PostItNotes.app
```

메모 데이터는 앱 번들이 아니라 `~/Library/Application Support/PostItNotes/`에 저장되므로
앱을 교체해도 그대로 유지됩니다.

## 요구사항

- macOS 13.0+
- Xcode 15+
- Claude CLI (AI 기능 사용 시)

## 라이선스

Copyright 2024. All rights reserved.
