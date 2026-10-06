#!/usr/bin/env bash
# 서버 바깥에서 보는 read-only 점검: tailnet 노드 상태와 키 만료, 인터넷에서 본 실제 포트,
# CDN 경유와 origin 직접 접근의 차이, 로컬 ssh config. FAIL 이 하나라도 있으면 exit 1.
#
#   TS_HOST=<tailnet hostname> SSH_HOST=<ssh alias> [SITE_DOMAIN=<domain>] bash check-external.sh
set -uo pipefail

TS_HOST="${TS_HOST:?TS_HOST 에 서버의 tailnet hostname 을 지정한다}"
SSH_HOST="${SSH_HOST:?SSH_HOST 에 tailnet 으로 서버에 붙는 ssh alias 를 지정한다}"
SITE_DOMAIN="${SITE_DOMAIN:-}"
ORIGIN_IP="${ORIGIN_IP:-}"
OPEN_PORTS="${OPEN_PORTS:-}"
CLOSED_PORTS="${CLOSED_PORTS:-22}"
CDN_ONLY_PORTS="${CDN_ONLY_PORTS:-80 443}"

pass=0
fail=0

if [ -t 1 ]; then G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; N=$'\033[0m'
else G=''; R=''; Y=''; N=''; fi

ok()   { printf '  %sPASS%s  %s\n' "$G" "$N" "$1"; pass=$((pass + 1)); }
no()   { printf '  %sFAIL%s  %s\n' "$R" "$N" "$1"; fail=$((fail + 1)); }
warn() { printf '  %sWARN%s  %s\n' "$Y" "$N" "$1"; }
info() { printf '        %s\n' "$1"; }
sec()  { printf '\n== %s\n' "$1"; }

for c in tailscale nc curl python3; do
  command -v "$c" >/dev/null 2>&1 || { echo "필요한 명령이 없다: $c" >&2; exit 1; }
done

if [ "$(uname -s)" = Darwin ]; then probe() { nc -z -G 8 "$1" "$2" >/dev/null 2>&1; }
else probe() { nc -z -w 8 "$1" "$2" >/dev/null 2>&1; }; fi

TS_JSON=$(tailscale status --json 2>/dev/null)

# 서버 자신에서 돌리면 모든 포트 검사가 loopback 을 재서 거짓 통과한다.
SELF=""
[ -n "$TS_JSON" ] && SELF=$(python3 -c 'import json,sys; print((json.load(sys.stdin).get("Self") or {}).get("HostName",""))' <<<"$TS_JSON")
if [ "$SELF" = "$TS_HOST" ]; then
  echo "$TS_HOST 자신에서 실행 중이다. 다른 머신에서 돌린다 (서버 안 점검은 check-server.sh)" >&2
  exit 2
fi

# ---------------------------------------------------------------- Tailscale
sec "1. Tailscale"

if [ -z "$TS_JSON" ]; then
  no "tailscale status 실패 (tailscaled 가 안 떠 있거나 로그인 안 됨)"
else
  BACKEND=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("BackendState",""))' <<<"$TS_JSON")
  [ "$BACKEND" = "Running" ] && ok "로컬 BackendState = Running" \
                             || no "로컬 BackendState = ${BACKEND:-unknown}"

  # 주의 1: python3 - <<EOF 와 <<<"$JSON" 을 같이 쓰면 stdin 리다이렉트가 충돌한다.
  #         스크립트는 -c 로 주고 stdin 은 JSON 전용으로 남긴다.
  # 주의 2: TAB 은 IFS whitespace 라 연속 구분자가 하나로 합쳐진다. 빈 값(KeyExpiry=null)이
  #         섞이면 필드가 통째로 밀리므로 TSV 대신 key=value 로 주고받는다.
  PEER=$(TS_HOST="$TS_HOST" python3 -c '
import json, os, sys
d = json.load(sys.stdin)
want = os.environ["TS_HOST"]
for p in (d.get("Peer") or {}).values():
    if p.get("HostName") == want:
        for k, v in [
            ("ONLINE",  p.get("Online")),
            ("EXPIRED", p.get("Expired")),
            ("KEYEXP",  p.get("KeyExpiry") or ""),
            ("CURADDR", p.get("CurAddr") or ""),
            ("RELAY",   p.get("Relay") or ""),
            ("TSIPS",   ",".join(p.get("TailscaleIPs") or [])),
        ]:
            print("%s=%s" % (k, v))
        break
' <<<"$TS_JSON")
  if [ -z "$PEER" ]; then
    no "tailnet 에서 노드를 찾지 못했다: $TS_HOST"
  else
    ONLINE=""; EXPIRED=""; KEYEXP=""; CURADDR=""; RELAY=""; TSIPS=""
    while IFS='=' read -r k v; do
      case "$k" in
        ONLINE)  ONLINE="$v"  ;;
        EXPIRED) EXPIRED="$v" ;;
        KEYEXP)  KEYEXP="$v"  ;;
        CURADDR) CURADDR="$v" ;;
        RELAY)   RELAY="$v"   ;;
        TSIPS)   TSIPS="$v"   ;;
      esac
    done <<<"$PEER"
    info "tailscale ip : $TSIPS"

    [ "$ONLINE" = "True" ] && ok "노드 Online" || no "노드 offline"

    if [ -z "$KEYEXP" ]; then
      ok "키 만료 비활성화됨 (KeyExpiry = null)"
    else
      no "키 만료가 살아 있다: $KEYEXP — 그 시점에 SSH 경로가 끊긴다"
      info "admin 콘솔 > Machines > $TS_HOST > Disable key expiry"
    fi

    [ "$EXPIRED" = "True" ] && no "노드 키가 이미 만료됨 (Temporarily extend key 로 복구)"

    if [ -n "$CURADDR" ]; then
      info "경로: direct $CURADDR"
      [ -z "$ORIGIN_IP" ] && ORIGIN_IP="${CURADDR%:*}"
    else
      warn "direct 경로 없음 (relay ${RELAY:-?} 경유 — 느리지만 동작은 한다)"
    fi
  fi
fi

# --------------------------------------------------------------- SSH 도달성
sec "2. SSH ($SSH_HOST)"

SSH_OUT=$(ssh -o ConnectTimeout=10 -o BatchMode=yes "$SSH_HOST" \
            'echo OK; hostname' 2>&1 | tr '\n' ' ')
case "$SSH_OUT" in
  OK\ *) ok "접속 성공 — $SSH_OUT" ;;
  *)     no "접속 실패 — ${SSH_OUT:-무응답}" ;;
esac

# public IP 를 아직 모르면 서버에 물어본다.
if [ -z "$ORIGIN_IP" ]; then
  ORIGIN_IP=$(ssh -o ConnectTimeout=10 -o BatchMode=yes "$SSH_HOST" \
                'curl -s -m 8 https://api.ipify.org' 2>/dev/null)
fi

# ------------------------------------------------------------- 포트 실측
sec "3. 인터넷에서 본 포트"

if [ -z "$ORIGIN_IP" ]; then
  warn "public IP 를 알아내지 못해 건너뛴다 (ORIGIN_IP 로 지정 가능)"
else
  info "origin: $ORIGIN_IP"
  for p in $OPEN_PORTS; do
    if probe "$ORIGIN_IP" "$p"; then
      ok "tcp/$p 열림 (기대대로)"
    else
      no "tcp/$p 가 막혔다 — 웹이 죽었거나 방화벽이 바뀌었다"
    fi
  done
  for p in $CLOSED_PORTS; do
    if probe "$ORIGIN_IP" "$p"; then
      no "tcp/$p 가 공개되어 있다 — SSH 는 tailnet 전용이어야 한다"
    else
      ok "tcp/$p 차단됨 (기대대로)"
    fi
  done
  # 이 머신은 CDN 대역이 아니므로, 닿는다는 건 OS 방화벽의 소스 제한이 풀려
  # origin 이 직접 노출됐다는 뜻이다.
  for p in $CDN_ONLY_PORTS; do
    if probe "$ORIGIN_IP" "$p"; then
      no "tcp/$p 가 CDN 밖에서도 열려 있다 — origin 직접 노출"
    else
      ok "tcp/$p 차단됨 — CDN 경유만 허용 (기대대로)"
    fi
  done
fi

# ------------------------------------------------------------- 웹 응답
sec "4. 웹 응답"

if [ -z "$SITE_DOMAIN" ]; then
  warn "SITE_DOMAIN 이 비어 건너뛴다"
else
  code=$(curl -s -o /dev/null -m 12 -w '%{http_code}' "https://$SITE_DOMAIN/" 2>/dev/null)
  case "$code" in
    2*|3*) ok "https://$SITE_DOMAIN/ (CDN 경유) -> $code" ;;
    *)     no "https://$SITE_DOMAIN/ (CDN 경유) -> ${code:-무응답}" ;;
  esac

  if [ -n "$ORIGIN_IP" ]; then
    # CDN 을 우회해 origin 에 직접 붙어 본다. 응답이 오는 쪽이 이상 신호다 -
    # 통과/실패가 뒤집혀 있다.
    code=$(curl -sk -o /dev/null -m 12 -w '%{http_code}' \
             --resolve "$SITE_DOMAIN:443:$ORIGIN_IP" "https://$SITE_DOMAIN/" 2>/dev/null)
    case "$code" in
      2*|3*) no "https://$SITE_DOMAIN/ (origin 직접) -> $code — CDN 우회가 가능하다" ;;
      *)     ok "origin 직접 접근 차단됨 (${code:-무응답}) — CDN 경유만 허용" ;;
    esac
  fi
fi

# --------------------------------------------------------- ssh config 정합성
sec "5. ~/.ssh/config"

# ssh -G 는 Include 와 Match 까지 해석한 최종 HostName 을 낸다.
HN=$(ssh -G "$SSH_HOST" 2>/dev/null | awk '$1 == "hostname" { print $2; exit }')
info "HostName = ${HN:-?}"
case "$HN" in
  *.ts.net|"$TS_HOST") ok "tailnet 이름을 가리킨다 (설계대로)" ;;
  100.*)
    o2=$(cut -d. -f2 <<<"$HN")
    if [ "$o2" -ge 64 ] && [ "$o2" -le 127 ]; then ok "tailscale IP 를 가리킨다 (설계대로)"
    else warn "100.64.0.0/10 밖의 100.x 주소다 — tailscale IP 가 아니다"; fi ;;
  *) warn "tailnet 주소가 아니다 — 공개 IP 직결이면 설계와 어긋난다" ;;
esac

# ------------------------------------------------------------------ 요약
sec "요약"
printf '  PASS %d / FAIL %d\n' "$pass" "$fail"
printf '  범위 밖: 서버 안 방화벽·sshd(check-server.sh), 공급자 control plane(check-oci.sh)\n'
[ "$fail" -eq 0 ] || exit 1
