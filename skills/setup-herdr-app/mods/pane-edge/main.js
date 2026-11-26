// cmd-alt-left/right (keys.json "layout:main-prompts": "pane-edge.left" / "pane-edge.right")
// go to the pane on that side, and past the last one to the neighbouring tab, landing on
// its pane at the edge the move came from. A 0px layout block keeps this copy shown:
// <mod>.<command> reaches shown copies only.

import { div, View } from "gpui-kit";
import { focused, nextCommand, run } from "herdr";

// direction -> [tab command, the way back to the near edge of the tab it lands on]
const PAST_EDGE = { right: ["tab.next", "left"], left: ["tab.prev", "right"] };

// pane.go reports nothing when there is no pane that way, so compare focus. Commands
// apply after the call returns, so wait a tick first: cx.sleep() without ms never resolves.
async function moved(cx, direction) {
  const before = focused()?.pane;
  run("pane.go", { direction });
  await cx.sleep(1);
  return focused()?.pane !== before;
}

export default class PaneEdge extends View {
  init(_props, cx) {
    cx.spawn(async (cx) => {
      for (;;) {
        const direction = await nextCommand();
        if (!(direction in PAST_EDGE) || (await moved(cx, direction))) continue;
        const [tabCommand, back] = PAST_EDGE[direction];
        const tab = focused()?.tab;
        run(tabCommand);
        await cx.sleep(1);
        if (focused()?.tab === tab) continue;
        // Bounded: pane.go has no wrap-around today, but an endless loop would pin the window.
        for (let i = 0; i < 50 && (await moved(cx, back)); i++);
      }
    });
  }

  render() {
    return div();
  }
}
