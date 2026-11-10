---
name: setup-output-style
description: >
  Claude Code에 한국어 간결 응답 output style(`korean-concise`)을 설치, 선택, 검증, 제거하는 스킬.
  영어 시스템 프롬프트·리마인더 사이에서 응답이 영어로 미끄러지는 것을 매 요청 실리는 한국어 지시로 막는다.
  "output style 설치", "한국어 output style", "한국어 간결 스타일", "답변이 영어로 나와",
  "korean concise style", "install output style", "output style 제거" 등에서 트리거.
---

# setup-output-style

번들된 `references/korean-concise.md`를 Claude Code user output style로 설치하고 기본 style로 선택한다.

## 대상

| 항목 | 위치 |
|------|------|
| Style 파일 | `~/.claude/output-styles/korean-concise.md` |
| 기본 선택 | `~/.claude/settings.json`의 `"outputStyle": "korean-concise"` |

Codex는 output style 기능이 없다. Config reference의 `personality`는 deprecated이고 `model_verbosity`는 GPT-5 Responses API 길이 옵션이라 언어를 정하지 않는다. Codex의 응답 언어는 `setup-global-config`가 설치하는 `~/.codex/AGENTS.md`의 Communication 규칙이 맡는다. 이 skill은 Codex 파일을 건드리지 않는다.

## 설치 절차

1. 이 `SKILL.md` 기준으로 `references/korean-concise.md`를 resolve하고 끝까지 읽는다.
2. Style 파일이 없으면 parent directory를 만들고 canonical bytes를 그대로 복사한다. 있으면 `cmp -s "$canonical" "$target"`으로 비교한다.
   - Exit `0`: 이미 설치됨.
   - Exit `1`: 차이를 보이고 사용자 승인 뒤 `<target>.bak.<timestamp>`로 `cp -p` backup하고 덮어쓴다.
3. `~/.claude/settings.json`의 `outputStyle`을 확인한다.
   - 없으면 `"korean-concise"`로 추가한다. JSON은 `jq`로 key 하나만 바꾸고, 다른 key의 값이 그대로인지 `jq -S` 비교로 확인한다.
   - 다른 값이 있으면 사용자 설정이므로 보이고 승인 뒤 바꾼다.
4. Project 설정이 user 설정을 이긴다. 작업 repo들의 `.claude/settings.json`·`.claude/settings.local.json`에서 `outputStyle`을 찾아 목록으로 보고한다. 사용자가 지정한 project만 `korean-concise`로 바꾸거나 key를 지운다.
5. `cmp`와 `jq -r .outputStyle`로 결과를 확인하고, Claude Code 재시작 뒤 적용된다고 보고한다.

## 제거 절차

1. Style 파일이 canonical과 같으면 지운다. backup이 있으면 경로를 보이고 복원 여부를 묻는다. 다르면 사용자 수정일 수 있으므로 지우지 않고 차이를 보고한다.
2. `~/.claude/settings.json`의 `outputStyle`이 `korean-concise`면 key를 지운다. Project 설정의 같은 값은 목록으로 보고하고 지정된 것만 지운다.

## Gotchas

- `outputStyle` 값은 frontmatter `name`과 대소문자까지 같아야 한다. 틀리면 오류 없이 Default style로 돈다.
- `keep-coding-instructions: true`가 빠지면 Claude Code의 software engineering 지시가 system prompt에서 빠진다.
- Style 파일은 Claude Code 시작 때 읽는다. 실행 중인 세션은 재시작해야 바뀐다. 재시작 뒤 `/output-style`로 선택 상태를 확인한다.
- Output style은 지시이지 강제가 아니다. 반드시 지켜야 하는 동작은 hook으로 건다.
- Tracked 문서에 machine-local absolute path를 쓰지 않는다.
