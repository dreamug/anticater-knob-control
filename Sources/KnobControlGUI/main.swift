import AppKit
import SwiftUI
import IOKit.hid

private let vendorID = 0x05ac
private let productID = 0x022c

private enum KnobInput: String, CaseIterable, Identifiable, Codable {
    case rotateLeft = "rotate_left"
    case rotateRight = "rotate_right"
    case press = "press"
    case pressRotateLeft = "press_rotate_left"
    case pressRotateRight = "press_rotate_right"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rotateLeft: return "左旋"
        case .rotateRight: return "右旋"
        case .press: return "按下"
        case .pressRotateLeft: return "按住左旋"
        case .pressRotateRight: return "按住右旋"
        }
    }
}

private enum ActionType: String, CaseIterable, Identifiable, Codable {
    case shortcut
    case key
    case mouse
    case scroll
    case shell
    case noop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shortcut: return "快捷键"
        case .key: return "按键"
        case .mouse: return "鼠标"
        case .scroll: return "滚动"
        case .shell: return "命令"
        case .noop: return "无动作"
        }
    }
}

private struct MappingConfig: Codable {
    var global: [String: ActionConfig]
    var apps: [String: [String: ActionConfig]]
}

private struct ActionConfig: Codable, Equatable {
    var type: String
    var description: String?
    var keys: [String]?
    var button: String?
    var clicks: Int?
    var dx: Int?
    var dy: Int?
    var command: String?

    static func empty() -> ActionConfig {
        ActionConfig(type: "noop", description: "", keys: [], button: "left", clicks: 1, dx: 0, dy: 0, command: "")
    }
}

private struct AppInfo: Identifiable, Hashable {
    let bundleID: String
    let name: String
    let path: String
    let isRunning: Bool

    var id: String { bundleID }
}

private enum ProfileID: Hashable {
    case global
    case app(String)
}

@MainActor
private final class AppCatalog: ObservableObject {
    @Published var apps: [AppInfo] = []
    @Published var query = ""
    @Published var status = "未扫描"

    var filteredApps: [AppInfo] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            return apps
        }

        return apps.filter {
            $0.name.lowercased().contains(trimmed)
                || $0.bundleID.lowercased().contains(trimmed)
                || $0.path.lowercased().contains(trimmed)
        }
    }

    func app(bundleID: String) -> AppInfo? {
        apps.first { $0.bundleID == bundleID }
            ?? appInfoFromBundleID(bundleID)
    }

    func refresh() {
        let running = runningApps()
        var byBundleID = running

        for url in installedAppURLs() {
            guard let bundle = Bundle(url: url),
                  let bundleID = bundle.bundleIdentifier,
                  isVisibleApplication(bundle: bundle) else {
                continue
            }

            if byBundleID[bundleID] == nil {
                byBundleID[bundleID] = AppInfo(
                    bundleID: bundleID,
                    name: appName(bundle: bundle, url: url),
                    path: url.path,
                    isRunning: false
                )
            }
        }

        apps = byBundleID.values.sorted {
            if $0.isRunning != $1.isRunning {
                return $0.isRunning && !$1.isRunning
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        status = "发现 \(apps.count) 个应用"
    }

    private func runningApps() -> [String: AppInfo] {
        var result: [String: AppInfo] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier else {
                continue
            }

            result[bundleID] = AppInfo(
                bundleID: bundleID,
                name: app.localizedName ?? bundleID,
                path: app.bundleURL?.path ?? "",
                isRunning: true
            )
        }
        return result
    }

    private func installedAppURLs() -> [URL] {
        let fm = FileManager.default
        var roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications")
        ]

        roots.append(contentsOf: mountedApplicationRoots())

        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        var urls: [URL] = []

        for root in roots where fm.fileExists(atPath: root.path) {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                if url.pathExtension == "app" {
                    urls.append(url)
                    enumerator.skipDescendants()
                }
            }
        }

        return urls
    }

    private func mountedApplicationRoots() -> [URL] {
        let volumes = URL(fileURLWithPath: "/Volumes")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: volumes,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries.map { $0.appendingPathComponent("Applications") }
    }
}

@MainActor
private final class ConfigStore: ObservableObject {
    @Published var config: MappingConfig
    @Published var selectedProfile: ProfileID = .global
    @Published var status = ""

    let projectRoot: URL
    let configURL: URL

    init() {
        projectRoot = findProjectRoot()
        configURL = projectRoot.appendingPathComponent("config/app-mapping.json")

        do {
            let url = FileManager.default.fileExists(atPath: configURL.path)
                ? configURL
                : projectRoot.appendingPathComponent("config/app-mapping.example.json")
            let data = try Data(contentsOf: url)
            config = try JSONDecoder().decode(MappingConfig.self, from: data)
            status = "已加载 \(url.lastPathComponent)"
        } catch {
            config = MappingConfig(global: defaultActions(), apps: [:])
            status = "配置加载失败，已使用空配置"
        }
    }

    var sortedAppIDs: [String] {
        config.apps.keys.sorted()
    }

    func title(for profile: ProfileID) -> String {
        switch profile {
        case .global:
            return "全局默认"
        case .app(let bundleID):
            return bundleID
        }
    }

    func actionBinding(_ input: KnobInput) -> Binding<ActionConfig> {
        Binding(
            get: {
                switch self.selectedProfile {
                case .global:
                    return self.config.global[input.rawValue] ?? ActionConfig.empty()
                case .app(let bundleID):
                    return self.config.apps[bundleID]?[input.rawValue] ?? self.config.global[input.rawValue] ?? ActionConfig.empty()
                }
            },
            set: { newValue in
                switch self.selectedProfile {
                case .global:
                    self.config.global[input.rawValue] = newValue
                case .app(let bundleID):
                    var appActions = self.config.apps[bundleID] ?? [:]
                    appActions[input.rawValue] = newValue
                    self.config.apps[bundleID] = appActions
                }
            }
        )
    }

    func addCurrentApp() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else {
            status = "没有找到当前 App"
            return
        }

        addApp(bundleID: bundleID)
    }

    func addApp(_ app: AppInfo) {
        addApp(bundleID: app.bundleID)
    }

    func addApp(bundleID: String) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if config.apps[trimmed] == nil {
            config.apps[trimmed] = defaultActions()
        }
        selectedProfile = .app(trimmed)
        status = "已添加 \(trimmed)"
    }

    func deleteSelectedApp() {
        guard case .app(let bundleID) = selectedProfile else { return }
        config.apps.removeValue(forKey: bundleID)
        selectedProfile = .global
        status = "已删除 \(bundleID)"
    }

    func reload() {
        do {
            let data = try Data(contentsOf: configURL)
            config = try JSONDecoder().decode(MappingConfig.self, from: data)
            status = "已重新加载配置"
        } catch {
            status = "重新加载失败：\(error.localizedDescription)"
        }
    }

    func save() {
        do {
            try FileManager.default.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(config)
            try data.write(to: configURL)
            status = "已保存 \(configURL.lastPathComponent)"
        } catch {
            status = "保存失败：\(error.localizedDescription)"
        }
    }

    func action(for input: KnobInput, bundleID: String) -> ActionConfig? {
        config.apps[bundleID]?[input.rawValue] ?? config.global[input.rawValue]
    }
}

@MainActor
private final class FrontmostAppModel: ObservableObject {
    @Published var name = "unknown"
    @Published var bundleID = "unknown"

    private var timer: Timer?

    func start() {
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }
    }

    private func update() {
        let app = NSWorkspace.shared.frontmostApplication
        name = app?.localizedName ?? "unknown"
        bundleID = app?.bundleIdentifier ?? "unknown"
    }
}

@MainActor
private final class KnobService: ObservableObject {
    @Published var isRunning = false
    @Published var deviceStatus = "未启动"
    @Published var lastEvent = "暂无事件"

    private var manager: IOHIDManager?
    private weak var store: ConfigStore?

    func toggle(store: ConfigStore) {
        isRunning ? stop() : start(store: store)
    }

    func start(store: ConfigStore) {
        guard !isRunning else { return }

        self.store = store
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: vendorID,
            kIOHIDProductIDKey: productID
        ] as CFDictionary)

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            let service = Unmanaged<KnobService>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in service.deviceStatus = "已连接：\(deviceName(device))" }
        }, Unmanaged.passUnretained(self).toOpaque())

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, _ in
            guard let context else { return }
            let service = Unmanaged<KnobService>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in service.deviceStatus = "设备已断开" }
        }, Unmanaged.passUnretained(self).toOpaque())

        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            let service = Unmanaged<KnobService>.fromOpaque(context).takeUnretainedValue()
            let element = IOHIDValueGetElement(value)
            let page = IOHIDElementGetUsagePage(element)
            let usage = IOHIDElementGetUsage(element)
            let intValue = IOHIDValueGetIntegerValue(value)

            guard intValue == 1, let input = knobInput(page: page, usage: usage) else {
                return
            }

            Task { @MainActor in service.handle(input) }
        }, Unmanaged.passUnretained(self).toOpaque())

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let seized = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        if seized != kIOReturnSuccess {
            let normal = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            guard normal == kIOReturnSuccess else {
                deviceStatus = "启动失败：0x\(hex(UInt32(bitPattern: normal), width: 8))"
                self.manager = nil
                return
            }
            deviceStatus = "已启动，但未独占设备"
        } else {
            deviceStatus = "已启动并独占设备"
        }

        if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let first = devices.first {
            deviceStatus = "已连接：\(deviceName(first))"
        }

        isRunning = true
    }

    func stop() {
        guard let manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        isRunning = false
        deviceStatus = "已停止"
    }

    private func handle(_ input: KnobInput) {
        guard let store else { return }
        let app = NSWorkspace.shared.frontmostApplication
        let appName = app?.localizedName ?? "unknown"
        let bundleID = app?.bundleIdentifier ?? "unknown"

        guard let action = store.action(for: input, bundleID: bundleID) else {
            lastEvent = "\(clock()) \(input.rawValue) / \(appName) / 无动作"
            return
        }

        let ok = ActionExecutor.run(action)
        let detail = action.description?.isEmpty == false ? action.description! : action.type
        lastEvent = "\(clock()) \(input.rawValue) / \(appName) / \(detail) / \(ok ? "ok" : "failed")"
    }
}

@main
private struct KnobControlApp: App {
    @StateObject private var store = ConfigStore()
    @StateObject private var frontmost = FrontmostAppModel()
    @StateObject private var knobService = KnobService()
    @StateObject private var appCatalog = AppCatalog()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(frontmost)
                .environmentObject(knobService)
                .environmentObject(appCatalog)
                .frame(minWidth: 980, minHeight: 640)
                .onAppear {
                    frontmost.start()
                    appCatalog.refresh()
                }
        }
        .windowStyle(.titleBar)
    }
}

private struct ContentView: View {
    @EnvironmentObject private var store: ConfigStore
    @EnvironmentObject private var frontmost: FrontmostAppModel
    @EnvironmentObject private var knobService: KnobService
    @EnvironmentObject private var appCatalog: AppCatalog
    @State private var newBundleID = ""

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 230, ideal: 280)
        } detail: {
            VStack(spacing: 0) {
                header
                Divider()
                editor
                Divider()
                footer
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 12) {
            List(selection: $store.selectedProfile) {
                Section("默认") {
                    Text("全局默认").tag(ProfileID.global)
                }

                Section("应用") {
                    ForEach(store.sortedAppIDs, id: \.self) { bundleID in
                        ConfiguredAppRow(info: appCatalog.app(bundleID: bundleID), fallbackBundleID: bundleID)
                        .tag(ProfileID.app(bundleID))
                    }
                }

                Section("发现的应用") {
                    ForEach(appCatalog.filteredApps) { app in
                        Button {
                            store.addApp(app)
                        } label: {
                            DiscoveredAppRow(app: app, configured: store.config.apps[app.bundleID] != nil)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(spacing: 8) {
                TextField("搜索应用", text: $appCatalog.query)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("刷新发现") {
                        appCatalog.refresh()
                    }
                    Text(appCatalog.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                TextField("手动输入应用标识", text: $newBundleID)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("添加") {
                        store.addApp(bundleID: newBundleID)
                        newBundleID = ""
                    }
                    Button("添加当前应用") {
                        store.addCurrentApp()
                    }
                }
                Button("删除选中应用", role: .destructive) {
                    store.deleteSelectedApp()
                }
                .disabled(!isAppSelected)
            }
            .padding([.horizontal, .bottom], 12)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedProfileTitle)
                        .font(.title2.weight(.semibold))
                    Text("当前前台应用：\(frontmost.name)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(knobService.isRunning ? "停止监听" : "启动监听") {
                    knobService.toggle(store: store)
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("重新加载") {
                    store.reload()
                }

                Button("保存配置") {
                    store.save()
                }
                .keyboardShortcut("s", modifiers: [.command])
            }

            HStack {
                StatusPill(text: knobService.deviceStatus, active: knobService.isRunning)
                Text(knobService.lastEvent)
                    .lineLimit(1)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
    }

    private var editor: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(KnobInput.allCases) { input in
                    ActionEditorRow(input: input, action: store.actionBinding(input))
                }
            }
            .padding(18)
        }
    }

    private var footer: some View {
        HStack {
            Text(store.status)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("配置：\(store.configURL.lastPathComponent)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var isAppSelected: Bool {
        if case .app = store.selectedProfile { return true }
        return false
    }

    private var selectedProfileTitle: String {
        switch store.selectedProfile {
        case .global:
            return "全局默认"
        case .app(let bundleID):
            return appCatalog.app(bundleID: bundleID)?.name ?? store.title(for: store.selectedProfile)
        }
    }
}

private struct ConfiguredAppRow: View {
    let info: AppInfo?
    let fallbackBundleID: String

    var body: some View {
        HStack(spacing: 8) {
            AppIconView(path: info?.path, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(info?.name ?? fallbackBundleID)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(info?.isRunning == true ? "自定义映射 · 运行中" : "自定义映射")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DiscoveredAppRow: View {
    let app: AppInfo
    let configured: Bool

    var body: some View {
        HStack(spacing: 8) {
            AppIconView(path: app.path, size: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    if app.isRunning {
                        Text("运行中")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.green.opacity(0.18), in: Capsule())
                    }
                    if configured {
                        Text("已添加")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.16), in: Capsule())
                    }
                }
                Text(configured ? "已在左侧应用列表中" : "点击添加到应用列表")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct AppIconView: View {
    let path: String?
    let size: CGFloat

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .frame(width: size, height: size)
            .cornerRadius(5)
    }

    private var icon: NSImage {
        if let path, !path.isEmpty {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return NSWorkspace.shared.icon(forFileType: "app")
    }
}

private struct ActionEditorRow: View {
    let input: KnobInput
    @Binding var action: ActionConfig
    @State private var isRecordingShortcut = false
    @State private var shortcutMonitor: Any?

    private var keysText: Binding<String> {
        Binding(
            get: { displayKeyList(action.keys ?? []) },
            set: { text in
                action.keys = parseKeyList(text)
            }
        )
    }

    private var actionType: Binding<String> {
        Binding(
            get: { action.type },
            set: { action.type = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(input.title)
                    .font(.headline)
                    .frame(width: 96, alignment: .leading)

                Picker("类型", selection: actionType) {
                    ForEach(ActionType.allCases) { type in
                        Text(type.title).tag(type.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                TextField("描述", text: optionalString($action.description))
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 180)
            }

            fields
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        .onDisappear {
            stopShortcutRecording()
        }
    }

    @ViewBuilder
    private var fields: some View {
        switch action.type {
        case "shortcut", "key":
            HStack {
                Text("按键")
                    .frame(width: 96, alignment: .leading)
                    .foregroundStyle(.secondary)
                TextField("可手动输入，逗号分隔", text: keysText)
                    .textFieldStyle(.roundedBorder)
                Button(isRecordingShortcut ? "请按组合键" : "录制组合键") {
                    isRecordingShortcut ? stopShortcutRecording() : startShortcutRecording()
                }
                Button("清空") {
                    action.keys = []
                }
            }
        case "mouse":
            HStack {
                Text("鼠标")
                    .frame(width: 96, alignment: .leading)
                    .foregroundStyle(.secondary)
                Picker("按钮", selection: optionalString($action.button)) {
                    Text("左键").tag("left")
                    Text("右键").tag("right")
                    Text("中键").tag("middle")
                }
                .frame(width: 160)
                Stepper("点击 \(action.clicks ?? 1) 次", value: optionalInt($action.clicks, defaultValue: 1), in: 1...5)
            }
        case "scroll":
            HStack {
                Text("滚动")
                    .frame(width: 96, alignment: .leading)
                    .foregroundStyle(.secondary)
                Stepper("横向 \(action.dx ?? 0)", value: optionalInt($action.dx, defaultValue: 0), in: -20...20)
                Stepper("纵向 \(action.dy ?? 0)", value: optionalInt($action.dy, defaultValue: 0), in: -20...20)
            }
        case "shell":
            HStack {
                Text("命令")
                    .frame(width: 96, alignment: .leading)
                    .foregroundStyle(.secondary)
                TextField("输入要执行的命令", text: optionalString($action.command))
                    .textFieldStyle(.roundedBorder)
            }
        default:
            HStack {
                Text("无动作")
                    .frame(width: 96, alignment: .leading)
                    .foregroundStyle(.secondary)
                Text("这个手势会被忽略。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func startShortcutRecording() {
        stopShortcutRecording()
        isRecordingShortcut = true
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard let key = keyName(for: event) else {
                return nil
            }

            var keys: [String] = []
            let flags = event.modifierFlags
            if flags.contains(.command) { keys.append("command") }
            if flags.contains(.control) { keys.append("control") }
            if flags.contains(.option) { keys.append("option") }
            if flags.contains(.shift) { keys.append("shift") }
            if flags.contains(.function) { keys.append("fn") }
            keys.append(key)

            action.keys = keys
            stopShortcutRecording()
            return nil
        }
    }

    private func stopShortcutRecording() {
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
        }
        shortcutMonitor = nil
        isRecordingShortcut = false
    }
}

private struct StatusPill: View {
    let text: String
    let active: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(active ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.quaternary, in: Capsule())
    }
}

private enum ActionExecutor {
    static func run(_ action: ActionConfig) -> Bool {
        switch action.type {
        case "shortcut", "key":
            return sendKeys(action.keys ?? [])
        case "mouse":
            return click(button: action.button ?? "left", clicks: action.clicks ?? 1)
        case "scroll":
            return scroll(dx: action.dx ?? 0, dy: action.dy ?? 0)
        case "shell":
            return runShell(action.command)
        case "noop":
            return true
        default:
            return false
        }
    }

    private static func sendKeys(_ keys: [String]) -> Bool {
        let normalized = keys.map { $0.lowercased() }
        if normalized.count == 1, let media = mediaKeyTypes[normalized[0]] {
            sendMediaKey(media)
            return true
        }

        var flags = CGEventFlags()
        var keyCodes: [CGKeyCode] = []

        for key in normalized {
            if let flag = modifierFlags[key] {
                flags.insert(flag)
            } else if let code = keyCodesByName[key] {
                keyCodes.append(code)
            } else if let media = mediaKeyTypes[key] {
                sendMediaKey(media)
            } else {
                return false
            }
        }

        for keyCode in keyCodes {
            sendKey(keyCode, down: true, flags: flags)
            sendKey(keyCode, down: false, flags: flags)
        }
        return true
    }

    private static func sendKey(_ keyCode: CGKeyCode, down: Bool, flags: CGEventFlags) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down) else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    private static func sendMediaKey(_ keyType: Int) {
        postMediaKey(keyType, down: true)
        postMediaKey(keyType, down: false)
    }

    private static func postMediaKey(_ keyType: Int, down: Bool) {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(down ? 0xA00 : 0xB00))
        let data1 = (keyType << 16) | ((down ? 0xA : 0xB) << 8)
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        )?.cgEvent else { return }
        event.post(tap: .cghidEventTap)
    }

    private static func click(button: String, clicks: Int) -> Bool {
        let mouseButton: CGMouseButton
        let downType: CGEventType
        let upType: CGEventType

        switch button.lowercased() {
        case "left":
            mouseButton = .left; downType = .leftMouseDown; upType = .leftMouseUp
        case "right":
            mouseButton = .right; downType = .rightMouseDown; upType = .rightMouseUp
        case "middle", "center":
            mouseButton = .center; downType = .otherMouseDown; upType = .otherMouseUp
        default:
            return false
        }

        let point = CGEvent(source: nil)?.location ?? .zero
        for _ in 0..<max(clicks, 1) {
            CGEvent(mouseEventSource: nil, mouseType: downType, mouseCursorPosition: point, mouseButton: mouseButton)?.post(tap: .cghidEventTap)
            CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: point, mouseButton: mouseButton)?.post(tap: .cghidEventTap)
        }
        return true
    }

    private static func scroll(dx: Int, dy: Int) -> Bool {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0) else {
            return false
        }
        event.post(tap: .cghidEventTap)
        return true
    }

    private static func runShell(_ command: String?) -> Bool {
        guard let command, !command.isEmpty else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }
}

private let modifierFlags: [String: CGEventFlags] = [
    "command": .maskCommand, "cmd": .maskCommand,
    "control": .maskControl, "ctrl": .maskControl,
    "option": .maskAlternate, "opt": .maskAlternate, "alt": .maskAlternate,
    "shift": .maskShift, "fn": .maskSecondaryFn
]

private let mediaKeyTypes: [String: Int] = [
    "volume_up": 0, "volume_down": 1, "mute": 7,
    "play_pause": 16, "next_track": 17, "previous_track": 18
]

private let keyCodesByName: [String: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
    "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
    "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
    "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
    "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "return": 36,
    "enter": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
    ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49,
    "`": 50, "delete": 51, "backspace": 51, "escape": 53, "esc": 53,
    "left": 123, "right": 124, "down": 125, "up": 126,
    "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
    "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111
]

private let keyNameByCode: [CGKeyCode: String] = {
    var result: [CGKeyCode: String] = [:]
    for (name, code) in keyCodesByName {
        if result[code] == nil || name.count > result[code]!.count {
            result[code] = name
        }
    }
    result[36] = "return"
    result[49] = "space"
    result[53] = "escape"
    return result
}()

private func knobInput(page: UInt32, usage: UInt32) -> KnobInput? {
    guard page == 0x000c else { return nil }
    switch usage {
    case 0x00e9: return .rotateLeft
    case 0x00ea: return .rotateRight
    case 0x00e2: return .press
    case 0x006f: return .pressRotateLeft
    case 0x0070: return .pressRotateRight
    default: return nil
    }
}

private func defaultActions() -> [String: ActionConfig] {
    var actions: [String: ActionConfig] = [:]
    for input in KnobInput.allCases {
        actions[input.rawValue] = ActionConfig.empty()
    }
    return actions
}

private func optionalString(_ binding: Binding<String?>) -> Binding<String> {
    Binding(
        get: { binding.wrappedValue ?? "" },
        set: { binding.wrappedValue = $0 }
    )
}

private func optionalInt(_ binding: Binding<Int?>, defaultValue: Int) -> Binding<Int> {
    Binding(
        get: { binding.wrappedValue ?? defaultValue },
        set: { binding.wrappedValue = $0 }
    )
}

private func deviceName(_ device: IOHIDDevice) -> String {
    let product = property(device, kIOHIDProductKey) ?? "unknown"
    let manufacturer = property(device, kIOHIDManufacturerKey) ?? "unknown"
    let serial = property(device, kIOHIDSerialNumberKey) ?? "unknown"
    return "\(product) / \(manufacturer) / \(serial)"
}

private func property(_ device: IOHIDDevice, _ key: String) -> String? {
    IOHIDDeviceGetProperty(device, key as CFString).map { "\($0)" }
}

private func appName(bundle: Bundle, url: URL) -> String {
    let localizedName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
    let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
    return localizedName ?? bundleName ?? url.deletingPathExtension().lastPathComponent
}

private func isVisibleApplication(bundle: Bundle) -> Bool {
    let backgroundOnly = bundle.object(forInfoDictionaryKey: "LSBackgroundOnly") as? Bool ?? false
    let uiElement = bundle.object(forInfoDictionaryKey: "LSUIElement") as? Bool ?? false
    return !backgroundOnly && !uiElement
}

private func appInfoFromBundleID(_ bundleID: String) -> AppInfo? {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
          let bundle = Bundle(url: url) else {
        return nil
    }

    return AppInfo(
        bundleID: bundleID,
        name: appName(bundle: bundle, url: url),
        path: url.path,
        isRunning: NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleID && $0.activationPolicy == .regular
        }
    )
}

private func displayKeyList(_ keys: [String]) -> String {
    keys.map { displayKeyName($0) }.joined(separator: " + ")
}

private func parseKeyList(_ text: String) -> [String] {
    text
        .replacingOccurrences(of: "+", with: ",")
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .compactMap { tokenFromDisplayName($0) }
}

private func displayKeyName(_ token: String) -> String {
    switch token.lowercased() {
    case "command", "cmd": return "⌘"
    case "control", "ctrl": return "⌃"
    case "option", "opt", "alt": return "⌥"
    case "shift": return "⇧"
    case "fn": return "fn"
    case "volume_down": return "降低音量"
    case "volume_up": return "提高音量"
    case "play_pause": return "播放/暂停"
    case "previous_track": return "上一首"
    case "next_track": return "下一首"
    case "mute": return "静音"
    case "return": return "回车"
    case "escape", "esc": return "退出"
    case "left": return "左方向"
    case "right": return "右方向"
    case "up": return "上方向"
    case "down": return "下方向"
    case "space": return "空格"
    default:
        return token.count == 1 ? token.uppercased() : token
    }
}

private func tokenFromDisplayName(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    switch trimmed.lowercased() {
    case "⌘", "command", "cmd", "命令": return "command"
    case "⌃", "control", "ctrl", "控制": return "control"
    case "⌥", "option", "opt", "alt", "选项": return "option"
    case "⇧", "shift", "换挡", "上档": return "shift"
    case "fn", "功能": return "fn"
    case "降低音量": return "volume_down"
    case "提高音量": return "volume_up"
    case "播放/暂停", "播放", "暂停": return "play_pause"
    case "上一首", "上一个媒体项目": return "previous_track"
    case "下一首", "下一个媒体项目": return "next_track"
    case "静音": return "mute"
    case "回车", "return", "enter": return "return"
    case "退出", "escape", "esc": return "escape"
    case "左方向", "left": return "left"
    case "右方向", "right": return "right"
    case "上方向", "up": return "up"
    case "下方向", "down": return "down"
    case "空格", "space": return "space"
    default:
        return trimmed.lowercased()
    }
}

private func keyName(for event: NSEvent) -> String? {
    if let named = keyNameByCode[CGKeyCode(event.keyCode)] {
        return named
    }

    guard let characters = event.charactersIgnoringModifiers?.lowercased(),
          let first = characters.first else {
        return nil
    }

    return String(first)
}

private func clock() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: Date())
}

private func hex<T: FixedWidthInteger>(_ value: T, width: Int) -> String {
    String(format: "%0\(width)x", UInt64(value))
}

private func findProjectRoot() -> URL {
    let fm = FileManager.default
    var candidates: [URL] = []
    candidates.append(URL(fileURLWithPath: fm.currentDirectoryPath))

    if let env = ProcessInfo.processInfo.environment["ANTICATER_KNOB_HOME"] {
        candidates.append(URL(fileURLWithPath: env))
    }

    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    var cursor = executable.deletingLastPathComponent()
    for _ in 0..<8 {
        candidates.append(cursor)
        cursor.deleteLastPathComponent()
    }

    for candidate in candidates {
        if fm.fileExists(atPath: candidate.appendingPathComponent("config/app-mapping.json").path)
            || fm.fileExists(atPath: candidate.appendingPathComponent("config/app-mapping.example.json").path) {
            return candidate
        }
    }

    return URL(fileURLWithPath: fm.currentDirectoryPath)
}
