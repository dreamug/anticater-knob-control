import AppKit
import SwiftUI
import IOKit.hid
import AudioToolbox

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

private enum ModifierMode: String, CaseIterable, Identifiable, Codable {
    case none
    case command
    case shift
    case option
    case control
    case commandShift = "command_shift"
    case commandOption = "command_option"
    case commandControl = "command_control"
    case shiftOption = "shift_option"
    case shiftControl = "shift_control"
    case optionControl = "option_control"
    case commandShiftOption = "command_shift_option"
    case commandShiftControl = "command_shift_control"
    case commandOptionControl = "command_option_control"
    case shiftOptionControl = "shift_option_control"
    case commandShiftOptionControl = "command_shift_option_control"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "无修饰键"
        case .command: return "⌘ 命令键"
        case .shift: return "⇧ 上档键"
        case .option: return "⌥ 选项键"
        case .control: return "⌃ 控制键"
        case .commandShift: return "⌘⇧ 命令键 + 上档键"
        case .commandOption: return "⌘⌥ 命令键 + 选项键"
        case .commandControl: return "⌘⌃ 命令键 + 控制键"
        case .shiftOption: return "⇧⌥ 上档键 + 选项键"
        case .shiftControl: return "⇧⌃ 上档键 + 控制键"
        case .optionControl: return "⌥⌃ 选项键 + 控制键"
        case .commandShiftOption: return "⌘⇧⌥ 命令键 + 上档键 + 选项键"
        case .commandShiftControl: return "⌘⇧⌃ 命令键 + 上档键 + 控制键"
        case .commandOptionControl: return "⌘⌥⌃ 命令键 + 选项键 + 控制键"
        case .shiftOptionControl: return "⇧⌥⌃ 上档键 + 选项键 + 控制键"
        case .commandShiftOptionControl: return "⌘⇧⌥⌃ 全部修饰键"
        }
    }

    var compactTitle: String {
        switch self {
        case .none: return ""
        case .command: return "⌘"
        case .shift: return "⇧"
        case .option: return "⌥"
        case .control: return "⌃"
        case .commandShift: return "⌘⇧"
        case .commandOption: return "⌘⌥"
        case .commandControl: return "⌘⌃"
        case .shiftOption: return "⇧⌥"
        case .shiftControl: return "⇧⌃"
        case .optionControl: return "⌥⌃"
        case .commandShiftOption: return "⌘⇧⌥"
        case .commandShiftControl: return "⌘⇧⌃"
        case .commandOptionControl: return "⌘⌥⌃"
        case .shiftOptionControl: return "⇧⌥⌃"
        case .commandShiftOptionControl: return "⌘⇧⌥⌃"
        }
    }

    func mappingKey(for input: KnobInput) -> String {
        self == .none ? input.rawValue : "\(rawValue)+\(input.rawValue)"
    }

    func gestureTitle(for input: KnobInput) -> String {
        let base = "\(gestureSymbol(input)) \(input.title)"
        guard self != .none else { return base }
        return "\(compactTitle) + \(base)"
    }

    static func current() -> ModifierMode {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        var parts: [String] = []
        if flags.contains(.maskCommand) { parts.append("command") }
        if flags.contains(.maskShift) { parts.append("shift") }
        if flags.contains(.maskAlternate) { parts.append("option") }
        if flags.contains(.maskControl) { parts.append("control") }
        guard !parts.isEmpty else { return .none }
        return allCases.first { $0.rawValue == parts.joined(separator: "_") } ?? .none
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

private enum ActionTemplate: String, CaseIterable, Identifiable {
    case browser
    case coding
    case media
    case design
    case editing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .browser: return "浏览器"
        case .coding: return "代码编辑"
        case .media: return "媒体控制"
        case .design: return "设计绘图"
        case .editing: return "剪辑时间线"
        }
    }

    var subtitle: String {
        switch self {
        case .browser: return "标签页、刷新、前进后退"
        case .coding: return "编辑器切换、命令面板、问题跳转"
        case .media: return "音量、播放暂停、上一首下一首"
        case .design: return "画笔大小、硬度、画笔工具"
        case .editing: return "逐帧移动、播放暂停、大步移动"
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

private struct AppContext {
    let name: String
    let bundleID: String
}

private struct ActionResolution {
    let action: ActionConfig?
    let source: String
}

private struct PendingPressAction {
    let date: Date
    let app: AppContext
    let resolution: ActionResolution
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
    private let legacyConfigURL: URL

    init() {
        projectRoot = findProjectRoot()
        configURL = userConfigURL()
        legacyConfigURL = projectRoot.appendingPathComponent("config/app-mapping.json")

        do {
            let url = Self.initialConfigURL(
                configURL: configURL,
                legacyConfigURL: legacyConfigURL,
                projectRoot: projectRoot
            )
            let data = try Data(contentsOf: url)
            config = try JSONDecoder().decode(MappingConfig.self, from: data)
            if url != configURL {
                save(silent: true)
                status = "已迁移配置到 \(configURL.path)"
            } else {
                status = "已加载本地配置：\(configURL.path)"
            }
        } catch {
            config = MappingConfig(global: defaultActions(), apps: [:])
            save(silent: true)
            status = "配置加载失败，已创建本地配置：\(configURL.path)"
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

    func actionBinding(_ input: KnobInput, modifierMode: ModifierMode) -> Binding<ActionConfig> {
        let key = modifierMode.mappingKey(for: input)
        return Binding(
            get: {
                switch self.selectedProfile {
                case .global:
                    return self.config.global[key] ?? ActionConfig.empty()
                case .app(let bundleID):
                    return self.config.apps[bundleID]?[key] ?? self.config.global[key] ?? ActionConfig.empty()
                }
            },
            set: { newValue in
                switch self.selectedProfile {
                case .global:
                    self.config.global[key] = newValue
                case .app(let bundleID):
                    var appActions = self.config.apps[bundleID] ?? [:]
                    appActions[key] = newValue
                    self.config.apps[bundleID] = appActions
                }
                self.save(silent: true)
            }
        )
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
        save(silent: true)
    }

    func addCurrentApp(template: ActionTemplate? = nil, modifierMode: ModifierMode = .none) {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else {
            status = "没有找到当前应用"
            return
        }

        addApp(bundleID: bundleID)
        if let template {
            applyTemplate(template, modifierMode: modifierMode)
        }
    }

    func applyTemplate(_ template: ActionTemplate, modifierMode: ModifierMode = .none) {
        let actions = templateActions(template)
        let modeSuffix = modifierMode == .none ? "" : "（\(modifierMode.title)）"
        switch selectedProfile {
        case .global:
            if modifierMode == .none {
                config.global = actions
            } else {
                config.global = merging(actions, into: config.global, modifierMode: modifierMode)
            }
            status = "已应用「\(template.title)」模板到全局默认\(modeSuffix)"
        case .app(let bundleID):
            if modifierMode == .none {
                config.apps[bundleID] = actions
            } else {
                var appActions = config.apps[bundleID] ?? defaultActions()
                appActions = merging(actions, into: appActions, modifierMode: modifierMode)
                config.apps[bundleID] = appActions
            }
            status = "已应用「\(template.title)」模板\(modeSuffix)"
        }
        save(silent: true)
    }

    func deleteSelectedApp() {
        guard case .app(let bundleID) = selectedProfile else { return }
        config.apps.removeValue(forKey: bundleID)
        selectedProfile = .global
        status = "已删除 \(bundleID)"
        save(silent: true)
    }

    func reload() {
        do {
            let data = try Data(contentsOf: configURL)
            config = try JSONDecoder().decode(MappingConfig.self, from: data)
            status = "已重新加载本地配置：\(configURL.path)"
        } catch {
            status = "重新加载失败：\(error.localizedDescription)"
        }
    }

    func save(silent: Bool = false) {
        do {
            try FileManager.default.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(config)
            try data.write(to: configURL)
            if !silent {
                status = "已保存本地配置：\(configURL.path)"
            }
        } catch {
            if !silent {
                status = "保存失败：\(error.localizedDescription)"
            }
        }
    }

    private static func initialConfigURL(configURL: URL, legacyConfigURL: URL, projectRoot: URL) -> URL {
        let exampleURL = projectRoot.appendingPathComponent("config/app-mapping.example.json")
        let fm = FileManager.default
        if fm.fileExists(atPath: configURL.path) {
            return configURL
        }
        if fm.fileExists(atPath: legacyConfigURL.path) {
            return legacyConfigURL
        }
        return exampleURL
    }

    func action(for input: KnobInput, modifierMode: ModifierMode, activeBundleID: String, activeAppName: String, lockedBundleID: String?) -> ActionResolution {
        if let lockedBundleID, lockedBundleID == activeBundleID {
            if let appActions = config.apps[activeBundleID] {
                if let action = appActions[modifierMode.mappingKey(for: input)], modifierMode != .none {
                    return ActionResolution(action: action, source: "\(activeAppName) 映射 · \(modifierMode.compactTitle)")
                }
                if let action = appActions[input.rawValue] {
                    return ActionResolution(action: action, source: "\(activeAppName) 映射")
                }
            }
            if let action = config.global[modifierMode.mappingKey(for: input)], modifierMode != .none {
                return ActionResolution(action: action, source: "全局默认 · \(modifierMode.compactTitle)")
            }
            return ActionResolution(action: config.global[input.rawValue], source: "全局默认")
        }

        if let action = config.global[modifierMode.mappingKey(for: input)], modifierMode != .none {
            return ActionResolution(action: action, source: "全局默认 · \(modifierMode.compactTitle)")
        }
        return ActionResolution(action: config.global[input.rawValue], source: "全局默认")
    }

    private func merging(_ source: [String: ActionConfig], into target: [String: ActionConfig], modifierMode: ModifierMode) -> [String: ActionConfig] {
        var result = target
        for input in KnobInput.allCases {
            result[modifierMode.mappingKey(for: input)] = source[input.rawValue] ?? ActionConfig.empty()
        }
        return result
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
    @Published private(set) var lockedBundleID: String?
    @Published private(set) var lockedAppName: String?
    @Published private(set) var inputCounts: [KnobInput: Int] = [:]
    @Published private(set) var lastInput: KnobInput?
    @Published private(set) var lastModifierMode: ModifierMode = .none
    @Published private(set) var pressSequenceCount = 0
    @Published private(set) var rawEventCount = 0
    @Published private(set) var decodedEventCount = 0
    @Published private(set) var ignoredEventCount = 0
    @Published private(set) var lastRawEvent = "暂无 HID 输入"
    @Published private(set) var inputAccessStatus = "输入监控：未检查"
    @Published private(set) var accessibilityStatus = "辅助功能：未检查"

    private let triplePressGap: TimeInterval = 0.55
    private var manager: IOHIDManager?
    private weak var store: ConfigStore?
    private var pendingPressActions: [PendingPressAction] = []
    private var pendingPressWorkItem: DispatchWorkItem?
    private var pendingPressTargetApp: AppContext?
    private var lastExternalApp: AppContext?
    private var listenMode = "未监听"
    private var connectedDeviceName: String?

    var lockModeTitle: String {
        if let lockedAppName {
            return "已锁定 \(lockedAppName)"
        }
        return "全局默认"
    }

    func effectiveMappingTitle(frontmostBundleID: String, frontmostName: String) -> String {
        if isSelfApp(bundleID: frontmostBundleID) {
            return "全局默认"
        }
        guard let lockedBundleID else {
            return "全局默认"
        }
        if lockedBundleID == frontmostBundleID {
            return "\(frontmostName) 映射"
        }
        return "全局默认"
    }

    func toggle(store: ConfigStore) {
        isRunning ? stop() : start(store: store)
    }

    func start(store: ConfigStore) {
        guard !isRunning else { return }

        refreshInputAccessStatus()
        refreshAccessibilityStatus()
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
            Task { @MainActor in service.updateConnectedDevice(deviceName(device)) }
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
            let input = knobInput(page: page, usage: usage)

            Task { @MainActor in
                service.recordHIDEvent(page: page, usage: usage, intValue: intValue, input: input)
            }

            guard intValue == 1, let input else {
                return
            }

            Task { @MainActor in service.handle(input) }
        }, Unmanaged.passUnretained(self).toOpaque())

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let seizedResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        if seizedResult == kIOReturnSuccess {
            listenMode = "独占监听"
            deviceStatus = "已启动独占监听"
        } else {
            let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            guard openResult == kIOReturnSuccess else {
                deviceStatus = "启动失败：独占 0x\(hex(UInt32(bitPattern: seizedResult), width: 8)) / 普通 0x\(hex(UInt32(bitPattern: openResult), width: 8))"
                lastEvent = "请在系统设置里重新添加「手轮控制台」到输入监控"
                self.manager = nil
                return
            }
            listenMode = "普通监听"
            deviceStatus = "已启动普通监听，系统音量可能仍会响应"
        }

        if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let first = devices.first {
            updateConnectedDevice(deviceName(first))
        }

        isRunning = true
        lastEvent = "\(clock()) 已启动监听"
    }

    func stop() {
        guard let manager else { return }
        flushPendingPressActions()
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        isRunning = false
        listenMode = "未监听"
        deviceStatus = "已停止"
        lastEvent = "\(clock()) 已停止监听"
    }

    func clearMappingLock() {
        lockedBundleID = nil
        lockedAppName = nil
        lastEvent = "\(clock()) 已恢复全局默认"
    }

    func inputCount(for input: KnobInput) -> Int {
        inputCounts[input, default: 0]
    }

    func resetInputCounters() {
        inputCounts = [:]
        lastInput = nil
        lastModifierMode = .none
        pressSequenceCount = 0
        rawEventCount = 0
        decodedEventCount = 0
        ignoredEventCount = 0
        lastRawEvent = "暂无 HID 输入"
        lastEvent = "\(clock()) 已清空输入计数"
    }

    func testSystemVolume() {
        let action = ActionConfig(
            type: "key",
            description: "音量自检",
            keys: ["volume_up"],
            button: nil,
            clicks: nil,
            dx: nil,
            dy: nil,
            command: nil
        )
        let result = ActionExecutor.run(action)
        let detail = result.detail ?? action.description ?? "音量自检"
        lastEvent = "\(clock()) 音量自检 / \(detail) / \(result.ok ? "ok" : "failed")"
        OverlayPresenter.shared.show(result.overlay ?? ActionOverlayPayload(
            title: result.ok ? "音量自检完成" : "音量自检失败",
            subtitle: detail,
            systemImage: result.ok ? "speaker.wave.2.fill" : "exclamationmark.triangle.fill",
            tint: result.ok ? .accentColor : .red,
            progress: nil,
            ok: result.ok
        ))
    }

    func requestInputMonitoringAccess() {
        let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        refreshInputAccessStatus()
        lastEvent = granted ? "\(clock()) 输入监控权限已允许" : "\(clock()) 已请求输入监控权限，请在系统设置确认"
    }

    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
            lastEvent = "\(clock()) 已打开输入监控设置"
        }
    }

    func requestAccessibilityAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)
        refreshAccessibilityStatus()
        lastEvent = granted ? "\(clock()) 辅助功能权限已允许" : "\(clock()) 已请求辅助功能权限，请在系统设置确认"
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
            lastEvent = "\(clock()) 已打开辅助功能设置"
        }
    }

    private func handle(_ input: KnobInput) {
        guard let store else { return }
        let app = currentAppContext()
        let modifierMode = ModifierMode.current()
        rememberExternalApp(app)
        recordInput(input, modifierMode: modifierMode)

        if input == .press, modifierMode == .none {
            handlePress(app: app, store: store)
            return
        }

        let resolution = store.action(
            for: input,
            modifierMode: modifierMode,
            activeBundleID: app.bundleID,
            activeAppName: app.name,
            lockedBundleID: effectiveLockedBundleID(for: app)
        )
        perform(input: input, modifierMode: modifierMode, app: app, resolution: resolution)
    }

    private func handlePress(app: AppContext, store: ConfigStore) {
        let now = Date()
        if let last = pendingPressActions.last,
           now.timeIntervalSince(last.date) > triplePressGap {
            flushPendingPressActions()
        }

        let targetApp = pendingPressTargetApp ?? lockTargetApp(for: app)
        pendingPressTargetApp = targetApp

        let resolution = store.action(
            for: .press,
            modifierMode: .none,
            activeBundleID: app.bundleID,
            activeAppName: app.name,
            lockedBundleID: effectiveLockedBundleID(for: app)
        )
        pendingPressActions.append(PendingPressAction(date: now, app: app, resolution: resolution))
        pressSequenceCount = pendingPressActions.count

        if pendingPressActions.count >= 3 {
            cancelPendingPressWorkItem()
            pendingPressActions.removeAll()
            pressSequenceCount = 0
            pendingPressTargetApp = nil
            toggleMappingLock(for: targetApp)
            return
        }

        lastEvent = "\(clock()) press / \(targetApp.name) / 等待三击确认（\(pendingPressActions.count)/3）"
        OverlayPresenter.shared.show(ActionOverlayPayload(
            title: "三击确认 \(pendingPressActions.count)/3",
            subtitle: "目标：\(targetApp.name)",
            systemImage: "hand.tap.fill",
            tint: .accentColor,
            progress: Double(pendingPressActions.count) / 3.0,
            ok: true
        ))
        schedulePendingPressFlush()
    }

    private func toggleMappingLock(for app: AppContext) {
        guard app.bundleID != "unknown" else {
            lastEvent = "\(clock()) 三击 / 没有找到当前应用"
            OverlayPresenter.shared.show(ActionOverlayPayload(
                title: "三击失败",
                subtitle: "没有找到当前应用",
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange,
                progress: nil,
                ok: false
            ))
            return
        }
        guard !isSelfApp(bundleID: app.bundleID) else {
            lockedBundleID = nil
            lockedAppName = nil
            lastEvent = "\(clock()) 三击 / 控制台使用全局默认"
            OverlayPresenter.shared.show(ActionOverlayPayload(
                title: "已恢复全局默认",
                subtitle: "控制台不启用应用锁定",
                systemImage: "lock.open.fill",
                tint: .accentColor,
                progress: nil,
                ok: true
            ))
            return
        }

        if lockedBundleID == app.bundleID {
            lockedBundleID = nil
            lockedAppName = nil
            lastEvent = "\(clock()) 三击 / 已恢复全局默认"
            OverlayPresenter.shared.show(ActionOverlayPayload(
                title: "已恢复全局默认",
                subtitle: app.name,
                systemImage: "lock.open.fill",
                tint: .accentColor,
                progress: nil,
                ok: true
            ))
        } else {
            lockedBundleID = app.bundleID
            lockedAppName = app.name
            lastEvent = "\(clock()) 三击 / 已锁定 \(app.name)"
            OverlayPresenter.shared.show(ActionOverlayPayload(
                title: "已锁定 \(app.name)",
                subtitle: "应用映射已生效",
                systemImage: "lock.fill",
                tint: .accentColor,
                progress: nil,
                ok: true
            ))
        }
    }

    private func schedulePendingPressFlush() {
        cancelPendingPressWorkItem()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.flushPendingPressActions()
            }
        }
        pendingPressWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + triplePressGap, execute: workItem)
    }

    private func cancelPendingPressWorkItem() {
        pendingPressWorkItem?.cancel()
        pendingPressWorkItem = nil
    }

    private func flushPendingPressActions() {
        cancelPendingPressWorkItem()
        let actions = pendingPressActions
        pendingPressActions.removeAll()
        pendingPressTargetApp = nil
        pressSequenceCount = 0

        for pending in actions {
            perform(input: .press, modifierMode: .none, app: pending.app, resolution: pending.resolution)
        }
    }

    private func rememberExternalApp(_ app: AppContext) {
        guard app.bundleID != "unknown", !isSelfApp(bundleID: app.bundleID) else { return }
        lastExternalApp = app
    }

    private func lockTargetApp(for app: AppContext) -> AppContext {
        if app.bundleID != "unknown", !isSelfApp(bundleID: app.bundleID) {
            return app
        }
        return lastExternalApp ?? app
    }

    private func recordInput(_ input: KnobInput, modifierMode: ModifierMode) {
        inputCounts[input, default: 0] += 1
        lastInput = input
        lastModifierMode = modifierMode
    }

    private func recordHIDEvent(page: UInt32, usage: UInt32, intValue: Int, input: KnobInput?) {
        rawEventCount += 1
        if intValue == 1, input != nil {
            decodedEventCount += 1
        } else {
            ignoredEventCount += 1
        }

        let decoded = input.map { " -> \($0.title)" } ?? ""
        lastRawEvent = "page=0x\(hex(page, width: 4)) usage=0x\(hex(usage, width: 4)) int=\(intValue)\(decoded)"
    }

    private func refreshInputAccessStatus() {
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        if access == kIOHIDAccessTypeGranted {
            inputAccessStatus = "输入监控：已允许"
        } else if access == kIOHIDAccessTypeDenied {
            inputAccessStatus = "输入监控：未允许"
        } else {
            inputAccessStatus = "输入监控：未决定"
        }
    }

    private func perform(input: KnobInput, modifierMode: ModifierMode, app: AppContext, resolution: ActionResolution) {
        let gestureTitle = modifierMode.gestureTitle(for: input)
        guard let action = resolution.action else {
            lastEvent = "\(clock()) \(gestureTitle) / \(app.name) / \(resolution.source) / 无动作"
            OverlayPresenter.shared.show(ActionOverlayPayload(
                title: "无动作",
                subtitle: "\(gestureTitle) · \(resolution.source)",
                systemImage: overlaySystemImage(for: input),
                tint: .secondary,
                progress: nil,
                ok: true
            ))
            return
        }

        refreshAccessibilityStatus()
        if ActionExecutor.needsAccessibility(action), !AXIsProcessTrusted() {
            lastEvent = "\(clock()) \(gestureTitle) / \(app.name) / \(resolution.source) / 需要辅助功能权限 / failed"
            OverlayPresenter.shared.show(ActionOverlayPayload(
                title: "需要辅助功能权限",
                subtitle: "\(gestureTitle) · \(resolution.source)",
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange,
                progress: nil,
                ok: false
            ))
            return
        }

        let result = ActionExecutor.run(action)
        let detail = result.detail ?? (action.description?.isEmpty == false ? action.description! : action.type)
        lastEvent = "\(clock()) \(gestureTitle) / \(app.name) / \(resolution.source) / \(detail) / \(result.ok ? "ok" : "failed")"
        let overlay = result.overlay ?? ActionOverlayPayload(
            title: result.ok ? detail : "执行失败",
            subtitle: "\(gestureTitle) · \(resolution.source)",
            systemImage: result.ok ? overlaySystemImage(for: input) : "exclamationmark.triangle.fill",
            tint: result.ok ? .accentColor : .red,
            progress: nil,
            ok: result.ok
        )
        OverlayPresenter.shared.show(overlay)
    }

    private func currentAppContext() -> AppContext {
        let app = NSWorkspace.shared.frontmostApplication
        return AppContext(
            name: app?.localizedName ?? "unknown",
            bundleID: app?.bundleIdentifier ?? "unknown"
        )
    }

    private func effectiveLockedBundleID(for app: AppContext) -> String? {
        isSelfApp(bundleID: app.bundleID) ? nil : lockedBundleID
    }

    private func isSelfApp(bundleID: String) -> Bool {
        bundleID == Bundle.main.bundleIdentifier
    }

    private func updateConnectedDevice(_ name: String) {
        connectedDeviceName = name
        deviceStatus = "\(listenMode)：\(name)"
    }

    private func refreshAccessibilityStatus() {
        accessibilityStatus = AXIsProcessTrusted() ? "辅助功能：已允许" : "辅助功能：未允许"
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

        MenuBarExtra("手轮控制台", systemImage: "slider.horizontal.3") {
            Button("显示控制台") {
                NSApp.activate(ignoringOtherApps: true)
            }
            Button(knobService.isRunning ? "停止监听" : "启动监听") {
                knobService.toggle(store: store)
            }
            Divider()
            Text(knobService.deviceStatus)
            Text(knobService.inputAccessStatus)
            Text(knobService.accessibilityStatus)
            Text("映射模式：\(knobService.lockModeTitle)")
            Text(knobService.lastEvent)
            Divider()
            Button("退出") {
                knobService.stop()
                NSApp.terminate(nil)
            }
        }
    }
}

private struct ContentView: View {
    @EnvironmentObject private var store: ConfigStore
    @EnvironmentObject private var frontmost: FrontmostAppModel
    @EnvironmentObject private var knobService: KnobService
    @EnvironmentObject private var appCatalog: AppCatalog
    @State private var newBundleID = ""
    @State private var selectedTemplate: ActionTemplate = .browser
    @State private var selectedModifierMode: ModifierMode = .none

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

                Button("重新加载") {
                    store.reload()
                }

                Button("保存配置") {
                    store.save()
                }
            }

            StatusDashboard(
                running: knobService.isRunning,
                deviceStatus: knobService.deviceStatus,
                frontmostName: frontmost.name,
                lockMode: knobService.lockModeTitle,
                effectiveMapping: knobService.effectiveMappingTitle(
                    frontmostBundleID: frontmost.bundleID,
                    frontmostName: frontmost.name
                ),
                inputAccessStatus: knobService.inputAccessStatus,
                accessibilityStatus: knobService.accessibilityStatus,
                inputCounts: knobService.inputCounts,
                lastInput: knobService.lastInput,
                lastModifierMode: knobService.lastModifierMode,
                pressSequenceCount: knobService.pressSequenceCount,
                rawEventCount: knobService.rawEventCount,
                decodedEventCount: knobService.decodedEventCount,
                ignoredEventCount: knobService.ignoredEventCount,
                lastRawEvent: knobService.lastRawEvent,
                lastEvent: knobService.lastEvent
            )

            templateBar
        }
        .padding(18)
    }

    private var templateBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("编辑模式")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("修饰键", selection: $selectedModifierMode) {
                    ForEach(ModifierMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .frame(width: 230)

                Text(selectedModifierMode == .none ? "正在编辑普通手轮动作" : "正在编辑 \(selectedModifierMode.title) + 手轮动作")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Text("快速模板")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("模板", selection: $selectedTemplate) {
                    ForEach(ActionTemplate.allCases) { template in
                        Text(template.title).tag(template)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)

                Button("应用到当前配置") {
                    store.applyTemplate(selectedTemplate, modifierMode: selectedModifierMode)
                }

                Button("为当前应用创建并套用") {
                    store.addCurrentApp(template: selectedTemplate, modifierMode: selectedModifierMode)
                }

                Menu("监听工具") {
                    Button("解除三击锁定") {
                        knobService.clearMappingLock()
                    }
                    .disabled(knobService.lockedBundleID == nil)

                    Button("清空计数") {
                        knobService.resetInputCounters()
                    }

                    Button("音量自检") {
                        knobService.testSystemVolume()
                    }
                }

                Menu("权限设置") {
                    Button("请求权限") {
                        knobService.requestInputMonitoringAccess()
                    }

                    Button("打开输入监控") {
                        knobService.openInputMonitoringSettings()
                    }

                    Button("请求辅助功能") {
                        knobService.requestAccessibilityAccess()
                    }

                    Button("打开辅助功能") {
                        knobService.openAccessibilitySettings()
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var editor: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(KnobInput.allCases) { input in
                    ActionEditorRow(
                        input: input,
                        modifierMode: selectedModifierMode,
                        action: store.actionBinding(input, modifierMode: selectedModifierMode)
                    )
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
                .help(store.configURL.path)
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
    let modifierMode: ModifierMode
    @Binding var action: ActionConfig
    @State private var showShortcutRecorder = false

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
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(gestureSymbol(input))
                            .font(.title3.weight(.semibold))
                            .frame(width: 24)
                        Text(modifierMode == .none ? input.title : "\(modifierMode.compactTitle) + \(input.title)")
                            .font(.headline)
                    }
                    Text(actionSummary(action))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 150, alignment: .leading)

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
        .sheet(isPresented: $showShortcutRecorder) {
            ShortcutRecorderSheet(input: input, modifierMode: modifierMode) { keys in
                action.keys = keys
                showShortcutRecorder = false
            } onCancel: {
                showShortcutRecorder = false
            }
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
                Button("录制组合键") {
                    showShortcutRecorder = true
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

}

private struct ShortcutRecorderSheet: View {
    let input: KnobInput
    let modifierMode: ModifierMode
    let onCapture: ([String]) -> Void
    let onCancel: () -> Void
    @State private var preview = "等待输入"
    @State private var monitor: Any?

    var body: some View {
        VStack(spacing: 18) {
            Text("录制组合键")
                .font(.title2.weight(.semibold))
            Text("为「\(modifierMode.gestureTitle(for: input))」按下你想绑定的组合键")
                .foregroundStyle(.secondary)
            Text(preview)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("取消") {
                    stop()
                    onCancel()
                }
                Button("清空") {
                    stop()
                    onCapture([])
                }
            }
        }
        .padding(28)
        .frame(width: 420)
        .onAppear { start() }
        .onDisappear { stop() }
    }

    private func start() {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard let key = keyName(for: event) else { return nil }
            var keys: [String] = []
            let flags = event.modifierFlags
            if flags.contains(.command) { keys.append("command") }
            if flags.contains(.control) { keys.append("control") }
            if flags.contains(.option) { keys.append("option") }
            if flags.contains(.shift) { keys.append("shift") }
            // macOS often sets .function for hardware/layout reasons even when Fn was not intentionally held.
            // Keep Fn available for manual input, but do not add it during shortcut recording.
            keys.append(key)
            preview = displayKeyList(keys)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                stop()
                onCapture(keys)
            }
            return nil
        }
    }

    private func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
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

private struct StatusDashboard: View {
    let running: Bool
    let deviceStatus: String
    let frontmostName: String
    let lockMode: String
    let effectiveMapping: String
    let inputAccessStatus: String
    let accessibilityStatus: String
    let inputCounts: [KnobInput: Int]
    let lastInput: KnobInput?
    let lastModifierMode: ModifierMode
    let pressSequenceCount: Int
    let rawEventCount: Int
    let decodedEventCount: Int
    let ignoredEventCount: Int
    let lastRawEvent: String
    let lastEvent: String

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                DashboardTile(
                    title: "设备状态",
                    value: running ? "监听中" : "未监听",
                    detail: "\(deviceStatus) · \(inputAccessStatus) · \(accessibilityStatus)",
                    color: running ? .green : .gray
                )
                DashboardTile(
                    title: "当前应用",
                    value: frontmostName,
                    detail: "正在使用：\(effectiveMapping)",
                    color: .blue
                )
                DashboardTile(
                    title: "三击锁定",
                    value: lockMode,
                    detail: pressSequenceCount > 0 ? "按下计数：\(pressSequenceCount)/3" : "快速按下三次切换当前应用",
                    color: .purple
                )
                DashboardTile(
                    title: "最近动作",
                    value: lastEvent == "暂无事件" ? "等待手轮输入" : lastEvent,
                    detail: "实时执行反馈",
                    color: .orange
                )
            }

            InputMonitorStrip(
                inputCounts: inputCounts,
                lastInput: lastInput,
                lastModifierMode: lastModifierMode,
                rawEventCount: rawEventCount,
                decodedEventCount: decodedEventCount,
                ignoredEventCount: ignoredEventCount,
                lastRawEvent: lastRawEvent
            )
        }
    }
}

private struct InputMonitorStrip: View {
    let inputCounts: [KnobInput: Int]
    let lastInput: KnobInput?
    let lastModifierMode: ModifierMode
    let rawEventCount: Int
    let decodedEventCount: Int
    let ignoredEventCount: Int
    let lastRawEvent: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("输入监视")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("原始 \(rawEventCount)")
                Text("识别 \(decodedEventCount)")
                Text("忽略 \(ignoredEventCount)")
                Text("最近 \(lastInput.map { lastModifierMode.gestureTitle(for: $0) } ?? "暂无")")
                    .foregroundStyle(.secondary)
                Text(lastRawEvent)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .font(.caption)

            HStack(spacing: 8) {
                ForEach(KnobInput.allCases) { input in
                    InputCounterPill(
                        input: input,
                        count: inputCounts[input, default: 0],
                        active: lastInput == input
                    )
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct InputCounterPill: View {
    let input: KnobInput
    let count: Int
    let active: Bool

    var body: some View {
        HStack(spacing: 5) {
            Text(gestureSymbol(input))
            Text(input.title)
            Text("\(count)")
                .fontWeight(.semibold)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(active ? Color.accentColor.opacity(0.28) : Color.gray.opacity(0.14), in: Capsule())
    }
}

private struct DashboardTile: View {
    let title: String
    let value: String
    let detail: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }
}

private enum ActionOverlayStyle {
    case action
    case macVolume
}

private struct ActionOverlayPayload {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let progress: Double?
    let ok: Bool
    var style: ActionOverlayStyle = .action
}

private struct ActionOverlayView: View {
    let payload: ActionOverlayPayload

    var body: some View {
        switch payload.style {
        case .action:
            actionOverlay
        case .macVolume:
            MacVolumeOverlayView(payload: payload)
        }
    }

    private var actionOverlay: some View {
        HStack(spacing: 14) {
            Image(systemName: payload.systemImage)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(payload.tint)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 7) {
                Text(payload.title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                Text(payload.subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let progress = payload.progress {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.secondary.opacity(0.18))
                            Capsule()
                                .fill(payload.tint)
                                .frame(width: max(8, proxy.size.width * min(max(progress, 0), 1)))
                        }
                    }
                    .frame(height: 7)
                    .padding(.top, 1)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: 310, height: payload.progress == nil ? 88 : 108)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 22, x: 0, y: 10)
    }
}

private struct MacVolumeOverlayView: View {
    let payload: ActionOverlayPayload

    private let segmentCount = 16

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 28)

            Image(systemName: payload.systemImage)
                .font(.system(size: 86, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.82))
                .frame(height: 92)

            Spacer(minLength: 16)

            HStack(spacing: 3) {
                ForEach(0..<segmentCount, id: \.self) { index in
                    Rectangle()
                        .fill(index < filledSegments ? Color.white.opacity(0.82) : Color.black.opacity(0.34))
                        .frame(width: 8, height: 8)
                }
            }
            .accessibilityLabel(payload.title)

            Spacer(minLength: 24)
        }
        .frame(width: 228, height: 228)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.58),
                    Color.black.opacity(0.48)
                ],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 28, x: 0, y: 14)
    }

    private var filledSegments: Int {
        let progress = min(max(payload.progress ?? 0, 0), 1)
        guard progress > 0 else { return 0 }
        return max(1, Int((progress * Double(segmentCount)).rounded(.up)))
    }
}

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class OverlayPresenter {
    static let shared = OverlayPresenter()

    private var panel: OverlayPanel?
    private var hostingView: NSHostingView<ActionOverlayView>?
    private var hideWorkItem: DispatchWorkItem?

    func show(_ payload: ActionOverlayPayload) {
        hideWorkItem?.cancel()
        let panel = panel(for: payload)
        hostingView?.rootView = ActionOverlayView(payload: payload)
        position(panel, for: payload)

        panel.alphaValue = max(panel.alphaValue, 0.02)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.hide() }
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + displayDuration(for: payload), execute: workItem)
    }

    private func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    private func panel(for payload: ActionOverlayPayload) -> OverlayPanel {
        if let panel { return panel }

        let size = overlaySize(for: payload)
        let panel = OverlayPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let hostingView = NSHostingView(rootView: ActionOverlayView(payload: payload))
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView

        self.panel = panel
        self.hostingView = hostingView
        return panel
    }

    private func position(_ panel: NSPanel, for payload: ActionOverlayPayload) {
        let size = overlaySize(for: payload)
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin: NSPoint
        switch payload.style {
        case .action:
            origin = NSPoint(
                x: screenFrame.maxX - size.width - 28,
                y: screenFrame.maxY - size.height - 34
            )
        case .macVolume:
            origin = NSPoint(
                x: screenFrame.midX - size.width / 2,
                y: screenFrame.midY - size.height / 2
            )
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        hostingView?.frame = NSRect(origin: .zero, size: size)
    }

    private func overlaySize(for payload: ActionOverlayPayload) -> NSSize {
        switch payload.style {
        case .action:
            return NSSize(width: 310, height: payload.progress == nil ? 88 : 108)
        case .macVolume:
            return NSSize(width: 228, height: 228)
        }
    }

    private func displayDuration(for payload: ActionOverlayPayload) -> TimeInterval {
        switch payload.style {
        case .action:
            return 1.6
        case .macVolume:
            return 1.15
        }
    }
}

private struct ActionRunResult {
    let ok: Bool
    let detail: String?
    let overlay: ActionOverlayPayload?

    static func success(_ detail: String? = nil, overlay: ActionOverlayPayload? = nil) -> ActionRunResult {
        ActionRunResult(ok: true, detail: detail, overlay: overlay)
    }

    static func failure(_ detail: String? = nil, overlay: ActionOverlayPayload? = nil) -> ActionRunResult {
        ActionRunResult(ok: false, detail: detail, overlay: overlay)
    }
}

private enum ActionExecutor {
    static func run(_ action: ActionConfig) -> ActionRunResult {
        switch action.type {
        case "shortcut", "key":
            return sendKeys(action.keys ?? [])
        case "mouse":
            return click(button: action.button ?? "left", clicks: action.clicks ?? 1) ? .success() : .failure()
        case "scroll":
            return scroll(dx: action.dx ?? 0, dy: action.dy ?? 0) ? .success() : .failure()
        case "shell":
            return runShell(action.command) ? .success() : .failure()
        case "noop":
            return .success()
        default:
            return .failure("未知动作类型：\(action.type)")
        }
    }

    static func needsAccessibility(_ action: ActionConfig) -> Bool {
        switch action.type {
        case "shortcut", "key", "mouse", "scroll":
            if let keys = action.keys?.map({ $0.lowercased() }), keys.count == 1, SystemAudioController.canHandle(keys[0]) {
                return false
            }
            return true
        default:
            return false
        }
    }

    private static func sendKeys(_ keys: [String]) -> ActionRunResult {
        let normalized = keys.map { $0.lowercased() }
        if normalized.count == 1, SystemAudioController.canHandle(normalized[0]) {
            return SystemAudioController.handle(normalized[0])
        }

        if normalized.count == 1, let media = mediaKeyTypes[normalized[0]] {
            sendMediaKey(media)
            return .success()
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
                return .failure("无法识别按键：\(key)")
            }
        }

        for keyCode in keyCodes {
            sendKey(keyCode, down: true, flags: flags)
            sendKey(keyCode, down: false, flags: flags)
        }
        return .success()
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
            process.waitUntilExit()
            return process.terminationStatus == 0
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

private enum SystemAudioController {
    private struct VolumeSnapshot {
        let value: Float32
        let source: String
    }

    private struct VolumeWrite {
        let ok: Bool
        let source: String
        let status: OSStatus
    }

    static func canHandle(_ key: String) -> Bool {
        ["volume_down", "volume_up", "mute"].contains(key)
    }

    static func handle(_ key: String) -> ActionRunResult {
        switch key {
        case "volume_down":
            return adjustVolume(by: -0.06)
        case "volume_up":
            return adjustVolume(by: 0.06)
        case "mute":
            return toggleMute()
        default:
            return .failure("无法处理系统音量按键：\(key)")
        }
    }

    private static func adjustVolume(by delta: Float32) -> ActionRunResult {
        guard let deviceID = defaultOutputDevice() else {
            return .failure("找不到默认输出设备")
        }

        guard let before = currentVolume(deviceID: deviceID) else {
            return .failure("无法读取默认输出设备音量（device \(deviceID)）")
        }

        let target = min(max(before.value + delta, 0), 1)
        let write = setVolume(deviceID: deviceID, target)
        let after = currentVolume(deviceID: deviceID)
        let beforeText = percent(before.value)
        let targetText = percent(target)
        let afterText = after.map { percent($0.value) } ?? "未知"
        let source = after?.source ?? write.source
        let detail = "音量 \(beforeText) -> \(afterText)（目标 \(targetText)，\(source)，status \(write.status)）"
        let overlayValue = Double(after?.value ?? target)
        let overlay = ActionOverlayPayload(
            title: "音量 \(afterText)",
            subtitle: delta > 0 ? "提高音量 · \(source)" : "降低音量 · \(source)",
            systemImage: speakerImage(for: Float32(overlayValue)),
            tint: write.ok ? .accentColor : .red,
            progress: overlayValue,
            ok: write.ok,
            style: .macVolume
        )
        return write.ok ? .success(detail, overlay: overlay) : .failure(detail, overlay: overlay)
    }

    private static func currentVolume(deviceID: AudioDeviceID) -> VolumeSnapshot? {
        var address = volumeAddress()
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
        if status == noErr {
            return VolumeSnapshot(value: volume, source: "VirtualMain")
        }

        var channelValues: [Float32] = []
        for element in [AudioObjectPropertyElement(1), AudioObjectPropertyElement(2)] {
            var channelAddress = scalarVolumeAddress(element: element)
            guard AudioObjectHasProperty(deviceID, &channelAddress) else { continue }
            var channelVolume = Float32(0)
            var channelSize = UInt32(MemoryLayout<Float32>.size)
            let channelStatus = AudioObjectGetPropertyData(deviceID, &channelAddress, 0, nil, &channelSize, &channelVolume)
            if channelStatus == noErr {
                channelValues.append(channelVolume)
            }
        }

        guard !channelValues.isEmpty else { return nil }
        let average = channelValues.reduce(Float32(0), +) / Float32(channelValues.count)
        return VolumeSnapshot(value: average, source: "声道音量")
    }

    private static func setVolume(deviceID: AudioDeviceID, _ volume: Float32) -> VolumeWrite {
        var address = volumeAddress()
        var newVolume = volume
        let size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectHasProperty(deviceID, &address) {
            var settable = DarwinBoolean(false)
            var settableAddress = address
            let settableStatus = AudioObjectIsPropertySettable(deviceID, &settableAddress, &settable)
            if settableStatus == noErr, settable.boolValue {
                let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &newVolume)
                if status == noErr {
                    return VolumeWrite(ok: true, source: "VirtualMain", status: status)
                }
            }
        }

        var statuses: [OSStatus] = []
        var successes = 0
        for element in [AudioObjectPropertyElement(1), AudioObjectPropertyElement(2)] {
            var channelAddress = scalarVolumeAddress(element: element)
            guard AudioObjectHasProperty(deviceID, &channelAddress) else { continue }
            var channelSettable = DarwinBoolean(false)
            var settableAddress = channelAddress
            let settableStatus = AudioObjectIsPropertySettable(deviceID, &settableAddress, &channelSettable)
            guard settableStatus == noErr, channelSettable.boolValue else {
                statuses.append(settableStatus)
                continue
            }
            var channelVolume = volume
            let status = AudioObjectSetPropertyData(deviceID, &channelAddress, 0, nil, size, &channelVolume)
            statuses.append(status)
            if status == noErr {
                successes += 1
            }
        }

        return VolumeWrite(
            ok: successes > 0,
            source: successes > 0 ? "声道音量" : "无可写音量属性",
            status: statuses.first ?? -1
        )
    }

    private static func toggleMute() -> ActionRunResult {
        guard let deviceID = defaultOutputDevice() else {
            return .failure("找不到默认输出设备")
        }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var muted = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let readStatus = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)
        guard readStatus == noErr else {
            let before = currentVolume(deviceID: deviceID)
            let write = setVolume(deviceID: deviceID, 0)
            let after = currentVolume(deviceID: deviceID)
            let detail = "静音 fallback：音量 \(before.map { percent($0.value) } ?? "未知") -> \(after.map { percent($0.value) } ?? "未知")（status \(write.status)）"
            let overlay = ActionOverlayPayload(
                title: "静音",
                subtitle: "音量 \(after.map { percent($0.value) } ?? "未知")",
                systemImage: "speaker.slash.fill",
                tint: write.ok ? .accentColor : .red,
                progress: after.map { Double($0.value) },
                ok: write.ok,
                style: .macVolume
            )
            return write.ok ? .success(detail, overlay: overlay) : .failure(detail, overlay: overlay)
        }

        var newMuted = muted == 0 ? UInt32(1) : UInt32(0)
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &newMuted)
        let detail = muted == 0 ? "静音已开启（status \(status)）" : "静音已关闭（status \(status)）"
        let ok = status == noErr
        let overlay = ActionOverlayPayload(
            title: muted == 0 ? "静音" : "取消静音",
            subtitle: "默认输出设备",
            systemImage: muted == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill",
            tint: ok ? .accentColor : .red,
            progress: muted == 0 ? 0 : currentVolume(deviceID: deviceID).map { Double($0.value) },
            ok: ok,
            style: .macVolume
        )
        return ok ? .success(detail, overlay: overlay) : .failure(detail, overlay: overlay)
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        return status == noErr ? deviceID : nil
    }

    private static func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func scalarVolumeAddress(element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
    }

    private static func percent(_ value: Float32) -> String {
        "\(Int(round(value * 100)))%"
    }

    private static func speakerImage(for value: Float32) -> String {
        if value <= 0.01 {
            return "speaker.slash.fill"
        }
        if value < 0.36 {
            return "speaker.wave.1.fill"
        }
        return "speaker.wave.3.fill"
    }
}

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
    case 0x00e9: return .rotateRight
    case 0x00ea: return .rotateLeft
    case 0x00e2: return .press
    case 0x006f: return .pressRotateRight
    case 0x0070: return .pressRotateLeft
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

private func templateActions(_ template: ActionTemplate) -> [String: ActionConfig] {
    switch template {
    case .browser:
        return [
            KnobInput.rotateLeft.rawValue: shortcut("上一个标签页", ["control", "shift", "tab"]),
            KnobInput.rotateRight.rawValue: shortcut("下一个标签页", ["control", "tab"]),
            KnobInput.press.rawValue: shortcut("刷新页面", ["command", "r"]),
            KnobInput.pressRotateLeft.rawValue: shortcut("后退", ["command", "["]),
            KnobInput.pressRotateRight.rawValue: shortcut("前进", ["command", "]"])
        ]
    case .coding:
        return [
            KnobInput.rotateLeft.rawValue: shortcut("上一个编辑器", ["command", "shift", "["]),
            KnobInput.rotateRight.rawValue: shortcut("下一个编辑器", ["command", "shift", "]"]),
            KnobInput.press.rawValue: shortcut("命令面板", ["command", "shift", "p"]),
            KnobInput.pressRotateLeft.rawValue: shortcut("上一个问题", ["f8"]),
            KnobInput.pressRotateRight.rawValue: shortcut("下一个问题", ["shift", "f8"])
        ]
    case .media:
        return [
            KnobInput.rotateLeft.rawValue: ActionConfig(type: "key", description: "降低音量", keys: ["volume_down"], button: nil, clicks: nil, dx: nil, dy: nil, command: nil),
            KnobInput.rotateRight.rawValue: ActionConfig(type: "key", description: "提高音量", keys: ["volume_up"], button: nil, clicks: nil, dx: nil, dy: nil, command: nil),
            KnobInput.press.rawValue: ActionConfig(type: "key", description: "播放 / 暂停", keys: ["play_pause"], button: nil, clicks: nil, dx: nil, dy: nil, command: nil),
            KnobInput.pressRotateLeft.rawValue: shortcut("上一首", ["previous_track"]),
            KnobInput.pressRotateRight.rawValue: shortcut("下一首", ["next_track"])
        ]
    case .design:
        return [
            KnobInput.rotateLeft.rawValue: shortcut("缩小画笔", ["["]),
            KnobInput.rotateRight.rawValue: shortcut("放大画笔", ["]"]),
            KnobInput.press.rawValue: shortcut("画笔工具", ["b"]),
            KnobInput.pressRotateLeft.rawValue: shortcut("降低硬度", ["shift", "["]),
            KnobInput.pressRotateRight.rawValue: shortcut("提高硬度", ["shift", "]"])
        ]
    case .editing:
        return [
            KnobInput.rotateLeft.rawValue: shortcut("前一帧", ["left"]),
            KnobInput.rotateRight.rawValue: shortcut("后一帧", ["right"]),
            KnobInput.press.rawValue: shortcut("播放 / 暂停", ["space"]),
            KnobInput.pressRotateLeft.rawValue: shortcut("向前大步移动", ["shift", "left"]),
            KnobInput.pressRotateRight.rawValue: shortcut("向后大步移动", ["shift", "right"])
        ]
    }
}

private func shortcut(_ description: String, _ keys: [String]) -> ActionConfig {
    ActionConfig(type: "shortcut", description: description, keys: keys, button: nil, clicks: nil, dx: nil, dy: nil, command: nil)
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

private func actionSummary(_ action: ActionConfig) -> String {
    let desc = action.description?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let desc, !desc.isEmpty {
        return desc
    }

    switch action.type {
    case "shortcut", "key":
        let keys = action.keys ?? []
        return keys.isEmpty ? "未设置按键" : displayKeyList(keys)
    case "mouse":
        return "鼠标\(displayMouseButton(action.button ?? "left")) · \(action.clicks ?? 1) 次"
    case "scroll":
        return "横向 \(action.dx ?? 0)，纵向 \(action.dy ?? 0)"
    case "shell":
        return action.command?.isEmpty == false ? "执行命令" : "未设置命令"
    case "noop":
        return "忽略这个手势"
    default:
        return "未识别动作"
    }
}

private func gestureSymbol(_ input: KnobInput) -> String {
    switch input {
    case .rotateLeft: return "↺"
    case .rotateRight: return "↻"
    case .press: return "●"
    case .pressRotateLeft: return "●↺"
    case .pressRotateRight: return "●↻"
    }
}

private func overlaySystemImage(for input: KnobInput) -> String {
    switch input {
    case .rotateLeft: return "arrow.counterclockwise"
    case .rotateRight: return "arrow.clockwise"
    case .press: return "circle.fill"
    case .pressRotateLeft: return "arrow.counterclockwise.circle.fill"
    case .pressRotateRight: return "arrow.clockwise.circle.fill"
    }
}

private func displayMouseButton(_ value: String) -> String {
    switch value.lowercased() {
    case "right": return "右键"
    case "middle", "center": return "中键"
    default: return "左键"
    }
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

private func userConfigURL() -> URL {
    let fm = FileManager.default
    let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
    return base
        .appendingPathComponent("ANTICATER Knob Control", isDirectory: true)
        .appendingPathComponent("app-mapping.json")
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
