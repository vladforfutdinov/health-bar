# History

## 2026-11-09 — initial design

- AppKit `NSStatusItem` over SwiftUI `MenuBarExtra`: `MenuBarExtra` forces a template (monochrome) label; the icon must be coloured.
- Icon colour follows the official `status.indicator`, not component statuses: Supabase has ~189 region components and one degraded region would keep the icon orange.
- incident.io pages (OpenAI, Supabase): their Statuspage-compatible `summary.json` returned 1 of 189 components for Supabase and no groups for OpenAI, so groups/components come from the page's own `/proxy/<host>` feed, with fallback to `summary.json`. Incidents come from `summary.json` because its update text is plain, while the proxy's is a rich-text tree.
- Platform detection: `/proxy/<host>` returns 404 on Statuspage hosts (checked on githubstatus, status.claude.com, vercel-status), which is cached as "Statuspage".
- Release pipeline (Developer ID, notarytool, Sparkle on gh-pages, Homebrew tap) ported from reLayout, macOS only.

## 2026-11-09 — menu glyphs moved into item titles

On macOS 27.2 `NSMenuItem.image` is not drawn in the status menu at all: a drawingHandler image, a plain bitmap and an SF Symbol all stayed invisible while the state checkmark column rendered (repro: scratch app popping an `NSMenu` and screen-capturing it). No user default controlling it was found. The glyph is now an `NSTextAttachment` at the start of `attributedTitle`, which renders. No unit-test seam: the symptom is AppKit menu drawing.

## 2026-11-09 — stable status item identity

Thaw (Ice fork) keyed the item as `<bundle id>:HealthBar: ok`, i.e. by its accessibility label, which included the current state. Every state change looked like a new item, and new items land in Thaw's hidden section, so the item vanished even after being moved to the visible section. The label is now the constant `HealthBar` (state goes to the accessibility value and tooltip), matching reLayout.

That alone didn't keep it visible. Open as of 2026-11-10: with Thaw 3.0.0-alpha.13 and beta.6 in the **standard** hiding method the item still vanishes when the hidden section collapses (Thaw log: "phantom frame … occupied by an overlapping neighbour", "remains stranded after move", then `StrandedMenuBarItems`). With Thaw's **native** hiding method, or without Thaw, it stays. reLayout stays in both modes. Ruled out, each with no effect: ad-hoc vs. self-signed code signature, `autosaveName` default vs. equal to the label, creating the item before vs. in `applicationDidFinishLaunching`, position next to vs. away from Thaw's divider, a fresh bundle id, a template (monochrome) image with `imagePosition = .imageOnly`. Kept anyway: constant label, `autosaveName = "HealthBar"`, creation in `applicationDidFinishLaunching`. Stale Thaw state can be cleared with Thaw quit: `defaults delete com.stonerl.Thaw StrandedMenuBarItems`.
