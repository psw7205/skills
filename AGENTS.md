# Repository Guidelines

## Project Structure & Module Organization

This repository is a small skill collection, not an application. Keep changes scoped to the relevant skill or document.

- `skills/<skill-name>/SKILL.md`: one directory per skill; this is the primary source file.
- `skills/<skill-name>/references/`: optional supporting material when a skill needs reference docs.
- `skills/<skill-name>/scripts/`: optional shell scripts that a skill invokes at runtime.
- `.claude-plugin/marketplace.json`: manifest that controls skill categorization in `npx skills add`. Always register new skills in the `skills` array.
- `docs/`: 스킬 빌딩 참고 자료 및 플랜 아카이브.
- `.claude/settings.local.json`: local agent/editor settings; do not rely on it for shared behavior.

현재 `git-commit`, `self-feedback-loop`, `session-history`, `skill-guide`, `tmux`, `trace-change-why`, `video-subtitle-dl` 7개 스킬이 등록되어 있다. Prefer shallow layouts unless reference files or scripts are necessary.

## Build, Test, and Development Commands

There is no build pipeline or automated test suite in this repo. Use lightweight inspection commands from the repository root:

```bash
find skills -maxdepth 2 -name SKILL.md | sort
rg -n '^name:|^description:' skills/*/SKILL.md
sed -n '1,120p' skills/<skill-name>/SKILL.md
git status --short
```

- `find ...`: list all skill entry points.
- `rg ...`: verify required frontmatter fields.
- `sed ...`: inspect a skill quickly without opening an editor.
- `git status --short`: confirm only intended files changed.

If the `skills` CLI is available locally, use `npx skills add ./` as a smoke test.

## Coding Style & Naming Conventions

Write concise Markdown with short, imperative instructions. Use ATX headings (`#`, `##`) and keep examples minimal.

- Prefer ASCII unless the file already uses Korean or another language.
- Use lowercase kebab-case for skill directories and names, for example `trace-change-why`.
- Keep frontmatter minimal: `name`, `description`, and only necessary metadata.
- Add fenced code blocks only when they clarify usage or commands.

## Testing Guidelines

Validation is manual:

- confirm frontmatter parses and required fields are present,
- verify file paths and commands against the real repository,
- re-read the skill end-to-end for trigger clarity and contradictions,
- run `npx skills add ./` when possible.

## Commit & Pull Request Guidelines

Use short imperative commit subjects in Korean, for example `video-subtitle-dl 스킬 추가 및 관련 문서 정리`.

Pull requests should stay narrow and include a short summary, affected paths, manual validation performed, and sample trigger phrases when behavior changes.
