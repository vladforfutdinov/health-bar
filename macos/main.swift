import AppKit
import SwiftUI
#if SPARKLE
import Sparkle
#endif

enum Glyph {
    case filled(NSColor), half(NSColor), ring(NSColor), dashed(NSColor)

    init(_ level: Level) {
        switch level {
        case .ok, .maintenance: self = .filled(Self.color(level))
        case .degraded: self = .half(Self.color(level))
        case .outage: self = .ring(Self.color(level))
        }
    }

    /// Geometry from design/status-icons.svg (16-unit grid). Colours resolve at draw time,
    /// so the system colours follow light/dark menu bars.
    func image(size: CGFloat = 16) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            let u = r.width / 16
            let c = NSPoint(x: r.midX, y: r.midY)
            let ring = NSBezierPath(ovalIn: r.insetBy(dx: 2.25 * u, dy: 2.25 * u))
            ring.lineWidth = 1.5 * u
            switch self {
            case .filled(let color):
                color.setFill()
                NSBezierPath(ovalIn: r.insetBy(dx: 1.5 * u, dy: 1.5 * u)).fill()
            case .half(let color):
                color.set()
                ring.stroke()
                let half = NSBezierPath()
                half.move(to: NSPoint(x: c.x, y: c.y + 5.75 * u))
                half.appendArc(withCenter: c, radius: 5.75 * u, startAngle: 90, endAngle: -90, clockwise: true)
                half.close()
                half.fill()
            case .ring(let color):
                color.setStroke()
                ring.stroke()
            case .dashed(let color):
                color.setStroke()
                ring.setLineDash([2.2 * u, 2.2 * u], count: 2, phase: 0)
                ring.stroke()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// `nil` = not loaded / unreachable.
    static func color(_ level: Level?) -> NSColor {
        switch level {
        case nil: return themed(srgb(110, 110, 113), light: (198, 198, 202))
        case .ok: return themed(srgb(41, 178, 75), light: (46, 198, 83))
        case .maintenance: return themed(.systemBlue, light: (0, 104, 240))
        case .degraded: return themed(.systemOrange, light: (245, 128, 0))
        case .outage: return themed(.systemRed, light: (228, 28, 38))
        }
    }

    private static func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }

    /// `dark` on dark appearances; on light ones an sRGB shade with more contrast on white, grey kept pale so it stays apart from the colours.
    private static func themed(_ dark: NSColor, light rgb: (CGFloat, CGFloat, CGFloat)) -> NSColor {
        let light = srgb(rgb.0, rgb.1, rgb.2)
        return NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light }
    }

    /// Menu bar icon: one sector per service, clockwise from 12 o'clock in config order.
    /// Adjacent sectors of one colour are drawn as a single arc, so an all-green bar has no seams.
    /// - Parameter hole: inner radius as a fraction of the outer one; 0 draws a pie, > 0 a donut.
    static func pie(_ levels: [Level?], hole: CGFloat = 0, size: CGFloat = 16) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            let u = r.width / 16
            let c = NSPoint(x: r.midX, y: r.midY)
            let disc = r.insetBy(dx: 1.5 * u, dy: 1.5 * u)
            let outer = disc.width / 2, inner = outer * hole
            let n = levels.count
            guard n > 0, let start = (0..<n).first(where: { levels[$0] != levels[($0 + n - 1) % n] }) else {
                color(levels.first ?? nil).setFill()
                let ring = NSBezierPath(ovalIn: disc)
                if inner > 0 {
                    ring.append(NSBezierPath(ovalIn: NSRect(x: c.x - inner, y: c.y - inner, width: 2 * inner, height: 2 * inner)))
                    ring.windingRule = .evenOdd
                }
                ring.fill()
                return true
            }
            let step = 360 / CGFloat(n)
            var t = 0
            while t < n {
                let level = levels[(start + t) % n]
                var len = 1
                while t + len < n, levels[(start + t + len) % n] == level { len += 1 }
                color(level).setFill()
                let from = 90 - step * CGFloat(start + t), to = 90 - step * CGFloat(start + t + len)
                let sector = NSBezierPath()
                if inner > 0 {
                    sector.appendArc(withCenter: c, radius: outer, startAngle: from, endAngle: to, clockwise: true)
                    sector.appendArc(withCenter: c, radius: inner, startAngle: to, endAngle: from, clockwise: false)
                } else {
                    sector.move(to: c)
                    sector.appendArc(withCenter: c, radius: outer, startAngle: from, endAngle: to, clockwise: true)
                }
                sector.close()
                sector.fill()
                t += len
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Uptime strip: one bar per day, oldest on the left, on a panel of the menu's background colour
    /// so the gaps and frame stay put under the selection highlight. Bars use the icon's colours.
    static let stripBar: CGFloat = 3, stripGap: CGFloat = 1.5, stripFrame: CGFloat = 2

    /// - Parameters:
    ///   - days: `nil` days draw as empty grey bars, the placeholder while nothing is loaded.
    ///   - bar: bar width; `RowView` widens bars so the strip fills its row.
    static func strip(_ days: [Level?], bar: CGFloat = stripBar, height: CGFloat = 14) -> NSImage {
        let gap = stripGap, frame = stripFrame
        let panel = NSRect(x: 0, y: 0, width: CGFloat(days.count) * (bar + gap) - gap + 2 * frame, height: height + 2 * frame)
        let image = NSImage(size: NSSize(width: panel.maxX, height: panel.height), flipped: false) { _ in
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(roundedRect: panel, xRadius: 2.5, yRadius: 2.5).fill()
            for (i, level) in days.enumerated() {
                let r = NSRect(x: panel.minX + frame + CGFloat(i) * (bar + gap), y: frame, width: bar, height: height)
                color(level).setFill()
                NSBezierPath(roundedRect: r, xRadius: 0.75, yRadius: 0.75).fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}

/// A menu row drawn by hand: a title line and, for services, the uptime strip with one tooltip per bar
/// (a menu item has a single tooltip). It draws its own selection and sends the item's action on click,
/// optionally leaving the menu open.
final class RowView: NSView, NSViewToolTipOwner {
    /// Left edge of native item titles in a menu without a state column.
    static let textX: CGFloat = 16
    private static let gap: CGFloat = 3
    private static let percentFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
    /// Space between the strip and the widest percentage.
    private static let percentGap: CGFloat = 8

    private let title: (_ highlighted: Bool) -> NSAttributedString
    private let strip: NSImage?
    private let percent: String?
    private let stripX: CGFloat
    private let rightEdge: CGFloat
    private let top: CGFloat
    private let closesMenu: Bool
    private var tips: [NSView.ToolTipTag: String] = [:]

    /// - Parameters:
    ///   - days: strip bars, oldest first; `nil` for a single-line row.
    ///   - percent: shown right of the strip.
    ///   - lead: strip offset from the title's left edge, to align it with the service name.
    ///   - dayTips: one tooltip per strip bar, oldest first.
    ///   - tip: tooltip for the rest of the row.
    ///   - rightEdge: where the percentage ends, in view coordinates; the strip stretches up to it.
    ///   - closesMenu: `false` keeps the menu open after the click.
    init(title: @escaping (Bool) -> NSAttributedString, days: [Level?]?, percent: String? = nil, lead: CGFloat = 0,
         dayTips: [String] = [], tip: String? = nil, rightEdge: CGFloat, width: CGFloat, closesMenu: Bool = true) {
        self.title = title
        self.percent = percent
        self.rightEdge = rightEdge
        self.closesMenu = closesMenu
        stripX = Self.textX + lead
        // Every row reserves the widest percentage, so all strips end at the same x.
        let widest = ceil(NSAttributedString(string: "100.00 %", attributes: [.font: Self.percentFont]).size().width)
        let span = rightEdge - widest - Self.percentGap - stripX - 2 * Glyph.stripFrame + Glyph.stripGap
        let bar = days.map { max(Glyph.stripBar, span / CGFloat(max($0.count, 1)) - Glyph.stripGap) } ?? Glyph.stripBar
        strip = days.map { Glyph.strip($0, bar: bar) }
        let line = ceil(title(false).size().height)
        top = strip == nil ? 3 : 4
        let height = top + line + (strip.map { Self.gap + $0.size.height + 5 } ?? 3)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        autoresizingMask = [.width]
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel(title(false).string)

        let stripY = top + line + Self.gap
        addTip(NSRect(x: 0, y: 0, width: width, height: stripY), tip)
        if let strip {
            for (i, text) in dayTips.enumerated() {
                let x = stripX + Glyph.stripFrame + CGFloat(i) * (bar + Glyph.stripGap) - Glyph.stripGap / 2
                addTip(NSRect(x: x, y: stripY, width: bar + Glyph.stripGap, height: strip.size.height), text)
            }
            addTip(NSRect(x: stripX + strip.size.width, y: stripY, width: width, height: height - stripY), tip)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func addTip(_ rect: NSRect, _ text: String?) {
        guard let text else { return }
        tips[addToolTip(rect, owner: self, userData: nil)] = text
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        tips[tag] ?? ""
    }

    override func draw(_ dirtyRect: NSRect) {
        let highlighted = enclosingMenuItem?.isHighlighted == true
        if highlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 8, yRadius: 8).fill()
        }
        let line = title(highlighted)
        line.draw(at: NSPoint(x: Self.textX, y: top))
        guard let strip else { return }
        let y = top + ceil(line.size().height) + Self.gap
        strip.draw(in: NSRect(origin: NSPoint(x: stripX, y: y), size: strip.size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        guard let percent else { return }
        let text = NSAttributedString(string: percent, attributes: [
            .font: Self.percentFont,
            .foregroundColor: highlighted ? NSColor.selectedMenuItemTextColor : NSColor.secondaryLabelColor,
        ])
        text.draw(at: NSPoint(x: rightEdge - text.size().width, y: y + (strip.size.height - text.size().height) / 2))
    }

    override func mouseUp(with event: NSEvent) {
        guard let item = enclosingMenuItem, let action = item.action else { return }
        if closesMenu { item.menu?.cancelTracking() }
        // After this event: the action may refill the menu, removing this view.
        RunLoop.main.perform(inModes: [.common]) { NSApp.sendAction(action, to: item.target, from: item) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    /// Refilled in place, so an open menu picks up data that arrives while it is shown.
    private let menu = NSMenu()
    private let fetcher = StatusFetcher()
    private var config = Config.default
    private var states: [ServiceState] = []
    private var updatedAt: Date?
    /// Services whose result for the current poll has not arrived yet.
    private var pending = 0
    /// Bumped per poll; a slower, superseded poll's results are dropped.
    private var generation = 0
    /// Right edge of the last rendered menu; kept while services load so their shorter "updating…" titles don't pull it in.
    private var titleEdge: CGFloat = 0
    private var timer: Timer?
    private var settingsWindow: NSWindow?
    #if SPARKLE
    private var updater: SPUStandardUpdaterController?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if SPARKLE
        updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        #endif
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // macOS keys the position by process name + autosaveName; the bundle id keeps dev and release builds apart.
        statusItem.autosaveName = Bundle.main.bundleIdentifier ?? "HealthBar"
        menu.autoenablesItems = false
        menu.showsStateColumn = false
        menu.delegate = self
        statusItem.menu = menu
        setIcon([], label: "loading")
        config = Config.load()
        startTimer()
        refresh()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(refresh), name: NSWorkspace.didWakeNotification, object: nil)
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: TimeInterval(config.refreshSeconds), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll(force: false) }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// From the Settings window. Services keep their data across a reorder; added ones are read at once.
    private func configChanged(_ new: Config) {
        let old = config
        config = new
        if new.refreshSeconds != old.refreshSeconds { startTimer() }
        guard new.services.map(\.url) != old.services.map(\.url) else { return render() }
        let known = Dictionary(zip(old.services.map(\.url), states), uniquingKeysWith: { a, _ in a })
        states = new.services.map { known[$0.url] ?? ServiceState() }
        // Results in flight are indexed by the old list.
        generation += 1
        pending = 0
        poll(force: false)
    }

    /// Launch, wake and the Refresh item drop what is shown and read everything again, details included.
    @objc private func refresh() {
        states = config.services.map { _ in ServiceState() }
        updatedAt = nil
        poll(force: true)
    }

    /// Every service reads its status; details follow per `detailsDue` unless `force`.
    private func poll(force: Bool) {
        if pending > 0 && !force { return }
        generation += 1
        pending = config.services.count
        if pending == 0 { updatedAt = Date() }
        let gen = generation, fetcher = fetcher
        for (i, service) in config.services.enumerated() {
            let before = states[i]
            // Off the main actor, back through the run loop: the main queue is not drained while the menu is open.
            Task.detached {
                let after = await fetcher.poll(service, before, force: force)
                RunLoop.main.perform(inModes: [.common]) {
                    MainActor.assumeIsolated { [weak self] in self?.apply(after, at: i, generation: gen) }
                }
            }
        }
        render()
    }

    /// Each service renders as soon as its own result arrives.
    private func apply(_ state: ServiceState, at i: Int, generation gen: Int) {
        guard gen == generation, i < states.count else { return }
        states[i] = state
        pending -= 1
        if pending == 0 { updatedAt = Date() }
        render()
    }

    private func render() {
        let levels = states.map { try? $0.status?.get().level }
        setIcon(levels, label: updatedAt == nil ? "loading" : "\(IconState(levels: levels))")
        fillMenu()
    }

    private func setIcon(_ levels: [Level?], label: String) {
        guard let button = statusItem.button else { return }
        button.image = Glyph.pie(levels, hole: 0.6)
        // Menu bar managers (Thaw, Ice, Bartender) key items by this label; a changing one reads as a new item.
        button.setAccessibilityLabel("HealthBar")
        button.setAccessibilityValue(label)
        button.toolTip = "HealthBar: \(label)"
    }

    // MARK: Menu

    private func fillMenu() {
        menu.removeAllItems()
        let rows = config.services.enumerated().map { i, service in
            let state = i < states.count ? states[i] : ServiceState()
            return (item: serviceItem(service, state), uptime: state.details?.uptime)
        }
        var right = (rows.compactMap { $0.item.attributedTitle?.size().width }.max() ?? 0) + 20
        if pending > 0 { right = max(right, titleEdge) }
        titleEdge = right
        for row in rows {
            let base = row.item.attributedTitle ?? NSAttributedString()
            let marked = { (highlighted: Bool) -> NSAttributedString in
                let line = highlighted ? Self.whitened(base) : base
                guard let mark = self.linkMark(highlighted ? .selectedMenuItemTextColor : .secondaryLabelColor) else { return line }
                return self.trailing(line, mark, rightEdge: right)
            }
            var tip = row.item.toolTip
            if let uptime = row.uptime {
                let note = "Last \(uptime.days.count) days; uptime of the least available component"
                tip = tip.map { $0 + "\n\n" + note } ?? note
            }
            // Same height loaded or not, so the menu doesn't jump while services fill in.
            row.item.view = RowView(
                title: marked, days: row.uptime?.days.map(\.level) ?? Array(repeating: nil, count: StatusFetcher.historyDays),
                percent: row.uptime.map { String(format: "%.2f %%", $0.percent) },
                lead: 12 + NSAttributedString(string: "  ", attributes: [.font: NSFont.menuFont(ofSize: 0)]).size().width,
                dayTips: row.uptime?.days.map(dayTip) ?? [], tip: tip,
                rightEdge: RowView.textX + right, width: RowView.textX + right + 14)
            menu.addItem(row.item)
        }
        if !config.services.isEmpty { menu.addItem(.separator()) }

        let updated = updatedAt.map { "Updated \(DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short))" }
        menu.addItem(disabled(updated ?? "Updating…"))
        let refresh = withShortcut(action("Refresh", #selector(refresh)), "r", rightEdge: right)
        let refreshTitle = refresh.attributedTitle ?? NSAttributedString()
        // Stays open so the services can be watched refilling.
        refresh.view = RowView(title: { $0 ? Self.whitened(refreshTitle) : refreshTitle }, days: nil,
                               rightEdge: RowView.textX + right, width: RowView.textX + right + 14, closesMenu: false)
        menu.addItem(refresh)
        menu.addItem(.separator())
        // Views: macOS 26 gives items titled "About …" and "Settings…" stock icons, which indent the rows.
        let about = action("About HealthBar", #selector(openAbout))
        let aboutTitle = NSAttributedString(string: about.title, attributes: [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.labelColor])
        about.view = RowView(title: { $0 ? Self.whitened(aboutTitle) : aboutTitle }, days: nil,
                             rightEdge: RowView.textX + right, width: RowView.textX + right + 14)
        menu.addItem(about)
        let settings = withShortcut(action("Settings…", #selector(openSettings)), ",", rightEdge: right)
        let settingsTitle = settings.attributedTitle ?? NSAttributedString()
        settings.view = RowView(title: { $0 ? Self.whitened(settingsTitle) : settingsTitle }, days: nil,
                                rightEdge: RowView.textX + right, width: RowView.textX + right + 14)
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(withShortcut(action("Quit HealthBar", #selector(quit)), "q", rightEdge: right))
    }

    private static func whitened(_ title: NSAttributedString) -> NSAttributedString {
        let white = NSMutableAttributedString(attributedString: title)
        white.addAttribute(.foregroundColor, value: NSColor.selectedMenuItemTextColor, range: NSRange(location: 0, length: white.length))
        return white
    }

    /// The row opens the status page; failure and incidents go to the tooltip.
    private func serviceItem(_ service: ServiceConfig, _ state: ServiceState) -> NSMenuItem {
        let item = open("", state.details?.pageURL ?? service.url)
        switch state.status {
        case nil:
            setTitle(item, "\(service.name) — updating…", Glyph.dashed(Glyph.color(nil)))
        case .failure(let error):
            setTitle(item, "\(service.name) — unreachable", Glyph.dashed(Glyph.color(nil)), color: .secondaryLabelColor)
            item.toolTip = error.localizedDescription
        case .success(let page):
            setTitle(item, "\(service.name) — \(page.description)", Glyph(page.level))
            let incidents = state.details?.incidents ?? []
            if !incidents.isEmpty { item.toolTip = incidents.map { "\($0.name) — \($0.stage)" }.joined(separator: "\n") }
        }
        return item
    }

    /// Shows `⌘<key>` as text; `menuHasKeyEquivalent` handles the key. A real key equivalent, even on a hidden
    /// twin item, makes macOS reserve a shortcut column on every row.
    private func withShortcut(_ item: NSMenuItem, _ key: String, rightEdge: CGFloat) -> NSMenuItem {
        let hint = NSAttributedString(string: "⌘" + key.uppercased(), attributes: [
            .font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.tertiaryLabelColor,
        ])
        let font = NSFont.menuFont(ofSize: 0)
        let title = item.attributedTitle ?? NSAttributedString(string: item.title, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        item.attributedTitle = trailing(title, hint, rightEdge: rightEdge)
        return item
    }

    private func linkMark(_ color: NSColor) -> NSAttributedString? {
        guard let icon = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: "Opens in browser")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [color])))
        else { return nil }
        let mark = NSTextAttachment()
        mark.image = icon
        mark.bounds = NSRect(origin: NSPoint(x: 0, y: (NSFont.menuFont(ofSize: 0).capHeight - icon.size.height) / 2), size: icon.size)
        return NSAttributedString(attachment: mark)
    }

    /// Right-aligns `trailing` at `rightEdge` with a tab stop, in place of macOS's chevron and shortcut columns.
    private func trailing(_ title: NSAttributedString, _ trailing: NSAttributedString, rightEdge: CGFloat) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let line = NSMutableAttributedString(attributedString: title)
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .right, location: rightEdge)]
        line.append(NSAttributedString(string: "\t", attributes: [.font: font]))
        line.append(trailing)
        line.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: line.length))
        return line
    }

    /// Glyph goes into the title, not `NSMenuItem.image`: macOS 27 menus don't draw item images.
    private func setTitle(_ item: NSMenuItem, _ text: String, _ glyph: Glyph, color: NSColor? = nil) {
        let font = NSFont.menuFont(ofSize: 0)
        let dot = NSTextAttachment()
        dot.image = glyph.image(size: 12)
        dot.bounds = NSRect(x: 0, y: (font.capHeight - 12) / 2, width: 12, height: 12)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color ?? .labelColor]
        let title = NSMutableAttributedString(attachment: dot)
        title.append(NSAttributedString(string: "  " + text, attributes: attrs))
        item.title = text
        item.attributedTitle = title
    }

    /// Date, then each affected component with its status and time in it, most severe first.
    private func dayTip(_ day: UptimeDay) -> String {
        let date = DateFormatter()
        date.setLocalizedDateFormatFromTemplate("EEE d MMM")
        let head = date.string(from: day.date)
        if day.outages.isEmpty { return "\(head) — no outages" }
        let span = DateComponentsFormatter()
        span.unitsStyle = .abbreviated
        span.allowedUnits = [.hour, .minute, .second]
        span.maximumUnitCount = 2
        var order: [String] = [], parts: [String: [String]] = [:]
        for o in day.outages {
            if parts[o.component] == nil { order.append(o.component) }
            parts[o.component, default: []].append("\(o.status.replacingOccurrences(of: "_", with: " ")) \(span.string(from: o.seconds) ?? "")")
        }
        let limit = 8
        var lines = order.prefix(limit).map { "\($0) — \(parts[$0]!.joined(separator: ", "))" }
        if order.count > limit { lines.append("+\(order.count - limit) more") }
        return ([head] + lines).joined(separator: "\n")
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    private func open(_ title: String, _ url: URL) -> NSMenuItem {
        let item = action(title, #selector(openURL(_:)))
        item.representedObject = url
        return item
    }

    // MARK: Actions

    @objc private func openURL(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.open(url) }
    }

    /// Not `NSApplication.terminate(_:)` directly: macOS 26 gives items with that action a stock icon, which indents the row.
    @objc private func quit() { NSApp.terminate(nil) }

    /// The standard About panel: icon, name and version from the bundle, copyright from `NSHumanReadableCopyright`.
    @objc private func openAbout() {
        let credits = NSMutableAttributedString(string: "Status of the services you depend on, in the menu bar.\n\n", attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor,
        ])
        let slug = (Bundle.main.object(forInfoDictionaryKey: "HBRepoSlug") as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "vladforfutdinov/health-bar"
        credits.append(NSAttributedString(string: "github.com/\(slug)", attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .link: URL(string: "https://github.com/\(slug)")!,
        ]))
        credits.append(NSAttributedString(string: "\nMIT License", attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: credits.length))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        bringForward(nil)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let onChange: (Config) -> Void = { [weak self] in self?.configChanged($0) }
            #if SPARKLE
            let model = SettingsModel(config: config, fetcher: fetcher, updater: updater?.updater, onChange: onChange)
            #else
            let model = SettingsModel(config: config, fetcher: fetcher, onChange: onChange)
            #endif
            let window = SettingsWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
            window.title = "HealthBar Settings"
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        bringForward(settingsWindow)
    }

    /// Activates the app and fronts `window` once the status menu has finished closing. Activating while it closes,
    /// or with the cooperative `NSApp.activate()`, left keyboard focus with the previous app.
    private func bringForward(_ window: NSWindow?) {
        RunLoop.main.perform(inModes: [.common]) {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    /// ⌘R, ⌘, and ⌘Q while the menu is open, without items carrying key equivalents (see `withShortcut`).
    nonisolated func menuHasKeyEquivalent(_ menu: NSMenu, for event: NSEvent, target: AutoreleasingUnsafeMutablePointer<AnyObject?>,
                                          action: UnsafeMutablePointer<Selector?>) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else { return false }
        let selector: Selector
        switch event.charactersIgnoringModifiers {
        case "r": selector = #selector(refresh)
        case ",": selector = #selector(openSettings)
        case "q": selector = #selector(quit)
        default: return false
        }
        target.pointee = self
        action.pointee = selector
        return true
    }
}

#if SPARKLE
extension AppDelegate: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                             immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        immediateInstallHandler()
        return true
    }
}
#endif

/// Closes on Escape unless a sheet is open (the sheet's Cancel takes it); caught in `sendEvent` because the
/// services list consumes Escape before `cancelOperation` reaches the window.
final class SettingsWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53, attachedSheet == nil {
            performClose(nil)
            return
        }
        super.sendEvent(event)
    }
}

@main
enum HealthBarApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.mainMenu = editingMainMenu()
        app.run()
    }
}
