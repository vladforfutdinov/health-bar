import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
#if SPARKLE
import Sparkle
#endif

/// State behind the Settings window. Every config change is saved and handed to `onChange` at once.
@MainActor
final class SettingsModel: ObservableObject {
    @Published var config: Config {
        didSet {
            guard config != oldValue else { return }
            config.save()
            onChange(config)
        }
    }
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var message: String?
    #if SPARKLE
    let updater: SPUUpdater?
    #endif
    private let fetcher: StatusFetcher
    private let onChange: (Config) -> Void

    #if SPARKLE
    init(config: Config, fetcher: StatusFetcher, updater: SPUUpdater?, onChange: @escaping (Config) -> Void) {
        self.config = config
        self.fetcher = fetcher
        self.updater = updater
        self.onChange = onChange
    }
    #else
    init(config: Config, fetcher: StatusFetcher, onChange: @escaping (Config) -> Void) {
        self.config = config
        self.fetcher = fetcher
        self.onChange = onChange
    }
    #endif

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            message = nil
        } catch {
            message = "Launch at Login: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// `true` when `text` is an address whose `status.json` answers 200, `false` when not, `nil` when it is no address.
    func probe(_ text: String) async -> Bool? {
        guard let url = ServiceConfig.pageURL(from: text) else { return nil }
        return await fetcher.answers(url)
    }

    /// Adds or updates a service from the service sheet. A new or changed address must answer `status.json`;
    /// an empty name takes the page's own.
    /// - Returns: why it was refused, or `nil` once saved.
    func save(_ draft: ServiceDraft) async -> String? {
        guard let url = ServiceConfig.pageURL(from: draft.address) else { return "Not a web address." }
        if url != draft.original, config.contains(url) { return "\(url.host ?? "") is already in the list." }
        var pageName: String?
        if url != draft.original {
            do {
                pageName = try await fetcher.pageName(url)
            } catch is DecodingError, FetchError.http(404) {
                return "\(url.host ?? "") is not a Statuspage or incident.io status page."
            } catch {
                return "\(url.host ?? ""): \(error.localizedDescription)"
            }
        }
        // The config may have changed while the page was being read.
        if url != draft.original, config.contains(url) { return "\(url.host ?? "") is already in the list." }
        if let original = draft.original, !config.contains(original) { return "This service was deleted meanwhile." }
        let typed = draft.name.trimmingCharacters(in: .whitespaces)
        let name = typed.isEmpty ? (pageName ?? url.host ?? url.absoluteString) : typed
        var c = config
        if let original = draft.original, let old = (c.ungrouped + c.groups.flatMap(\.services)).first(where: { $0.url == original }) {
            c.replace(original, with: ServiceConfig(name: name, url: url, enabled: old.enabled), inGroup: draft.group)
        } else {
            c.add(ServiceConfig(name: name, url: url), toGroup: draft.group)
        }
        config = c
        return nil
    }

    func newGroup(named name: String) -> String {
        config.addGroup(named: name)
    }

    func renameGroup(_ id: String, to name: String) {
        guard let g = config.groups.firstIndex(where: { $0.id == id }) else { return }
        config.groups[g].name = name
    }

    /// Why `name` can't be used for the group `id` (`nil` for a new one): empty, or taken. `nil` if it can.
    func nameProblem(_ name: String, for id: String?) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "" }
        if config.groups.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return "A group with this name already exists."
        }
        return nil
    }
}

/// What the service sheet edits; `original` is the address of the service being edited, `nil` for a new one.
struct ServiceDraft: Identifiable {
    var original: URL?
    var address: String
    var name: String
    var group: String
    var id: String { original?.absoluteString ?? "new" }
}

/// What the group sheet edits: `group` is the one being edited, `nil` for a new one.
private struct GroupDraft: Identifiable {
    var group: ServiceGroup?
    var id: String { group?.id ?? "new" }
}

/// Where a drag would land: before or after the row `key`.
private struct DropMark: Equatable {
    var key: String
    var after: Bool
}

/// The insertion line's state. `dragging` turns on when a drag enters a row and off at the drop, so the extra
/// `dropUpdated` macOS 26 sends after `performDrop` can't bring the line back.
private struct DropState: Equatable {
    var mark: DropMark?
    var dragging = false
}

/// Drop target over one row: tracks which half the pointer is in for the insertion line, then hands over the payload.
private struct RowDrop: DropDelegate {
    let key: String
    let height: CGFloat
    @Binding var state: DropState
    let perform: (_ payload: String, _ after: Bool) -> Void

    func dropEntered(info: DropInfo) {
        state.dragging = true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if state.dragging { state.mark = DropMark(key: key, after: info.location.y > height / 2) }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if state.mark?.key == key { state.mark = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        let after = info.location.y > height / 2
        state = DropState()
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { item, _ in
            DispatchQueue.main.async {
                if let payload = item as? String { perform(payload, after) }
            }
        }
        return true
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    /// Unfolded group ids; at first those with something enabled.
    @State private var expanded: Set<String>
    @State private var drop = DropState()
    @State private var editingGroup: GroupDraft?
    @State private var editing: ServiceDraft?

    init(model: SettingsModel) {
        self.model = model
        _expanded = State(initialValue: Set(model.config.groups.filter { $0.services.contains(where: \.enabled) }.map(\.id)))
    }

    private var allExpanded: Bool { model.config.groups.allSatisfy { expanded.contains($0.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            services
                .padding(.horizontal, 20)
                .padding(.top, 16)
            Form {
                Section {
                    Picker("Check status every", selection: $model.config.refreshSeconds) {
                        ForEach(Config.refreshChoices, id: \.self) { Text(Self.interval($0)).tag($0) }
                    }
                    Toggle("Launch at Login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                    if let message = model.message {
                        Text(message).foregroundStyle(.red)
                    }
                }

                #if SPARKLE
                if let updater = model.updater {
                    Section("Updates") {
                        Toggle("Check for updates automatically", isOn: Binding(
                            get: { updater.automaticallyChecksForUpdates }, set: { updater.automaticallyChecksForUpdates = $0 }))
                        Toggle("Download and install updates automatically", isOn: Binding(
                            get: { updater.automaticallyDownloadsUpdates }, set: { updater.automaticallyDownloadsUpdates = $0 }))
                        HStack {
                            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Check Now") { updater.checkForUpdates() }
                        }
                    }
                }
                #endif
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 480)
        .sheet(item: $editingGroup) { draft in
            GroupSheet(group: draft.group, problem: { model.nameProblem($0, for: draft.group?.id) }) { name in
                if let id = draft.group?.id {
                    model.renameGroup(id, to: name)
                } else {
                    expanded.insert(model.newGroup(named: name))
                }
            } delete: { keepServices in
                if let id = draft.group?.id { model.config.removeGroup(id, keepingServices: keepServices) }
            }
        }
        .sheet(item: $editing) { draft in
            ServiceSheet(draft: draft, groups: model.config.groups, probe: model.probe) { draft in
                let problem = await model.save(draft)
                if problem == nil { expanded.insert(draft.group) }
                return problem
            } delete: { url in
                model.config.remove(url)
            }
        }
    }

    /// Its own scrolling list: inside a `Form` a `List` is clipped instead of scrolled.
    private var services: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Services").font(.headline)
                Spacer()
                Button(allExpanded ? "Fold all" : "Unfold all") {
                    expanded = allExpanded ? [] : Set(model.config.groups.map(\.id))
                }
                .buttonStyle(.link)
            }
            List {
                ForEach($model.config.ungrouped, id: \.url) { $service in
                    serviceRow($service, in: Config.noGroup)
                }
                ForEach(model.config.groups) { group in
                    DisclosureGroup(isExpanded: Binding(
                        get: { expanded.contains(group.id) },
                        set: { if $0 { expanded.insert(group.id) } else { expanded.remove(group.id) } }
                    )) {
                        ForEach(groupServices(group.id), id: \.wrappedValue.url) { service in
                            serviceRow(service, in: group.id)
                        }
                    } label: {
                        groupHeader(group)
                    }
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: false))
            .frame(height: 320)
            HStack {
                Spacer()
                Button("New Group…") { editingGroup = GroupDraft(group: nil) }
                Button("New Service…") {
                    editing = ServiceDraft(original: nil, address: "", name: "", group: Config.noGroup)
                }
            }
            Text("Any Statuspage or incident.io status page. Drag services and groups by their grip to reorder; services can move between groups. The menu and the icon's sectors follow the order of the checked services.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Bindings to the services of group `id`, looked up by id so a reorder can't point them at another group.
    private func groupServices(_ id: String) -> [Binding<ServiceConfig>] {
        guard let g = model.config.groups.firstIndex(where: { $0.id == id }) else { return [] }
        return model.config.groups[g].services.indices.map { i in
            Binding(get: { model.config.groups[g].services[i] }, set: { model.config.groups[g].services[i] = $0 })
        }
    }

    private func pencil(_ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "pencil") }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(help)
    }

    private func serviceRow(_ service: Binding<ServiceConfig>, in group: String) -> some View {
        let s = service.wrappedValue
        let key = "service:" + s.url.absoluteString
        return HStack {
            Toggle(s.name, isOn: service.enabled).toggleStyle(.checkbox)
            Spacer()
            Text(s.url.host ?? s.url.absoluteString).foregroundStyle(.secondary)
            pencil("Edit \(s.name)") {
                editing = ServiceDraft(original: s.url, address: s.url.absoluteString, name: s.name, group: group)
            }
            Grip()
        }
        .contentShape(Rectangle())
        .draggable(key) { Text(s.name).padding(4) }
        .modifier(DropZone(key: key, state: $drop) { payload, after in
            guard let url = Self.serviceURL(payload) else { return }
            model.config.move(url, to: s.url, after: after)
        })
    }

    private func groupHeader(_ g: ServiceGroup) -> some View {
        let key = "group:" + g.id
        return HStack {
            Text(g.name).fontWeight(.medium)
            Spacer()
            pencil("Edit the group") { editingGroup = GroupDraft(group: g) }
            Grip()
        }
        .contentShape(Rectangle())
        .help("Drag to reorder; drop a service here to move it to the top of this group")
        .draggable(key) { Text(g.name).padding(4) }
        .modifier(DropZone(key: key, state: $drop) { payload, after in
            if let url = Self.serviceURL(payload) {
                model.config.move(url, intoGroup: g.id)
                expanded.insert(g.id)
            } else if payload.hasPrefix("group:") {
                model.config.moveGroup(String(payload.dropFirst(6)), to: g.id, after: after)
            }
        })
    }

    private static func serviceURL(_ payload: String) -> URL? {
        payload.hasPrefix("service:") ? URL(string: String(payload.dropFirst(8))) : nil
    }

    private static func interval(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds) seconds" : seconds == 60 ? "minute" : "\(seconds / 60) minutes"
    }
}

/// Drag handle: two columns of three 2-pt dots on a 4-pt pitch, pixel-aligned; the pointer turns into an open hand over it.
private struct Grip: View {
    var body: some View {
        Canvas { context, _ in
            for x in [0, 4] as [CGFloat] {
                for y in [0, 4, 8] as [CGFloat] {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)), with: .foreground)
                }
            }
        }
        .frame(width: 6, height: 10)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
        }
        .help("Drag to reorder")
    }
}

/// Adds or edits a service: address, name and group. The address is checked when it loses focus.
/// An existing service can be deleted from here.
private struct ServiceSheet: View {
    let groups: [ServiceGroup]
    let probe: (String) async -> Bool?
    let save: (ServiceDraft) async -> String?
    let delete: (URL) -> Void
    private let isNew: Bool
    @State private var draft: ServiceDraft
    /// Result of the check of `draft.address`: `nil` while unknown.
    @State private var answers: Bool?
    @State private var checking = false
    @FocusState private var addressFocused: Bool
    @State private var problem: String?
    @State private var saving = false
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    init(draft: ServiceDraft, groups: [ServiceGroup], probe: @escaping (String) async -> Bool?,
         save: @escaping (ServiceDraft) async -> String?, delete: @escaping (URL) -> Void) {
        self.groups = groups
        self.probe = probe
        self.save = save
        self.delete = delete
        isNew = draft.original == nil
        _draft = State(initialValue: draft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "New Service" : "Edit Service").font(.headline)
            Form {
                TextField("Status page", text: $draft.address, prompt: Text("status.example.com"))
                    .overlay(alignment: .trailing) { addressMark.padding(.trailing, 4) }
                    .focused($addressFocused)
                    .onChange(of: addressFocused) { focused in if !focused { check() } }
                    .onChange(of: draft.address) { _ in
                        answers = nil
                        checking = false
                    }
                    .task { if !isNew { check() } }
                TextField("Name", text: $draft.name, prompt: Text(isNew ? "From the page" : ""))
                Picker("Group", selection: $draft.group) {
                    Text("No group").tag(Config.noGroup)
                    Divider()
                    ForEach(groups) { Text($0.name).tag($0.id) }
                }
            }
            if let problem {
                Text(problem).foregroundStyle(.red).font(.callout)
            }
            HStack {
                if let original = draft.original {
                    Button("Delete…", role: .destructive) { confirmingDelete = true }
                        .disabled(saving)
                        .alert("Delete \(draft.name.isEmpty ? original.host ?? "" : draft.name)?", isPresented: $confirmingDelete) {
                            Button("Delete", role: .destructive) {
                                delete(original)
                                dismiss()
                            }
                            Button("Cancel", role: .cancel) {}
                        }
                }
                if saving { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    // A save in flight still writes when it returns; closing now would let it add what was cancelled.
                    .disabled(saving)
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving || draft.address.trimmingCharacters(in: .whitespaces).isEmpty || (!isNew && draft.name.trimmingCharacters(in: .whitespaces).isEmpty))
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    /// Green check when the address answers 200, a warning when it doesn't, a spinner while checking.
    @ViewBuilder
    private var addressMark: some View {
        if checking {
            ProgressView().controlSize(.small)
        } else if answers == true {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("status.json answers")
        } else if answers == false {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red).help("No status page at this address")
        }
    }

    /// Checks the address as it stands; a result for an address since edited is dropped.
    private func check() {
        let address = draft.address
        guard !address.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        checking = true
        Task {
            let result = await probe(address)
            guard address == draft.address else { return }
            checking = false
            answers = result
        }
    }

    private func commit() {
        saving = true
        problem = nil
        Task {
            problem = await save(draft)
            saving = false
            if problem == nil { dismiss() }
        }
    }
}

/// Creates a group or edits one: its name, and deleting it, which asks what happens to its services.
private struct GroupSheet: View {
    let group: ServiceGroup?
    let problem: (String) -> String?
    let done: (String) -> Void
    let delete: (_ keepServices: Bool) -> Void
    @State private var name: String
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    init(group: ServiceGroup?, problem: @escaping (String) -> String?, done: @escaping (String) -> Void,
         delete: @escaping (_ keepServices: Bool) -> Void) {
        self.group = group
        self.problem = problem
        self.done = done
        self.delete = delete
        _name = State(initialValue: group?.name ?? "")
    }

    var body: some View {
        let issue = problem(name)
        VStack(alignment: .leading, spacing: 12) {
            Text(group == nil ? "New Group" : "Edit Group").font(.headline)
            TextField("Name", text: $name, prompt: Text("Group name"))
                .onSubmit { if issue == nil { finish() } }
            if let issue, !issue.isEmpty {
                Text(issue).foregroundStyle(.red).font(.callout)
            }
            HStack {
                if let group {
                    Button("Delete…", role: .destructive) { confirmingDelete = true }
                        .alert("Delete the group \(group.name)?", isPresented: $confirmingDelete) {
                            if group.services.isEmpty {
                                Button("Delete", role: .destructive) { remove(keeping: false) }
                            } else {
                                Button("Keep Services") { remove(keeping: true) }
                                Button("Delete Services Too", role: .destructive) { remove(keeping: false) }
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            if !group.services.isEmpty {
                                Text("It has \(group.services.count) service\(group.services.count == 1 ? "" : "s"). Kept services move out of the group.")
                            }
                        }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(group == nil ? "Create" : "Save", action: finish)
                    .keyboardShortcut(.defaultAction)
                    .disabled(issue != nil)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func remove(keeping: Bool) {
        delete(keeping)
        dismiss()
    }

    private func finish() {
        done(name.trimmingCharacters(in: .whitespaces))
        dismiss()
    }
}

/// Accepts drops on a row and draws the blue insertion line above or below it.
private struct DropZone: ViewModifier {
    let key: String
    @Binding var state: DropState
    let perform: (_ payload: String, _ after: Bool) -> Void

    func body(content: Content) -> some View {
        let mark = state.mark?.key == key ? state.mark : nil
        content
            .overlay(alignment: mark?.after == true ? .bottom : .top) {
                if let mark {
                    Rectangle().fill(Color.accentColor).frame(height: 2).offset(y: mark.after ? 3 : -3)
                }
            }
            .overlay {
                GeometryReader { geo in
                    Color.clear.onDrop(of: [.plainText], delegate: RowDrop(key: key, height: geo.size.height, state: $state, perform: perform))
                }
            }
    }
}

/// Edit and window commands for the Settings window's text fields: an accessory app has no visible menu bar,
/// but key equivalents still go through `NSApp.mainMenu`.
@MainActor
func editingMainMenu() -> NSMenu {
    let edit = NSMenu(title: "Edit")
    edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
    edit.addItem(.separator())
    edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    let window = NSMenu(title: "Window")
    window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    let main = NSMenu()
    for sub in [NSMenu(title: "HealthBar"), edit, window] {
        let item = NSMenuItem(title: sub.title, action: nil, keyEquivalent: "")
        item.submenu = sub
        main.addItem(item)
    }
    return main
}
