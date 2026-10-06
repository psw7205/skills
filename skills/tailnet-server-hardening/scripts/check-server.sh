#!/usr/bin/env bash
# 서버 안에서 보는 read-only 점검: tailscaled, OS 방화벽(ufw)의 포트·소스 제한과 CDN 대역 drift,
# sshd 실효 설정, 시리얼 콘솔 전제(계정 패스워드), 디스크·재부팅. FAIL 이 하나라도 있으면 exit 1.
#
#   ssh <alias> 'TS_HOST=<tailnet hostname> bash -s' < check-server.sh
set -uo pipefail

TS_HOST="${TS_HOST:?TS_HOST 에 이 서버의 tailnet hostname 을 지정한다}"
SSH_USER="${SSH_USER:-$(id -un)}"
UFW_ALLOWED_PORTS="${UFW_ALLOWED_PORTS:-80 443}"
WEB_PORTS="${WEB_PORTS:-80 443}"
CDN_IP_URLS="${CDN_IP_URLS:-https://www.cloudflare.com/ips-v4 https://www.cloudflare.com/ips-v6}"

# 다른 호스트에서 돌리면 그 호스트의 방화벽을 점검하고도 통과로 보고한다.
_self=$(tailscale status --json 2>/dev/null | python3 -c 'import json,sys; print((json.load(sys.stdin).get("Self") or {}).get("HostName",""))' 2>/dev/null)
if [ "$_self" != "$TS_HOST" ]; then
  printf '이 스크립트는 %s 안에서 실행해야 한다. 현재 tailnet hostname: %s (%s)\n' \
    "$TS_HOST" "${_self:-알 수 없음}" "$(hostname 2>/dev/null)" >&2
  exit 2
fi
unset _self

pass=0
fail=0

if [ -t 1 ]; then G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; N=$'\033[0m'
else G=''; R=''; Y=''; N=''; fi

ok()   { printf '  %sPASS%s  %s\n' "$G" "$N" "$1"; pass=$((pass + 1)); }
no()   { printf '  %sFAIL%s  %s\n' "$R" "$N" "$1"; fail=$((fail + 1)); }
warn() { printf '  %sWARN%s  %s\n' "$Y" "$N" "$1"; }
info() { printf '        %s\n' "$1"; }
sec()  { printf '\n== %s\n' "$1"; }

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if sudo -n true 2>/dev/null; then SUDO="sudo -n"
  else echo "루트 권한이 필요하다 (NOPASSWD sudo 또는 root 로 실행)" >&2; exit 1; fi
fi

# ---------------------------------------------------------------- Tailscale
sec "1. Tailscale"

if ! command -v tailscale >/dev/null 2>&1; then
  no "tailscale 명령이 없다"
else
  TS=$(tailscale status --json 2>/dev/null)
  if [ -z "$TS" ]; then
    no "tailscale status 실패 (tailscaled 가 죽었을 수 있다)"
  else
    # 빈 값이 섞여도 필드가 밀리지 않도록 key=value 로 받는다.
    eval_out=$(python3 -c '
import json, sys
d = json.load(sys.stdin)
s = d.get("Self") or {}
for k, v in [
    ("BACKEND", d.get("BackendState") or ""),
    ("ONLINE",  s.get("Online")),
    ("KEYEXP",  s.get("KeyExpiry") or ""),
]:
    print("%s=%s" % (k, v))
' <<<"$TS" 2>/dev/null)

    BACKEND=""; ONLINE=""; KEYEXP=""
    while IFS='=' read -r k v; do
      case "$k" in BACKEND) BACKEND="$v";; ONLINE) ONLINE="$v";; KEYEXP) KEYEXP="$v";; esac
    done <<<"$eval_out"

    [ "$BACKEND" = "Running" ] && ok "BackendState = Running" \
                               || no "BackendState = ${BACKEND:-unknown}"
    [ "$ONLINE" = "True" ] && ok "tailnet Online" || no "tailnet offline"

    # 노드 키 만료. 이 값이 채워져 있으면 그 날짜에 SSH 경로가 끊긴다.
    if [ -z "$KEYEXP" ]; then
      ok "노드 키 만료 비활성화됨"
    else
      no "노드 키 만료가 살아 있다: $KEYEXP"
      info "admin 콘솔 > Machines > Disable key expiry"
    fi
  fi
  $SUDO systemctl is-active --quiet tailscaled 2>/dev/null \
    && ok "tailscaled 서비스 active" || warn "tailscaled 서비스 상태 확인 불가"
fi

# ------------------------------------------------------------- OS 방화벽
sec "2. OS 방화벽 (ufw)"

if ! command -v ufw >/dev/null 2>&1; then
  warn "ufw 가 없다 (firewalld 나 iptables 를 쓰는 구성일 수 있다)"
  $SUDO iptables -S 2>/dev/null | head -10 | while IFS= read -r l; do info "$l"; done
else
  UFW=$($SUDO ufw status verbose 2>/dev/null)
  grep -q '^Status: active' <<<"$UFW" && ok "ufw active" || no "ufw 가 꺼져 있다"

  if grep -q 'deny (incoming)' <<<"$UFW"; then
    ok "기본 정책 deny (incoming)"
  else
    no "기본 정책이 deny (incoming) 가 아니다"
    info "$(grep -i '^Default:' <<<"$UFW")"
  fi

  # ALLOW 규칙을 "To|From" 으로 뽑는다. To 는 ALLOW 앞, From 은 "ALLOW IN" 뒤다.
  # 꼬리의 "# 주석" 은 버리고, (v6) 는 문자열 중간에도 오므로 전부 지운다.
  rules=$($SUDO ufw status 2>/dev/null \
          | awk '/ALLOW/ {
                   l = $0
                   gsub(/ \(v6\)/, "", l)
                   sub(/ +#.*/, "", l)
                   i = index(l, "ALLOW")
                   to = substr(l, 1, i - 1)
                   from = substr(l, i)
                   sub(/^ALLOW([[:space:]]+(IN|OUT))?[[:space:]]+/, "", from)
                   gsub(/^[[:space:]]+|[[:space:]]+$/, "", to)
                   gsub(/^[[:space:]]+|[[:space:]]+$/, "", from)
                   print to "|" from
                 }' | sort -u)

  # 문자열을 그대로 비교하면 "80/tcp" 와 "80,443/tcp" 같은 동등 표기에 걸린다.
  # 포트 번호 집합으로 환산해서 비교한다.
  ufw_ports=""
  tailnet_allow=0
  other=""
  web_world=""
  web_srcs=""
  while IFS= read -r r; do
    [ -z "$r" ] && continue
    to=${r%%|*}
    from=${r#*|}
    case "$to" in
      *"on tailscale0"*) info "allow: $to  <-  $from"; tailnet_allow=1; continue ;;
    esac
    spec=${to%%/*}                     # "80,443/tcp" -> "80,443"
    case "$spec" in
      ''|*[!0-9,]*) info "allow: $to  <-  $from"; other="$other [$to]" ;;
      *)
        ufw_ports="$ufw_ports $(tr ',' ' ' <<<"$spec")"
        # 웹 포트는 소스까지 본다. Anywhere 면 origin 이 인터넷에 직접 노출된다.
        case "$from" in
          *[0-9].[0-9]*|*:*) web_srcs="$web_srcs$from
" ;;
          *)                 web_world="$web_world [$to <- $from]" ;;
        esac
        ;;
    esac
  done <<<"$rules"

  web_srcs=$(printf '%s' "$web_srcs" | sed '/^$/d' | sort -u)
  n_src=$(printf '%s\n' "$web_srcs" | sed '/^$/d' | wc -l | tr -d ' ')
  info "웹 포트($(tr ' ' ',' <<<"$WEB_PORTS" | sed 's/,$//')) 허용 소스: ${n_src}개 대역"

  if [ -n "$web_world" ]; then
    no "웹 포트가 Anywhere 로 열려 있다:$web_world — origin 이 인터넷에 직접 노출된다"
  elif [ "$n_src" -gt 0 ]; then
    ok "웹 포트가 특정 대역에서만 허용됨 (${n_src}건) — origin 직접 접근 차단"
  else
    no "웹 포트 ALLOW 규칙이 없다 — CDN 이 origin 에 못 닿는다"
  fi

  # CDN 공개 목록과의 drift 확인. 대역이 바뀌면 일부 요청이 조용히 막힌다.
  # 네트워크에 기대는 검사라 실패해도 FAIL 로 세지 않는다.
  if [ "$n_src" -gt 0 ]; then
    cf=$(for u in $CDN_IP_URLS; do curl -s -m 8 "$u"; echo; done 2>/dev/null \
          | tr -d '\r' | sed '/^$/d' | sort -u)
    if [ -z "$cf" ]; then
      warn "CDN 공개 IP 목록을 못 받아 대역 동기화 확인을 건너뛴다"
    else
      missing=$(comm -23 <(printf '%s\n' "$cf") <(printf '%s\n' "$web_srcs"))
      stale=$(comm -13 <(printf '%s\n' "$cf") <(printf '%s\n' "$web_srcs"))
      if [ -z "$missing" ] && [ -z "$stale" ]; then
        ok "CDN 공개 대역과 동기화됨 ($(printf '%s\n' "$cf" | wc -l | tr -d ' ')건)"
      else
        warn "CDN 공개 대역과 어긋난다 (갱신: $CDN_IP_URLS)"
        [ -n "$missing" ] && info "누락(차단 위험): $(tr '\n' ' ' <<<"$missing")"
        [ -n "$stale" ]   && info "폐기(불필요):   $(tr '\n' ' ' <<<"$stale")"
      fi
    fi
  fi

  got=$(tr ' ' '\n' <<<"$ufw_ports" | sed '/^$/d' | sort -un | tr '\n' ' ')
  want=$(tr ' ' '\n' <<<"$UFW_ALLOWED_PORTS" | sed '/^$/d' | sort -un | tr '\n' ' ')

  [ "$tailnet_allow" -eq 1 ] && ok "tailscale0 인터페이스 허용됨 (SSH 경로)" \
                             || no "tailscale0 허용 규칙이 없다 — SSH 가 끊긴다"

  if [ -n "$other" ]; then
    no "예상 밖 ALLOW 규칙:$other"
  elif [ "$got" = "$want" ]; then
    ok "허용 포트가 기대와 일치: $got"
  else
    no "허용 포트 불일치"
    info "기대: $want"
    info "실제: $got"
  fi
fi

# ----------------------------------------------------------------- sshd
sec "3. sshd 실효 설정"

# sshd -T 는 파일이 아니라 모든 설정 소스를 병합한 최종 적용값을 낸다.
SSHD=$($SUDO sshd -T 2>/dev/null)
if [ -z "$SSHD" ]; then
  no "sshd -T 실패"
else
  chk() {   # chk <키> <기대값>
    local k="$1" want="$2" got
    got=$(awk -v k="$k" 'tolower($1) == k { print $2; exit }' <<<"$SSHD")
    [ "$got" = "$want" ] && ok "$k = $got" || no "$k = ${got:-없음} (기대: $want)"
  }
  chk passwordauthentication       no
  chk kbdinteractiveauthentication no
  chk permitrootlogin              no
  chk permitemptypasswords         no
  chk pubkeyauthentication         yes

  info "port: $(awk 'tolower($1) == "port" { print $2 }' <<<"$SSHD" | tr '\n' ' ')"
fi

for svc in ssh sshd; do
  if $SUDO systemctl is-active --quiet "$svc" 2>/dev/null; then
    ok "$svc 서비스 active"; break
  fi
done

# ------------------------------------------------------------ 비상 경로
sec "4. 비상 경로 전제 (시리얼 콘솔)"

# 시리얼 콘솔은 login 프롬프트로 떨어진다. 패스워드가 없으면 SSH 키가 있어도 못 들어간다.
PW=$($SUDO passwd -S "$SSH_USER" 2>/dev/null | awk '{print $2}')
case "$PW" in
  P)  ok "$SSH_USER 패스워드 설정됨 — 시리얼 콘솔 로그인 가능" ;;
  L)  no "$SSH_USER 계정이 잠겨 있다 — 시리얼 콘솔로 못 들어간다" ;;
  NP) no "$SSH_USER 패스워드 없음 — 시리얼 콘솔이 무용지물이다 (sudo passwd $SSH_USER)" ;;
  *)  warn "패스워드 상태 확인 불가 (passwd -S -> ${PW:-없음})" ;;
esac

# ------------------------------------------------------------ 시스템 상태
sec "5. 시스템"

info "uptime : $(uptime -p 2>/dev/null || uptime)"

DISK=$(df -h / | awk 'NR == 2 { print $5 " used of " $2 }')
USEPCT=$(df / | awk 'NR == 2 { gsub(/%/, "", $5); print $5 }')
info "disk / : $DISK"
[ "${USEPCT:-0}" -lt 85 ] && ok "루트 디스크 여유 있음" || no "루트 디스크 ${USEPCT}% — 정리 필요"

if [ -f /var/run/reboot-required ]; then
  warn "재부팅 대기 중 ($(cat /var/run/reboot-required.pkgs 2>/dev/null | tr '\n' ' '))"
else
  ok "재부팅 요구 없음"
fi

if command -v docker >/dev/null 2>&1; then
  n=$($SUDO docker ps -q 2>/dev/null | wc -l | tr -d ' ')
  info "docker 실행 중 컨테이너: ${n:-?}"
fi

# ------------------------------------------------------------------ 요약
sec "요약"
printf '  PASS %d / FAIL %d\n' "$pass" "$fail"
printf '  범위 밖: 인터넷에서 본 실측(check-external.sh), 공급자 control plane(check-oci.sh)\n'
[ "$fail" -eq 0 ] || exit 1
