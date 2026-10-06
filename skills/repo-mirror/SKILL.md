---
name: repo-mirror
description: >
  macOS 개발 머신의 repo 트리(~/Repository 같은 여러 repo 묶음)를 외장 볼륨, 다른 Mac, Linux·WSL 머신으로
  rsync 병렬 복사·백업·미러링하는 스킬. .git은 보존하고 재생성 가능한 산출물은 제외하며,
  대상 파일시스템에 따라 한글 파일명 NFD→NFC 변환과 rsync 바이너리(openrsync vs rsync 3.x)를 고른다.
  "repo 백업", "레포 통째로 옮겨", "Repository 외장하드로 백업", "WSL로 레포 복사", "리눅스로 레포 미러링",
  "새 맥으로 레포 옮기기", "rsync로 동기화", "한글 파일명 깨져", "git status가 deleted untracked로 가득",
  "backup my repos", "mirror repositories to linux", "rsync repos to wsl", "copy workspace to new machine" 등에서 트리거.
---

# repo-mirror

여러 repo가 든 작업 트리를 다른 저장소로 옮긴다. git clone + 델타 대신 rsync를 쓰는 이유는 커밋 안 된 작업, stash, 로컬 branch, untracked 설정 파일까지 그대로 가져가기 때문이다.

## 번들

| 파일 | 역할 |
|------|------|
| `scripts/mirror.sh` | 최상위 항목별 병렬 rsync. `mirror.sh [options] SRC DEST`, 옵션은 `--help` |
| `references/excludes-base.txt` | 재생성 가능한 산출물 기본 제외 목록 |

`~/.agents/skills/repo-mirror/` 또는 `${CLAUDE_PLUGIN_ROOT}/skills/repo-mirror/`로 resolve한다. 스크립트는 `bash`로 실행한다 — `--split` 목록의 단어 분할이 zsh에서는 다르게 동작한다.

## 절차

1. **대상 분류** — 파일시스템이 무엇인지로 옵션이 갈린다.

   | 대상 | 옵션 | rsync |
   |------|------|-------|
   | macOS 볼륨, 다른 Mac | 기본 | `/usr/bin/rsync`(openrsync) |
   | Linux, WSL2 ext4 | `--to-linux` | rsync 3.x 필수 |

   `--to-linux`는 `--iconv=utf-8-mac,utf-8`, `-H`, `--no-owner --no-group`을 켠다. WSL에서 `/mnt/c` 아래로 보내면 NTFS라서 권한·대소문자 문제가 따로 생기므로 ext4 쪽 경로를 쓴다.
2. **제외 목록 확정** — `excludes-base.txt`를 복사해서 수정한 뒤 `--exclude-from`으로 넘긴다. 아래는 사용자에게 물어서 정한다. 기본값이 없다.
   - DB 런타임 데이터 디렉토리(`mysql-data/`, `psql*-data/` 등). 새 머신에서 DB를 클린 기동할지에 달렸다
   - DB 덤프(`*.dump`, `*.sql.gz`, `*.sqlite*`). 마이그레이션·스키마 `.sql`은 코드이므로 남긴다
   - 옮기지 않을 개인 디렉토리. 루트 기준 앵커 패턴(`/personal/`)으로 쓴다
3. **여유 공간 확인** — 대상의 여유 공간과, 제외를 적용한 원본 크기를 비교한다. `--dry-run --stats`를 한 항목에 돌려 보면 추정할 수 있다. 원본 머신에 여유가 없으면 중간 아카이브(tar) 방식은 쓸 수 없다.
4. **dry run** — `--dry-run`으로 한 번 돌리고 로그에서 의외로 빠지는 경로가 있는지 본다.
5. **실행** — 첫 실행에는 `--delete`를 붙이지 않는다. 큰 최상위 디렉토리가 하나에 몰려 있으면 `--split "<dir> ..."`로 자식 단위로 쪼갠다. 실행이 중간에 끊겨도 `--partial` 덕에 재실행하면 이어서 받는다.
6. **자격증명은 별도 패스** — 기본 제외에 걸리지 않더라도 `~/.aws`, `~/.ssh`, `.env*`, 키스토어·서명 키는 사용자 확인 후 `--ignore-existing`으로 따로 보낸다. 대상에 이미 있는 자격증명을 덮지 않기 위해서다.
7. **검증** — 아래 검증 절을 따른다.

## 검증

- 스크립트 종료 코드와 `[rc=N]` 줄. 0이 아니면 그 항목 로그(`--log-dir`)를 본다. rc 24(전송 중 원본 파일 사라짐)는 경고로 취급하고 통과시킨다.
- repo 몇 개를 골라 대상에서 `git status --porcelain`이 원본과 같은지 본다. Linux에서 `deleted` + `untracked`가 쌍으로 쏟아지면 파일명 정규화(NFD) 문제다 — `--to-linux` 없이 보낸 것이다.
- 원본을 지우는 정리 작업은 대상 사본이 원본과 같거나 앞선 것을 확인한 뒤에만 한다. 확인 없이 지우면 복구할 곳이 없다.

## Gotchas

- **macOS `/usr/bin/rsync`는 openrsync다(protocol 29).** `--iconv`, `--info=progress2`, `--mkpath`가 없다. GNU 문서의 플래그를 그대로 쓰면 usage error가 난다.
- **Homebrew rsync를 linked 상태로 두면 Xcode Organizer의 Distribute가 깨진다.** openrsync는 로컬 복사에서도 PATH의 `rsync`를 server로 띄우는데, Xcode가 넘기는 `-E`가 GNU rsync에서는 다른 뜻이라 IPA 생성 단계에서 `Copy failed`로 끝난다. rsync 3.x는 `brew unlink rsync` 후 `/opt/homebrew/opt/rsync/bin/rsync` 절대경로로만 부른다. 스크립트도 그렇게 찾는다.
- **Mac에서 만든 한글 파일명은 NFD로 저장된 경우가 많다.** APFS는 정규화를 가리지 않고 찾아 주지만 Linux ext4는 바이트 그대로 비교한다. NFD로 넘어간 파일은 Linux git이 index의 NFC 경로와 다른 파일로 본다. `--iconv=utf-8-mac,utf-8`이 전송 중에 NFC로 바꾼다. 이미 NFD로 넘어간 사본은 다시 보내도 새 이름이 추가될 뿐이므로 해당 디렉토리를 지우고 다시 받는다.
- **제외 패턴은 앵커가 없으면 모든 깊이에 걸린다.** `build/`, `Library/`, `target/`, `Logs/`는 Unity·Gradle 산출물용이지만, 같은 이름의 소스 디렉토리도 빠진다. dry run 로그에서 확인한다.
- **`.git`은 제외하지 않는다.** 히스토리와 stash가 이 방식의 핵심 가치다. `.git` 안의 `objects/pack`은 크지만 증분 재실행에서는 거의 다시 보내지 않는다.
- **WSL 홈의 일부 디렉토리는 Windows로 가는 symlink일 수 있다.** 예를 들어 `~/.aws`가 `/mnt/c/Users/<user>/.aws`를 가리키면, 거기로 보낸 자격증명은 Windows 프로필에 저장된다. 자격증명 패스 전에 `ls -la`로 확인한다.
- **대상 머신의 도구 차이는 rsync 범위 밖이다.** 복사가 끝나도 대상의 git 버전, 패키지 매니저 버전, 셸 PATH 차이로 빌드가 깨질 수 있다. 복사 검증과 빌드 검증은 따로 보고한다.
