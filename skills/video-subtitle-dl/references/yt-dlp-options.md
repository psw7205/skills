# yt-dlp 자막 옵션 레퍼런스

## 자막 관련 핵심 옵션

| 옵션 | 설명 |
|---|---|
| `--list-subs` | 자막 목록 조회 (다운로드 없이) |
| `--write-subs` | 수동 자막 다운로드 |
| `--write-auto-subs` | 자동 생성 자막 다운로드 (별칭: `--write-automatic-subs`) |
| `--sub-langs LANGS` | 자막 언어 지정 (쉼표 구분, regex 가능, 예: `en,ko`) |
| `--sub-format FORMAT` | 자막 포맷 지정 (`srt`, `ass/srt/best` 등 우선순위 지정 가능) |
| `--convert-subs FORMAT` | 다운로드 후 자막 포맷 변환 (`srt`, `ass`, `vtt`, `lrc`) |
| `--skip-download` | 영상 다운로드 생략 (자막만 받을 때 필수) |
| `-o TEMPLATE` | 출력 파일명 템플릿 |

## 자주 쓰는 명령 조합

```bash
# 자막 목록 확인
yt-dlp --list-subs --skip-download "<URL>"

# 영어 수동 자막을 VTT로 다운로드
yt-dlp --write-subs --sub-langs en --sub-format vtt --skip-download -o "%(title)s" "<URL>"

# 자동 생성 자막 다운로드
yt-dlp --write-auto-subs --sub-langs en --sub-format vtt --skip-download -o "%(title)s" "<URL>"

# 여러 언어 동시 다운로드
yt-dlp --write-subs --sub-langs en,ko,ja --sub-format vtt --skip-download -o "%(title)s" "<URL>"

# 모든 자막 다운로드
yt-dlp --write-subs --sub-langs all --sub-format vtt --skip-download -o "%(title)s" "<URL>"

# VTT로 다운로드 후 SRT로 자동 변환
yt-dlp --write-subs --sub-langs ko --sub-format vtt --convert-subs srt --skip-download -o "%(title)s" "<URL>"
```

## 인증이 필요한 경우

비공개 영상, 유료 콘텐츠, 로그인 필요 플랫폼에서 사용.

### 브라우저 쿠키 사용 (추천)

```bash
# Chrome 쿠키 자동 추출
yt-dlp --cookies-from-browser chrome --write-subs --skip-download "<URL>"

# Firefox
yt-dlp --cookies-from-browser firefox --write-subs --skip-download "<URL>"

# Safari
yt-dlp --cookies-from-browser safari --write-subs --skip-download "<URL>"
```

`--cookies-from-browser` 구문: `BROWSER[+KEYRING][:PROFILE][::CONTAINER]`

### 쿠키 파일 직접 지정

```bash
yt-dlp --cookies cookies.txt --write-subs --skip-download "<URL>"
```

쿠키 파일은 Netscape 포맷. 브라우저 확장(EditThisCookie, cookies.txt 등)으로 내보내기 가능.

### 계정 로그인

```bash
yt-dlp --username USER --password PASS --write-subs --skip-download "<URL>"
```

2FA가 있으면 `--twofactor CODE` (별칭: `-2`) 추가.

## 플랫폼별 참고사항

### YouTube
- 자동 생성 자막이 대부분 존재 (`--write-auto-subs`)
- 수동 자막이 있으면 수동 자막 우선
- age-restricted 영상은 `--cookies-from-browser` 필요할 수 있음

### Vimeo
- 임베드 플레이어(`player.vimeo.com/video/ID`)로 접근하면 자막 추출 가능한 경우 있음
- 비공개 영상은 쿠키 인증 필요
- Referer가 필요한 경우: `--add-headers "Referer:https://원본사이트.com"`

### Bilibili
- `--sub-langs`에 `zh-Hans` (간체), `zh-Hant` (번체) 사용

### TikTok
- 자동 자막이 있는 영상만 추출 가능
- 쿠키 인증이 필요한 경우가 많음

## 트러블슈팅

| 증상 | 원인 | 해결 |
|---|---|---|
| "No subtitles found" | 자막 없는 영상 | `--write-auto-subs` 시도 |
| "Login required" | 인증 필요 | `--cookies-from-browser` 사용 |
| "Unsupported URL" | 미지원 플랫폼 | `yt-dlp --update` 후 재시도 |
| 403 Forbidden | 지역 제한 또는 인증 | 쿠키 또는 VPN 사용 |
| 자막 파일이 빈 파일 | 포맷 미지원 | `--sub-format best` 사용 |
