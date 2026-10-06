# 설정 — `figma-spec-sync.json`

대상 repo에 두고 git으로 공유한다. file key·node-id는 비밀이 아니다. 비밀은 토큰 하나이고 그건 머신 로컬에만 둔다.

## 토큰

Figma → Settings → Security → Personal access tokens. 필요 scope는 `file_content:read`뿐이다.

```bash
mkdir -p ~/.config/figma && echo '<token>' > ~/.config/figma/token && chmod 600 ~/.config/figma/token
# 또는 세션 한정
export FIGMA_TOKEN=<token>
```

스크립트는 env를 먼저, 없으면 파일을 읽는다. repo에 커밋하지 않는다.

## 스키마

| 키 | 필수 | 의미 |
|---|---|---|
| `fileKey` | 필수 | Figma URL `figma.com/design/<fileKey>/<fileSlug>?node-id=<nodeId>`의 file key |
| `nodeId` | 필수 | 스냅샷 루트 노드. URL의 하이픈 형식(`1234-5678`) 그대로 써도 된다 — 스크립트가 콜론으로 정규화한다. 보통 기획 섹션들을 담은 페이지의 최상위 프레임 또는 섹션 |
| `out` | 필수 | 스냅샷 md 경로. 설정 파일 위치 기준 상대 경로 |
| `plan` | 게이트에 필요 | 정합 plan(대조표) 경로. `snapshot-delta.mjs`가 이 문서 §Sync 상태의 `Figma file version` 행을 읽는다. 없으면 게이트만 "판정 불가"고 delta는 나온다 |
| `title` | 선택 | md 제목. 기본 `Figma 기획 스냅샷` |
| `fileSlug` | 선택 | URL의 slug 부분. 링크에만 쓰이고 없어도 링크는 동작한다 |
| `images` | 선택 | 화면 PNG + `index.html` 갤러리 디렉토리. 용량이 크고 가장 먼저 낡으므로 **repo 밖**을 권장한다. 지정하면 `<images>/.sync-state.json`이 version 캐시가 된다 |
| `state` | 선택 | version 캐시 파일 위치를 `images` 밖으로 옮길 때만 |
| `deltaBase` | 선택 | delta·게이트의 기준 rev. 기본 `HEAD`. 스냅샷을 사용자 승인 **전에** commit하는 lane이면 publish 지점(`main` 등)으로 준다 — 그 lane에서는 commit이 "확인했다"의 표시가 아니라서 |

경로는 전부 설정 파일이 있는 디렉토리 기준이다. CLI 플래그(`--out`, `--images`, `--base` 등)는 설정을 덮어쓰고 cwd 기준으로 해석된다.

이 파일은 repo에 commit되어 공유되므로 여기 적힌 경로는 실행자가 직접 준 값이 아니다. 그래서 `out`은 repo 안이어야 하고(`snapshot-delta`도 같은 조건을 요구한다), `state`는 repo 안이거나 `images` 아래여야 한다. `images`는 용량 때문에 repo 밖을 권장하므로 가두지 않으며, 대신 stale 정리는 이 스크립트가 만든 `NN_이름.png` 형태만 지운다. repo 밖 임의 경로가 필요하면 설정이 아니라 CLI 플래그로 준다.

## 예시

```json
{
  "fileKey": "AbCdEfGhIjKlMnOpQrStUv",
  "nodeId": "1234-5678",
  "fileSlug": "admin-2026",
  "title": "관리자 Figma 기획 스냅샷",
  "out": "docs/references/figma-admin.md",
  "images": "../figma-admin-screens",
  "plan": "docs/plans/admin-figma-alignment.md",
  "deltaBase": "HEAD"
}
```

## 탐색 순서

`--config <path>` → `./figma-spec-sync.json` → `./docs/figma-spec-sync.json`. Figma 파일이 둘 이상이면 설정 파일을 이름만 다르게 두고 `--config`로 고른다.

## 추출 규칙 (스크립트 상수)

- 화면: `FRAME`이고 1000×600 이상. 이름이 `-`·`Container`·빈 값이면 md 표에서 빠지지만 PNG는 받는다.
- 기획 설명: `TEXT` 노드 본문(`characters`)이 60자 이상. 같은 문구가 여러 화면에 반복되면 첫 등장만 남긴다.
- 섹션: depth 1 `SECTION`만. 그 아래 중첩 섹션은 라벨을 잃고 화면만 상위로 평평하게 들어간다.

이 상수를 바꾸면 스냅샷이 전면 재작성되고 delta가 폭발한다. 바꾸는 commit에서는 delta를 판정에 쓰지 않는다.

## 정기 실행

밤마다 pull을 걸어두면 아침에 §3 delta부터 시작할 수 있다. cron·launchd 등 OS 스케줄러에 `node <skill>/scripts/figma-sync.mjs --config <path>`를 감싼 래퍼를 등록하되, 스케줄러는 셸 프로필을 읽지 않으므로 node와 스크립트를 절대 경로로 부른다. 변경 판정은 md working-tree의 dirty 여부가 아니라 스크립트 stdout의 "변경 감지"/"변경 없음"으로 한다 — md를 commit하지 않는 설계에서는 dirty가 영구화돼 매일 오탐이 된다. 이 래퍼가 `images`의 유일한 소유자다(SKILL.md §Gotchas).
