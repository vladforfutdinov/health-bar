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
    var updater: SPUUpdater?
    #endif
    private let fetcher: StatusFetcher
    private let onChange: (Config) -> Void

    init(config: Config, fetcher: StatusFetcher, onChange: @escaping (Config) -> Void) {
        self.config = config
        self.fetcher = fetcher
        self.onChange = onChange
    }

    /// Shows `text` under Launch at Login, where the window's other errors go.
    /// `nil` clears it.
    func report(_ text: String?) { message = text }

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

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    /// Unfolded group ids; at first those with something enabled.
    @State private var expanded: Set<String>
    @State private var confirmation: Confirmation?
    /// Selected row: "s:" + a service's URL or "g:" + a group's id. Arrow keys move it once Tab reaches the list.
    @State private var selection: String?
    @FocusState private var listFocused: Bool
    @State private var editingGroup: GroupDraft?
    @State private var editing: ServiceDraft?

    init(model: SettingsModel) {
        self.model = model
        let saved = UserDefaults.standard.stringArray(forKey: Self.expandedKey)
        _expanded = State(initialValue: Set(saved ?? model.config.groups.filter { $0.services.contains(where: \.enabled) }.map(\.id)))
    }

    /// Unfolded groups, kept between openings of the window.
    private static let expandedKey = "settingsExpandedGroups"

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
                    }
                }
                #endif
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: AppDelegate.settingsSize.width)
        .frame(minHeight: AppDelegate.settingsSize.height, maxHeight: .infinity)
        // The list takes the focus first, not the Expand All link; set again after the window picks its first responder.
        .defaultFocus($listFocused, true)
        .onAppear {
            listFocused = true
            DispatchQueue.main.async { listFocused = true }
        }
        .onChange(of: expanded) { UserDefaults.standard.set(Array($0), forKey: Self.expandedKey) }
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
        .sheet(item: $confirmation, content: ConfirmSheet.init)
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
                HStack(alignment: .center, spacing: 4) {
                    Text("Services").font(.headline)
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                        .help(Self.servicesHelp)
                        .accessibilityLabel(Self.servicesHelp)
                }
                Spacer()
                Button(allExpanded ? "Collapse All" : "Expand All") {
                    expanded = allExpanded ? [] : Set(model.config.groups.map(\.id))
                }
                .buttonStyle(.link)
            }
            List(selection: $selection) {
                ForEach($model.config.ungrouped, id: \.url) { $service in
                    serviceRow($service, in: Config.noGroup)
                        .tag("s:" + service.url.absoluteString)
                }
                .onMove { model.config.ungrouped.move(fromOffsets: $0, toOffset: $1) }
                ForEach($model.config.groups) { $group in
                    DisclosureGroup(isExpanded: Binding(
                        get: { expanded.contains(group.id) },
                        set: { if $0 { expanded.insert(group.id) } else { expanded.remove(group.id) } }
                    )) {
                        ForEach($group.services, id: \.url) { $service in
                            serviceRow($service, in: group.id)
                                .tag("s:" + service.url.absoluteString)
                        }
                        .onMove { from, to in
                            guard let g = model.config.groups.firstIndex(where: { $0.id == group.id }) else { return }
                            model.config.groups[g].services.move(fromOffsets: from, toOffset: to)
                        }
                    } label: {
                        groupHeader(group)
                    }
                    .tag("g:" + group.id)
                }
                .onMove { model.config.groups.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: false))
            .frame(minHeight: 200, maxHeight: .infinity)
            .focused($listFocused)
            .onDeleteCommand(perform: deleteSelected)
            .background(listKeys)
            HStack {
                Button("Import…", action: importConfig)
                Button("Export…", action: exportConfig)
                Spacer()
                Button("New Group…") { editingGroup = GroupDraft(group: nil) }
                Button("New Service…") {
                    editing = ServiceDraft(original: nil, address: "", name: "", group: Config.noGroup)
                }
            }
        }
    }

    private static let servicesHelp = "Any Statuspage or incident.io status page. Drag rows to reorder; to move a service to another group, use Move to Group in its context menu. The menu follows the order of the checked services."

    /// Writes the whole config (services, groups, interval) as JSON.
    private func exportConfig() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "HealthBar Settings.json"
        panel.allowedContentTypes = [.json]
        guard let window = NSApp.keyWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try model.config.exported().write(to: url)
                model.report(nil)
            } catch {
                model.report("Export failed: \(error.localizedDescription)")
            }
        }
    }

    /// Replaces the config with an exported file (or a 0.2.x services.json), after a confirmation.
    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard let window = NSApp.keyWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let imported = try Config.importing(Data(contentsOf: url))
                confirmation = Confirmation(
                    title: "Replace your services with “\(url.deletingPathExtension().lastPathComponent)”?",
                    message: "Services, groups and the check interval are replaced by the file’s. This can’t be undone; export first to keep the current ones.",
                    choices: [Confirmation.Choice(title: "Replace") {
                        model.config = imported
                        model.report(nil)
                        expanded = Set(imported.groups.filter { $0.services.contains(where: \.enabled) }.map(\.id))
                    }])
            } catch {
                model.report("\(url.lastPathComponent) is not a HealthBar settings file.")
            }
        }
    }

    /// Keys for the selected row while the list has focus: Space checks a service or folds a group, Return edits,
    /// ⌥⌘↑/↓ move it. Hidden buttons, because `onKeyPress` needs macOS 14.
    private var listKeys: some View {
        Group {
            Button("") { toggleSelected() }.keyboardShortcut(.space, modifiers: [])
            Button("") { editSelected() }.keyboardShortcut(.return, modifiers: [])
            Button("") { shiftSelected(-1) }.keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("") { shiftSelected(1) }.keyboardShortcut(.downArrow, modifiers: [.command, .option])
        }
        .disabled(!listFocused || selection == nil)
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private var selectedService: (service: ServiceConfig, group: String)? {
        guard let sel = selection, sel.hasPrefix("s:"), let url = URL(string: String(sel.dropFirst(2))),
              let group = model.config.group(of: url),
              let service = (model.config.ungrouped + model.config.groups.flatMap(\.services)).first(where: { $0.url == url })
        else { return nil }
        return (service, group)
    }

    private var selectedGroup: ServiceGroup? {
        guard let sel = selection, sel.hasPrefix("g:") else { return nil }
        return model.config.groups.first { $0.id == String(sel.dropFirst(2)) }
    }

    private func toggleSelected() {
        if let (s, group) = selectedService {
            var on = s
            on.enabled.toggle()
            model.config.replace(s.url, with: on, inGroup: group)
        } else if let g = selectedGroup {
            if expanded.contains(g.id) { expanded.remove(g.id) } else { expanded.insert(g.id) }
        }
    }

    private func editSelected() {
        if let (s, group) = selectedService {
            editing = ServiceDraft(original: s.url, address: s.url.absoluteString, name: s.name, group: group)
        } else if let g = selectedGroup {
            editingGroup = GroupDraft(group: g)
        }
    }

    private func deleteSelected() {
        if let (s, _) = selectedService {
            confirmation = .deleting(s.name) { model.config.remove(s.url) }
        } else if let g = selectedGroup {
            confirmation = .deleting(g) { model.config.removeGroup(g.id, keepingServices: $0) }
        }
    }

    private func shiftSelected(_ offset: Int) {
        if let (s, _) = selectedService {
            model.config.shift(s.url, by: offset)
        } else if let g = selectedGroup {
            model.config.shiftGroup(g.id, by: offset)
        }
    }

    private func pencil(_ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "pencil") }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(help)
            .accessibilityLabel(help)
    }

    private func serviceRow(_ service: Binding<ServiceConfig>, in group: String) -> some View {
        let s = service.wrappedValue
        let position = model.config.position(of: s.url)
        let edit = { editing = ServiceDraft(original: s.url, address: s.url.absoluteString, name: s.name, group: group) }
        return HStack {
            Toggle(s.name, isOn: service.enabled).toggleStyle(.checkbox)
            Spacer()
            Text(s.url.host ?? s.url.absoluteString).foregroundStyle(.secondary)
            pencil("Edit \(s.name)", action: edit)
            Grip()
        }
        .contextMenu {
            Button("Move Up") { model.config.shift(s.url, by: -1) }
                .disabled(position?.index == 0)
            Button("Move Down") { model.config.shift(s.url, by: 1) }
                .disabled(position.map { $0.index == $0.count - 1 } ?? true)
            Menu("Move to Group") {
                Button("No Group") { moveService(s, to: Config.noGroup) }
                    .disabled(group == Config.noGroup)
                Divider()
                ForEach(model.config.groups) { g in
                    Button(g.name) { moveService(s, to: g.id) }
                        .disabled(g.id == group)
                }
            }
            Divider()
            Button("Edit…", action: edit)
            Button("Delete…") { confirmation = .deleting(s.name) { model.config.remove(s.url) } }
        }
    }

    private func moveService(_ s: ServiceConfig, to group: String) {
        model.config.replace(s.url, with: s, inGroup: group)
        if group != Config.noGroup { expanded.insert(group) }
    }

    private func groupHeader(_ g: ServiceGroup) -> some View {
        let index = model.config.groups.firstIndex { $0.id == g.id }
        return HStack {
            Text(g.name).fontWeight(.medium)
            Spacer()
            pencil("Edit the group \(g.name)") { editingGroup = GroupDraft(group: g) }
            Grip()
        }
        .contextMenu {
            Button("Move Up") { model.config.shiftGroup(g.id, by: -1) }
                .disabled(index == 0)
            Button("Move Down") { model.config.shiftGroup(g.id, by: 1) }
                .disabled(index == model.config.groups.count - 1)
            Divider()
            Button("Edit…") { editingGroup = GroupDraft(group: g) }
            Button("Delete…") { confirmation = .deleting(g) { model.config.removeGroup(g.id, keepingServices: $0) } }
        }
    }

    /// "30 seconds", "1 minute"… in the user's language.
    private static func interval(_ seconds: Int) -> String {
        let f = DateComponentsFormatter()
        f.unitsStyle = .full
        f.allowedUnits = [.second, .minute]
        return f.string(from: TimeInterval(seconds)) ?? "\(seconds) s"
    }
}

/// A destructive action waiting for confirmation, shown by `ConfirmSheet`.
private struct Confirmation: Identifiable {
    struct Choice {
        let title: String
        let run: () -> Void
    }

    let id = UUID()
    let title: String
    let message: String
    let choices: [Choice]

    static func deleting(_ name: String, delete: @escaping () -> Void) -> Confirmation {
        Confirmation(title: "Delete “\(name)”?", message: "This can’t be undone.", choices: [Choice(title: "Delete", run: delete)])
    }

    /// A group with services offers to keep them (they move out of the group) or delete them too.
    static func deleting(_ group: ServiceGroup, delete: @escaping (_ keepServices: Bool) -> Void) -> Confirmation {
        guard !group.services.isEmpty else { return deleting(group.name) { delete(false) } }
        let count = String(AttributedString(localized: "^[\(group.services.count) service](inflect: true)").characters)
        return Confirmation(
            title: "Delete “\(group.name)”?",
            message: "It has \(count). Delete Group Only moves them out of the group. This can’t be undone.",
            choices: [Choice(title: "Delete Group Only") { delete(true) }, Choice(title: "Delete Group and Services") { delete(false) }])
    }
}

/// Confirmation in the style of the app's other sheets. Cancel is the default button, so Return and Escape both cancel.
private struct ConfirmSheet: View {
    let confirmation: Confirmation
    @Environment(\.dismiss) private var dismiss

    init(_ confirmation: Confirmation) {
        self.confirmation = confirmation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(confirmation.title).font(.headline)
            Text(confirmation.message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                ForEach(confirmation.choices, id: \.title) { choice in
                    Button(choice.title, role: .destructive) {
                        dismiss()
                        choice.run()
                    }
                }
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onExitCommand { dismiss() }
    }
}

/// Drag handle mark: two columns of three 2-pt dots on a 4-pt pitch, pixel-aligned. The whole row drags; this only shows that it can.
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
        .accessibilityHidden(true)
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
    @State private var confirmation: Confirmation?
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
                    Button("Delete…", role: .destructive) {
                        confirmation = .deleting(draft.name.isEmpty ? original.host ?? "" : draft.name) {
                            delete(original)
                            dismiss()
                        }
                    }
                    .disabled(saving)
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
        .sheet(item: $confirmation, content: ConfirmSheet.init)
    }

    /// Green check when the address answers 200, a warning when it doesn't, a spinner while checking.
    @ViewBuilder
    private var addressMark: some View {
        if checking {
            ProgressView().controlSize(.small)
        } else if answers == true {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("status.json answers")
                .accessibilityLabel("Status page found")
        } else if answers == false {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red).help("No status page at this address")
                .accessibilityLabel("No status page at this address")
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
    @State private var confirmation: Confirmation?
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
                    Button("Delete…", role: .destructive) { confirmation = .deleting(group) { remove(keeping: $0) } }
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
        .sheet(item: $confirmation, content: ConfirmSheet.init)
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

/// ⌘Q, edit commands for the Settings window's text fields and ⌘W: an accessory app has no visible menu bar,
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
    let app = NSMenu(title: "HealthBar")
    app.addItem(withTitle: "Quit HealthBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    let window = NSMenu(title: "Window")
    window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    let main = NSMenu()
    for sub in [app, edit, window] {
        let item = NSMenuItem(title: sub.title, action: nil, keyEquivalent: "")
        item.submenu = sub
        main.addItem(item)
    }
    return main
}
