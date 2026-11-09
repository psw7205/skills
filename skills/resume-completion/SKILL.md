---
name: resume-completion
description: >
  claude --resume Tab, codex resume Tab에서 세션 목록을 타이틀·마지막 작업 시각·짧은 id와 함께
  fzf로 띄우고, 고른 세션의 uuid를 커맨드라인에 채우는 zsh completion을 설치·검증·갱신·제거한다.
  fzf-tab이 있으면 fzf 창과 미리보기, 없으면 zsh 기본 메뉴로 동작한다.
  "resume 자동완성", "resume 탭 완성", "세션 목록 탭", "claude resume tab", "codex resume tab",
  "resume completion 설치", "세션 picker 설치", "resume fzf", "세션 자동완성 안 떠",
  "claude --resume 탭 안 돼", "install resume completion", "session picker for claude resume",
  "codex resume completion", "fzf session picker" 등에서 트리거.
---

# resume-completion

`claude --resume`와 `codex resume`의 세션 인자를 Tab으로 고르게 한다. 사용자가 알아보는 신호는 타이틀이므로 목록은 타이틀이 앞이고 uuid는 뒤에 짧게만 보이며, 고르면 uuid가 들어간다.

별도 키 바인딩을 만들지 않는다. zsh completion 함수(`_claude`, `_codex`)만 제공하고, 셸에 `fzf-tab`이 로드돼 있으면 일반 Tab이 fzf 창이 된다. 현재 디렉토리 세션과 다른 프로젝트 세션이 그룹 헤더로 나뉘고 `<`/`>`로 그룹을 오간다. 오른쪽 미리보기에는 cwd, 시각, 최근 대화가 나온다.

## 구성 파일

| 파일 | 역할 |
|------|------|
| `scripts/resume-completion/resume-completion.plugin.zsh` | fpath 등록과 zstyle(그룹 헤더, 정렬 끔, preview, 그룹 전환 키). oh-my-zsh 플러그인 진입점 |
| `scripts/resume-completion/_claude` | `claude` completion. `--resume`/`-r` 다음 단어에서 세션 후보, 나머지 옵션은 `claude --help`를 파싱해 제공 |
| `scripts/resume-completion/_codex` | `codex completion zsh` 출력을 다른 이름으로 로드하고 `session_id` 자리만 세션 후보로 치환 |
| `scripts/resume-completion/_resume_completion_sessions` | 두 completion이 공유하는 후보 생성. 표시 문자열 조립과 그룹 분리 |
| `scripts/resume-completion/resume-sessions` | `claude` 또는 `codex` 세션을 `epoch·id·cwd·title` TSV로 출력. Claude는 mtime 캐시 사용 |
| `scripts/resume-completion/resume-preview` | fzf 미리보기. 메타데이터와 최근 사용자·에이전트 메시지 |
| `scripts/test-resume-completion.zsh` | zpty로 실제 Tab 시나리오를 돌리는 검증. 일반 compsys 경로와 fzf-tab(가짜 fzf) 경로 모두 |

`${CLAUDE_PLUGIN_ROOT}/skills/resume-completion/scripts/resume-completion/` 또는 `~/.agents/skills/resume-completion/scripts/resume-completion/`로 resolve한다.

## 데이터 소스

- Claude: `${CLAUDE_CONFIG_DIR:-~/.claude}/projects/*/<uuid>.jsonl`. 타이틀은 `agent-name`(`--name`으로 지은 이름) 줄 우선, 없으면 마지막 `ai-title`, 둘 다 없으면 첫 사용자 메시지. 현재 디렉토리 판정은 디렉토리 이름이 아니라 transcript 안의 `cwd` 값으로 한다.
- Codex: `${CODEX_HOME:-~/.codex}/state_<n>.sqlite`의 `threads` 테이블. `name` 우선, 없으면 `title`, 없으면 `first_user_message`. `archived=1`, `source='exec'`, subagent(`{...}` 형태 source)는 제외. 미리보기는 `thread_history_<n>.sqlite`.
- 의존: `jq`(Claude 미리보기와 타이틀 fallback), `sqlite3`(Codex). 없으면 해당 부분만 비고 completion 자체는 동작한다.

## 설치 절차

1. 전제 확인: `zsh`, `fzf`, `jq`, `sqlite3`, 그리고 fzf 창을 원하면 `fzf-tab`이 셸에 로드돼 있어야 한다. `fzf-tab`이 없으면 zsh 기본 메뉴로 동작하며 미리보기와 그룹 전환은 없다.
2. 플러그인 디렉토리 복사. 심볼릭 링크가 아니라 복사다. 스킬 경로는 설치 도구가 바꿀 수 있고, 셸 시작 경로가 그 변동을 따라가게 두지 않는다.
   - oh-my-zsh: 대상 `"${ZSH_CUSTOM:-$ZSH/custom}/plugins/resume-completion"`을 `mkdir -p`로 만든 뒤 `cp -R "<skill>/scripts/resume-completion/." "${ZSH_CUSTOM:-$ZSH/custom}/plugins/resume-completion/"`로 내용을 복사한다. `~/.zshrc`의 `plugins=(...)`에 `resume-completion`을 추가한다. 위치는 무관하다. oh-my-zsh가 플러그인 디렉토리를 compinit 전에 fpath에 넣고 plugin 파일은 compinit 뒤에 source한다.
   - 그 외 zsh: 원하는 대상(예: `~/.zsh/plugins/resume-completion`)을 `mkdir -p`로 만들고 `cp -R "<skill>/scripts/resume-completion/." "<dir>/"`로 내용을 복사한다. `~/.zshrc`에서 `compinit`보다 앞에 `fpath=(<dir> $fpath)`, 뒤에 `source <dir>/resume-completion.plugin.zsh`를 둔다. 기존 `~/.zcompdump*`를 지워야 새 `_claude`·`_codex`가 등록된다.
3. 기존 `~/.zshrc`를 덮어쓰지 않는다. 플러그인 이름 한 줄만 추가하고 diff를 보여준다.
4. Claude 캐시를 미리 만든다: `zsh <dir>/resume-sessions claude >/dev/null`. 첫 스캔은 transcript 총량에 비례해 수 초 걸리고, 이걸 건너뛰면 첫 Tab이 그만큼 멈춘다.
5. 새 셸에서 `claude --resume ` 뒤 Tab, `codex resume ` 뒤 Tab으로 확인한다. 기존 탭에는 반영되지 않는다.

## 검증

```bash
zsh <skill>/scripts/test-resume-completion.zsh
```

임시 Claude transcript와 Codex DB를 만들어 개인 세션 저장소 대신 사용하고, zpty로 대화형 zsh를 띄워 실제 키 입력으로 검사한다. 일반 compsys 경로에서는 후보와 그룹 헤더, alias를 거친 호출, `claude --` 옵션 목록, Codex upstream 서브커맨드·옵션 보존을 본다. fzf-tab 경로에서는 가짜 fzf로 선택했을 때 uuid가 삽입되는지, 타이핑한 글자가 fzf 검색어가 되고 삽입 시 치환되는지, 표시가 충돌한 두 세션을 각각 고를 수 있는지 본다. 셸 문법이 들어 있는 cwd·타이틀의 비실행과 재설치 시 파일 갱신·중첩 부재도 검사한다. `FZF_TAB_PLUGIN`으로 fzf-tab 경로를 지정하거나 빈 값으로 그 절을 건너뛴다.

수동 확인은 `claude --resume ` 뒤 Tab이다. 후보가 없으면 `zsh <dir>/resume-sessions claude | head`로 데이터 소스부터 본다.

## 설정

플러그인 파일을 source한 뒤 `~/.zshrc`에서 덮어쓴다.

```zsh
# 다른 프로젝트 그룹의 최대 개수 (기본 200)
zstyle ':resume-completion:claude' others-limit 100
zstyle ':resume-completion:codex' others-limit 100
# 그룹 전환 키 (기본 < >)
zstyle ':fzf-tab:complete:*:(claude|codex)-session' switch-group 'F1' 'F2'
# 미리보기 창
zstyle ':fzf-tab:complete:*:(claude|codex)-session' fzf-flags --preview-window=down,40%
```

환경변수: `CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `RESUME_COMPLETION_CACHE_DIR`(기본 `${XDG_CACHE_HOME:-~/.cache}/resume-completion`). `RESUME_COMPLETION_DEBUG=<file>`를 주면 후보 생성 시 context와 개수를 그 파일에 남긴다.

## 갱신과 제거

- 갱신: 스킬을 업데이트한 뒤 설치 절차 2를 다시 수행한다. 플러그인 디렉토리는 복사본이라 자동으로 따라가지 않는다.
- 제거: `plugins=(...)`에서 `resume-completion`을 빼고 플러그인 디렉토리와 캐시 디렉토리를 지운다. 설정 파일의 다른 내용은 건드리지 않는다.

## Gotchas

- fzf-tab은 `compadd -d`로 표시 문자열이 주어지면 단어 대신 그 문자열만 보여준다. 삽입과 미리보기가 표시 문자열로 후보를 역조회하므로 표시 문자열은 후보마다 유일해야 한다. 끝에 id 앞 8자리를 붙이고, 표시가 충돌한 후보는 전체 UUID로 확장한다. UUIDv7의 앞 8자리는 시간 접두어라 유일하지 않다.
- fzf-tab은 후보들의 공통 접두어가 있으면 fzf를 열기 전에 그 접두어를 먼저 삽입한다. Codex 세션 id는 UUIDv7이라 전부 `01`로 시작해 첫 Tab에 `01`만 들어가는 증상이 난다. 후보 생성 함수가 `compstate[insert]=automenu`로 이 단계를 끈다.
- fzf-tab은 마지막 compadd 호출의 context로 preview·flags zstyle을 찾는다. Codex는 upstream `_arguments`가 세션 후보 뒤에 다시 compadd를 불러 context가 `codex-command-resume`으로 덮이므로, 플러그인의 Codex zstyle은 그 context까지 함께 매칭한다. 이게 빠지면 Codex만 미리보기 창이 없다.
- fzf-tab은 compsys의 알파벳 정렬을 따로 적용한다. `sort false` zstyle이 빠지면 최신순이 타이틀 순으로 바뀐다.
- 후보는 `compadd -U`로 typed prefix 필터를 끄고, fzf-tab의 `query-string input first`로 입력한 검색어를 우선한다. `claude -r lotte` 뒤 Tab에서 `lotte`가 uuid 필터나 타이틀의 공통 접두어가 아니라 fzf 검색어가 돼야 하기 때문이다. 선택한 후보를 다시 넣을 때 입력 문자열도 치환한다.
- `codex completion zsh`가 생성하는 spec은 top-level에 선택적 `prompt` 위치 인자를 서브커맨드 앞에 두어서, 있는 그대로 쓰면 `codex resume` 뒤 Tab이 `resume`을 prompt로 먹고 서브커맨드 목록을 낸다. `_codex`가 그 줄을 지우고 dispatch 인덱스를 `$line[2]`에서 `$line[1]`로 보정한다. Codex 버전이 바뀌어 치환 검증이 실패하면 upstream 없이 최소 동작(`resume`·`fork` 다음 단어만 세션 후보)으로 내려간다. `codex` 뒤 Tab이 서브커맨드 대신 파일을 내면 그 상태다.
- `~/.claude/projects/` 디렉토리 이름은 cwd 인코딩 규칙이 Claude Code 버전마다 달라(`.`·공백·`_` 보존 여부) 역변환할 수 없다. 현재 디렉토리 그룹은 transcript의 `cwd`로 판정하므로, worktree에서 시작한 세션은 main repo 디렉토리에서는 "다른 프로젝트"로 보인다.
- Claude 전체 스캔은 transcript 수백 MB 기준 수 초다. 파일 경로와 mtime을 키로 TSV 캐시를 두고 바뀐 파일만 다시 읽는다. 타이틀이 이상하면 캐시 파일을 지우고 다시 만든다.
- 서브에이전트 transcript는 `<uuid>/subagents/` 하위에 있어 glob에서 제외된다. 상위 디렉토리의 `<uuid>.jsonl`만 후보다.
- alias로 플래그가 붙은 `claude`·`codex`도 동작한다. zsh가 completion 전에 alias를 풀어 `words`에 플래그가 들어온 상태로 보기 때문이다.
- `_claude`의 옵션 목록은 `claude --help`를 셸마다 한 번 파싱한 결과다. help 형식이 바뀌어 파싱 결과가 비면 옵션 completion만 빠지고 세션 후보는 그대로 나온다.
- Codex의 sqlite 스키마(`threads` 테이블의 `name`, `title`, `first_user_message`, `cwd`, `archived`, `source`)는 저장 계약이다. Codex가 저장소를 옮기면 Codex 그룹만 비고 `resume-sessions codex`가 빈 출력을 낸다.
