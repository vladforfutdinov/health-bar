import AppKit
import SwiftUI
#if SPARKLE
import Sparkle
#endif

enum Glyph {
    case filled(NSColor), half(NSColor), ring(NSColor), dashed(NSColor), dotted(NSColor)

    /// With "Differentiate without color" on, maintenance gets a centre dot so it isn't told from OK by hue alone.
    init(_ level: Level) {
        switch level {
        case .maintenance where NSWorkspace.shared.accessibilityDisplayShouldDifferentiateWithoutColor:
            self = .dotted(Self.color(level))
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
            case .dotted(let color):
                color.setFill()
                NSBezierPath(ovalIn: r.insetBy(dx: 1.5 * u, dy: 1.5 * u)).fill()
                NSColor.white.setFill()
                NSBezierPath(ovalIn: r.insetBy(dx: 6 * u, dy: 6 * u)).fill()
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
    /// - Parameters:
    ///   - hole: inner radius as a fraction of the outer one; 0 draws a pie, > 0 a donut.
    ///   - mark: a character drawn in the hole, for status without colour.
    static func pie(_ levels: [Level?], hole: CGFloat = 0, mark: String? = nil, size: CGFloat = 16) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            let u = r.width / 16
            let c = NSPoint(x: r.midX, y: r.midY)
            let disc = r.insetBy(dx: 1.5 * u, dy: 1.5 * u)
            let outer = disc.width / 2, inner = outer * hole
            func drawMark() {
                guard let mark else { return }
                let text = NSAttributedString(string: mark, attributes: [
                    .font: NSFont.systemFont(ofSize: 7.5 * u, weight: .heavy), .foregroundColor: NSColor.labelColor,
                ])
                let size = text.size()
                text.draw(at: NSPoint(x: c.x - size.width / 2, y: c.y - size.height / 2))
            }
            let n = levels.count
            guard n > 0, let start = (0..<n).first(where: { levels[$0] != levels[($0 + n - 1) % n] }) else {
                color(levels.first ?? nil).setFill()
                let ring = NSBezierPath(ovalIn: disc)
                if inner > 0 {
                    ring.append(NSBezierPath(ovalIn: NSRect(x: c.x - inner, y: c.y - inner, width: 2 * inner, height: 2 * inner)))
                    ring.windingRule = .evenOdd
                }
                ring.fill()
                drawMark()
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
            drawMark()
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Uptime strip: one bar per day, oldest on the left, on a panel of the menu's background colour
    /// so the gaps and frame stay put under the selection highlight. Bars use the icon's colours.
    static let stripBar: CGFloat = 3, stripGap: CGFloat = 1.5, stripFrame: CGFloat = 2, stripHeight: CGFloat = 14

    static func stripSize(count: Int, bar: CGFloat) -> NSSize {
        NSSize(width: CGFloat(count) * (bar + stripGap) - stripGap + 2 * stripFrame, height: stripHeight + 2 * stripFrame)
    }

    /// Draws the strip into the current context, so its colours resolve in the drawing view's appearance;
    /// an `NSImage` drawing handler ran later and cached, and rows scrolled into a dark menu came out light.
    /// - Parameters:
    ///   - days: `nil` days draw as empty grey bars, the placeholder while nothing is loaded.
    ///   - bar: bar width; `RowView` widens bars so the strip fills its row.
    ///   - alpha: bar opacity, for the faint strip under "No uptime history".
    static func drawStrip(_ days: [Level?], at origin: NSPoint, bar: CGFloat, alpha: CGFloat = 1) {
        let panel = NSRect(origin: origin, size: stripSize(count: days.count, bar: bar))
        NSColor.windowBackgroundColor.withAlphaComponent(alpha).setFill()
        NSBezierPath(roundedRect: panel, xRadius: 2.5, yRadius: 2.5).fill()
        for (i, level) in days.enumerated() {
            let r = NSRect(x: panel.minX + stripFrame + CGFloat(i) * (bar + stripGap), y: panel.minY + stripFrame, width: bar, height: stripHeight)
            color(level).withAlphaComponent(alpha).setFill()
            NSBezierPath(roundedRect: r, xRadius: 0.75, yRadius: 0.75).fill()
        }
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
    private let days: [Level?]?
    private let bar: CGFloat
    private let stripSize: NSSize?
    private let percent: String?
    private let stripX: CGFloat
    private let rightEdge: CGFloat
    private let top: CGFloat
    private let closesMenu: Bool
    private let note: String?
    private let stripText: String?
    /// Height that shows the title and the top edge of the strip: how much of a cut-off row a list shows.
    let peekHeight: CGFloat
    private var tips: [NSView.ToolTipTag: () -> String] = [:]
    private static let noteFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    private static let widestPercent = ceil(NSAttributedString(string: percentText(100), attributes: [.font: percentFont]).size().width)

    /// Uptime as the user's locale writes a percentage, two decimals.
    static func percentText(_ percent: Double) -> String {
        (percent / 100).formatted(.percent.precision(.fractionLength(2)))
    }

    /// - Parameters:
    ///   - days: strip bars, oldest first; `nil` for a single-line row.
    ///   - percent: shown right of the strip.
    ///   - lead: strip offset from the title's left edge, to align it with the service name.
    ///   - dayTip: the tooltip for strip bar `i` (oldest first), built when it is shown.
    ///   - tip: tooltip for the rest of the row.
    ///   - rightEdge: where the percentage ends, in view coordinates; the strip stretches up to it.
    ///   - closesMenu: `false` keeps the menu open after the click.
    ///   - note: a third line under the strip (an incident or the fetch error), truncated to the row.
    ///   - label: what VoiceOver reads; defaults to the title's text.
    ///   - stripText: drawn in the strip's place instead of its bars, e.g. when the page publishes no history.
    init(title: @escaping (Bool) -> NSAttributedString, days: [Level?]?, percent: String? = nil, lead: CGFloat = 0,
         dayTip: ((Int) -> String)? = nil, tip: String? = nil, rightEdge: CGFloat, width: CGFloat, closesMenu: Bool = true,
         note: String? = nil, label: String? = nil, stripText: String? = nil) {
        self.title = title
        self.stripText = stripText
        self.percent = percent
        self.note = note
        self.rightEdge = rightEdge
        self.closesMenu = closesMenu
        stripX = Self.textX + lead
        // Every row reserves the widest percentage, so all strips end at the same x.
        let span = rightEdge - Self.widestPercent - Self.percentGap - stripX - 2 * Glyph.stripFrame + Glyph.stripGap
        let bar = days.map { max(Glyph.stripBar, span / CGFloat(max($0.count, 1)) - Glyph.stripGap) } ?? Glyph.stripBar
        self.days = days
        self.bar = bar
        let strip = days.map { Glyph.stripSize(count: $0.count, bar: bar) }
        stripSize = strip
        let line = ceil(title(false).size().height)
        top = strip == nil ? 3 : 4
        let noteHeight = note == nil ? 0 : 2 + ceil(Self.noteFont.ascender - Self.noteFont.descender + Self.noteFont.leading)
        let height = top + line + (strip.map { Self.gap + $0.height + noteHeight + 5 } ?? 3)
        peekHeight = top + line + Self.gap + (strip.map { $0.height * 0.4 } ?? 0)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        autoresizingMask = [.width]
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel(label ?? title(false).string.replacingOccurrences(of: "\u{FFFC}", with: "").replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespaces))

        let stripY = top + line + Self.gap
        let rowTip = tip.map { text in { text } }
        addTip(NSRect(x: 0, y: 0, width: width, height: stripY), rowTip)
        if let strip, let days {
            if let dayTip {
                for i in days.indices {
                    let x = stripX + Glyph.stripFrame + CGFloat(i) * (bar + Glyph.stripGap) - Glyph.stripGap / 2
                    addTip(NSRect(x: x, y: stripY, width: bar + Glyph.stripGap, height: strip.height)) { dayTip(i) }
                }
            }
            addTip(NSRect(x: stripX + strip.width, y: stripY, width: width, height: height - stripY), rowTip)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func addTip(_ rect: NSRect, _ text: (() -> String)?) {
        guard let text else { return }
        tips[addToolTip(rect, owner: self, userData: nil)] = text
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        tips[tag]?() ?? ""
    }

    /// Set for a row inside `ServiceListView`: clicking runs it, and `hovered` (set by the list) drives the
    /// highlight, since the enclosing menu item is the whole list.
    var onClick: (() -> Void)?
    var hovered = false {
        didSet { if hovered != oldValue { needsDisplay = true } }
    }

    override func draw(_ dirtyRect: NSRect) {
        let highlighted = onClick == nil ? enclosingMenuItem?.isHighlighted == true : hovered
        if highlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 8, yRadius: 8).fill()
        }
        let line = title(highlighted)
        line.draw(at: NSPoint(x: Self.textX, y: top))
        guard let days, let strip = stripSize else { return }
        let y = top + ceil(line.size().height) + Self.gap
        let secondary = highlighted ? NSColor.selectedMenuItemTextColor : NSColor.secondaryLabelColor
        Glyph.drawStrip(days, at: NSPoint(x: stripX, y: y), bar: bar, alpha: stripText == nil ? 1 : 0.25)
        if let stripText {
            let text = NSAttributedString(string: stripText, attributes: [.font: Self.noteFont, .foregroundColor: secondary])
            text.draw(at: NSPoint(x: stripX + 6, y: y + (strip.height - text.size().height) / 2))
        }
        if let note {
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byTruncatingTail
            NSAttributedString(string: note, attributes: [.font: Self.noteFont, .foregroundColor: secondary, .paragraphStyle: style])
                .draw(in: NSRect(x: stripX, y: y + strip.height + 2, width: rightEdge - stripX, height: bounds.height - y - strip.height))
        }
        guard let percent else { return }
        let text = NSAttributedString(string: percent, attributes: [.font: Self.percentFont, .foregroundColor: secondary])
        text.draw(at: NSPoint(x: rightEdge - text.size().width, y: y + (strip.height - text.size().height) / 2))
    }

    override func accessibilityPerformPress() -> Bool { press() }

    override func mouseUp(with event: NSEvent) { _ = press() }

    /// Runs `onClick`, or sends the menu item's action; after this event, since the action may refill the menu.
    private func press() -> Bool {
        if let onClick {
            enclosingMenuItem?.menu?.cancelTracking()
            RunLoop.main.perform(inModes: [.common], block: onClick)
            return true
        }
        guard let item = enclosingMenuItem, let action = item.action else { return false }
        if closesMenu { item.menu?.cancelTracking() }
        RunLoop.main.perform(inModes: [.common]) { NSApp.sendAction(action, to: item.target, from: item) }
        return true
    }
}

/// The services in the menu: `RowView`s stacked in a scroll view showing at most `visibleRows` of them.
final class ServiceListView: NSView {
    var onScroll: ((CGFloat) -> Void)?
    private let scrollView = NSScrollView()
    private let rows: [RowView]

    init(rows: [RowView], visibleRows: Int, scroll: CGFloat) {
        let width = rows.map(\.frame.width).max() ?? 0
        let content = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: rows.reduce(0) { $0 + $1.frame.height }))
        var y: CGFloat = 0
        for row in rows {
            row.frame = NSRect(x: 0, y: y, width: width, height: row.frame.height)
            row.autoresizingMask = [.width]
            content.addSubview(row)
            y += row.frame.height
        }
        // The next row's title and the edge of its strip peek out, so the list reads as scrollable.
        let overflow = rows.count > visibleRows
        let visible = rows.prefix(visibleRows).reduce(0) { $0 + $1.frame.height } + (overflow ? rows[visibleRows].peekHeight : 0)
        self.rows = rows
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: visible))
        autoresizingMask = [.width]
        scrollView.frame = bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = false
        // The standard overlay scroller: appears while scrolling, over the rows' right padding.
        scrollView.hasVerticalScroller = overflow
        // No rubber-band bounce when everything fits.
        scrollView.verticalScrollElasticity = overflow ? .automatic : .none
        scrollView.horizontalScrollElasticity = .none
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.documentView = content
        // The scroller takes width from the visible area; content as wide as before would scroll sideways.
        content.setFrameSize(NSSize(width: scrollView.contentSize.width, height: content.frame.height))
        content.autoresizingMask = [.width]
        addSubview(scrollView)
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(scroll, max(0, content.frame.height - visible))))
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Visible rows repaint on every scroll step: pieces copied from earlier frames came out in a lighter shade
    /// in a dark menu (macOS 27) until a full redraw.
    @objc private func scrolled() {
        onScroll?(scrollView.contentView.bounds.origin.y)
        updateHover()
        let visible = scrollView.contentView.bounds
        for row in rows where row.frame.intersects(visible) { row.needsDisplay = true }
    }

    override func mouseMoved(with event: NSEvent) { updateHover() }
    override func mouseEntered(with event: NSEvent) { updateHover() }
    override func mouseExited(with event: NSEvent) { clearHighlight() }

    /// One owner for the highlight: rows scrolling under a still pointer get no enter/exit events of their own.
    private func updateHover() {
        guard let window, let content = scrollView.documentView else { return }
        let inside = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        let point = content.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        for row in rows { row.hovered = inside && row.frame.contains(point) }
    }

    func clearHighlight() {
        rows.forEach { $0.hovered = false }
    }
}

/// Top-left origin, so rows stack downwards from the top of a scroll view.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
    /// Responsive scrolling pre-renders rows beyond the visible edge, and in a dark menu on macOS 27 that
    /// content came out in the light palette until redrawn.
    override class var isCompatibleWithResponsiveScrolling: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    /// Refilled in place, so an open menu picks up data that arrives while it is shown.
    private let menu = NSMenu()
    private let fetcher = StatusFetcher()
    private var config = Config.default
    /// Last result per service, by address: results are matched to services by URL, never by position.
    private var states: [URL: ServiceState] = [:]
    private var updatedAt: Date?
    /// Requests started and not answered; a timer poll skips these and reads the rest.
    private var inFlight: [URL: Int] = [:]
    /// Bumped per request; an answer counts only if no later request for its service was started.
    private var requestID = 0
    /// The menu is rebuilt only while open, or when it opens after something changed.
    private var menuOpen = false
    private var menuStale = true
    /// Right edge of the last rendered menu; kept while services load so their shorter "updating…" titles don't pull it in.
    private var titleEdge: CGFloat = 0
    /// Scroll offset of the services list, carried across menu refills.
    private var listScroll: CGFloat = 0
    private weak var serviceList: ServiceListView?
    /// Services shown at once in the menu; more scroll.
    private static let visibleServices = 8
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
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(displayOptionsChanged), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
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
        let urls = Set(new.services.map(\.url))
        states = states.filter { urls.contains($0.key) }
        inFlight = inFlight.filter { urls.contains($0.key) }
        poll(new.services.filter { states[$0.url] == nil }, force: false)
    }

    @objc private func displayOptionsChanged() { render() }

    /// Launch, wake and the Refresh item drop what is shown and read everything again, details included.
    @objc private func refresh() {
        states = [:]
        updatedAt = nil
        poll(config.services, force: true)
    }

    private func poll(force: Bool) {
        poll(config.services.filter { inFlight[$0.url] == nil }, force: force)
    }

    /// Each of `services` reads its status, details following per `detailsDue` unless `force`; a request already in
    /// flight for one of them is superseded.
    private func poll(_ services: [ServiceConfig], force: Bool) {
        let fetcher = fetcher
        for service in services {
            requestID += 1
            let id = requestID, url = service.url, before = states[url] ?? ServiceState()
            inFlight[url] = id
            // Off the main actor, back through the run loop: the main queue is not drained while the menu is open.
            Task.detached {
                let after = await fetcher.poll(service, before, force: force)
                RunLoop.main.perform(inModes: [.common]) {
                    MainActor.assumeIsolated { [weak self] in self?.apply(after, for: url, request: id) }
                }
            }
        }
        if inFlight.isEmpty { updatedAt = Date() }
        render()
    }

    /// Each service renders as soon as its own result arrives.
    private func apply(_ state: ServiceState, for url: URL, request id: Int) {
        guard inFlight[url] == id else { return }
        inFlight[url] = nil
        states[url] = state
        if inFlight.isEmpty { updatedAt = Date() }
        render()
    }

    private func render() {
        let levels = config.services.map { try? states[$0.url]?.status?.get().level }
        setIcon(levels, label: summary(levels))
        if menuOpen { fillMenu() } else { menuStale = true }
    }

    /// The icon's state as a sentence, for VoiceOver and the tooltip.
    private func summary(_ levels: [Level?]) -> String {
        guard updatedAt != nil else { return "Loading" }
        guard !levels.isEmpty else { return "No services" }
        // Unreachable services (nil) count as problems too.
        let names = zip(config.services, levels).filter { $0.1 != .ok }.map(\.0.name)
        let total = String(AttributedString(localized: "^[\(levels.count) service](inflect: true)").characters)
        if names.isEmpty { return "All \(total) operational" }
        return "\(names.count) of \(total) with problems: " + names.prefix(3).joined(separator: ", ") + (names.count > 3 ? "…" : "")
    }

    private func setIcon(_ levels: [Level?], label: String) {
        guard let button = statusItem.button else { return }
        var mark: String?
        if NSWorkspace.shared.accessibilityDisplayShouldDifferentiateWithoutColor {
            switch levels.compactMap({ $0 }).max() {
            case .outage: mark = "!"
            case .degraded: mark = "~"
            default: mark = nil
            }
        }
        button.image = Glyph.pie(iconSectors(levels), hole: 0.6, mark: mark)
        // Menu bar managers (Thaw, Ice, Bartender) key items by this label; a changing one reads as a new item.
        button.setAccessibilityLabel("HealthBar")
        button.setAccessibilityValue(label)
        button.toolTip = "HealthBar: \(label)"
    }

    // MARK: Menu

    private func fillMenu() {
        menu.removeAllItems()
        menuStale = false
        let rows = config.services.map { service in
            let state = states[service.url] ?? ServiceState()
            return (head: serviceHead(service, state), uptime: state.details?.uptime, service: service, state: state)
        }
        var right = (rows.map { $0.head.title.size().width }.max() ?? 0) + 20
        if !inFlight.isEmpty { right = max(right, titleEdge) }
        titleEdge = right
        var serviceRows: [RowView] = []
        for row in rows {
            // Both versions built once per refill, not on every draw (rows redraw on each scroll step).
            let plain = trailing(row.head.title, Self.linkMarks.plain, rightEdge: right)
            let lit = trailing(Self.whitened(row.head.title), Self.linkMarks.highlighted, rightEdge: right)
            let marked = { (highlighted: Bool) in highlighted ? lit : plain }
            var tip = row.head.tip
            if let uptime = row.uptime {
                let note = "Last \(uptime.days.count) days; uptime of the least available component"
                tip = tip.map { $0 + "\n\n" + note } ?? note
            }
            // Same height loaded or not, so the menu doesn't jump while services fill in.
            let view = RowView(
                title: marked, days: row.uptime?.days.map(\.level) ?? Array(repeating: nil, count: StatusFetcher.historyDays),
                percent: row.uptime.map { RowView.percentText($0.percent) },
                lead: 12 + NSAttributedString(string: "  ", attributes: [.font: NSFont.menuFont(ofSize: 0)]).size().width,
                dayTip: row.uptime.map { uptime in { Self.dayTip(uptime.days[$0]) } }, tip: tip,
                rightEdge: RowView.textX + right, width: right + 2 * RowView.textX,
                note: Self.note(row.state), label: Self.spoken(row.service, row.state),
                // Read, but the page publishes no per-day history (uptime display off, or the feed refused).
                stripText: row.state.details != nil && row.uptime == nil ? "No uptime history" : nil)
            let url = row.head.url
            view.onClick = { NSWorkspace.shared.open(url) }
            serviceRows.append(view)
        }
        if !serviceRows.isEmpty {
            // One item holding all services, so they scroll inside the menu; a refill keeps the scroll position.
            let list = ServiceListView(rows: serviceRows, visibleRows: Self.visibleServices, scroll: listScroll)
            serviceList = list
            list.onScroll = { [weak self] in self?.listScroll = $0 }
            let item = NSMenuItem()
            item.view = list
            menu.addItem(item)

            menu.addItem(.separator())
        }

        let updated = updatedAt.map { "Updated \(DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short))" }
        menu.addItem(disabled(updated ?? "Updating…"))
        // Stays open so the services can be watched refilling.
        menu.addItem(row(action("Refresh", #selector(refresh)), key: "r", rightEdge: right, closesMenu: false))
        menu.addItem(.separator())
        menu.addItem(row(action("About HealthBar", #selector(openAbout)), rightEdge: right))
        #if SPARKLE
        menu.addItem(row(action("Check for Updates…", #selector(checkForUpdates)), rightEdge: right))
        #endif
        menu.addItem(row(action("Settings…", #selector(openSettings)), key: ",", rightEdge: right))
        menu.addItem(.separator())
        menu.addItem(row(action("Quit HealthBar", #selector(quit)), key: "q", rightEdge: right))
    }

    /// Third line of a service row: the first active incident (and how many more), or why it couldn't be read.
    private static func note(_ state: ServiceState) -> String? {
        switch state.status {
        case .failure(let error): return error.localizedDescription
        case .success:
            guard let incidents = state.details?.incidents, let first = incidents.first else { return nil }
            return "\(first.name) — \(first.stage)" + (incidents.count > 1 ? "  +\(incidents.count - 1) more" : "")
        case nil: return nil
        }
    }

    /// What VoiceOver reads for a service row.
    private static func spoken(_ service: ServiceConfig, _ state: ServiceState) -> String {
        var parts = [service.name]
        switch state.status {
        case nil: parts.append("updating")
        case .failure: parts.append("unreachable")
        case .success(let page): parts.append(page.description)
        }
        if let uptime = state.details?.uptime { parts.append("\(RowView.percentText(uptime.percent)) uptime over \(uptime.days.count) days") }
        if let note = note(state) { parts.append(note) }
        return parts.joined(separator: ", ")
    }

    private static func whitened(_ title: NSAttributedString) -> NSAttributedString {
        let white = NSMutableAttributedString(attributedString: title)
        white.addAttribute(.foregroundColor, value: NSColor.selectedMenuItemTextColor, range: NSRange(location: 0, length: white.length))
        return white
    }

    /// A service row's first line, its tooltip (the failure, or every active incident) and the page it opens.
    private func serviceHead(_ service: ServiceConfig, _ state: ServiceState) -> (title: NSAttributedString, tip: String?, url: URL) {
        let url = state.details?.pageURL ?? service.url
        switch state.status {
        case nil:
            return (titled("\(service.name) — updating…", Glyph.dashed(Glyph.color(nil))), nil, url)
        case .failure(let error):
            return (titled("\(service.name) — unreachable", Glyph.dashed(Glyph.color(nil)), color: .secondaryLabelColor), error.localizedDescription, url)
        case .success(let page):
            let incidents = state.details?.incidents ?? []
            let tip = incidents.isEmpty ? nil : incidents.map { "\($0.name) — \($0.stage)" }.joined(separator: "\n")
            return (titled("\(service.name) — \(page.description)", Glyph(page.level)), tip, url)
        }
    }

    /// Draws `item` as a `RowView` with `⌘<key>` right-aligned at `rightEdge`; the key itself is handled by a hidden
    /// twin item. A visible key equivalent adds a shortcut column to every row, and macOS 26 adds stock icons to
    /// standard items titled "About …", "Settings…" or "Quit …".
    private func row(_ item: NSMenuItem, key: String? = nil, rightEdge: CGFloat, closesMenu: Bool = true) -> NSMenuItem {
        let font = NSFont.menuFont(ofSize: 0)
        var title = NSAttributedString(string: item.title, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        if let key {
            // The key lives on a hidden, untitled twin: a menu doesn't send key equivalents to view items.
            let twin = NSMenuItem(title: "", action: item.action, keyEquivalent: key)
            twin.target = item.target
            twin.isHidden = true
            twin.allowsKeyEquivalentWhenHidden = true
            menu.addItem(twin)
            title = trailing(title, NSAttributedString(string: "⌘" + key.uppercased(), attributes: [
                .font: font, .foregroundColor: NSColor.tertiaryLabelColor,
            ]), rightEdge: rightEdge)
        }
        let line = title
        item.view = RowView(title: { $0 ? Self.whitened(line) : line }, days: nil,
                            rightEdge: RowView.textX + rightEdge, width: rightEdge + 2 * RowView.textX, closesMenu: closesMenu)
        return item
    }

    /// The external-link mark after a service's title, plain and on the selection highlight.
    private static let linkMarks = (plain: linkMark(.secondaryLabelColor), highlighted: linkMark(.selectedMenuItemTextColor))

    private static func linkMark(_ color: NSColor) -> NSAttributedString {
        guard let icon = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: "Opens in browser")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [color])))
        else { return NSAttributedString() }
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

    /// The status glyph and text of a row; the glyph is an attachment because macOS 27 menus don't draw item images.
    private func titled(_ text: String, _ glyph: Glyph, color: NSColor? = nil) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let dot = NSTextAttachment()
        dot.image = glyph.image(size: 12)
        dot.bounds = NSRect(x: 0, y: (font.capHeight - 12) / 2, width: 12, height: 12)
        let title = NSMutableAttributedString(attachment: dot)
        title.append(NSAttributedString(string: "  " + text, attributes: [.font: font, .foregroundColor: color ?? .labelColor]))
        return title
    }

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f
    }()

    private static let spanFormat: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.unitsStyle = .abbreviated
        f.allowedUnits = [.hour, .minute, .second]
        f.maximumUnitCount = 2
        return f
    }()

    /// Date, then each affected component with its status and time in it, most severe first. Built on hover.
    private static func dayTip(_ day: UptimeDay) -> String {
        let head = dayFormat.string(from: day.date)
        if day.outages.isEmpty { return "\(head) — no outages" }
        let span = spanFormat
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

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: Actions

    #if SPARKLE
    @objc private func checkForUpdates() { updater?.checkForUpdates(nil) }
    #endif

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
        var options: [NSApplication.AboutPanelOptionKey: Any] = [.credits: credits]
        // The bundle's own icon: the system's copy of a legacy .icns is shrunk into a frame on macOS 26 and reads blurry.
        if let icon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap(NSImage.init(contentsOf:)) {
            options[.applicationIcon] = icon
        }
        NSApp.orderFrontStandardAboutPanel(options: options)
        bringForward(nil)
    }

    /// Settings window content size: the width, and the least height (also the SwiftUI frame's).
    static let settingsSize = NSSize(width: 480, height: 570)

    @objc private func openSettings() {
        if settingsWindow == nil {
            let onChange: (Config) -> Void = { [weak self] in self?.configChanged($0) }
            let model = SettingsModel(config: config, fetcher: fetcher, onChange: onChange)
            #if SPARKLE
            model.updater = updater?.updater
            #endif
            let window = SettingsWindow(contentRect: .zero, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            let hosting = NSHostingController(rootView: SettingsView(model: model))
            // Only the height changes (the list grows); the width is fixed and the default height is the least.
            // SwiftUI's frame (fixed width, least height, unbounded height) becomes the window's min and max size.
            hosting.sizingOptions = [.minSize, .maxSize]
            window.contentViewController = hosting
            window.standardWindowButton(.zoomButton)?.isEnabled = false
            window.collectionBehavior.insert(.fullScreenNone)
            window.title = "HealthBar Settings"
            window.isReleasedWhenClosed = false
            // Reopens where it was last closed (centred the first time), clamped to the allowed size.
            let restored = window.setFrameUsingName("Settings")
            let height = max(Self.settingsSize.height, restored ? window.contentRect(forFrameRect: window.frame).height : 0)
            window.setContentSize(NSSize(width: Self.settingsSize.width, height: height))
            if !restored { window.center() }
            window.setFrameAutosaveName("Settings")
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
    /// Called before the menu opens: it is rebuilt here only if something changed while it was closed.
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menuStale { fillMenu() }
    }

    func menuWillOpen(_ menu: NSMenu) { menuOpen = true }

    func menuDidClose(_ menu: NSMenu) {
        menuOpen = false
        serviceList?.clearHighlight()
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
