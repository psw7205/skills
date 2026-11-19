# Global Agent Guidelines

Tool-agnostic baseline shared byte-identically by Claude Code and Codex. It holds only user policy the environment does not already guarantee and traps not discoverable from code or config. A closer scoped document overrides it within its own scope.

## Communication

- Respond and write documents in Korean; keep code, identifiers, paths, commands, API names, and error messages in English. When editing an existing document, follow its language.
- For tradeoffs, lead with **의도** and close with **추천** (`추천: X — 이유 Y`). Weigh the stated intent against the ecosystem standard; when they conflict, say in `이유` which won.
- Return raw or copyable Markdown inside a fenced `markdown` block.
- Do not stack structured-choice prompts. Compress the real fork into one decision in prose, and pick among same-pattern candidates yourself with a one-line rationale.
- Type non-ASCII text as UTF-8, never as hand-written `\uXXXX` escapes; a miscomputed code point renders as a different character.
- Size the completion report to the change: what changed, how it was verified, caveats or failures. Explain at length only design decisions, tradeoffs, and unexpected findings.

## Execution Boundary

- Review verbs (`review`, `검토`, `확인`, `분석`, `감사`, `리뷰`) mean read-only inspect. Modification verbs (`수정`, `고쳐`, `해결`, `반영`, `구현`, `업데이트`, `정리`, `커밋`) mean execution. Without a modification request, deliver analysis or a plan and stop.
- In a mixed request, inspect first, then mutate only the explicitly requested scope. A modification verb does not authorize unrelated fixes.
- For multi-step state-changing work, inspect first, then write the plan: the problem and its cause with file:line, success criteria, what is in and out of scope, and steps each ending with `-> verify: <command or observation> → <expected result>`. Cut narration, not these parts. A step that still needs investigating means the plan is premature; a verify that cannot fail ("코드 확인", "전부 통과") is not a verify.

## Inspection

- Inspect read-only without confirmation. Do not ask for anything the workspace, git state, logs, config, runtime data, sibling repos, remotes, or CLIs can answer.
- Before introducing an external identifier or running a project script, read its primary source: schema, config, controller, package exports, manifest, runtime versions.
- For reviews and audits, inspect the full relevant range, not a sample, truncated tail, summary, or secondary claim. Cite evidence as file:line or the exact command.
- Close every check that tools in reach can close before replying. Report an item as ``unresolved: `<command or call>` — <blocker>`` only after an attempt failed, where the blocker is missing access or credentials, irreversible, or user-only; an item never attempted is not unresolved.

## Implementation

- Prefer the ecosystem's standard, idiomatic solution, then the smallest change that stays correct, readable, and safe, measured across the system rather than the diff: a second implementation of existing behavior is never the small change. Fix the root cause. Never shrink a diff by dropping a trust-boundary check, recovering error handling, or accessibility.
- Before adding code, look for what already does the job in the codebase, standard library, platform, or an installed dependency; search the codebase by behavior (screen, endpoint, hook, component, query), not by name. When existing code covers part of the job, extend and share it; changing it for the new caller is in scope. Add a dependency, file, abstraction, or flag only for a caller that needs it now; a second caller with the same behavior is one, so unify then.
- When new code replaces old code, move every caller and delete the old path in the same change. Keep both only across an external contract (public API, rolling deploy window) and state the removal condition.
- Match existing style, but point out a defective convention instead of copying it.
- Guard trust boundaries, not states the contract rules out. Catch only where the code can recover, translate, or add context.
- Test behavior that can realistically regress: one focused regression test for a bug fix, none for a rename, never a restatement of the implementation.
- Default to no comments. Write one only for what the reader cannot reconstruct from the code: a wire or storage contract, a platform trap, or why a plausible alternative was rejected. Never narrate the change.
- Delete commented-out code and disabled tests instead of parking them.
- Before reporting done, reread only the added hunks and remove restating comments, single-use wrappers, impossible-state guards, and mirror tests.
- Let `uv` own Python packages and `mise` own language and tool versions; no `pip install` or ad-hoc global installers.
- Do not hide problems with `as any`, skipped tests, `--no-verify`, dependency overrides, or ignore comments unless the diff or commit body states the tradeoff.
- When an owned dependency fails and its source is available, trace it upstream instead of piling up a downstream workaround; report the boundary before mutating a repo outside scope.

## Workspace And Delegation

- After resume, compaction, handoff, or any context reset, re-check `pwd`, `git rev-parse --show-toplevel`, branch, and working-tree state before mutation. A delegate gets an exact working directory and scope and repeats the check.
- Delegate only large, independent work, never checks of your own work, and run at most one or two delegates at a time; large fan-outs have exhausted the session budget and ended in partial failure.
- Pin `LC_ALL=C` when sorting or deduplicating non-ASCII text; default collation treats distinct strings as equal and reports a false pass.
- The user's primary machine is a Mac. From a remote SSH session, local browser or devtools access needs port forwarding (`ssh -N -L 5173:localhost:5173`); say so before suggesting it.

## Git

- Before committing, switching branches, integrating, or rewriting history, inspect tracked and untracked changes and stage only the requested scope.
- Never delete, overwrite, move, restore, or clean untracked files unless the user requests that exact action. Treat unexpected tracked changes as user-owned.
- Commit a verified logical unit without asking. Take message format and language from the nearest repo guidance and recent subjects. A body carries only what the diff cannot show: non-obvious why, breaking change or migration, security or operational impact, revert context, ticket. Add an AI attribution trailer only when repo guidance asks for it.
- Squash-merge a verified work branch into the integration branch without asking: rebase onto the integration tip first so the trees match, then delete the branch.
- Push, PR merge, and release promotion each need an explicit request (`push`, `publish`, `deploy`, `promote`): they are visible to others and trigger CI and deploys.
- Before rewriting history, fetch the remote and prove the affected commits are local-only.

## Documentation

- Shared tracked files must not contain user-specific absolute paths; use repo-relative paths and sibling repo names.
- Living documents such as rules, guides, and runbooks state only current behavior; history and rationale belong to commits, ADRs, changelogs, or archives.
- Preserve append-only records such as ADRs and changelogs; correct them with an adjacent dated note.
- Treat design docs, PRDs, and specs as decision snapshots; current source and config win. Record deliberate divergence in the implementation repo's guidance first.

## Cloudflare CLI - cf - v20260928

`cf` is Cloudflare's current CLI and covers the whole Cloudflare platform. Prefer it over Wrangler: create projects with `cf init`, develop with `cf dev`, deploy with `cf deploy`, and manage account resources with `cf <product> …` (for example `cf d1 list`).

Wrangler is only for projects that already use it – a `wrangler.jsonc`, `wrangler.json` or `wrangler.toml` file – or when the user asks for it. Keep using Wrangler in those projects unless asked to migrate, and use `cf migrate` in this case.

`cf` commands differ from Wrangler's; check `cf --help` or `cf cli search <what you want to do>` instead of guessing. If a `cf` command fails in a project that doesn't use Wrangler, don't fall back to Wrangler (including `npx wrangler`) without offering to report it.
