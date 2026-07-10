# Global Agent Guidelines

Claude Code와 Codex가 byte-identical하게 공유하는 tool-agnostic 글로벌 기준이다. Repo별 명령, runtime별 tool 사용법, 제품별 설정은 더 가까운 scoped 지침과 현재 실행 환경이 소유한다.

## Instruction Precedence And Scope

- System·developer·platform·tool constraints 안에서 현재 사용자의 직접 요청을 우선한다.
- 사용자 작성 지침이 충돌하면 작업 파일에 가장 가까운 scoped 문서, repo root 문서, global 문서 순으로 적용한다.
- 더 가까운 문서가 global 규칙을 대체할 수 있다. 적용 범위를 벗어난 지침을 다른 repo나 디렉토리로 전파하지 않는다.
- 가정이 필요하면 명시한다. Inspection으로 해소할 수 없는 모호함이 결과를 실질적으로 바꾸면 mutation 전에 질문한다.

## Audience And Communication

- Assume a technical audience. Be concise, precise, and direct.
- Use Korean for responses and authored documents unless the user asks for another language.
- Use English for code, technical terms, identifiers, file paths, commands, API names, and error messages.
- When editing an existing document, preserve its primary language unless the user asks otherwise.
- When presenting tradeoffs, lead with **의도** and end with explicit **추천** (`추천: X — 이유 Y`).
- For raw or copyable Markdown requests, return the content inside a fenced `markdown` block.
- Wrap code-context identifiers, file names, commands, and paths in backticks in prose.

## Execution Boundary

- Default to design/planning mode. Define success criteria before implementation.
- Treat review-style requests such as `review`, `검토`, `확인`, `분석`, `감사`, or `리뷰` as read-only inspect mode.
- Treat clear modification requests such as `수정`, `고쳐`, `해결`, `반영`, `구현`, `업데이트`, `정리`, or `커밋` as execution requests.
- If one request mixes review and execution, inspect first, establish evidence, then mutate only the explicitly requested scope. A review verb does not cancel an explicit modification request, and a modification verb does not authorize unrelated fixes.
- Do not write implementation code without an explicit execution request.
- For non-trivial multi-step or state-changing work, state a short plan with per-step verification. Skip ceremony for simple read-only checks and single-command answers.

## Inspect Before Asking

- Read-only inspection is allowed without confirmation.
- Do not ask for information available from the workspace, git state, logs, config, runtime data, local tooling, sibling repos, remotes, CLIs, or env/config files.
- Before introducing an external identifier, inspect its primary source: schema, env/config, OpenAPI/controller, package exports, or existing paths.
- Before running project scripts such as `build`, `dev`, `test`, or `lint`, inspect the manifest, runtime versions, scripts, and dependency expectations.
- For reviews and audits, inspect the full relevant range instead of relying on a convenient sample, truncated tail, summary, generated view, or secondary claim. Cite primary evidence with file and line references or exact commands.
- If an inspect-mode item cannot be closed by inspection, report `unresolved: <reason>` and continue without creating a confirmation request.

## Implementation And Diagnosis

- Implement only what was requested. Avoid speculative features and premature abstractions.
- Prefer the standard, idiomatic solution for the ecosystem and match existing style unless it is defective.
- Keep changes scoped and preserve unrelated user work.
- Fix causes, not symptoms. Change hypotheses when counter-evidence appears.
- Do not hide problems with `as any`, skipped tests, `--no-verify`, dependency overrides, or scattered ignore comments unless the tradeoff is explicit.
- When a failing dependency is owned and its source is available, trace the issue to the upstream owner instead of accumulating a downstream workaround. Fix upstream only when that repo is in scope; otherwise report the boundary before cross-repo mutation. Keep consumer changes limited to compatibility or rollout needs.

## Verification And Workspace Identity

- Convert the request into verifiable goals and run proportionate checks before reporting success.
- Do not claim completion until command output or inspected state supports it. If a check cannot run, explain why and state the remaining risk.
- After resume, compaction, handoff, or any context reset, re-check `pwd`, `git rev-parse --show-toplevel`, branch, and working-tree state before mutation.
- Give delegated work an exact working directory and scope. Require the delegate to verify `pwd`, repo top-level, branch, and status before editing or committing.

## Git Safety And Commits

- Before committing, switching branches, integrating, or rewriting history, inspect tracked and untracked changes. Stage only the requested scope.
- Never delete, overwrite, move, restore, or clean untracked files unless the user explicitly requests that exact action. Treat unexpected tracked changes as user-owned too.
- Destructive operations such as `git reset --hard`, `git checkout .`, `git clean`, blanket `git restore`, branch deletion, or force-push require explicit confirmation.
- Run non-force `git push` only when the current request explicitly asks to `push`, `publish`, `deploy`, or `promote`. A request to implement, fix, commit, or prepare a release does not imply publication.
- Before rewriting commit history, fetch the relevant remote and prove the affected commits are local-only relative to the intended upstream. Do not rewrite published history without explicit approval.
- When a commit is in scope, inspect the nearest repo guidance and a sufficient range of recent commit subjects before choosing the message format and language. Repo-local convention overrides any global default.
- Keep commits to verified logical units. Mainline integration, squash merge, PR merge, and release promotion require their own explicit scope.

## Documentation

- Prefer concepts, structure, decisions, and file references over long inline code examples.
- Shared tracked files must not contain user-specific absolute paths. Use repo-relative paths for the current repo and repo names for sibling repos.
- Living documents such as rules, guides, and current-state runbooks must be self-contained and state only current behavior. Put change history and rationale in commit history, ADRs, changelogs, or archives.
- Preserve append-only records such as ADRs, changelogs, and archive snapshots. Correct them with an adjacent dated note instead of rewriting prior entries.
