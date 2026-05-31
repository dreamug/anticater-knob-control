#!/usr/bin/env swift

import Foundation
import IOKit.hid

private let vendorID = 0x05ac
private let productID = 0x022c

private final class HIDProbe {
    private let manager: IOHIDManager

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func run() {
        print("ANTICATER HID probe")
        print("===================")
        print("")
        print("直接监听 VendorID=0x\(hex(vendorID, width: 4)) ProductID=0x\(hex(productID, width: 4)) 的原始 HID value。")
        print("请旋转或按下手轮；按 Control-C 退出。")
        print("")

        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: vendorID,
            kIOHIDProductIDKey as String: productID
        ]

        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

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
            let usagePage = IOHIDElementGetUsagePage(element)
            let usage = IOHIDElementGetUsage(element)
            let reportID = IOHIDElementGetReportID(element)
            let intValue = IOHIDValueGetIntegerValue(value)
            let timestamp = IOHIDValueGetTimeStamp(value)
            let name = usageName(page: usagePage, usage: usage)

            print("\(clock()) value \(name) page=0x\(hex(usagePage, width: 4)) usage=0x\(hex(usage, width: 4)) reportID=\(reportID) int=\(intValue) time=\(timestamp)")
            fflush(stdout)
        }, nil)

        IOHIDManagerRegisterInputReportCallback(
            manager,
            { _, result, _, _, reportID, report, reportLength in
                guard result == kIOReturnSuccess else {
                    print("\(clock()) report error=0x\(hex(UInt32(bitPattern: result), width: 8))")
                    fflush(stdout)
                    return
                }

                let bytes = UnsafeBufferPointer(start: report, count: reportLength)
                    .map { String(format: "%02x", $0) }
                    .joined(separator: " ")

                print("\(clock()) report id=\(reportID) bytes=[\(bytes)]")
                fflush(stdout)
            },
            nil
        )

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            print("无法打开 HID manager: 0x\(hex(UInt32(bitPattern: openResult), width: 8))")
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

private func deviceName(_ device: IOHIDDevice) -> String {
    let product = property(device, kIOHIDProductKey) ?? "unknown"
    let manufacturer = property(device, kIOHIDManufacturerKey) ?? "unknown"
    let serial = property(device, kIOHIDSerialNumberKey) ?? "unknown"
    return "\(product) manufacturer=\(manufacturer) serial=\(serial)"
}

private func property(_ device: IOHIDDevice, _ key: String) -> String? {
    IOHIDDeviceGetProperty(device, key as CFString).map { "\($0)" }
}

private func usageName(page: UInt32, usage: UInt32) -> String {
    switch (page, usage) {
    case (0x0001, 0x0030): return "GenericDesktop.X"
    case (0x0001, 0x0031): return "GenericDesktop.Y"
    case (0x0001, 0x0038): return "GenericDesktop.Wheel"
    case (0x0009, 0x0001): return "Button.1"
    case (0x0009, 0x0002): return "Button.2"
    case (0x0009, 0x0003): return "Button.3"
    case (0x000c, 0x006f): return "Consumer.DisplayBrightnessIncrement"
    case (0x000c, 0x0070): return "Consumer.DisplayBrightnessDecrement"
    case (0x000c, 0x00cd): return "Consumer.PlayPause"
    case (0x000c, 0x00b5): return "Consumer.ScanNextTrack"
    case (0x000c, 0x00b6): return "Consumer.ScanPreviousTrack"
    case (0x000c, 0x00e2): return "Consumer.Mute"
    case (0x000c, 0x00e9): return "Consumer.VolumeIncrement"
    case (0x000c, 0x00ea): return "Consumer.VolumeDecrement"
    case (0x000c, 0x0238): return "Consumer.ACPan"
    case (_, 0xffffffff): return "Array.CurrentSelection"
    default:
        if usage == 0 {
            return "PaddingOrNull"
        }
        return "Unknown"
    }
}

private func clock() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter.string(from: Date())
}

private func hex<T: FixedWidthInteger>(_ value: T, width: Int) -> String {
    String(format: "%0\(width)x", UInt64(value))
}

HIDProbe().run()
