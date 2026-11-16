# Good Text Viewer

macOS용 경량 `.txt` 전용 뷰어입니다. AppKit만 사용하며 빠른 실행과 읽기에 집중합니다.

- 정식 버전: **1.0.1**
- 개발/배포: **Dev Dot.**

## 요구 사항

- macOS 13 이상
- Apple Silicon 및 Intel Mac
- Xcode 16 이상 또는 호환되는 최신 Xcode Command Line Tools
- 외부 패키지 없음

## Homebrew 설치

macOS 13 이상에서 Apple 공증을 받은 앱을 설치합니다.

```sh
brew install --cask arden-deq/tap/dev-dot-good-text-viewer
```

설치 후 응용 프로그램 폴더에서 **Good Text Viewer**를 실행하세요. Homebrew가 tap 신뢰를 요청하면 `brew trust --cask arden-deq/tap/dev-dot-good-text-viewer`를 실행한 뒤 설치를 다시 시도하세요.

## 빌드 및 실행

프로젝트 루트에서 다음 명령을 실행합니다.

```sh
make test
make run
```

`make run`은 릴리스 실행 파일을 빌드하고 `dist/Good Text Viewer.app` 앱 번들을 만든 뒤 실행합니다. 앱만 만들려면 `make package`, 릴리스 바이너리만 빌드하려면 `make build`를 사용하세요.

Finder에서 직접 실행할 때는 `dist/Good Text Viewer.app`을 더블 클릭하면 됩니다. 원하는 경우 이 앱을 `/Applications`로 복사할 수 있습니다.

## 사용법

1. 앱을 실행합니다.
2. `⌘O`를 누르거나 **파일 > 열기…**에서 `.txt` 파일을 선택합니다. `.txt` 파일을 앱 창으로 끌어 놓아도 열립니다.
3. 한쪽 보기와 두쪽 보기를 바꾸고 글자 크기·자간을 읽기 편하게 조절합니다.
4. 하단 진행도 선을 드래그해 원하는 위치로 이동할 수 있습니다.
5. 방향키, Page Up/Page Down 또는 Space/Shift-Space로 페이지를 이동합니다.

지원 파일은 확장자가 `.txt`인 일반 텍스트입니다. 문서가 UTF-8이 아니면 앱이 지원하는 대체 인코딩으로 자동 판별합니다.
오래된 고정폭 문서의 인위적인 줄바꿈은 반복 패턴이 강할 때만 자동으로 정리합니다. 최근 문서의 줄바꿈을 원문 그대로 보고 싶다면 **보기 > 오래된 문서 줄바꿈 자동 정리**를 끄면 됩니다.

Finder에서 파일을 열려면 `.txt` 파일을 보조 클릭한 뒤 **다음으로 열기 > Good Text Viewer**를 선택합니다. 앱을 `/Applications`로 복사해 두면 **다음으로 열기** 목록에서 찾기 쉽습니다.

## 키보드 단축키

| 기능 | 단축키 |
| --- | --- |
| 텍스트 파일 열기 | `⌘O` |
| 한쪽 보기 | `⌘1` |
| 두쪽 보기 | `⌘2` |
| 글자 크게 | `⌘+` |
| 글자 작게 | `⌘-` |
| 자간 넓게 | `⌥⌘]` |
| 자간 좁게 | `⌥⌘[` |
| 다음 페이지 | `→`, `Page Down` 또는 `Space` |
| 이전 페이지 | `←`, `Page Up` 또는 `Shift-Space` |

## 패키징과 서명

`Scripts/package.sh`는 SwiftPM 릴리스 바이너리를 표준 macOS 앱 번들 구조로 복사하고 로컬 실행용 ad-hoc 서명을 적용한 뒤 서명을 검증합니다. 생성 결과는 언제나 다음 위치입니다.

```text
dist/Good Text Viewer.app
```

이 서명은 현재 Mac에서 개발·실행하기 위한 것입니다. 다른 사용자에게 인터넷으로 배포하면 Gatekeeper가 앱을 차단할 수 있습니다. 공개 배포에는 **Developer ID Application** 인증서, hardened runtime 서명, Apple 공증(`notarytool`), staple 과정이 별도로 필요합니다.

앱 정보 창에는 정식 버전 `1.0.1`, 개발/배포 사업자명 `Dev Dot.`, 저작권 정보와 앱 아이콘이 표시됩니다. 번들 식별자는 `com.devdot.goodtextviewer`입니다.

## 일반 다운로드용 릴리스

다음 명령은 universal 앱과 SHA-256 파일을 만듭니다.

```sh
make release
```

생성 결과:

```text
dist/Good-Text-Viewer-1.0.1-macOS-universal.zip
dist/Good-Text-Viewer-1.0.1-macOS-universal.zip.sha256
```

기본 결과는 ad-hoc 서명된 로컬 검증본입니다. 공개 게시본은 Developer ID로 서명하고 Apple 공증을 마친 뒤 만들어야 합니다.

## Homebrew Cask 배포

공개 GitHub 릴리스에 위 ZIP을 업로드한 뒤 다음 명령으로 Cask를 생성합니다.

```sh
./Scripts/render-cask.sh <github-owner>/<app-repository>
```

결과는 `HomebrewTap/Casks/dev-dot-good-text-viewer.rb`입니다. 이 파일을 `<github-owner>/homebrew-tap` 저장소의 같은 경로에 게시하면 사용자는 다음 형식으로 설치할 수 있습니다.

```sh
brew install --cask <github-owner>/tap/dev-dot-good-text-viewer
```

Developer ID 인증서와 `notarytool` 키체인 프로필을 준비한 환경에서는 아래 공개 배포 명령이 서명, 공증, staple, Gatekeeper 검사, ZIP, SHA-256, Cask 생성을 순서대로 수행합니다.

```sh
GOOD_TEXT_VIEWER_SIGNING_IDENTITY="Developer ID Application: …" \
GOOD_TEXT_VIEWER_NOTARY_PROFILE="notary-profile" \
./Scripts/make-publish-release.sh <github-owner>/<app-repository>
```

Homebrew 작업 파일과 체크리스트는 `Packaging/homebrew`에 있습니다.

## 정리

```sh
make clean
```

SwiftPM 빌드 산출물과 생성된 앱 번들을 삭제합니다.
