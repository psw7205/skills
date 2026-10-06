# OCI 전용 절차

Oracle Cloud Infrastructure 인스턴스에 SKILL.md 절차를 적용할 때 공급자 쪽 세부 사항.

## 2중 방화벽

OCI는 VCN 레벨(Security List, NSG)과 OS 레벨(ufw·firewalld·iptables)이 따로 막는다. 포트를 닫거나 열 때 둘 다 바꾼다.

- **Security List**: 콘솔 > Networking > VCN > Subnet > Security List에서 TCP 22 ingress 삭제. VNIC에 NSG가 붙어 있으면 NSG 규칙도 본다 — 빠뜨리면 방화벽의 절반을 놓친다.
- **OS**: Ubuntu 이미지는 ufw, Oracle Linux 이미지는 firewalld(`firewall-cmd --remove-service=ssh --permanent && firewall-cmd --reload`). OCI Ubuntu 이미지는 `iptables-persistent`와 REJECT 규칙이 든 `/etc/iptables/rules.v4`를 깔고 나온다. 로더를 남겨 두면 부팅 때 그 규칙이 ufw 규칙과 함께 적용되므로, ufw로 옮길 때 `apt remove iptables-persistent netfilter-persistent`로 로더를 걷고 `iptables -S`로 남은 규칙을 확인한다.
- CDN 대역 제한을 ufw에 두면 Security List는 80/443을 `0.0.0.0/0`으로 두게 되고 두 레이어의 선언이 어긋난다. 의도된 상태이며, `check-oci.sh`도 이를 정상으로 본다.

기본 계정은 Ubuntu 이미지 `ubuntu`, Oracle Linux 이미지 `opc`다.

## 시리얼 콘솔 (Console Connection)

콘솔 > Compute > Instance > Console Connection에서 연결을 만든다. Cloud Shell에서 붙을 때는 `ssh-rsa` 서명 허용이 필요하다. OpenSSH 8.8+는 기본 거부하므로 옵션 없이 붙으면 `Permission denied (publickey)`가 난다.

```bash
ssh -i ~/.ssh/id_rsa -o IdentitiesOnly=yes -o PubkeyAcceptedKeyTypes=+ssh-rsa \
  -o ProxyCommand='ssh -i ~/.ssh/id_rsa -o IdentitiesOnly=yes \
    -o PubkeyAcceptedKeyTypes=+ssh-rsa -W %h:%p -p 443 \
    <console-connection-ocid>@instance-console.<region>.oci.oraclecloud.com' \
  <instance-ocid>
```

- 세션 종료는 `~~.` (중첩 SSH라 틸드 두 개).
- console connection을 재생성하면 호스트 키가 바뀐다. `ssh-keygen -R <instance-ocid>` 후 접속한다.
- 쓴 뒤에는 connection을 삭제한다. `check-oci.sh`가 살아 있는 연결을 FAIL로 센다.
- Cloud Shell 홈은 세션이 끝나도 유지된다. 콘솔용으로 만든 키가 홈에 남는지 `check-oci.sh`가 보고한다.

### 계정 패스워드가 없을 때: GRUB single-user

1. 콘솔 세션을 **열어 둔 채** 다른 탭에서 `oci compute instance action --instance-id <ocid> --action SOFTRESET`.
2. 부팅 중 ESC로 GRUB 진입 → `e` → `linux` 줄 끝에 ` init=/bin/bash` → `Ctrl-X`.
3. root 셸에서 `mount -o remount,rw /` → `passwd <user>` → 정상 재부팅.

`init=/bin/bash`는 systemd를 건너뛰므로 그 상태에서 `tailscale up`은 동작하지 않는다. 패스워드만 설정하고 재부팅한다. SOFTRESET은 ephemeral public IP를 유지한다(IP는 stop·terminate 때 풀린다).

## Run Command

Always Free 인스턴스에는 `Compute Instance Run Command` 플러그인이 설치되지 않는 경우가 있다. 인스턴스 설정의 `desired-state: ENABLED`는 희망 상태일 뿐이므로 실제 목록으로 확인한다.

```bash
oci instance-agent plugin list \
  --compartment-id <compartment-ocid> --instanceagent-id <instance-ocid> --all \
  | jq -r '.data[] | "\(.status)\t\(.name)"'
```

목록에 없으면 명령을 보내도 `ACCEPTED`로 큐에 머물 뿐 실행되지 않는다. 나중에 플러그인이 설치되면 지연 실행될 수 있으므로, `check-oci.sh`가 큐에 머문 명령을 FAIL로 센다.

## Cloud Shell 위치 판별

Cloud Shell을 양성 판별하는 확인된 표식이 없다. `OCI_CLI_CLOUD_SHELL`은 oci CLI의 user-agent 분류용이라 설정이 보장되지 않는다. `check-oci.sh`는 로컬 Mac(`uname`)과 OCI 인스턴스 안(metadata `169.254.169.254`가 displayName을 돌려줌)을 배제하는 방식으로 막는다.
