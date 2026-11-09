#!/usr/bin/env bash
input=$(cat) || exit 0
command -v jq >/dev/null 2>&1 || exit 0
agent="${1:-claude}"
case "$agent" in claude|codex) ;; *) exit 0 ;; esac

# 판정을 jq(Oniguruma) 안에서 하는 이유: grep -E는 locale이 C면 한글 뒤 수량자가
# 마지막 byte에만 걸려 조용히 빗나간다.
jq -c --arg agent "$agent" '
  def fence:
    [capture("^[ \\t]*(?<mark>`{3,}|~{3,})(?<info>.*)$")] | .[0];

  def documented_blocker:
    [capture("^\\s*(?:[-*+]\\s+)?unresolved:\\s*`[^`\\s][^`]*`\\s+[—–-]\\s+(?<blocker>\\S.*)$"; "i")]
    | any(.[];
        (.blocker | test("(확인|검증|시도)하지 ?않았|(실행|돌려|열어|띄워|시도)(해)? ?보지 ?않|\\b(did ?n[o'"'"']t|have ?n[o'"'"']t|not yet) (verif|check|test|run|tri)"; "i") | not)
        and (.blocker | test("^(?:나중에\\s+(?:확인|검증|시도)|(?:미정|TODO|TBD|not yet|later)\\b)"; "i") | not));

  def flagged_lines:
    gsub("^\\s+|\\s+$"; "") | split("\n")
    | (.[0] | fence) as $first
    | (.[-1] | fence) as $last
    | if length > 1 and $first != null and $last != null
         and ($first.info | test("^\\s*(markdown|md)\\s*$"; "i"))
         and ($last.info | test("^\\s*$"))
         and $first.mark[0:1] == $last.mark[0:1]
         and ($last.mark | length) >= ($first.mark | length)
      then .[1:-1] else . end
    | reduce .[] as $line ({mark: null, size: 0, out: []};
        ($line | fence) as $f
        | if .mark != null then
            if $f != null and $f.mark[0:1] == .mark
               and ($f.mark | length) >= .size and ($f.info | test("^\\s*$"))
            then .mark = null else . end
        elif $f != null then .mark = $f.mark[0:1] | .size = ($f.mark | length)
        else .out += [$line]
        end)
    | .out
    | map(select(
        test("(확인|검증)하지 ?(않았|않은|못했|못한)|확인 ?못 ?했|확인(을)? ?안 ?했|아직 확인|미확인|(실행|돌려|열어|띄워|시도)(해)? ?보지 ?(않|못)|시도하지 ?않았|\\bunverified\\b|\\bunresolved\\b|\\b(did ?n[o'"'"']t|have ?n[o'"'"']t|not yet) (verif|check|test|run|tri)"; "i")
        and (test("^\\s*#") | not)
        and (test("^\\s*(?:[-*+]\\s+)?(?:미확인\\s*(?:항목)?(?:은|이)?\\s*:?\\s*(?:없음|없습니다)|no\\s+(?:unverified|unresolved)\\s+items(?:\\s+remain)?)\\.?\\s*$"; "i") | not)
        and (documented_blocker | not)
      ))
    | map(if length > 300 then .[0:300] + "…" else . end);

  if (.stop_hook_active == true)
     or ($agent == "claude" and ((.background_tasks // []) | length > 0))
     or ((.last_assistant_message // "") | type != "string")
  then empty
  else
    (.last_assistant_message // "" | flagged_lines) as $hits
    | if ($hits | length) == 0 then empty
      else (
            "verify-gate: 마지막 응답에 확인하지 않은 항목이 남아 있습니다.\n\n"
            + ($hits[0:10] | map("- " + (sub("^\\s+"; ""))) | join("\n"))
            + "\n\n턴을 끝내기 전에 각 항목을 지금 도구로 확인하세요. "
            + "확인한 항목은 결과로 보고를 고치고, 정말 막힌 항목만 "
            + "unresolved: `실제로 실행한 명령` — blocker 형식으로 남기세요. "
            + "시도 없는 \"방법이 없다\", \"관계없다고 판단\"은 blocker가 아닙니다. "
            + "대기 중인 작업은 사용 가능한 도구로 결과를 기다린 뒤 보고하세요. "
            + "공유 상태 변경이나 되돌리기 어려운 작업이 필요한 확인이면 그 사실을 blocker로 적으세요."
          ) as $feedback
        | if $agent == "codex" then {decision: "block", reason: $feedback}
          else {hookSpecificOutput: {hookEventName: "Stop", additionalContext: $feedback}}
          end
      end
  end
' <<<"$input" 2>/dev/null || true
exit 0
