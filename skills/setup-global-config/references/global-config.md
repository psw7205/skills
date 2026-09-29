# Global Agent Guidelines

Tool-agnostic baseline shared byte-identically by Claude Code and Codex. Repo-specific commands, runtime-specific tool usage, and product settings belong to closer scoped instructions and the current execution environment — a closer document overrides what is here, and its rules do not propagate outside their own scope.

Only two things belong in this file: user policy the execution environment does not already guarantee, and traps that cannot be discovered by reading code or config. Anything a competent agent infers from context stays out.

## Communication

- Korean for responses and authored documents; English for code, identifiers, paths, commands, API names, and error messages. When editing an existing document, follow that document's language.
- When presenting tradeoffs, lead with **의도** and close with an explicit **추천** (`추천: X — 이유 Y`). Pick the 추천 by weighing fit with the stated intent and constraints against the ecosystem standard or best practice; when they conflict, say in `이유` which won and why.
- For raw or copyable Markdown requests, return the content inside a fenced `markdown` block.
- Do not stack consecutive structured-choice prompts. Discuss in plain prose, compress the real fork into a single decision, and pick among same-pattern implementation candidates yourself with a one-line rationale.
- Type non-ASCII text directly as UTF-8. Never hand-write `\uXXXX` escapes; a miscomputed code point silently renders as a different character.

## Execution Boundary

- Without a modification request, the deliverable is analysis or a plan; stop there. Define success criteria before multi-step implementation.
- For multi-step state-changing work, write a short plan whose steps each end with `-> verify: <check>`.
- Review verbs (`review`, `검토`, `확인`, `분석`, `감사`, `리뷰`) mean read-only inspect. Modification verbs (`수정`, `고쳐`, `해결`, `반영`, `구현`, `업데이트`, `정리`, `커밋`) mean execution.
- When one request mixes both, inspect first to establish evidence, then mutate only the explicitly requested scope. A review verb does not cancel an explicit modification request, and a modification verb does not authorize unrelated fixes.

## Inspect Before Asking

- Inspect read-only without confirmation, and do not ask for anything the workspace, git state, logs, config, runtime data, sibling repos, remotes, or CLIs can answer.
- Before introducing an external identifier or running a project script, read its primary source: schema, env/config, OpenAPI/controller, package exports, manifest, runtime versions.
- For reviews and audits, inspect the full relevant range rather than a convenient sample, truncated tail, summary, generated view, or secondary claim. Cite evidence as file:line or the exact command run.
- If an inspect-mode item cannot be closed by inspection, report `unresolved: <reason>` and continue without creating a confirmation request.

## Implementation

- Prefer the ecosystem's standard, idiomatic solution; a smaller diff is not a reason to pick a non-standard one. Match existing style, but point out a defective convention instead of copying it.
- Default to no comments. Names, structure, and tests carry the explanation. Write one only for what the reader cannot reconstruct from the code and would otherwise get wrong: a wire or storage contract, a library or platform trap, or why a plausible alternative was rejected. Never restate what the next line does, never label a section, never narrate the change you just made.
- Keep each fact next to the code that owns it — restatements and comment-to-comment references both drift from what they describe.
- Delete commented-out code and disabled tests instead of parking them; version control already holds the history, while a disabled block reads as intent rather than removal.
- Let the declared toolchain own installs: `uv` for Python packages, `mise` for language and tool versions. Do not reach for `pip install` or ad-hoc global installers.
- Do not hide problems with `as any`, skipped tests, `--no-verify`, dependency overrides, or scattered ignore comments unless the diff or commit body states the tradeoff.
- When a failing dependency is owned and its source is available, trace it to the upstream owner instead of accumulating a downstream workaround. Fix upstream only when that repo is in scope; otherwise report the boundary before cross-repo mutation.

## Verification And Workspace Identity

- After resume, compaction, handoff, or any context reset, re-check `pwd`, `git rev-parse --show-toplevel`, branch, and working-tree state before mutation. Delegated work gets an exact working directory and scope, and the delegate repeats the same check before editing or committing.
- A delegate's prompt states the exact question, the deliverables, a rough tool budget, an output-length limit, what is out of scope, and when to stop early.
- Delegate only large, independent work — not tasks a few tool calls finish, and not checks of your own work. Run at most one or two delegates at a time: large parallel fan-outs have exhausted the session budget and ended in partial failure, below sequential throughput.
- Pin the locale with `LC_ALL=C` when sorting or deduplicating text containing non-ASCII characters. Default collation treats distinct strings as equal and drops them, so the comparison reports a false pass.

## Environment

- The primary machine is a Mac. In a remote SSH session, local browser or devtools access needs port forwarding (for example `ssh -N -L 5173:localhost:5173`); say so before suggesting it.

## Git

- Before committing, switching branches, integrating, or rewriting history, inspect tracked and untracked changes and stage only the requested scope.
- Never delete, overwrite, move, restore, or clean untracked files unless the user explicitly requests that exact action. Treat unexpected tracked changes as user-owned too.
- Committing a verified logical unit needs no prior confirmation. The gate covers publication, not the commit.
- Run non-force `git push` only when the current request explicitly asks to `push`, `publish`, `deploy`, or `promote`: a push is visible to others and triggers CI and deploy pipelines, so the owner checks and dogfoods locally first. A request to implement, fix, commit, or prepare a release does not imply publication.
- Before rewriting commit history, fetch the relevant remote and prove the affected commits are local-only relative to the intended upstream.
- Take commit message format and language from the nearest repo guidance and recent commit subjects.
- Squash-merge a verified work branch into the integration branch without asking. Rebase it onto the integration tip first so that, after the squash commit, the branch tree equals the integration tree; only then delete the branch (`git branch -D` loses nothing once the trees match). Pushing the result, merging a PR, and promoting a release still need their own explicit request.

## Documentation

- Prefer concepts, structure, decisions, and file references over long inline code examples.
- Shared tracked files must not contain user-specific absolute paths. Use repo-relative paths for the current repo and repo names for sibling repos.
- Living documents such as rules, guides, and current-state runbooks must be self-contained and state only current behavior. Change history and rationale belong to commit history, ADRs, changelogs, or archives.
- Preserve append-only records such as ADRs, changelogs, and archive snapshots. Correct them with an adjacent dated note instead of rewriting prior entries.
- Treat design documents, PRDs, and specs as decision snapshots, not runtime truth. Current source and config win. Record deliberate divergence in the implementation repo's own guidance first, then note it in the design document.
