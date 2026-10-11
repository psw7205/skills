---
name: herdr-fork-sync
description: >
  개인 herdr fork 브랜치를 upstream 최신 stable 태그 위로 rebase 동기화하고, 생성물인 API 스키마
  재생성, 검증, fork 태그, GitHub Release까지 이어가는 스킬. upstream 태그와 fork 태그 구분,
  rebase 중 ours/theirs 반전, `v*` 태그 push 금지, `herdr update`가 fork 빌드를 덮어쓰는 함정을 다룬다.
  "herdr 동기화", "herdr 업스트림 반영", "herdr 새 버전 나왔어", "herdr 포크 업데이트",
  "mobile-binding 리베이스", "herdr 최신 태그로 올려줘", "herdr fork 릴리스", "sync herdr fork",
  "rebase herdr onto upstream", "update herdr fork", "herdr fork release" 등에서 트리거.
---

# herdr-fork-sync

upstream(herdrdev/herdr)에서 새 stable 태그가 나올 때마다 fork 브랜치를 그 위로 다시 얹고, 결과를 검증하고 태그하고 배포한다.

전략은 merge가 아니라 **rebase-onto-tag**다. fork 델타는 작고 추가형이라 선형 이력이 델타 가독성과 충돌 처리에 유리하다. 자동화는 fork 저장소 안의 `scripts/fork/sync-upstream.sh`가 담당하고, 이 스킬은 사전 점검, 충돌 판단, 결과 검토, 배포 가드만 다룬다.

## 적용 범위와 제약

- 대상은 `upstream` 리모트가 `herdrdev/herdr`를 가리키는 fork checkout이다. `git remote -v`로 먼저 확인한다. 없으면 이 스킬의 대상이 아니다.
- upstream에 PR, issue, push를 만들지 않는다. herdr 레포 규칙상 승인된 기여자가 아니면 PR 경로가 닫혀 있고, 기능 제안은 사용자가 Discussions에서 직접 한다.
- `git push`는 사용자가 명시적으로 요청할 때만 한다. 스크립트도 기본은 push하지 않는다.
- upstream 규칙상 `skills/herdr/SKILL.md`, `docs/next/CHANGELOG.md`, `distribution/`, `docs/preview/`, `docs/versions/`는 fork 커밋에서 건드리지 않는다. 그래야 rebase마다 충돌이 없다.

## 1. 사전 점검

inspect만 하고 아무것도 바꾸지 않는다.

```bash
git rev-parse --show-toplevel && git remote -v
git status --porcelain && git worktree list
base="$(git describe --tags --abbrev=0 --match 'v[0-9]*' HEAD)"; echo "$base"
git ls-remote --tags upstream | grep -E 'refs/tags/v[0-9]' | tail -3
git log --oneline "$base..HEAD"
```

- base와 최신 upstream 태그가 같으면 rebase할 게 없다. 검증과 태그만 필요한지 요청을 다시 본다.
- 같은 커밋을 가리키는 다른 worktree 브랜치가 있으면 rebase 뒤 stale가 된다. 지우지 말고 보고만 한다.
- `preview-*` 태그는 대상이 아니다. stable은 preview를 승격한 것이라 stable 태그만 따라가면 된다.

## 2. 실행

```bash
scripts/fork/sync-upstream.sh --dry-run        # 계획만 출력
scripts/fork/sync-upstream.sh                  # 최신 v* 태그로
scripts/fork/sync-upstream.sh v0.9.4           # 특정 태그로
```

스크립트 순서: `git fetch upstream --tags`, `git rebase --onto <new> <old> <branch>`, 생성물 스키마 재생성(달라지면 fixup + autosquash), `just ci` + `just docs-contract-test`, `<branch>-<new>` 주석 태그.

| 옵션 | 쓰는 때 |
|------|---------|
| `--continue` | 수동 충돌 해결 뒤 재개 |
| `--check "<recipes>"`, `--skip-check` | 검증 범위 조정. `--check check`는 Windows SDK(xwin)가 있어야 돈다 |
| `--no-tag` | 시험 실행 |
| `--push` | 사용자가 배포까지 요청했을 때만 |

도구가 없다는 오류는 레포의 `mise.toml`이 활성화되지 않은 것이다. `mise trust && mise install`.

## 3. 충돌 처리

스크립트가 멈추면 충돌 파일 목록이 나온다. 유형별로 판단한다.

- **`docs/next/api/herdr-api.schema.json`**: 생성물. 손으로 합치지 않는다. 스크립트가 upstream 사본을 받고 재생성한다(`HERDR_UPDATE_API_SCHEMA=1 just test-one generated_protocol_schema_artifact_is_current`). 다른 파일과 함께 충돌해도 이 파일은 두고 나머지만 해결한다.
- **context 이동(`src/platform/mod.rs` 같은 곳)**: fork가 추가한 블록은 그대로고 upstream이 주변을 바꾼 경우. 삽입 위치만 다시 정하고 fork 블록은 통째로 유지한다. 이전 fork 태그의 같은 파일(`git show <branch>-<old>:<path>`)이 정답에 가깝다.
- **문서 메서드 표(`docs/next/website/src/content/docs/socket-api.mdx`)**: upstream 행을 받고 fork 메서드만 다시 끼워 넣는다.
- **API 등록 지점(`src/api/mod.rs`, `src/app/api.rs`, `src/api/schema/`)**: upstream이 같은 자리에 메서드를 추가한 경우. 양쪽 다 살린다.

rebase 중에는 `--ours`가 upstream, `--theirs`가 fork 커밋이다. merge와 반대라 자주 틀린다.

해결 후:

```bash
git add <files>
scripts/fork/sync-upstream.sh --continue
```

시그니처 변경이나 호출부 이동은 충돌 없이 합쳐져도 의미가 깨질 수 있다. 충돌이 코드 파일이면 `just ci`를 건너뛰지 않는다.

## 4. 결과 검토

```bash
git range-diff <old>..<branch>-<old> <new>..<branch>
```

패치가 의도한 만큼만 달라졌는지 본다. 스키마와 문서 표 외의 hunk가 바뀌었으면 이유를 설명할 수 있어야 한다.

## 5. 배포

사용자가 요청할 때만.

```bash
git push --force-with-lease origin <branch>
git push origin refs/tags/<branch>-<new>
```

태그 push가 `.github/workflows/fork-release.yml`을 트리거해 검증과 빌드 뒤 fork의 GitHub Release에 바이너리를 올린다. 설치:

```bash
curl -fsSL -o ~/.local/bin/herdr "https://github.com/<owner>/herdr/releases/download/<branch>-<new>/herdr-macos-aarch64"
chmod +x ~/.local/bin/herdr && herdr --version
```

로컬 빌드로 대신하려면 `cargo build --release` 뒤 `target/release/herdr`를 같은 자리에 둔다.

## 스크립트가 없을 때

같은 순서를 수동으로 한다. fetch, `git rebase --onto <new> <old> <branch>`, 스키마 재생성 뒤 `git commit --fixup`과 `git rebase -i --autosquash <new>`, `just ci && just docs-contract-test`, `git tag -a <branch>-<new>`. 태그 메시지에는 `Base: <new>` 줄이 있어야 한다. 워크플로가 이 줄을 읽는다.

## Gotchas

- `git push --tags`는 하지 않는다. upstream의 `v*`, `preview-*` 태그가 fork에 올라가 upstream 릴리스 워크플로가 fork에서 돌기 시작한다. 태그는 하나씩 `refs/tags/<name>`으로 push한다.
- fork 태그 이름은 `v`로 시작하면 안 된다. upstream `release.yml`이 `v*`에 반응한다.
- `herdr update`는 herdr.dev의 stable 매니페스트를 보고 fork 빌드를 upstream 바이너리로 덮어쓴다. fork 빌드를 쓰는 머신은 `config.toml`에 `[update] version_check = false`를 두고, 업데이트는 이 스킬로만 한다.
- `just check`는 Windows cross lint 때문에 xwin SDK가 필요하다. 기본 검증은 upstream preview preflight와 같은 `just ci` + `just docs-contract-test`다.
- `just`, `zig 0.16.0`, `cargo-nextest`는 레포 `mise.toml`로 활성화된다. `mise.toml`이 없는 커밋을 체크아웃한 worktree에서는 `mise x just@<v> zig@0.16.0 aqua:nextest-rs/nextest/cargo-nextest@<v> -- <script>`로 감싼다.
- upstream이 Zig나 Rust 버전을 올리면 `mise.toml`과 워크플로의 `ZIG_VERSION`도 같이 올린다. 기준은 `crates/ghostty-vt/build.rs`와 `rust-toolchain.toml`.
- 태그 push는 그 커밋에 워크플로 파일이 들어 있어야 트리거된다. 도구 커밋이 먼저, 태그가 나중이다.
- fork 커밋이 스키마 외에 문서 표 같은 생성물도 포함하면 코드 커밋과 문서 커밋으로 나눠 두는 편이 충돌 표면을 줄인다.
