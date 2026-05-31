# 设备记录

## 设备识别结果

系统命令里看到的设备：

```text
Product: ANTICATER_MINI
Manufacturer: CXKJ
Transport: Bluetooth Low Energy
VendorID: 0x05ac
ProductID: 0x022c
UsagePage: 1
Usage: 2
```

`UsagePage=1 / Usage=2` 表示 Generic Desktop / Mouse。

从 IORegistry 里还能看到它暴露了这些能力：

```text
DeviceUsagePairs:
- Mouse
- Pointer
- Keyboard
- Consumer Control

RelativePointer:
- X
- Y
- Button 1
- Button 2
- Button 3

Scroll:
- Wheel
- Consumer AC Pan
```

## 本机已有软件

已经安装官方配置软件：

```text
/Applications/ANTICATER.app
Bundle ID: COM.LQKJ.KEYBOARD.ANTICATER
```

这个 App 内部带有：

```text
libhidapi.0.12.0.dylib
```

说明它是通过 HID 和设备通信的。

## 风险点

- 如果手轮直接输出普通鼠标滚轮，系统和当前 App 会先收到滚动事件，拦截会比较麻烦。
- 如果能在官方 App 里把旋转改成少见快捷键，会更容易做成稳定方案。
- 如果官方 App 不能改出合适快捷键，就需要写底层 HID 监听器，可能需要辅助功能权限或输入监听权限。

## 已确认输入映射

根据 `tools/hid-probe.swift` 的输出，当前手轮输出的是 Consumer Control 媒体键：

```text
左旋: Consumer.VolumeIncrement / page=0x000c usage=0x00e9 / report bytes=[03 e9 00]
右旋: Consumer.VolumeDecrement / page=0x000c usage=0x00ea / report bytes=[03 ea 00]
按下: Consumer.Mute            / page=0x000c usage=0x00e2 / report bytes=[03 e2 00]
释放: report bytes=[03 00 00]
```

如果实际手感方向相反，可以在 `tools/knob-monitor.swift` 里交换 `0x00e9` 和 `0x00ea` 对应的语义。

## 待确认组合手势

设备还支持「按住然后左右转」。这个组合可能有两种实现：

- 先保持 `Consumer.Mute` 按下，再发送 `VolumeIncrement` / `VolumeDecrement`。
- 直接发送另一组 Consumer Control usage。

已确认组合手势会直接发送另一组 Consumer Control usage：

```text
按住左旋: Consumer.DisplayBrightnessIncrement / page=0x000c usage=0x006f / report bytes=[03 6f 00]
按住右旋: Consumer.DisplayBrightnessDecrement / page=0x000c usage=0x0070 / report bytes=[03 70 00]
```

当前语义映射为：

```text
0x006f -> press_rotate_left
0x0070 -> press_rotate_right
```
