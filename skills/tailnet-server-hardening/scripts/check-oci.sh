#!/usr/bin/env bash
# OCI control plane read-only 점검 (OCI Cloud Shell 에서 실행): 인스턴스 상태, Security List·NSG
# ingress, origin 노출, 남은 console connection, 큐에 머문 Run Command, agent 플러그인, Cloud Shell
# 홈 위생. 조회 명령(search/get/list)만 쓴다. FAIL 이 하나라도 있으면 exit 1.
#
#   [SITE_DOMAIN=<domain>] bash check-oci.sh <instance-display-name>
set -uo pipefail

# control plane 조회는 인증만 되면 어디서든 같은 답을 주지만, origin 직접 검사와
# 홈 위생 검사는 실행 호스트 기준이라 다른 곳에서 돌리면 그 호스트의 실제 SSH 키를
# "남은 임시 키"로 보고하는 등 거짓이 된다. Cloud Shell 을 양성 판별하는 확인된
# 표식이 없어서(OCI_CLI_CLOUD_SHELL 은 user-agent 분류용이라 설정 보장이 없다)
# 로컬 Mac 과 OCI 인스턴스 안을 배제하는 방식으로 막는다.
_here=""
[ "$(uname -s)" = "Darwin" ] && _here="로컬 Mac"
if [ -z "$_here" ]; then
  _self=$(curl -s -m 3 -H "Authorization: Bearer Oracle" \
            http://169.254.169.254/opc/v2/instance/displayName 2>/dev/null)
  [ -n "$_self" ] && _here="OCI 인스턴스 \"$_self\" 안"
  unset _self
fi
if [ -n "$_here" ]; then
  {
    printf '이 스크립트는 OCI Cloud Shell 에서 실행해야 한다. 현재 위치: %s\n' "$_here"
    printf '  바깥에서 본 실측 -> check-external.sh / 서버 안 -> check-server.sh\n'
  } >&2
  exit 2
fi
unset _here

INSTANCE_NAME="${1:?usage: check-oci.sh <instance-display-name>}"

# 공개되어 있어야 하는 TCP 포트. 이 집합과 다르면 FAIL.
EXPECTED_TCP_PORTS="${EXPECTED_TCP_PORTS:-80-80 443-443}"

# origin 응답 확인용 도메인. 비우면 건너뛴다.
SITE_DOMAIN="${SITE_DOMAIN:-}"

pass=0
fail=0

if [ -t 1 ]; then G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; N=$'\033[0m'
else G=''; R=''; Y=''; N=''; fi

ok()   { printf '  %sPASS%s  %s\n' "$G" "$N" "$1"; pass=$((pass + 1)); }
no()   { printf '  %sFAIL%s  %s\n' "$R" "$N" "$1"; fail=$((fail + 1)); }
warn() { printf '  %sWARN%s  %s\n' "$Y" "$N" "$1"; }
info() { printf '        %s\n' "$1"; }
sec()  { printf '\n== %s\n' "$1"; }

# 값이 비면 이후 점검이 전부 공허한 PASS 가 되므로 즉시 중단한다.
require() {
  [ -n "$1" ] && return 0
  no "$2"
  printf '\n  %s조회에 실패했다. 이후 점검은 의미가 없으므로 중단한다.%s\n' "$R" "$N"
  printf '  PASS %d / FAIL %d\n' "$pass" "$fail"
  exit 1
}

for c in oci jq curl; do
  command -v "$c" >/dev/null 2>&1 || { echo "필요한 명령이 없다: $c" >&2; exit 1; }
done

# ingress 규칙 한 건을 "proto<TAB>source<TAB>detail" 로 정규화한다.
# security list 와 NSG 가 같은 스키마를 쓰므로 필터를 공유한다.
RULE_JQ='
  (if   .protocol == "6"   then "TCP"
   elif .protocol == "17"  then "UDP"
   elif .protocol == "1"   then "ICMP"
   elif .protocol == "all" then "ALL"
   else "proto-" + .protocol end) as $p
| (.["tcp-options"]["destination-port-range"]
   // .["udp-options"]["destination-port-range"]) as $r
| (.["icmp-options"]) as $i
| [ $p,
    (.source // "-"),
    (if $r then "\($r.min)-\($r.max)"
     elif $i then "type/code=\($i.type)/\($i.code // "-")"
     else "ALL" end)
  ] | @tsv'

# ---------------------------------------------------------------- 인스턴스
sec "1. 인스턴스"

INST=$(oci search resource structured-search \
  --query-text "query instance resources where displayName = '$INSTANCE_NAME' && lifecycleState != 'TERMINATED'" \
  2>/dev/null | jq -r '.data.items[0].identifier // empty')
require "$INST" "인스턴스를 찾지 못했다: $INSTANCE_NAME"

INST_JSON=$(oci compute instance get --instance-id "$INST" 2>/dev/null)
require "$INST_JSON" "instance get 실패 (권한 또는 네트워크)"

STATE=$(jq -r '.data["lifecycle-state"] // "UNKNOWN"' <<<"$INST_JSON")
COMP=$(jq -r '.data["compartment-id"] // empty'      <<<"$INST_JSON")
SHAPE=$(jq -r '.data.shape // "?"'                   <<<"$INST_JSON")
require "$COMP" "compartment-id 를 얻지 못했다"

info "name  : $INSTANCE_NAME"
info "ocid  : ...${INST: -16}"
info "shape : $SHAPE"
[ "$STATE" = "RUNNING" ] && ok "lifecycle-state = RUNNING" || no "lifecycle-state = $STATE"

VNIC_JSON=$(oci compute instance list-vnics --instance-id "$INST" --all 2>/dev/null)
require "$VNIC_JSON" "list-vnics 실패"

VNIC_COUNT=$(jq -r '.data | length' <<<"$VNIC_JSON")
[ "$VNIC_COUNT" -gt 1 ] && warn "VNIC 이 $VNIC_COUNT 개다. 모두 검사한다."

PUB=$(jq -r '.data[0]["public-ip"] // "none"' <<<"$VNIC_JSON")
info "public : $PUB"
info "private: $(jq -r '.data[0]["private-ip"] // "none"' <<<"$VNIC_JSON")"

# --------------------------------------------------------- 방화벽 (VCN)
sec "2. VCN 방화벽 ingress (Security List + NSG)"

tcp_ports=""
wide_open=0
udp_seen=0

# $1: RULE_JQ 로 정규화된 TSV 여러 줄, $2: 라벨
emit_rules() {
  local rules="$1" label="$2" proto src detail
  info "$label"
  [ -z "$rules" ] && { info "  (ingress 규칙 없음)"; return; }
  while IFS=$'\t' read -r proto src detail; do
    [ -z "$proto" ] && continue
    info "  $(printf '%-5s src=%-18s %s' "$proto" "$src" "$detail")"
    case "$proto" in
      ALL)  wide_open=1 ;;
      TCP)  if [ "$detail" = "ALL" ]; then wide_open=1
            else tcp_ports="$tcp_ports $detail"; fi ;;
      UDP)  udp_seen=1 ;;
    esac
  done < <(printf '%s\n' "$rules")
}

for SUBNET in $(jq -r '.data[]["subnet-id"]' <<<"$VNIC_JSON" | sort -u); do
  for SL in $(oci network subnet get --subnet-id "$SUBNET" 2>/dev/null \
              | jq -r '.data["security-list-ids"][]'); do
    RULES=$(oci network security-list get --security-list-id "$SL" 2>/dev/null \
            | jq -r ".data[\"ingress-security-rules\"][] | $RULE_JQ")
    emit_rules "$RULES" "security-list ...${SL: -12}"
  done
done

# NSG: VNIC 에 붙어 있으면 규칙까지 열거한다. 빠뜨리면 방화벽의 절반을 놓친다.
NSG_IDS=$(jq -r '.data[]["nsg-ids"][]?' <<<"$VNIC_JSON" | sort -u)
if [ -z "$NSG_IDS" ]; then
  info "nsg: none"
else
  for NSG in $NSG_IDS; do
    RULES=$(oci network nsg rules list --nsg-id "$NSG" --all 2>/dev/null \
            | jq -r ".data[] | select(.direction == \"INGRESS\") | $RULE_JQ")
    emit_rules "$RULES" "nsg ...${NSG: -12}"
  done
fi

norm() { tr ' ' '\n' <<<"$1" | sed '/^$/d' | sort -u | tr '\n' ' '; }
got=$(norm "$tcp_ports")
want=$(norm "$EXPECTED_TCP_PORTS")

if [ "$wide_open" -eq 1 ]; then
  no "전 포트를 여는 규칙이 있다 (protocol=all 또는 포트 범위 미지정)"
elif [ "$udp_seen" -eq 1 ]; then
  no "예상치 못한 UDP ingress 규칙이 있다"
elif [ "$got" = "$want" ]; then
  ok "열린 TCP 포트가 기대와 일치: $got"
  info "소스 제한은 OS 방화벽 레이어에 있다 — 여기 0.0.0.0/0 은 정상이다"
else
  no "열린 TCP 포트 불일치"
  info "기대: $want"
  info "실제: $got"
fi

# ---------------------------------------------------- 서비스 응답 (origin)
sec "3. 웹 응답과 origin 노출"

if [ "$PUB" = "none" ]; then
  warn "public IP 가 없어 건너뛴다"
else
  # Cloud Shell 도 CDN 대역이 아니다. origin 에 직접 닿으면 그게 이상 신호다 -
  # 통과/실패가 뒤집혀 있다.
  code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "http://$PUB/" 2>/dev/null)
  case "$code" in
    2*|3*) no "http://$PUB/ -> $code — CDN 밖에서 origin 에 닿는다" ;;
    *)     ok "http://$PUB/ 차단됨 (${code:-무응답}) — CDN 경유만 허용" ;;
  esac

  if [ -n "$SITE_DOMAIN" ]; then
    # 웹이 살아 있는지는 CDN 경유로 본다. origin 직접은 차단이 정상이라
    # 이 검사가 없으면 "다 막혔다" 와 "사이트가 죽었다" 를 구분하지 못한다.
    code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "https://$SITE_DOMAIN/" 2>/dev/null)
    case "$code" in
      2*|3*) ok "https://$SITE_DOMAIN/ (CDN 경유) -> $code" ;;
      *)     no "https://$SITE_DOMAIN/ (CDN 경유) -> ${code:-무응답}" ;;
    esac

    # CDN 을 우회해 origin 에 직접 SNI 를 주고 확인한다.
    code=$(curl -sk -o /dev/null -m 10 -w '%{http_code}' \
             --resolve "$SITE_DOMAIN:443:$PUB" "https://$SITE_DOMAIN/" 2>/dev/null)
    case "$code" in
      2*|3*) no "https://$SITE_DOMAIN/ (origin 직접) -> $code — CDN 우회가 가능하다" ;;
      *)     ok "origin 직접 접근 차단됨 (${code:-무응답}) — CDN 경유만 허용" ;;
    esac
  fi
fi

# ----------------------------------------------------- Console Connection
sec "4. Console Connection"

CC=$(oci compute instance-console-connection list --compartment-id "$COMP" --all 2>/dev/null \
     | jq -r --arg i "$INST" '.data[]? | select(.["instance-id"] == $i)
               | "\(.["lifecycle-state"])\t...\(.id[-12:])"')

if [ -z "$CC" ]; then
  ok "console connection 없음"
else
  live=0
  while IFS=$'\t' read -r st id; do
    info "$(printf '%-10s %s' "$st" "$id")"
    case "$st" in DELETED|DELETING) ;; *) live=$((live + 1)) ;; esac
  done <<<"$CC"
  [ "$live" -eq 0 ] && ok "살아 있는 console connection 없음" \
                    || no "살아 있는 console connection $live건 (사용 후 삭제할 것)"
fi

# ------------------------------------------------------------ Run Command
sec "5. Run Command"

# 판정 기준은 command 의 is-canceled 가 아니라 execution 의 상태다.
# 정상 완료(SUCCEEDED)한 명령은 문제가 아니고, 배달되지 못한 채 큐에 머문 것이 문제다.
EXECS=$(oci instance-agent command-execution list \
          --compartment-id "$COMP" --instance-id "$INST" --all 2>/dev/null \
        | jq -r '.data[]? | [ .["lifecycle-state"],
                              (.["delivery-state"] // "-"),
                              .["display-name"] ] | @tsv')

if [ -z "$EXECS" ]; then
  ok "실행 이력 없음"
else
  stuck=0
  while IFS=$'\t' read -r st dl nm; do
    info "$(printf '%-12s %-10s %s' "$st" "$dl" "$nm")"
    case "$st" in ACCEPTED|IN_PROGRESS) stuck=$((stuck + 1)) ;; esac
  done <<<"$EXECS"
  [ "$stuck" -eq 0 ] && ok "큐에 머문 명령 없음" \
                     || no "미배달 명령 $stuck건 (플러그인 설치 시 지연 실행될 수 있다)"
fi

# --------------------------------------------------------- Agent 플러그인
sec "6. Oracle Cloud Agent 플러그인"

PLUGINS=$(oci instance-agent plugin list \
            --compartment-id "$COMP" --instanceagent-id "$INST" --all 2>/dev/null \
          | jq -r '.data[]? | "\(.status)\t\(.name)"')

if [ -z "$PLUGINS" ]; then
  warn "플러그인 목록을 가져오지 못했다"
else
  while IFS=$'\t' read -r st nm; do info "$(printf '%-12s %s' "$st" "$nm")"; done <<<"$PLUGINS"
  if grep -q 'Compute Instance Run Command' <<<"$PLUGINS"; then
    info "Run Command 있음 - 비상 경로로 쓸 수 있다"
  else
    info "Run Command 없음 - 비상 경로로 쓸 수 없다 (references/oci.md)"
  fi
fi

# ------------------------------------------------------- Cloud Shell 홈
sec "7. Cloud Shell 홈 정리 상태"

# 홈 바로 아래와 ~/.ssh 둘 다 본다. 업로드나 오타로 홈에 떨어지는 경우가 있다.
# 여기는 위생 점검이다. 목록만 보고하고 아무것도 지우지 않는다 - 삭제는 사람이 한다.
keys=$(find "$HOME" "$HOME/.ssh" -maxdepth 1 -type f \
         \( -name 'id_rsa'      -o -name 'id_dsa'  -o -name 'id_ecdsa' \
            -o -name 'id_ed25519' -o -name '*.pem' -o -name '*.key' \) \
         2>/dev/null | sort -u)

if [ -n "$keys" ]; then
  warn "홈에 개인키 파일이 있다 - Cloud Shell 홈은 세션이 끝나도 유지된다"
  while IFS= read -r f; do
    info "$f    $(ssh-keygen -l -f "$f" </dev/null 2>/dev/null || echo '(지문 확인 불가)')"
  done <<<"$keys"
  info "위생 권고라 FAIL 로 세지 않는다. 남길지 지울지는 직접 판단한다."
else
  ok "임시 SSH 키 없음"
fi

junk=$(find "$HOME" -maxdepth 1 -name '--*' 2>/dev/null)
if [ -n "$junk" ]; then
  no "옵션 이름으로 만들어진 파일이 있다 (리다이렉트 오타 흔적)"
  while IFS= read -r f; do info "$f"; done <<<"$junk"
else
  ok "쓰레기 파일 없음"
fi

# ------------------------------------------------------------------ 요약
sec "요약"
printf '  PASS %d / FAIL %d\n' "$pass" "$fail"
printf '  범위 밖: 서버 안 방화벽·sshd(check-server.sh), tailnet·외부 실측(check-external.sh)\n'
[ "$fail" -eq 0 ] || exit 1
