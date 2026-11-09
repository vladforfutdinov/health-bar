# History

## 2026-11-09 — initial design

- AppKit `NSStatusItem` over SwiftUI `MenuBarExtra`: `MenuBarExtra` forces a template (monochrome) label; the icon must be coloured.
- Icon colour follows the official `status.indicator`, not component statuses: Supabase has ~189 region components and one degraded region would keep the icon orange.
- incident.io pages (OpenAI, Supabase): their Statuspage-compatible `summary.json` returned 1 of 189 components for Supabase and no groups for OpenAI, so groups/components come from the page's own `/proxy/<host>` feed, with fallback to `summary.json`. Incidents come from `summary.json` because its update text is plain, while the proxy's is a rich-text tree.
- Platform detection: `/proxy/<host>` returns 404 on Statuspage hosts (checked on githubstatus, status.claude.com, vercel-status), which is cached as "Statuspage".
- Release pipeline (Developer ID, notarytool, Sparkle on gh-pages, Homebrew tap) ported from reLayout, macOS only.
