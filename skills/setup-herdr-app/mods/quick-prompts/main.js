import { View, div } from "gpui-kit";
import { h_flex } from "gpui-base";
import { agents, appHome, focused, hc, notify, readTextFile, run, theme } from "herdr";

const SENDABLE = new Set(["idle", "done", "working"]);

// The focused terminal, only when it is an agent that can take a message now.
// Plain shells and pre-start dialogs (update, hook trust) report no status and
// are left out, so Enter never lands on a dialog's default choice.
function target() {
  const address = focused()?.terminal;
  const agent = address && agents().find((a) => a.address === address);
  return agent && SENDABLE.has(agent.status) ? agent : null;
}

export default class QuickPrompts extends View {
  init(_props, cx) {
    this.prompts = [];
    this.job = null;
    cx.spawn(async (cx) => {
      try {
        this.prompts = JSON.parse(await readTextFile(`${appHome()}/mods/quick-prompts/prompts.json`) ?? "[]");
      } catch (e) {
        notify({ title: "quick-prompts", body: `prompts.json: ${e}`, level: "error" });
      }
      cx.notify();
    });
  }

  finish(job, cx, error) {
    if (this.job !== job) return;
    this.job = null;
    cx.notify();
    if (error) notify({ title: "quick-prompts", body: error, level: "error" });
  }

  // Not `hc send`: since herdr-core 0.1.20 it holds while the person has an unsent
  // draft (draft_wait, up to 60 s), and a mod's exec is killed at 30 s, which cancels
  // the send. Paste through the app at once instead; only Enter goes through
  // `hc keys`, which presses it after ~3 s without person input in that terminal
  // (a click on the pane counts), and that pause cannot be configured.
  send(i, text, cx) {
    const agent = target();
    if (!agent || this.job) return;
    const job = { i };
    this.job = job;
    cx.notify();
    const saved = cx.read_from_clipboard();
    cx.write_to_clipboard(text);
    run("terminal.paste");
    cx.timer.after(15000, (cx) => this.finish(job, cx, `${agent.address}: pasted, but Enter is still waiting for input to stop; press Enter yourself`));
    cx.spawn(async (cx) => {
      const r = await hc(["keys", agent.address, "enter"]).catch((e) => ({ code: 1, stderr: String(e) }));
      if (saved !== undefined) cx.write_to_clipboard(saved);
      this.finish(job, cx, r.code === 0 ? null : `${agent.address}: pasted, but Enter failed: ${r.stderr.trim()}`);
    });
  }

  render() {
    const t = theme();
    const on = Boolean(target()) && !this.job;
    return h_flex().size_full().px(12).gap(6).items_center().bg(t.chrome).border_t(1).border_color(t.border)
      .children(this.prompts.map((p, i) => {
        const sending = this.job?.i === i;
        return div().id(`qp-${i}`).h(24).px(10).flex_none().flex().items_center().rounded(12)
          .border(1).border_color(sending ? t.accent : t.border).text_size(12)
          .text_color(on || sending ? t.foreground : t.dim)
          .when(on, (el) => el.cursor_pointer().hover((s) => s.bg(t.hover)))
          .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
          .on_click((_e, cx) => this.send(i, p.text, cx))
          .child(sending ? `${p.label} · 보내는 중…` : p.label);
      }));
  }
}
