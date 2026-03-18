# Repository Guidelines

## Project Structure & Module Organization

This repository is a small skill collection, not an application. Keep changes scoped to the relevant skill or document.

- `skills/<skill-name>/SKILL.md`: one directory per skill; this is the primary source file.
- `skills/<skill-name>/references/`: optional supporting material when a skill needs reference docs.
- `docs/`: maintainer notes or research, if added later.
- `.claude/settings.local.json`: local agent/editor settings; do not rely on it for shared behavior.

Current examples include `skills/session-history/SKILL.md` and `skills/trace-change-why/SKILL.md`. Prefer shallow layouts unless reference files are necessary.

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

This repository currently has no commit history, so there is no convention to mirror. Use short imperative commit subjects, for example `Add session history skill`.

Pull requests should stay narrow and include a short summary, affected paths, manual validation performed, and sample trigger phrases when behavior changes.
