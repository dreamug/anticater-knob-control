# Tools

## input-probe.swift

监听当前 macOS 会话里的键盘、鼠标按钮、滚轮事件，并打印当前前台 App。

运行：

```bash
xcrun swift tools/input-probe.swift
```

如果提示无法创建事件监听，需要给运行它的终端或 Codex 权限：

```text
系统设置 -> 隐私与安全性 -> 辅助功能
系统设置 -> 隐私与安全性 -> 输入监控
```

如果系统弹出授权提示，允许后请重新运行一次脚本。

运行后请依次操作：

1. 左旋手轮 3 格。
2. 右旋手轮 3 格。
3. 按下手轮 3 次。

把终端里打印出来的事件保存下来，就能决定下一步是做快捷键映射，还是做更底层的 HID 监听。

## hid-probe.swift

直接监听 `ANTICATER_MINI` 的 HID value。

运行：

```bash
./run-hid-probe.sh
```

如果 `input-probe.swift` 没有任何输出，优先用这个工具继续查。

## knob-monitor.swift

把已经确认的 HID usage 翻译成手轮语义事件。

运行：

```bash
./run-knob-monitor.sh
```

当前映射：

```text
Consumer.VolumeIncrement -> rotate_left
Consumer.VolumeDecrement -> rotate_right
Consumer.Mute            -> press
Consumer.DisplayBrightnessIncrement -> press_rotate_left
Consumer.DisplayBrightnessDecrement -> press_rotate_right
```

## knob-mapper.swift

读取 `config/app-mapping.json`，根据当前前台 App 执行动作。

运行：

```bash
./run-knob-mapper.sh
```

支持的动作类型：

```json
{ "type": "shortcut", "keys": ["command", "r"] }
{ "type": "mouse", "button": "left", "clicks": 1 }
{ "type": "scroll", "dx": 0, "dy": -3 }
{ "type": "shell", "command": "say hello" }
{ "type": "noop" }
```

## KnobControlGUI

原生 macOS 图形界面源码在：

```text
Sources/KnobControlGUI/main.swift
```

运行：

```bash
./run-gui.sh
```
