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

private final class KnobMonitor {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

    func run() {
        print("ANTICATER knob monitor")
        print("======================")
        print("")
        print("监听 ANTICATER_MINI，并把 HID usage 翻译成 rotate_left / rotate_right / press。")
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

        IOHIDManagerRegisterInputValueCallback(manager, { _, _, _, value in
            let element = IOHIDValueGetElement(value)
            let page = IOHIDElementGetUsagePage(element)
            let usage = IOHIDElementGetUsage(element)
            let intValue = IOHIDValueGetIntegerValue(value)

            guard intValue == 1, let input = knobInput(page: page, usage: usage) else {
                return
            }

            let app = NSWorkspace.shared.frontmostApplication
            let appName = app?.localizedName ?? "unknown"
            let bundleID = app?.bundleIdentifier ?? "unknown"

            print("\(clock()) input=\(input.rawValue) source=\(usageName(page: page, usage: usage)) app=\(appName) bundleID=\(bundleID)")
            fflush(stdout)
        }, nil)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            print("无法打开 HID manager: 0x\(hex(UInt32(bitPattern: result), width: 8))")
            exit(1)
        }

        printExistingDevices()
        CFRunLoopRun()
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

private func usageName(page: UInt32, usage: UInt32) -> String {
    switch (page, usage) {
    case (0x000c, 0x006f): return "Consumer.DisplayBrightnessIncrement"
    case (0x000c, 0x0070): return "Consumer.DisplayBrightnessDecrement"
    case (0x000c, 0x00e9): return "Consumer.VolumeIncrement"
    case (0x000c, 0x00ea): return "Consumer.VolumeDecrement"
    case (0x000c, 0x00e2): return "Consumer.Mute"
    default: return "page=0x\(hex(page, width: 4)) usage=0x\(hex(usage, width: 4))"
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

KnobMonitor().run()
