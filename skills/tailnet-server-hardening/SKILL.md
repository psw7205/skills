---
name: tailnet-server-hardening
description: >
  클라우드 VM의 관리 경로를 Tailscale로 옮기고 공개 SSH를 닫는 하드닝 절차와,
  바깥·서버 안·공급자 control plane 세 관측 지점에서 read-only로 상태를 점검하는 스크립트를 제공하는 스킬.
  노드 키 만료 끄기, sshd 실효값 확인, 2중 방화벽, 웹 포트를 CDN(Cloudflare) 대역으로 제한, 비상 접근 경로 확보를 다룬다.
  OCI 전용 절차(Security List, 시리얼 콘솔, Run Command)는 참고 문서로 포함한다.
  "서버 SSH 포트 닫기", "tailscale로만 서버 접속", "22번 막아줘", "tailscale ssh 전환", "서버 하드닝",
  "노드 키 만료", "서버 헬스체크", "origin 직접 접근 막기", "cloudflare IP만 허용", "OCI 서버 접속 안 돼",
  "시리얼 콘솔 접속", "close public ssh", "tailscale only ssh", "harden vps", "server healthcheck",
  "restrict origin to cloudflare", "node key expired" 등에서 트리거.
---

# tailnet-server-hardening

인터넷에 노출된 VM의 관리 경로(SSH)를 tailnet 안으로 들이고, 공개 포트는 서비스 포트만 CDN 대역에 남긴다. 절차 자체보다 **순서**와 **검증 방식**이 핵심이다. 순서를 틀리면 서버에 다시 들어갈 길이 없어지고, 선언만 확인하면 실제로 막혔는지 모른다.

## 목표 상태

| 경로 | 이전 | 이후 |
|------|------|------|
| 관리 SSH | 인터넷 → 22 | tailnet → 22 (공개 22 닫힘) |
| 웹 80/443 | 인터넷 전체 | CDN 대역만 (origin 직접 접근 차단) |

## 절차

순서대로 진행한다. 각 단계의 검증이 통과하기 전에는 다음 단계로 가지 않는다.

1. **Tailscale 설치와 로그인** — 서버에서 `tailscale up --ssh`. Tailscale SSH를 쓰면 키 배포 없이 tailnet ACL로 접근을 통제한다.
2. **tailnet 경로 확인** — 다른 노드에서 `tailscale ping <host>`와 `ssh <user>@<tailnet ip 또는 이름>`이 실제로 되는지 본다. **이 확인 전에 공개 22를 닫으면 들어갈 길이 없어진다.**
3. **노드 키 만료 끄기** — admin 콘솔 > Machines > 해당 머신 > Disable key expiry. 다른 노드에서 `tailscale status --json | jq '.Peer[] | select(.HostName=="<host>") | .KeyExpiry'`가 `null`이면 된 것이다.
4. **sshd 하드닝** — `/etc/ssh/sshd_config.d/`에 `PermitRootLogin no`, `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `PubkeyAuthentication yes`를 둔다. 확인은 파일이 아니라 `sudo sshd -T`의 실효값으로 한다.
5. **공개 22 닫기** — 공급자 방화벽과 OS 방화벽 **둘 다**. OS 쪽 ufw 기준: `default deny incoming`, `allow in on tailscale0`, 서비스 포트만 허용.
6. **웹 포트를 CDN 대역으로 제한** — ufw에서 `allow 80/tcp`·`allow 443/tcp`를 지우고 CDN 공개 대역마다 `allow proto tcp from <cidr> to any port 80,443 comment 'cdn-origin'`을 넣는다. Cloudflare는 `https://www.cloudflare.com/ips-v4`, `ips-v6`. 주석을 달아 두어야 나중에 갱신 대상을 골라낼 수 있다.
7. **비상 경로 확보** — 아래 "비상 접근 경로"의 전제를 실제로 한 번 성공시켜 본다. 적어 두기만 한 경로는 확보된 것이 아니다.

공급자별 방화벽 조작과 콘솔 접근은 공급자 문서를 따른다. OCI는 `references/oci.md`.

## 점검 스크립트

관측 지점이 다르면 볼 수 있는 것이 다르므로 셋으로 나뉜다. 하나로 합치려면 한쪽에 다른 쪽의 자격증명을 심어야 하는데, 그건 얻는 것보다 잃는 것이 크다. 셋 다 조회만 하고, FAIL이 하나라도 있으면 exit 1, 실행 위치가 틀리면 exit 2.

| 스크립트 | 실행 위치 | 보는 것 |
|----------|-----------|---------|
| `scripts/check-external.sh` | tailnet의 다른 머신 | 노드 online·키 만료, 인터넷에서 본 실제 포트, CDN 경유 vs origin 직접, ssh config가 tailnet 주소를 가리키는지 |
| `scripts/check-server.sh` | 서버 안 | tailscaled, ufw 기본 정책·허용 포트·웹 포트 소스와 CDN 대역 drift, `sshd -T` 실효값, 콘솔 로그인 전제(계정 패스워드), 디스크·재부팅 |
| `scripts/check-oci.sh` | OCI Cloud Shell | 인스턴스 상태, Security List·NSG ingress, 남은 console connection, 큐에 머문 Run Command, agent 플러그인, Cloud Shell 홈 위생 |

```
TS_HOST=<host> SSH_HOST=<alias> SITE_DOMAIN=<domain> bash check-external.sh
ssh <alias> 'TS_HOST=<host> bash -s' < check-server.sh
SITE_DOMAIN=<domain> bash check-oci.sh <instance-display-name>
```

기대값은 환경변수로 바꾼다: `CLOSED_PORTS`·`CDN_ONLY_PORTS`·`OPEN_PORTS`(external), `UFW_ALLOWED_PORTS`·`WEB_PORTS`·`CDN_IP_URLS`·`SSH_USER`(server), `EXPECTED_TCP_PORTS`(oci). 서비스 포트를 새로 열었으면 기대값도 같이 바꿔야 FAIL이 사라진다.

## 비상 접근 경로

tailnet 경로가 끊겼을 때 위에서부터 시도한다.

1. **노드 키 만료** — `tailscale ping`이 `peer's node key has expired`면 서버는 정상이다. admin 콘솔에서 Temporarily extend key → 재연결되면 즉시 Disable key expiry. 서버에 들어갈 필요가 없다.
2. **공급자 시리얼 콘솔** — login 프롬프트로 떨어지므로 **OS 계정 패스워드가 미리 설정돼 있어야 한다.** 클라우드 이미지는 기본적으로 패스워드가 없어 "연결은 되는데 로그인은 못 하는" 상태가 된다. 패스워드는 그 서버에 의존하지 않는 곳에 보관한다. 서버에서 돌리는 패스워드 관리자에만 두면 순환이 된다.
3. **공급자 원격 명령 실행 기능** — 있으면 쓰지만, 실제 가용 여부를 사전에 확인해 둔다(OCI는 `references/oci.md`).

쓸 수 없는 경로: **공급자 방화벽에만 22를 다시 여는 것.** OS 방화벽이 따로 막고 있고, OS 방화벽을 바꾸려면 서버에 들어가야 하므로 순환이다.

## Gotchas

- **Tailscale 노드 키는 기본 180일 뒤 만료된다.** 만료되면 tailnet에서 분리돼 SSH 경로만 예고 없이 끊긴다. 웹(80/443)은 멀쩡해서 서비스 모니터링에도 안 잡힌다. 서버 노드는 구축 직후 끈다.
- **`PasswordAuthentication no`만으로는 패스워드 로그인이 안 막힐 수 있다.** `UsePAM yes`인 배포판에서는 keyboard-interactive 경로로 PAM을 타고 통과한다. `KbdInteractiveAuthentication no`를 명시하고, 배포판 기본값에 맡기지 않는다.
- **설정 파일이 아니라 실효값을 본다.** `sshd -T`는 모든 설정 소스를 병합한 최종값을 낸다. `sshd_config.d/`의 파일 순서나 `Match` 블록 때문에 파일 내용과 실효값이 다를 수 있다.
- **공급자 방화벽 규칙은 선언이고 `nc`는 실측이다.** 공급자 쪽에 포트를 열어도 OS 방화벽이 막으면 안 통하고, 그 반대도 있다. "열려 있다고 적혀 있는데 실제로는 막힌" 상태는 바깥에서 찔러 봐야만 구분된다.
- **CDN 대역 제한은 OS 방화벽이 유일한 강제 지점이 되기 쉽다.** 공급자 방화벽은 80/443을 `0.0.0.0/0`으로 두는 경우가 많아서, OS 방화벽 규칙이 풀리면 origin이 즉시 노출된다. 그래서 check-server는 포트뿐 아니라 **소스**까지 본다.
- **CDN이 대역을 추가하면 그만큼이 조용히 차단된다.** check-server의 drift 경고가 뜨면 6단계 루프를 다시 돌린다.
- **origin 직접 접근 검사는 통과/실패가 뒤집혀 있다.** 응답이 오면 FAIL이다. 반대로 사이트가 죽은 것과 다 막힌 것을 구분하려고 CDN 경유 응답을 같이 본다.
- **점검을 엉뚱한 위치에서 돌리면 거짓 통과한다.** 서버 자신에서 외부 점검을 돌리면 loopback을 재고, 다른 호스트에서 서버 점검을 돌리면 그 호스트의 방화벽을 본다. 스크립트는 tailnet hostname(`Self.HostName`)으로 위치를 가드한다.
- **CDN 경유 응답은 콜드 스타트에서 수 초 걸린다.** 타임아웃에 걸린 한 번의 000은 재실행으로 확인한 뒤 판단한다.
- **jq·python 파싱에서 빈 필드를 TSV로 주고받지 않는다.** TAB은 IFS whitespace라 연속 구분자가 합쳐져, `KeyExpiry=null` 같은 빈 값 뒤 필드가 통째로 밀린다. 스크립트는 key=value로 받는다.
