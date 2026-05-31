#!/usr/bin/env swift

import AppKit
import ApplicationServices
import Foundation

private struct FrontmostApp {
    let name: String
    let bundleID: String
    let pid: pid_t
}

private final class InputProbe {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastPrintedAppKey = ""
    private let systemDefinedEvent = CGEventType(rawValue: 14)!

    func run() {
        printHeader()
        printFrontmostAppIfChanged(force: true)

        if !CGPreflightListenEventAccess() {
            print("")
            print("macOS 还没有允许输入监听。系统可能会弹出授权提示。")
            _ = CGRequestListenEventAccess()
        }

        let mask = eventMask([
            .keyDown,
            .keyUp,
            .flagsChanged,
            .leftMouseDown,
            .leftMouseUp,
            .rightMouseDown,
            .rightMouseUp,
            .otherMouseDown,
            .otherMouseUp,
            .scrollWheel,
            systemDefinedEvent
        ])

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else {
                return Unmanaged.passUnretained(event)
            }

            let probe = Unmanaged<InputProbe>.fromOpaque(refcon).takeUnretainedValue()
            probe.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            print("")
            print("无法创建事件监听。请给当前终端或 Codex 辅助功能 / 输入监听权限后再运行。")
            print("系统设置 -> 隐私与安全性 -> 辅助功能 / 输入监控")
            exit(1)
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        print("")
        print("开始监听。请旋转或按下手轮；按 Control-C 退出。")
        print("")

        CFRunLoopRun()
    }

    private func handle(type: CGEventType, event: CGEvent) {
        printFrontmostAppIfChanged(force: false)

        let time = timestamp()
        let app = frontmostApp()
        let appText = app.map { "\($0.name) [\($0.bundleID)]" } ?? "unknown"

        switch type {
        case .keyDown, .keyUp:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = describeFlags(event.flags)
            print("\(time) key \(type == .keyDown ? "down" : "up") keyCode=\(keyCode) flags=\(flags) app=\(appText)")

        case .flagsChanged:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = describeFlags(event.flags)
            print("\(time) flags changed keyCode=\(keyCode) flags=\(flags) app=\(appText)")

        case .leftMouseDown, .leftMouseUp:
            printMouse(time: time, label: type == .leftMouseDown ? "left down" : "left up", event: event, appText: appText)

        case .rightMouseDown, .rightMouseUp:
            printMouse(time: time, label: type == .rightMouseDown ? "right down" : "right up", event: event, appText: appText)

        case .otherMouseDown, .otherMouseUp:
            printMouse(time: time, label: type == .otherMouseDown ? "other down" : "other up", event: event, appText: appText)

        case .scrollWheel:
            let y = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let x = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            let fixedY = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            let fixedX = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
            let point = event.location
            print("\(time) scroll x=\(x) y=\(y) fixedX=\(format(fixedX)) fixedY=\(format(fixedY)) pos=(\(format(point.x)),\(format(point.y))) app=\(appText)")

        case _ where type.rawValue == systemDefinedEvent.rawValue:
            if let nsEvent = NSEvent(cgEvent: event) {
                print("\(time) systemDefined subtype=\(nsEvent.subtype.rawValue) data1=\(nsEvent.data1) data2=\(nsEvent.data2) app=\(appText)")
            } else {
                print("\(time) systemDefined raw app=\(appText)")
            }

        default:
            print("\(time) event type=\(type.rawValue) app=\(appText)")
        }

        fflush(stdout)
    }

    private func printMouse(time: String, label: String, event: CGEvent, appText: String) {
        let button = event.getIntegerValueField(.mouseEventButtonNumber)
        let clicks = event.getIntegerValueField(.mouseEventClickState)
        let point = event.location
        print("\(time) mouse \(label) button=\(button) clicks=\(clicks) pos=(\(format(point.x)),\(format(point.y))) app=\(appText)")
    }

    private func printHeader() {
        print("ANTICATER input probe")
        print("=====================")
        print("")
        print("这个工具会只读监听键盘、鼠标按钮、滚轮和媒体/systemDefined 事件。")
    }

    private func printFrontmostAppIfChanged(force: Bool) {
        guard let app = frontmostApp() else {
            return
        }

        let key = "\(app.pid):\(app.bundleID)"
        guard force || key != lastPrintedAppKey else {
            return
        }

        lastPrintedAppKey = key
        print("")
        print("frontmost app: \(app.name) bundleID=\(app.bundleID) pid=\(app.pid)")
        print("")
        fflush(stdout)
    }
}

private func frontmostApp() -> FrontmostApp? {
    guard let app = NSWorkspace.shared.frontmostApplication else {
        return nil
    }

    return FrontmostApp(
        name: app.localizedName ?? "unknown",
        bundleID: app.bundleIdentifier ?? "unknown",
        pid: app.processIdentifier
    )
}

private func eventMask(_ types: [CGEventType]) -> CGEventMask {
    types.reduce(CGEventMask(0)) { mask, type in
        mask | (CGEventMask(1) << CGEventMask(type.rawValue))
    }
}

private func describeFlags(_ flags: CGEventFlags) -> String {
    var names: [String] = []

    if flags.contains(.maskCommand) { names.append("cmd") }
    if flags.contains(.maskControl) { names.append("ctrl") }
    if flags.contains(.maskAlternate) { names.append("opt") }
    if flags.contains(.maskShift) { names.append("shift") }
    if flags.contains(.maskSecondaryFn) { names.append("fn") }
    if flags.contains(.maskAlphaShift) { names.append("caps") }
    if flags.contains(.maskHelp) { names.append("help") }

    return names.isEmpty ? "none" : names.joined(separator: "+")
}

private func timestamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter.string(from: Date())
}

private func format(_ value: CGFloat) -> String {
    String(format: "%.1f", Double(value))
}

private func format(_ value: Double) -> String {
    String(format: "%.2f", value)
}

InputProbe().run()
