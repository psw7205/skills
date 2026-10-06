---
name: mac-disk-reclaim
description: >
  macOS 개발 머신(Xcode, Android, Docker·Colima, 여러 repo)의 디스크 공간을 회수하는 스킬.
  먼저 read-only로 실측하고, 항목을 "다시 만드는 비용"으로 등급을 나눈 뒤,
  되살릴 수 없는 데이터는 사본을 검증하고 나서만 지운다.
  "디스크 용량 확보", "맥 용량 줄이기", "저장공간 부족", "시스템 데이터 너무 커", "용량 정리해줘",
  "Xcode 용량", "시뮬레이터 지워도 돼?", "Docker 용량 줄이기", "node_modules 정리", "DerivedData 삭제",
  "free up disk space on mac", "reclaim disk space", "mac storage full", "clean developer caches" 등에서 트리거.
---

# mac-disk-reclaim

**측정 → 등급 → 확인 → 삭제** 순서로 진행한다. 삭제는 마지막 단계에서만 한다. 개발 머신의 공간은 대부분 캐시와 산출물이 차지하는데, 그 사이에 되살릴 수 없는 것(아카이브, 커밋 안 한 작업, DB 볼륨)이 섞여 있다. 크기순으로 지우면 그걸 같이 지우게 된다.

## 1. 측정 (read-only)

`bash scripts/survey.sh [repo-root ...]`로 알려진 공간 소비처를 잰다. 아무것도 지우지 않는다. 스크립트에 없는 곳은 `du -hd1 <dir> | sort -rh`로 내려가며 찾는다.

보고할 때는 실제로 잰 값만 쓴다. 아래 두 곳은 `du` 결과가 실제 사용량과 다르다.

- `/Library/Developer/CoreSimulator/Volumes`는 런타임 이미지를 마운트한 경로라 `du`가 부풀려 센다. 실제 크기는 `xcrun simctl runtime list`의 합계다.
- Colima·Lima·OrbStack의 VM 디스크는 sparse 파일이다. `ls -l`의 apparent 크기가 아니라 `du`가 실제 사용량이다.

## 2. 등급

"다시 만드는 비용"으로 나눈다. 크기가 기준이 아니다.

| 등급 | 성격 | 예 | 처리 |
|------|------|----|------|
| A | 자동 재생성, 비용 작음 | DerivedData, 시뮬레이터 dyld cache, Gradle·Homebrew·uv·yarn·pnpm·CocoaPods 캐시, 옛 IDE 버전 캐시, Docker build cache·미사용 이미지 | 합의하면 일괄 삭제 |
| B | 재생성 가능하지만 느리거나 사용 여부에 달림 | 시뮬레이터 런타임, AVD, Android system-image·NDK, iOS DeviceSupport, 중복 Xcode.app, 툴체인 옛 버전, repo의 `node_modules`·`Pods`·빌드 산출물 | 항목별로 쓰는지 묻는다 |
| C | 되살릴 수 없음 | Xcode Archives(dSYM), repo 원본, 커밋 안 한 변경·stash, DB 볼륨, 데이터가 든 Docker 볼륨 | 사본 검증 후에만 삭제 |

사용자에게는 등급별 표와 예상 회수량을 먼저 보여주고, 무엇을 지울지 합의한 뒤 진행한다.

## 3. 삭제 전 확인

- **repo 안의 산출물 디렉토리**: 지우기 전에 `git -C <repo> ls-files <dir>`이 비어 있는지 본다. 이름이 `build`여도 추적 파일이 든 경우가 있다.
- **Docker**: 컨테이너(멈춘 것 포함)가 쓰는 이미지는 `image prune -a`가 지우지 않는다. 볼륨은 `docker volume ls`와 `docker system df -v`로 무엇이 들었는지 본 뒤 개별로 지운다. `volume prune`은 어떤 컨테이너도 참조하지 않는 볼륨을 지우는데, `compose down`으로 컨테이너를 내려 둔 DB 볼륨이 정확히 여기에 걸린다. Docker 23+는 기본이 anonymous 볼륨만이고 `-a`를 붙이면 named 볼륨까지 지운다.
- **AVD·시뮬레이터**: 지금 쓰는 기기는 AVD `config.ini`의 `image.sysdir`, 프로젝트의 `ndkVersion`, Xcode 버전과 대조한다. NDK는 `grep -r ndkVersion`으로 참조가 없는 버전만 지운다.
- **C 등급**: 사본 위치에 복사하고 **내용으로** 비교한다. 파일이 있다는 것만으로는 부족하다.
  - 일반 파일: `rsync -a --checksum --dry-run --itemize-changes <원본>/ <사본>/`의 출력이 비어야 한다.
  - git repo: 체크섬에 더해 양쪽의 branch tip이 같거나 사본이 앞서 있는지(`merge-base --is-ancestor`), 커밋 안 한 변경과 stash가 양쪽에 같은지 본다.
  - 사본이 원본보다 뒤처져 있으면 지우지 않는다.

## 4. 삭제

| 대상 | 방법 |
|------|------|
| 시뮬레이터 런타임 | `xcrun simctl runtime delete <id>` 후 `simctl runtime list`로 사라졌는지 확인. 남아 있으면 `xcrun simctl shutdown all` 후 재시도 |
| 시뮬레이터 기기 | `xcrun simctl delete unavailable`, 데이터만 비우려면 `xcrun simctl erase all` |
| AVD 데이터만 초기화 | `<avd>.avd/userdata-qemu.img.qcow2`(변경분 overlay)를 지우면 AVD 설정은 남고 데이터만 초기화된다 |
| Docker·Colima | `docker builder prune -af`, `docker image prune -af` 후 `colima ssh -- sudo fstrim -av` |
| 툴체인 옛 버전 | `mise prune` |
| Homebrew | `brew cleanup --prune=all` |
| repo `.git`이 비대할 때 | `git gc` 후 `git fsck --connectivity-only`로 무결성 확인 |

삭제 전후로 `df -h /System/Volumes/Data`를 찍어 실제 회수량을 보고한다. 추정치를 결과로 보고하지 않는다.

## Gotchas

- **VM 안에서 지워도 macOS 공간은 바로 늘지 않는다.** Colima 등의 VM 디스크는 한 번 커진 블록을 돌려주지 않는다. 컨테이너 쪽 prune 뒤에 VM 안에서 `fstrim`을 해야 빈 블록이 호스트로 반환된다.
- **읽기 전용 권한이 걸린 트리는 `rm -rf`로 안 지워진다.** 쓰기 권한이 없는 디렉토리 안의 항목은 삭제할 수 없어 `Permission denied`가 쏟아진다(서명된 `.app` 번들 캐시, 권한이 박힌 에셋 등). `chmod -R u+w <dir>` 후 지우고, 지운 뒤 경로가 정말 사라졌는지 확인한다.
- **`du` 합계를 실사용량으로 보고하지 않는다.** 마운트 경로와 sparse 파일 때문에 합계가 볼륨 크기를 넘기도 한다. 결과는 `df`의 전후 차이로 보고한다.
- **"옛 버전"은 날짜가 아니라 참조로 판단한다.** JetBrains 캐시 디렉토리는 버전별로 쌓이므로 현재 설치된 IDE 버전(`Info.plist`의 `CFBundleShortVersionString`)과 다른 것만 지운다.
- **Xcode Archives에는 크래시 심볼화에 필요한 dSYM이 들어 있다.** 배포한 빌드의 크래시를 분석할 일이 있으면 C 등급으로 다루고, 사본을 만든 뒤에만 지운다.
- **재생성 비용을 사용자에게 알린다.** `node_modules`·`Pods`·CocoaPods spec repo를 지우면 각 프로젝트의 첫 빌드에서 의존성 설치가 다시 돈다. 병행 작업 중인 repo가 있으면 그 시간을 감안해 범위를 정한다.
