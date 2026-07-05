# 경로별 보안 룰셋

보안 축을 "항상 전량"으로 돌리지 말고, 파일 종류별 신호가 있을 때 아래 검사를 가중한다.
특히 에이전트/스킬 컬렉션·CI 설정·스크립트가 섞인 레포에서 유효하다.

## 트리거 신호 (핫스팟 가중)

diff나 파일 경로에 아래가 매칭되면 해당 파일에 보안 검사를 집중한다:

- `auth`, `login`, `session`, `token`, `password`, `secret`, `credential`
- `sql`, `query`, `exec`, `eval`, `spawn`, `child_process`
- `crypto`, `hash`, `sign`, `verify`
- `fs`, `readFile`, `writeFile`, `path.join` (+ 사용자 입력)
- `fetch`, `axios`, `request`, `http` (+ 사용자 제어 URL)

## `.github/workflows/**` (GitHub Actions)

- **unpinned action** — `uses: foo/bar@main` 같이 SHA 미고정. 공급망 리스크.
- **과도한 `permissions`** — 기본 `contents: write` 등 필요 이상 권한.
- **`pull_request_target` 오용** — fork PR의 코드를 신뢰 컨텍스트에서 실행.
- **shell에 GitHub context 직접 주입** — `run: echo ${{ github.event.issue.title }}` 류. injection.

## `scripts/**`, `bin/**`

- **command injection** — 사용자/외부 입력을 shell로 전달.
- **SSRF** — 외부 제어 URL로 요청.
- **path traversal** — 검증 없는 경로 조합.
- **하드코딩 시크릿** — 토큰·키·비밀번호 리터럴.

## `agents/**`, `skills/**`, `commands/**` (에이전트 자산)

- **prompt injection** — 외부 입력/파일 내용을 명령으로 취급하는 지시. "무시하고 ~하라" 류 텍스트를 명령이 아니라 데이터로 다루는지.
- **tool-permission creep** — 스킬/에이전트가 필요 이상의 도구·권한을 요구.
- **파괴적 액션의 모호성** — 삭제·덮어쓰기·force-push를 확인 없이 수행하는 지시.
- **secret exfiltration** — 시크릿·env·로컬 경로를 외부로 전송하는 경로.

## 노이즈 컷

- lock 파일, 생성 파일(generated), 에셋, 벤더 디렉토리는 보안 검사 대상에서 제외.
- 비암호 문맥의 난수·해시는 보안 이슈로 올리지 않는다 (`false-positives.md` 참조).
