// cmd-w (keys.json: "cmd-w": "mod.open:close-guard") opens this invisible overlay.
// It closes the focused tab at once, but asks first when an agent runs in it,
// idle ones too: tab.close ends the tab's terminals with no question.

import { div, View } from "gpui-kit";
import { agents, closeOverlay, focused, openOverlay, props, run, spaces } from "herdr";

const STATUS = { working: "작업 중", blocked: "입력 대기", done: "완료", idle: "대기 중" };

export default class CloseGuard extends View {
  init() {
    // props() is null under `herdr-app check`, which loads the mod with no overlay.
    const overlay = props()?.overlay;
    if (overlay) closeOverlay(overlay);
    const tab = focused()?.tab;
    if (!tab) return;
    const live = agents().filter((a) => a.tab === tab);
    // Unconfirmed, tab.close still asks before closing a space's last tab.
    if (!live.length) return run("tab.close", { id: tab });
    const last = spaces().find((s) => s.tabs.some((t) => t.id === tab))?.tabs.length === 1;
    const who = live.map((a) => `${a.program.name} ${STATUS[a.status]}`).join(", ");
    openOverlay({
      mod: "confirm",
      kind: "dialog",
      width: 400,
      height: 170,
      props: {
        title: "에이전트가 있는 탭을 닫을까요?",
        detail: `${who} · 닫으면 함께 종료됩니다.${last ? " 마지막 탭이라 스페이스도 닫힙니다." : ""}`,
        command: { name: "tab.close", args: { id: tab, confirmed: true } },
      },
    });
  }

  render() {
    return div();
  }
}
