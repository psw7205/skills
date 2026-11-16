#!/usr/bin/env bash
input=$(cat) || exit 0
command -v jq >/dev/null 2>&1 || exit 0
agent="${1:-claude}"
case "$agent" in claude|codex) ;; *) exit 0 ;; esac

# 사용자가 중단·거부한 확인을 다음 턴 보고에서 다시 꺼내면 훅이 재시도를 시키므로,
# 직전 턴까지 두 턴을 본다. transcript는 수십 MB까지 커지므로 꼬리만 읽는다.
user_stopped=false
transcript=$(jq -r '.transcript_path | strings' <<<"$input" 2>/dev/null) || transcript=""
if [ -n "$transcript" ] && [ -r "$transcript" ]; then
  user_stopped=$(tail -n 2000 "$transcript" | jq -R -s --arg agent "$agent" '
    def interrupt_marker: startswith("[Request interrupted by user");

    def turn_start:
      if $agent == "codex" then .type == "event_msg" and .payload.type == "task_started"
      else
        .type == "user" and (.isSidechain | not) and (.isMeta | not)
        and (.message.content
             | if type == "string" then (interrupt_marker | not)
               elif type == "array" then
                 all(.[]; .type != "tool_result")
                 and (any(.[]; .type == "text" and (.text | interrupt_marker)) | not)
               else false end)
      end;

    def user_stop:
      if $agent == "codex" then
        (.type == "event_msg" and .payload.type == "turn_aborted" and .payload.reason == "interrupted")
        or (.type == "response_item" and (.payload.type // "" | endswith("_call_output"))
            and (.payload.output | tostring | test("rejected by user(?! approval settings)")))
      else
        .type == "user" and (.isSidechain | not)
        and (.message.content
             | if type == "string" then interrupt_marker
               elif type == "array" then
                 any(.[];
                   (.type == "text" and (.text | interrupt_marker))
                   or (.type == "tool_result"
                       and (.content | tostring | contains("The user doesn'"'"'t want to proceed"))))
               else false end)
      end;

    [split("\n")[] | fromjson? | objects] as $rows
    | [$rows | to_entries[] | select(.value | turn_start) | .key] as $starts
    | ($starts | if length >= 2 then .[-2] else 0 end) as $from
    | any($rows[$from:][]; user_stop)
  ' 2>/dev/null) || user_stopped=false
  [ "$user_stopped" = true ] || user_stopped=false
fi

# 판정을 jq(Oniguruma) 안에서 하는 이유: grep -E는 locale이 C면 한글 뒤 수량자가
# 마지막 byte에만 걸려 조용히 빗나간다.
jq -c --arg agent "$agent" --argjson user_stopped "$user_stopped" '
  def fence:
    [capture("^[ \\t]*(?<mark>`{3,}|~{3,})(?<info>.*)$")] | .[0];

  def documented_blocker:
    [capture("^\\s*(?:[-*+]\\s+)?unresolved:\\s*`[^`\\s][^`]*`\\s+[—–-]\\s+(?<blocker>\\S.*)$"; "i")]
    | any(.[];
        (.blocker | test("(확인|검증|시도)하지 ?않았|(실행|돌려|열어|띄워|시도)(해)? ?보지 ?않|\\b(did ?n[o'"'"']t|have ?n[o'"'"']t|not yet) (verif|check|test|run|tri)"; "i") | not)
        and (.blocker | test("^(?:나중에\\s+(?:확인|검증|시도)|(?:미정|TODO|TBD|not yet|later)\\b)"; "i") | not));

  def user_stopped_blocker:
    test("^\\s*(?:[-*+]\\s+)?unresolved:\\s*(?:사용자\\s*(?:중단|거부)|user[- ](?:interrupted|declined|rejected|stopped))\\s+[—–-]\\s+\\S"; "i");

  # code span과 따옴표를 한 번의 왼쪽→오른쪽 스캔으로 지워, 한 구간 안의 구분자가
  # 다른 구간과 짝지어지지 않게 한다. backtick 하나로 감싼 판정어 단독(`unresolved`)은
  # 인용이 아니라 상태 라벨로 쓰이므로 남기고, 두 겹 이상 code span은 그 라벨을 설명하는
  # 인용이라 통째로 지운다.
  def strip_quoted:
    gsub("(?<tick>`+)(?!`)(?<body>.*?)(?<!`)\\k<tick>(?!`)|\"[^\"]*\"|“[^”]*”|‘[^’]*’";
      if (.tick // "" | length) == 1
         and (.body | test("^\\s*(unresolved|unverified|미확인)\\s*$"; "i"))
      then " " + .body + " " else "" end);

  def unverified_text:
    strip_quoted
    | test("(확인|검증)하지(?:는|도|조차|까지는?)? ?(않았|않은|못했|못한)|확인(?:을|은|도|까지는?)? ?(못|안) ?했|아직 확인|미확인|보지(?:는|도)? ?(않았|않은|못했|못한)|시도하지(?:는|도)? ?않았|\\bunverified\\b|\\bunresolved\\b|\\b(did ?n[o'"'"']t|have ?n[o'"'"']t|not yet) (verif|check|test|run|tri)"; "i")
      or test("(확인|검증|점검)해 ?(보세요|보시면|보시고|보시길|보실 ?수 ?있|볼 ?만|보면 ?좋|보는 ?(게|것이) ?좋)|직접 (확인|검증|점검)(하세요|하시면|하셔야|하실 ?수 ?있|해 ?(보세요|주세요|보시면)|할 ?수 ?있)|\\byou (can|could|may|might|should)( want to)? (double-?check|check|verify|confirm)\\b|\\bworth (checking|verifying)\\b"; "i");

  # 굵은 글씨 한 줄도 섹션 제목으로 쓰이지만, 문장으로 끝나면 보고 내용이다.
  def heading:
    test("^\\s*#{1,6}\\s")
    or (test("^\\s*\\*\\*[^*]+\\*\\*\\s*:?\\s*$") and (test("[.다]\\s*\\*\\*\\s*:?\\s*$") | not));

  def unverified_heading:
    strip_quoted
    | test("(확인|검증)하지 ?(못한|않은)|확인 ?(못|안) ?한|보지 ?(않은|못한)|아직 안 ?한|미확인|남은 ?(확인|검증)|\\bunverified\\b|\\bunresolved\\b|not (yet )?verified"; "i")
      and (test("없(음|습니다|다)|\\bnone\\b|\\bno\\s+(unverified|unresolved)"; "i") | not);

  def list_item: test("^\\s*(?:[-*+]|\\d+[.)])\\s+");

  def none_line:
    test("^\\s*(?:(?:[-*+]|\\d+[.)])\\s+)?(?:\\*\\*)?(?:없음|없습니다|none|n/a)\\.?(?:\\*\\*)?\\.?\\s*$"; "i");

  def all_clear:
    test("^\\s*(?:[-*+]\\s+)?(?:미확인\\s*(?:항목)?(?:은|이)?\\s*:?\\s*(?:없음|없습니다)|no\\s+(?:unverified|unresolved)\\s+items(?:\\s+remain)?)\\.?\\s*$"; "i");

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
    | reduce .out[] as $line ({section: false, listed: false, gap: false, hits: []};
        if ($line | heading) then
          .section = ($line | unverified_heading) | .listed = false | .gap = false
        elif ($line | test("^\\s*$")) then .gap = true
        else
          (if .section and .gap and .listed and ($line | list_item | not)
           then .section = false else . end)
          | .gap = false
          | (if .section and ($line | list_item) then .listed = true else . end)
          | if ($line | all_clear) or ($line | documented_blocker) or ($line | user_stopped_blocker) then .
            elif ($line | unverified_text) or (.section and ($line | none_line | not))
            then .hits += [$line]
            else . end
        end)
    | .hits
    | map(if length > 300 then .[0:300] + "…" else . end);

  if (.stop_hook_active == true)
     or $user_stopped
     or ($agent == "claude" and ((.background_tasks // []) | length > 0))
     or ((.last_assistant_message // "") | type != "string")
  then empty
  else
    (.last_assistant_message // "" | flagged_lines) as $hits
    | if ($hits | length) == 0 then empty
      else (
            "verify-gate: 마지막 응답에 확인하지 않은 항목이 남아 있습니다.\n\n"
            + ($hits[0:10] | map("- " + (sub("^\\s*(?:[-*+]\\s+)?"; ""))) | join("\n"))
            + "\n\n사용자가 중단하거나 거부한 확인은 다시 시도하지 말고 "
            + "unresolved: 사용자 중단 — 항목 형식으로 남기세요. "
            + "나머지는 턴을 끝내기 전에 지금 도구로 확인하세요. "
            + "사용자에게 넘긴 확인도 도구로 할 수 있으면 직접 하세요. "
            + "확인한 항목은 결과로 보고를 고치고, 정말 막힌 항목만 "
            + "unresolved: `실제로 실행한 명령` — blocker 형식으로 남기세요. "
            + "권한상 접근할 수 없는 확인은 그 근거를 blocker로 적고, 답에 필요 없는 확인이면 그 문장을 보고에서 빼세요. "
            + "시도도 근거도 없는 \"방법이 없다\"는 blocker가 아닙니다. "
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
