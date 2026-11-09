import AppKit
import ServiceManagement
#if SPARKLE
import Sparkle
#endif

enum Glyph {
    case filled(NSColor), half(NSColor), ring(NSColor), dashed(NSColor)

    init(_ state: IconState) {
        switch state {
        case .ok: self = .filled(.systemGreen)
        case .degraded: self = .half(.systemOrange)
        case .outage: self = .ring(.systemRed)
        case .unknown: self = .dashed(.systemGray)
        }
    }

    init(_ level: Level) {
        switch level {
        case .ok: self = .filled(.systemGreen)
        case .maintenance: self = .filled(.systemBlue)
        case .degraded: self = .half(.systemOrange)
        case .outage: self = .ring(.systemRed)
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
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let fetcher = StatusFetcher()
    private var config = Config.default
    private var configError: String?
    private var results: [Result<ServiceStatus, Error>] = []
    private var updatedAt: Date?
    private var refreshTask: Task<Void, Never>?
    private var timer: Timer?
    #if SPARKLE
    private var updater: SPUStandardUpdaterController?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if SPARKLE
        updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        #endif
        setIcon(.unknown, label: "loading")
        loadConfig()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(refresh), name: NSWorkspace.didWakeNotification, object: nil)
    }

    private func loadConfig() {
        do {
            config = try Config.loadOrCreate()
            configError = nil
        } catch {
            configError = error.localizedDescription
        }
        results = []
        timer?.invalidate()
        let t = Timer(timeInterval: TimeInterval(config.refreshSeconds), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        refresh()
    }

    @objc private func refresh() {
        refreshTask?.cancel()
        let services = config.services
        refreshTask = Task {
            let fresh = await fetcher.fetchAll(services)
            guard !Task.isCancelled else { return }
            results = fresh
            updatedAt = Date()
            render()
        }
        render()
    }

    private func render() {
        let levels = results.map { try? $0.get().level }
        let state = results.isEmpty ? IconState.unknown : IconState(levels: levels)
        setIcon(state, label: results.isEmpty ? "loading" : "\(state)")
        statusItem.menu = buildMenu()
    }

    private func setIcon(_ state: IconState, label: String) {
        guard let button = statusItem.button else { return }
        button.image = Glyph(state).image()
        button.setAccessibilityLabel("HealthBar: \(label)")
        button.toolTip = "HealthBar"
    }

    // MARK: Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (i, service) in config.services.enumerated() {
            menu.addItem(serviceItem(service, result: i < results.count ? results[i] : nil))
        }
        if !config.services.isEmpty { menu.addItem(.separator()) }

        let updated = updatedAt.map { "Updated \(DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short))" }
        menu.addItem(disabled(refreshTask != nil && results.isEmpty ? "Updating…" : updated ?? "Updating…"))
        if let configError { menu.addItem(disabled("Config error: \(configError)")) }
        menu.addItem(action("Refresh", #selector(refresh), key: "r"))
        menu.addItem(.separator())
        menu.addItem(action("Edit Config…", #selector(editConfig)))
        menu.addItem(action("Reload Config", #selector(reloadConfig)))
        let login = action("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        #if SPARKLE
        menu.addItem(action("Check for Updates…", #selector(checkForUpdates)))
        #endif
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit HealthBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    private func serviceItem(_ service: ServiceConfig, result: Result<ServiceStatus, Error>?) -> NSMenuItem {
        let item = NSMenuItem(title: service.name, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.autoenablesItems = false
        item.submenu = sub

        switch result {
        case nil:
            item.title = "\(service.name) — updating…"
            item.image = Glyph(.unknown).image(size: 12)
            sub.addItem(open("Open Status Page", service.url))
        case .failure(let error):
            item.attributedTitle = NSAttributedString(
                string: "\(service.name) — unreachable",
                attributes: [.foregroundColor: NSColor.secondaryLabelColor])
            item.image = Glyph(.unknown).image(size: 12)
            sub.addItem(disabled(error.localizedDescription))
            sub.addItem(.separator())
            sub.addItem(open("Open Status Page", service.url))
        case .success(let status):
            item.title = "\(service.name) — \(status.description)"
            item.image = Glyph(status.level).image(size: 12)
            for incident in status.incidents {
                let row = open("\(incident.name) — \(incident.stage)", incident.url)
                row.image = Glyph(incident.level).image(size: 12)
                row.toolTip = incident.lastUpdate
                sub.addItem(row)
            }
            if !status.incidents.isEmpty { sub.addItem(.separator()) }
            for component in status.items {
                let row = open(componentTitle(component), status.pageURL)
                row.image = Glyph(component.level).image(size: 12)
                sub.addItem(row)
            }
            if !status.items.isEmpty { sub.addItem(.separator()) }
            sub.addItem(open("Open Status Page", status.pageURL))
        }
        return item
    }

    private func componentTitle(_ c: Item) -> String {
        guard c.level != .ok else { return c.name }
        var title = "\(c.name) — \(humanize(c.status))"
        if !c.affected.isEmpty {
            let shown = c.affected.prefix(3).joined(separator: ", ")
            let more = c.affected.count > 3 ? " +\(c.affected.count - 3)" : ""
            title += " (\(shown)\(more))"
        }
        return title
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

    @objc private func editConfig() {
        _ = try? Config.loadOrCreate()
        NSWorkspace.shared.open(Config.fileURL)
    }

    @objc private func reloadConfig() {
        loadConfig()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
        }
        render()
    }

    #if SPARKLE
    @objc private func checkForUpdates() {
        updater?.checkForUpdates(nil)
    }
    #endif
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

@main
enum HealthBarApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
