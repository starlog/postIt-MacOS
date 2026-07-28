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

### 서브 카드 (한 메모 안의 여러 장)
- 제목 아래 탭 줄에서 메모 하나를 여러 장으로 나눠 씀 (한 번에 한 장만 표시)
- **추가**: 탭 줄 오른쪽 `+` (또는 탭 우클릭 > 새 서브 카드)
- **전환**: 탭 클릭 — 마지막에 보던 장이 다음 실행 때 복원됨
- **순서 변경**: 탭을 좌우로 드래그 (드래그 중 반투명 표시, 보고 있던 장은 그대로 유지)
- **이름 변경**: 탭 더블클릭 또는 우클릭 > 이름 변경 (기본 이름은 1, 2, 3...)
- **삭제**: 탭 우클릭 > 서브 카드 삭제 (내용이 있으면 확인창, 마지막 한 장은 삭제 불가)
- 장마다 서식·이미지·실행 취소 이력이 독립적으로 관리됨
- 창 모드와 탭 모드 양쪽에서 동일하게 동작
- 기존 메모는 자동으로 서브 카드 1장짜리로 열리며, 이전 버전 형식도 그대로 읽힘

### 화면 정리 및 멀티 모니터
- **Organize Notes** (Cmd+Shift+O): 열려 있는 메모를 겹침이 최소가 되도록 자동 배치
  - 큰 메모부터 왼쪽 위에서 오른쪽 아래로 줄 단위 배치, 각 줄은 가운데 정렬
  - 메모 크기는 사용자가 지정한 그대로 유지 (화면보다 큰 메모만 화면 크기로 축소)
  - 한 화면에 다 들어가지 않으면 줄 간격을 비례 축소해 겹침을 모든 줄에 고르게 분산
- **Move to Screen**: 연결된 모니터 목록에서 선택한 화면으로 모든 메모를 이동 후 자동 정리
  - 모니터 이름과 해상도를 표시하고, 현재 메모가 있는 화면에 체크 표시
  - 실행 중 모니터를 연결/해제해도 메뉴를 열 때마다 목록이 갱신됨
  - 탭 모드에서는 탭 창을 선택한 화면 중앙으로 이동
- View 메뉴와 메뉴바 아이콘 양쪽에서 접근 가능
- 두 번째 모니터에 둔 메모는 재실행 후에도 그 화면 위치 그대로 복원

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
- 리치 텍스트 지원 — **Format 메뉴**에서 적용 (적용할 텍스트를 먼저 선택해야 함)
  - `Cmd+B` 볼드 / `Cmd+I` 이탈릭 / `Cmd+U` 밑줄 / `Cmd+Shift+X` 취소선
- 실행 취소/재실행 (`Cmd+Z` / `Cmd+Shift+Z`), 메모마다 독립된 최대 100단계 스택
  - 입력뿐 아니라 볼드·이탈릭·밑줄·취소선·폰트 변경도 되돌리기 가능
  - 입력 / 삭제 / 서식이 각각 별도 단계로 끊겨서, 지운 글자를 `Cmd+Z`로 되살려도
    직전에 입력한 내용이 함께 사라지지 않음
- **F 버튼**: 폰트와 크기를 함께 지정하는 다이얼로그 (미리보기 포함)
  - 한국어 폰트 선택 (Apple SD 고딕 Neo, 나눔고딕, 나눔명조, 나눔바른고딕, D2 코딩, Apple 명조, 나눔손글씨 펜)
  - 크기 8~72pt, 입력란 또는 스테퍼로 지정
  - 현재 메모가 쓰는 폰트/크기가 초기값으로 채워짐
  - 메모 전체에 적용되며 단어별로 지정한 볼드·이탈릭은 그대로 유지
  - `Cmd+Z`로 되돌리기 가능
- **↩ 버튼**: 줄 바꿈 켜기/끄기 (메모마다 따로 기억, 끄면 가로 스크롤)
  - 켜짐은 진하게, 꺼짐은 흐리게 표시
- 폰트 크기 미세 조절 (A-/A+ 버튼, 메모 안의 크기 차이는 유지한 채 전체를 한 단계씩)
- 기본 폰트 및 크기 설정 (Settings 메뉴 — 새로 만드는 메모에 적용)

### 마크다운 미리보기
- MD 버튼으로 마크다운 렌더링/편집 모드 전환
- 헤더, 볼드, 이탈릭, 취소선(`~~텍스트~~`), 코드블록, 인라인 코드 지원
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
- **상단 메뉴바**: PostItNotes, Edit, Format, View, Settings
- **Edit 메뉴**: Undo (Cmd+Z), Redo (Cmd+Shift+Z), Cut, Copy, Paste, Select All
- **Format 메뉴**: Bold (Cmd+B), Italic (Cmd+I), Underline (Cmd+U), Strikethrough (Cmd+Shift+X)
- **View 메뉴**: Hide/Show Notes (Cmd+Shift+H), Organize Notes (Cmd+Shift+O), Move to Screen, Tab Mode (Cmd+Shift+T), Closed Notes
- **Settings 메뉴**: Set Hotkey, Set Default Font, Data Folder
- **상태바 메뉴**: New Note, Organize Notes, Move to Screen, Tab Mode, Closed Notes, Show/Hide Notes, Data Folder, Hotkey Settings, Quit

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

### 첫 실행 시 보안 경고에 대해

이 앱은 Developer ID 서명/공증(notarization) 없이 ad-hoc 서명으로 빌드됩니다.
하지만 **소스를 직접 받아 빌드하면 "확인되지 않은 개발자" 경고는 뜨지 않습니다.**

Gatekeeper 경고는 서명 상태가 아니라 `com.apple.quarantine` 속성 때문에 발생하는데,
이 속성은 브라우저/메일/AirDrop 같은 다운로드 경로가 붙이는 것이라 컴파일러가 만든
빌드 산출물에는 붙지 않습니다. (소스를 ZIP으로 받아도 산출물에는 전파되지 않습니다.)

```bash
# 경고 여부 확인 - com.apple.quarantine 이 없으면 그냥 실행됨
xattr -l /Applications/PostItNotes.app
```

반대로 **빌드된 `.app`을 압축해 다른 사람에게 전달하면 경고가 다시 뜹니다.**
받는 쪽에서 quarantine이 붙기 때문이며, 이때는 우클릭 > 열기로 한 번 허용하거나
아래 명령으로 속성을 제거하면 됩니다.

```bash
xattr -dr com.apple.quarantine /Applications/PostItNotes.app
```

불특정 다수에게 빌드된 앱을 배포하려면 Apple Developer Program 가입 후
Developer ID 서명 + notarization이 필요합니다.

## 요구사항

- macOS 13.0+
- Xcode 15+
- Claude CLI (AI 기능 사용 시)

## 라이선스

Copyright 2024. All rights reserved.
