---
name: video-subtitle-dl
description: >
  영상 URL에서 한국어 자막을 다운로드하거나, 영어 자막을 받아 한국어로 번역하는 스킬.
  수동 자막과 자동 생성 자막을 우선순위에 따라 자동 선택한다.
  "자막 다운로드", "자막 뽑아줘", "영상 스크립트 뽑아줘",
  "자막 번역해줘", "이 영상 자막 한국어로", "영상 번역",
  "CC 자막 뽑아줘", "영상 URL 자막", "유튜브 자막 가져와",
  "비디오 자막", "영상 링크 자막" 등에서 트리거.
  YouTube, Vimeo 등 yt-dlp 지원 플랫폼 대응.
---

# Video Subtitle Download & Translate

영상 URL에서 한국어 자막을 확보한다. 한국어 자막이 있으면 바로 다운로드, 없으면 영어 자막을 받아 번역한다.

## 사전 조건

`yt-dlp`가 필요하다. 먼저 존재 여부를 확인한다:

```bash
command -v yt-dlp
```

없으면 설치를 안내한다:

```bash
# macOS
brew install yt-dlp

# pip
pip install yt-dlp
```

## 실행 절차

### 1. URL 수신 및 자막 목록 조회

사용자로부터 영상 URL을 받는다. 자막 목록을 먼저 확인:

```bash
yt-dlp --list-subs --skip-download "<URL>"
```

출력에서 확인할 것:
- **Available subtitles**: 수동 자막 (업로더가 올린 자막)
- **Available automatic captions**: 자동 생성 자막

각 섹션에서 `ko`(한국어)와 `en`(영어) 존재 여부를 확인한다.

### 2. 자막 다운로드

아래 우선순위대로 첫 번째 매칭에서 다운로드한다:

| 순위 | 조건 | 액션 | 다음 단계 |
|------|------|------|-----------|
| 1 | 한국어 수동 자막 있음 | `--write-subs --sub-langs ko --convert-subs srt` | → Step 5 |
| 2 | 한국어 자동 자막 있음 | `--write-auto-subs --sub-langs ko --convert-subs srt` | → Step 5 |
| 3 | 영어 수동 자막 있음 | `--write-subs --sub-langs en` | → Step 4 |
| 4 | 영어 자동 자막 있음 | `--write-auto-subs --sub-langs en` | → Step 4 |
| 5 | 둘 다 없음 | — | → Step 6 (자막 없음) |

```bash
# 예: 한국어 수동 자막 다운로드 (SRT로 바로 변환)
yt-dlp --write-subs --sub-langs ko --sub-format vtt/srt/best --convert-subs srt --skip-download -o "%(title)s" "<URL>"

# 예: 영어 자동 자막 다운로드 (번역용이므로 VTT 유지)
yt-dlp --write-auto-subs --sub-langs en --sub-format vtt/srt/best --skip-download -o "%(title)s" "<URL>"
```

- `--sub-format vtt/srt/best`: yt-dlp가 VTT → SRT → 기타 순으로 사용 가능한 포맷을 자동 선택.
- `--convert-subs srt`: 한국어 자막 경로에서 SRT로 바로 변환. 번역이 필요한 영어 경로에서는 생략(VTT 원본 유지).
- `-o "%(title)s"`: 영상 제목 기반 파일명.

### 3. 다운로드 실패 시

`yt-dlp`가 실패하면 인증 옵션을 안내한다. 상세는 `references/yt-dlp-options.md` 참조.

사용자에게 선택지 제시:
1. **브라우저 쿠키 사용** — `--cookies-from-browser chrome`
2. **쿠키 파일 지정** — `--cookies cookies.txt`
3. **계정 로그인** — `--username` / `--password`

사용자가 선택하면 해당 옵션을 추가하여 재시도.

### 4. 번역 (영어 → 한국어)

**한국어 자막을 직접 받은 경우 이 단계를 건너뛴다.**

다운로드된 영어 자막 파일을 읽고 한국어로 번역한다. 상세 규칙은 `references/translation-guide.md` 참조.

핵심 규칙:
- **타임코드는 절대 수정하지 않는다.** 텍스트만 번역.
- 기술 용어, 고유명사, 브랜드명은 원문 유지.
- 자연스러운 구어체로 번역. 직역 금지.

번역 절차:
1. 원본 자막 파일을 Read로 읽는다
2. 500 cue 이하: 한 번에 번역
3. 500 cue 초과: 200-300 cue 단위로 청크 분할하여 번역
4. 번역된 내용을 새 파일로 저장

### 5. 포맷 변환 및 저장

**파일명 규칙:**
- 원본(영어): `{영상제목}.en.vtt` (예: `codex-for-software-engineers.en.vtt`)
- 번역본: `{영상제목}.ko.srt` (예: `codex-for-software-engineers.ko.srt`)
- 한국어 자막 직접 다운로드: `{영상제목}.ko.srt` — Step 2에서 `--convert-subs srt`로 이미 SRT이므로 추가 변환 불필요.
- 영상 제목은 `yt-dlp`가 생성한 파일명 기반. 특수문자 제거, 공백은 하이픈.

**SRT 변환 (번역 경로만 해당):** 영어 자막을 번역한 경우, `references/translation-guide.md`의 "VTT → SRT 변환 규칙"에 따라 변환.

**저장 위치:** 현재 작업 디렉토리 (`$PWD`)

### 6. 완료 / 자막 없음

**자막을 확보한 경우:**
- 저장된 파일 경로 (원본 + 번역본, 또는 한국어 자막만)
- 자막 cue 수

**자막이 없는 경우:**
- "이 영상에는 사용 가능한 자막(한국어/영어)이 없습니다." 출력 후 종료
