#!/usr/bin/env python3
"""Claude Code PreToolUse hook: allow the Artifact tool only when the user asked for one."""
import json
import re
import sys

KEYWORD = re.compile(r"아티[팩펙]트|artif[ae]ct|claude\.ai/(?:code/)?artifact/", re.IGNORECASE)
NEGATION = re.compile(
    r"쓰지|말고|말라|금지|제외|사용 ?안|안 ?(?:쓰|만들|해)|만들지|하지 ?마|치워|제거|지워|삭제|왜|대체|몇 ?번|때만|명시"
)
WINDOW = 25
NOT_TYPED = (
    "<task-notification",
    "Base directory for this skill",
    "## Page contract",
    "<command-",
    "<local-command",
    "<system-reminder",
)
DENY_REASON = (
    "사용자가 이 세션에서 Artifact를 요청하지 않았다. publish하지 말고 로컬 파일로 만들어 "
    "호스트 규칙의 미리보기 방식으로 보여줘라. 사용자가 원하면 '아티팩트'라고 직접 말한다."
)


def typed_text(entry):
    if entry.get("type") != "user" or entry.get("isMeta") or entry.get("isCompactSummary"):
        return None
    content = (entry.get("message") or {}).get("content")
    if isinstance(content, str):
        text = content
    elif isinstance(content, list):
        if any(isinstance(c, dict) and c.get("type") == "tool_result" for c in content):
            return None
        text = " ".join(c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text")
    else:
        return None
    text = text.strip()
    return None if not text or text.startswith(NOT_TYPED) else text


def verdict(text):
    """True: asks for an artifact. False: complains or forbids. None: no mention."""
    result = None
    for m in KEYWORD.finditer(text):
        if NEGATION.search(text[max(0, m.start() - WINDOW) : m.end() + WINDOW]):
            return False
        result = True
    return result


def allowed(transcript_path):
    state = False
    try:
        with open(transcript_path, encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    text = typed_text(json.loads(line))
                except ValueError:
                    continue
                if text:
                    v = verdict(text)
                    if v is not None:
                        state = v
    except (OSError, TypeError):
        return False
    return state


def main():
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return
    if payload.get("tool_name", "Artifact") != "Artifact" or allowed(payload.get("transcript_path")):
        return
    print(json.dumps(
        {"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": DENY_REASON,
        }},
        ensure_ascii=False,
    ))


if __name__ == "__main__":
    main()
