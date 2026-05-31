#!/usr/bin/env swift

import AppKit
import Foundation
import IOKit.hid

private let vendorID = 0x05ac
private let productID = 0x022c

private enum KnobInput: String {
    case rotateLeft = "rotate_left"
    case rotateRight = "rotate_right"
    case press = "press"
    case pressRotateLeft = "press_rotate_left"
    case pressRotateRight = "press_rotate_right"
}

private struct MappingConfig: Decodable {
    let global: [String: Action]
    let apps: [String: [String: Action]]
}

private struct Action: Decodable {
    let type: String
    let description: String?
    let keys: [String]?
    let button: String?
    let clicks: Int?
    let dx: Int?
    let dy: Int?
    let command: String?
}

private final class KnobMapper {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private let configURL: URL
    private var config: MappingConfig

    init() {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let primary = cwd.appendingPathComponent("config/app-mapping.json")
        let fallback = cwd.appendingPathComponent("config/app-mapping.example.json")
        configURL = FileManager.default.fileExists(atPath: primary.path) ? primary : fallback

        do {
            let data = try Data(contentsOf: configURL)
            config = try JSONDecoder().decode(MappingConfig.self, from: data)
        } catch {
            print("无法读取映射配置: \(error)")
            exit(1)
        }
    }

    func run() {
        print("ANTICATER knob mapper")
        print("=====================")
        print("")
        print("配置文件: \(configURL.path)")
        print("按当前前台 App 执行 rotate_left / rotate_right / press / press_rotate_left / press_rotate_right。")
        print("按 Control-C 退出。")
        print("")

        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: vendorID,
            kIOHIDProductIDKey: productID
        ] as CFDictionary)

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { _, _, _, device in
            print("device matched: \(deviceName(device))")
            fflush(stdout)
        }, nil)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { _, _, _, device in
            print("device removed: \(deviceName(device))")
            fflush(stdout)
        }, nil)

        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            let mapper = Unmanaged<KnobMapper>.fromOpaque(context).takeUnretainedValue()

            let element = IOHIDValueGetElement(value)
            let page = IOHIDElementGetUsagePage(element)
            let usage = IOHIDElementGetUsage(element)
            let intValue = IOHIDValueGetIntegerValue(value)

            guard intValue == 1, let input = knobInput(page: page, usage: usage) else {
                return
            }

            mapper.handle(input)
        }, Unmanaged.passUnretained(self).toOpaque())

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        let seized = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        if seized != kIOReturnSuccess {
            print("提示：无法独占手轮，原始音量/亮度/静音事件可能仍会被系统收到。")
            let normal = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            guard normal == kIOReturnSuccess else {
                print("无法打开 HID manager: 0x\(hex(UInt32(bitPattern: normal), width: 8))")
                exit(1)
            }
        }

        printExistingDevices()
        CFRunLoopRun()
    }

    private func handle(_ input: KnobInput) {
        let app = NSWorkspace.shared.frontmostApplication
        let appName = app?.localizedName ?? "unknown"
        let bundleID = app?.bundleIdentifier ?? "unknown"

        guard let action = actionFor(input: input, bundleID: bundleID) else {
            print("\(clock()) input=\(input.rawValue) app=\(appName) bundleID=\(bundleID) action=none")
            fflush(stdout)
            return
        }

        let ok = ActionExecutor.run(action)
        let detail = action.description ?? action.type
        print("\(clock()) input=\(input.rawValue) app=\(appName) bundleID=\(bundleID) action=\"\(detail)\" result=\(ok ? "ok" : "failed")")
        fflush(stdout)
    }

    private func actionFor(input: KnobInput, bundleID: String) -> Action? {
        config.apps[bundleID]?[input.rawValue] ?? config.global[input.rawValue]
    }

    private func printExistingDevices() {
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !devices.isEmpty else {
            print("暂时没有匹配到 ANTICATER_MINI。请确认它已连接。")
            print("")
            fflush(stdout)
            return
        }

        for device in devices {
            print("device ready: \(deviceName(device))")
        }

        print("")
        fflush(stdout)
    }
}

private enum ActionExecutor {
    static func run(_ action: Action) -> Bool {
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
            print("未知动作类型: \(action.type)")
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
                print("未知按键: \(key)")
                return false
            }
        }

        guard !keyCodes.isEmpty else {
            return true
        }

        for keyCode in keyCodes {
            sendKey(keyCode, down: true, flags: flags)
            sendKey(keyCode, down: false, flags: flags)
        }

        return true
    }

    private static func sendKey(_ keyCode: CGKeyCode, down: Bool, flags: CGEventFlags) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down) else {
            return
        }
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
        )?.cgEvent else {
            return
        }
        event.post(tap: .cghidEventTap)
    }

    private static func click(button: String, clicks: Int) -> Bool {
        let mouseButton: CGMouseButton
        let downType: CGEventType
        let upType: CGEventType

        switch button.lowercased() {
        case "left":
            mouseButton = .left
            downType = .leftMouseDown
            upType = .leftMouseUp
        case "right":
            mouseButton = .right
            downType = .rightMouseDown
            upType = .rightMouseUp
        case "middle", "center":
            mouseButton = .center
            downType = .otherMouseDown
            upType = .otherMouseUp
        default:
            print("未知鼠标按钮: \(button)")
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
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: Int32(dy),
            wheel2: Int32(dx),
            wheel3: 0
        ) else {
            return false
        }

        event.post(tap: .cghidEventTap)
        return true
    }

    private static func runShell(_ command: String?) -> Bool {
        guard let command, !command.isEmpty else {
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]

        do {
            try process.run()
            return true
        } catch {
            print("shell 执行失败: \(error)")
            return false
        }
    }
}

private let modifierFlags: [String: CGEventFlags] = [
    "command": .maskCommand,
    "cmd": .maskCommand,
    "control": .maskControl,
    "ctrl": .maskControl,
    "option": .maskAlternate,
    "opt": .maskAlternate,
    "alt": .maskAlternate,
    "shift": .maskShift,
    "fn": .maskSecondaryFn
]

private let mediaKeyTypes: [String: Int] = [
    "volume_up": 0,
    "volume_down": 1,
    "mute": 7,
    "play_pause": 16,
    "next_track": 17,
    "previous_track": 18
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

private func knobInput(page: UInt32, usage: UInt32) -> KnobInput? {
    guard page == 0x000c else {
        return nil
    }

    switch usage {
    case 0x00e9:
        return .rotateLeft
    case 0x00ea:
        return .rotateRight
    case 0x00e2:
        return .press
    case 0x006f:
        return .pressRotateLeft
    case 0x0070:
        return .pressRotateRight
    default:
        return nil
    }
}

private func deviceName(_ device: IOHIDDevice) -> String {
    let product = property(device, kIOHIDProductKey) ?? "unknown"
    let manufacturer = property(device, kIOHIDManufacturerKey) ?? "unknown"
    let serial = property(device, kIOHIDSerialNumberKey) ?? "unknown"
    return "\(product) manufacturer=\(manufacturer) serial=\(serial)"
}

private func property(_ device: IOHIDDevice, _ key: String) -> String? {
    IOHIDDeviceGetProperty(device, key as CFString).map { "\($0)" }
}

private func clock() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter.string(from: Date())
}

private func hex<T: FixedWidthInteger>(_ value: T, width: Int) -> String {
    String(format: "%0\(width)x", UInt64(value))
}

KnobMapper().run()

