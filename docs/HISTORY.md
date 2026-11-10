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

Follow-up, 2026-11-10 (Thaw 3.0.0-beta.6 source, thaw-app/Thaw):
- In Thaw's **standard** hiding mode macOS 27 hides items per app (`hiddenWins`, `AppSiblingSections.swift`): one item of an app in Hidden conceals all of them. Native mode is `visibleWins`.
- macOS keys an item's position as `status:<owner>::<autosaveName>`, the owner being the bundle id or the registered process name. Every build so far ran as process `HealthBar` with `autosaveName` `HealthBar`, so dev, release and test builds shared keys; Thaw "mirrors sibling keys" across them, and a stale `…healthbar.dev::HealthBar: ok` key (from the state-carrying label) kept attracting writes for the dev bundle id. Items landed on the same x, got a "phantom frame", were marked stranded and stayed parked.
- Changes: `autosaveName` = bundle id; dev builds use bundle id `….debug` and executable `HealthBarDev`.
- Result: the release build alone in Visible stays put in standard mode. With a dev and a release copy running together, Thaw still interpolates both into the same position slot (`Interpolated … to 1145 between 1143 and 1147`) and one of them goes phantom; quit one copy (or use native mode) while testing. Stale state is cleared with Thaw quit: `defaults delete com.stonerl.Thaw StrandedMenuBarItems`.

## 2026-11-10 — pie menu bar icon

The bar icon was one glyph for the worst status (filled / half / ring). It is now a pie with one sector per service in config order, each coloured by that service's `status.indicator`, so the icon shows which service is affected. Maintenance (blue) and unreachable (grey) now show in the icon too. Menu rows keep the per-status glyphs.

Drawn as a donut with the hole at 60% of the radius, picked over a full pie and a 45% hole from side-by-side renders at 16 pt on dark and light bars.

## 2026-11-10 — uptime strips replace the components submenu

The second menu level (groups and components) is gone; each service gets a 30-day uptime strip and percentage instead, and its submenu keeps only active incidents.
- Neither platform publishes page-level history, so the strip is built from components: each day is the worst component that day, the percentage is the least available component (the mean hid single-component outages on pages with 59–189 components).
- Polling split by cost (measured, gzip): `status.json` ~0.2 KB per service every minute; summary + history 4–58 KB per service, read at launch, on a status change, then hourly, or every 15 min while not operational. The old per-minute `summary.json` + `/proxy` cost ~19 KB per poll, ~28 MB/day.
- `incidents.json` was rejected as a history source: incident.io returns the last 25 incidents (26 days for OpenAI), and it carries no percentage.
- incident.io's percentage is computed with Statuspage's formula (major outage in full, partial 30%, degraded performance 0) so the two platforms read alike; incident.io's own `component_uptimes` is 90-day only.

## 2026-11-10 — menu updates while open

- Service rows lost their submenu (it held only "Open Status Page" and incidents); the row opens the page, incidents go to the tooltip, and an external-link mark sits where the chevron was.
- A menu opened during loading never showed the results. Two causes: each render assigned a new `NSMenu` to the status item (the open one is now refilled in place), and while a menu is tracked the run loop stays in `NSEventTrackingRunLoopMode`, where common-mode timers fire but the main dispatch queue is not drained, so neither `DispatchQueue.main` blocks nor `@MainActor` continuations ran until it closed (repro: `popUp` the menu, log from a main-queue block and from a common-mode timer). Poll results now come back via `RunLoop.main.perform(inModes: [.common])`.
- The link mark and the shortcuts are drawn as right-aligned tab-stop text: macOS reserves a key-equivalent column (~50 pt) on every row once any item shows one, which left a blank band right of the link marks. ⌘R and ⌘Q are owned by hidden twin items (`allowsKeyEquivalentWhenHidden`), which reserve no column.
- Each service is one two-line item (status, then strip), so the selection highlight covers the whole block; the strip sits on a panel of `windowBackgroundColor` so its gaps and frame don't turn blue under the highlight.
- Services are polled independently and each renders when its own result arrives, instead of after the slowest one.

## 2026-11-10 — per-day strip tooltips

- The strip stretches to fill the row: bars widen so the strip ends before the widest percentage (`100.00 %`), which is right-aligned under the link mark.
- Hovering a strip bar shows that day: each affected component (`Group · Component`) with its status and time in it, most severe first, capped at 8 lines.
- A menu item has one tooltip, so a service is now an `NSMenuItem.view` (`ServiceRowView`) with one `addToolTip` rect per bar. The view draws its own selection and text colours and sends the item's action on mouse-up.
- Durations: Statuspage's `uptime_showcase` gives seconds of partial (`p`) and major (`m`) outage per component per day. incident.io's `component_impacts` gives start/end per component, split at local midnight.
- Names: Statuspage from `summary.json` (`group_id`), already fetched. incident.io from `/proxy/<host>` (`summary.structure`, 4–8 KB gzip), read with the strip; if it fails, ids are shown.
- Checked in the `mac-vm` guest (macOS 26.6): per-bar tooltips change bar to bar, the row tooltip stays over the status line, a click opens the page, and the per-minute refill keeps the open menu (the replaced view drops its tooltip). A copy on the dev Mac closed its menu while the pointer was moved by script during the user's own work; not reproduced in the guest.

## 2026-11-10 — light-theme status colours, Quit action

- The standard system colours read pale on light menus and menu bars. Status colours are now dynamic: system colours on dark appearances, own sRGB shades on light ones (green 40,172,72; orange 245,128,0; red 228,28,38; blue 0,104,240; grey 188,188,193). A first set close to Apple's increased-contrast values (green 36,138,61, grey 108,108,112) was too dark: in the bar icon grey and green sectors merged while it filled in. Healthy strip bars were first dimmed (45% opacity on dark, 70% on light); they are now drawn opaque so the strip, the menu glyphs and the bar icon share one set of colours. Resolving system colours under `accessibilityHighContrastAqua` returned the standard values, so the shades are explicit.
- Tuned by eye: grey 15% lighter on light (198,198,202) and darker on dark (110,110,113, systemGray × 0.85²); green 15% brighter on light (46,198,83) and 15% darker on dark (41,178,75, from systemGreen).
- macOS 26 adds a stock icon to items whose action is `NSApplication.terminate(_:)`, indenting Quit; the item calls its own `quit` action instead.

## 2026-11-10 — refresh starts from no data

Refresh (menu, wake, launch, config reload) clears every service to "updating…" and the icon to grey before polling, so what is shown after it is only what that refresh read; services fill in as they answer.
- The Refresh item is a `RowView` that leaves the menu open, so the refill can be watched.
- A service without data shows an empty grey strip, so rows keep their height; while services load the menu's right edge doesn't move in for the shorter "updating…" titles.

## 2026-11-10 — build targets the declared minimum macOS

`swiftc` ran without `-target`, so the binary's `minos` was the build machine's macOS (27.2 locally, the `macos-latest` runner's in CI) while `Info.plist` declared 13.0: v0.1.0 and v0.2.0 do not launch on older systems. `build.sh` now passes `-target <arch>-apple-macos<LSMinimumSystemVersion>`. Found when a local build would not run in the macOS 26 test VM.

## 2026-11-10 — Settings window replaces the config file

- Services, poll interval, Launch at Login and Sparkle's update options moved into a Settings window (menu → Settings… ⌘,); Edit Config…, Reload Config, Launch at Login and Check for Updates… left the menu. Changes apply at once, no Save.
- Storage moved from `services.json` to `UserDefaults` (key `config`, the same JSON). The file is imported once when nothing is stored, then left in place and ignored. Watching the file for edits was considered and dropped with it.
- A new address is accepted only if its `status.json` decodes; the page's own name is the default service name. 404 or a non-status page reads as "not a Statuspage or incident.io status page".
- The poll interval is a fixed list (30 s – 15 min); an imported value snaps to the nearest, ties to the longer.
- Reordering or adding services keeps the data of those already loaded; only new ones are read in full.
- SwiftUI `Form` in an `NSWindow`. An accessory app shows no menu bar, but `NSApp.mainMenu` gets Edit and Close items so copy/paste and ⌘W work in the window.
- macOS 26 puts a stock gear icon on an item titled "Settings…", indenting it; the item is a `RowView` like Refresh.
- Services became a grouped catalog (`Core/Catalog.swift`, from a survey of pages serving `/api/v2/summary.json` on 2026-11-10) with an enabled flag per page; the original five are enabled by default. Pages added by address go to a Custom group, the only removable ones. Groups fold (Fold all / Unfold all) and are reordered by drag; per-service drag and renaming were dropped. The menu shows enabled services in group order.
- A stored config gains catalog pages it lacks, disabled, on load, so the list can grow in updates. A 0.2.x `services.json` import enables exactly its pages; ones outside the catalog go to Custom.
- Settings iteration (same day): services can sit outside any group (`Config.ungrouped`, listed and shown first); adding and editing a service is a sheet (address, name, group), as is naming a group (New Group…, pencil to rename); New Group… / New Service… sit under the list. Any address can be edited; a changed catalog address leaves the catalog page to be re-added unchecked on the next launch. The address is checked by a HEAD of `status.json` when the field loses focus (green check on 200), then by a GET on save, which also supplies the page's name. Removing a service or group asks first; a group's services can be kept (moved out of the group). Per-service and per-group drag use `draggable` / `onDrop` with a hand-drawn insertion line, since `List.onMove` reorders only within one `ForEach`; the line is drawn only between a drag entering a row and the drop, because macOS 26 sends `dropUpdated` again after `performDrop`. The services list is its own `List` above the `Form`: a `List` inside a `Form` is clipped, not scrolled. Per-group "N of M" counters were dropped.
- Settings follow-up: editing (pencil, after the address) and deleting (inside the edit sheet, confirmed) for services and all groups, catalog ones included; a deleted catalog page is remembered in `Config.removed` so it isn't re-added. Drag handle is a drawn 2×3-dot grip at the row's end (no SF Symbol has six dots). Settings closes on Escape, caught in the window's `sendEvent` because the list consumes it. About HealthBar opens the standard About panel with credits.
- Keyboard focus: opened from the status menu, the Settings window got no key events (Escape, typing) until clicked, though AppKit reported the app active and the window key. `activate(ignoringOtherApps: true)` run after the menu has closed fixes it; the same call during menu teardown, `NSApp.activate()`, and a non-activating `NSPanel` did not (checked with a key-event log in the VM).
- Menu width and shortcuts: once a hidden twin titled "Settings…" was added, macOS reserved the shortcut column again (a blank band on the right), apparently because of the stock icon macOS 26 gives that title. `NSMenuDelegate.menuHasKeyEquivalent` and key equivalents on the view items themselves were tried and never fire while the menu is open (checked with ⌘Q in the VM, against a standard item where it does). Twins stay, untitled; Refresh, About, Settings and Quit are `RowView`s; right padding equals the left.
- About icon: macOS 26 draws a legacy `.icns` app icon shrunk inside a grey rounded-square frame, which read blurry in the About panel. The panel gets the bundle's `AppIcon.icns` image directly (`.applicationIcon`). Finder and the Dock still show the framed icon; that needs an Icon Composer `.icon` asset.

## 2026-11-10 — many services

- With the catalog, the menu outgrew the screen. The services are one menu item holding a scroll view of `RowView`s, 8 visible; the scroll position survives the refills while data arrives. The list owns the hover highlight (rows scrolling under a still pointer get no enter/exit events) and the clicks.
- The bar icon keeps one sector per service up to 10; beyond that 10 sectors, each problem status getting a share proportional to its count (at least one), worst first (`iconSectors`).
- Checking a service in Settings saves at once; its data is fetched in the background (checked in the VM: the box flips within 0.15 s).
- `design/status-icons.svg` has a 5-sector logo variant (`logo5`) in all status colours, for further design.

## 2026-11-10 — concurrency review fixes

- Settings save awaits the page (up to the timeout); Cancel and Delete… in the service sheet were live meanwhile, so a cancelled add still landed, a deleted service came back under its new address, and two adds of one address both passed the duplicate check. Cancel and Delete… are disabled while saving, and `save` re-checks the address and the edited service after the await.
- `StatusFetcher` uses a session with `timeoutIntervalForResource = 30`: the request timeout counts only idle time, and one trickling page kept `pending > 0`, which skips every timer poll.
- Reviewed and left: results applied via `RunLoop.main.perform` were suspected of waiting for the next event with the menu closed; not seen in the VM (the icon filled in sector by sector with no input). A Statuspage host answering 200 with HTML on incident.io's `component_impacts` path would be cached as incident.io; not observed.
- App icon now comes from `design/g2.svg` (the 5-sector logo); `design/g206.svg` is the previous source.

## 2026-11-10 — HIG pass

Decisions from a review against Apple's HIG, and what the experiments showed:
- Reordering in Settings is back on `List.onMove` (native insertion line; the hand-drawn one landed in the wrong place on the user's Mac). Moving a service to another group, and Move Up/Down, are in each row's context menu.
- Menu services list: 8.5 rows visible so the cut-off row shows it scrolls, and a legacy (always visible) scroller in the rows' right padding. Rows carry a VoiceOver label ("GitHub, All Systems Operational, 99.83% uptime over 30 days") and press action; the status item reads a sentence instead of an enum name. A third line shows the first incident (+N more) or the fetch error.
- Arrow keys and Return in the list: not possible. A local event monitor gets no key events while a status menu tracks. Zero-height stand-in items per service did take the arrows, but the menu lays each out at 1 pt without counting it in its height (clipping the bottom or leaving a gap), shifts its content when one is highlighted, and won't send Return to an item that has a view. Reverted.
- Delete confirmations: name in quotes, "This can’t be undone.", buttons named by outcome (Delete Group Only / Delete Group and Services), Cancel as the default button (Return cancels).
- ⌘Q works in the Settings window (app menu in the hidden main menu); the window reopens where it was closed.
- Localisation prep: percentages via `FormatStyle.percent`, intervals via `DateComponentsFormatter`, plurals via automatic grammar agreement; UI strings stay English.
- Differentiate without color: `!`/`~` in the icon's hole, a centre dot on maintenance glyphs; normal appearance unchanged.
- Confirmations are a small sheet (`ConfirmSheet`) styled like the other sheets: SwiftUI's `.alert` on macOS 26 used large capsule buttons unlike the rest, and Escape didn't dismiss it (the window's Escape handler checks `attachedSheet`, which the alert isn't). Cancel is the default button; Return and Escape cancel.
- The Settings list has a selection (Tab reaches it; arrows move): Space checks a service or folds a group, Return edits, Delete deletes (confirmed), ⌥⌘↑/↓ move. Hidden buttons with key equivalents, enabled only while the list has focus, since `onKeyPress` needs macOS 14.
- Of the 59 catalog pages, 15 give no per-day history (checked 2026-11-10): Statuspage pages with uptime display off answer `uptime_showcase` with no timelines (Snyk, Deepgram, DigitalOcean, Linode, MongoDB, Grafana, New Relic, Mailgun, Jira, Figma, Zoom, Dropbox), Cloudflare's answers 404, Mistral's and Replit's `component_impacts` 403. Their rows say "No uptime history" in the strip's place, so a grey strip means only "loading".
- The menu list's scroller took width from its clip view while the content kept the full width, so it scrolled sideways; the content now matches the clip width.
- After 0.3.0: the menu list uses the standard overlay scroller (appears while scrolling) instead of an always-visible one, and the cut-off row shows its title and the top edge of its strip. "No uptime history" sits over a 25%-opacity placeholder strip.
