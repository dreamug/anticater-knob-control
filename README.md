# ANTICATER Knob Control

这个小项目的目标：把 `ANTICATER_MINI` 手轮做成一个按当前软件自动切换行为的 macOS 控制器。

## 当前结论

你的手轮在 macOS 里被识别为蓝牙 HID 设备：

- 产品名：`ANTICATER_MINI`
- 厂商：`CXKJ`
- 连接方式：Bluetooth Low Energy
- HID 类型：复合输入设备
- 能力：鼠标指针、滚轮、鼠标按钮、键盘、媒体控制

这意味着它可以被做成：

- 在浏览器里切换标签页
- 在 VS Code / Cursor 里切换文件或打开命令面板
- 在 Photoshop 里调笔刷大小
- 在 DaVinci Resolve 里移动时间线或播放暂停
- 在全局状态下控制音量、亮度或窗口

## 推荐方向

第一阶段先不要直接改固件，也不要一上来写很重的 GUI。

更稳的路线是：

1. 用 `/Applications/ANTICATER.app` 确认旋转和按下分别会输出什么。
2. 先把旋转/按下配置成稳定、少见、不容易和日常输入冲突的快捷键。
3. 写一个 macOS 后台小程序，根据当前前台 App 把这些输入翻译成不同动作。
4. 等规则稳定后，再考虑做菜单栏图标、配置界面和开机自启。

## 我们接下来要做什么

最小可行版本应该包含：

- 设备输入探测：确认左旋、右旋、按下分别是什么事件。
- 当前 App 识别：读取前台应用的 bundle id。
- 映射配置：按 app 定义 `rotate_left`、`rotate_right`、`press`。
- 动作执行：发送快捷键、执行 AppleScript 或调用系统命令。

## 文件结构

- `notes/device-profile.md`：目前查到的设备信息。
- `config/app-mapping.example.json`：第一版应用映射草案。
- `notes/roadmap.md`：实现路线和技术选型。
- `tools/input-probe.swift`：输入探测工具。

## 运行输入探测

```bash
./run-input-probe.sh
```

运行后依次左旋、右旋、按下手轮，观察终端输出。

如果提示无法创建事件监听，需要给运行它的终端或 Codex 权限：

```text
系统设置 -> 隐私与安全性 -> 辅助功能
系统设置 -> 隐私与安全性 -> 输入监控
```

授权后请重新运行一次脚本。

如果普通输入探测没有任何输出，改用更底层的 HID 探测：

```bash
./run-hid-probe.sh
```

确认 HID usage 后，可以运行语义监听器：

```bash
./run-knob-monitor.sh
```

它会把当前设备事件翻译成：

```text
rotate_left
rotate_right
press
press_rotate_left
press_rotate_right
```

其中 `press_rotate_left` 和 `press_rotate_right` 需要先用 HID probe 确认组合手势输出。

正式执行映射时运行：

```bash
./run-knob-mapper.sh
```

它会读取：

```text
config/app-mapping.json
```

如果这个文件不存在，会回退到：

```text
config/app-mapping.example.json
```

动作支持：

```text
shortcut / key: 发送键盘快捷键或媒体键
mouse: 点击当前鼠标位置
scroll: 发送滚动
shell: 执行 shell 命令
noop: 什么都不做
```

## 图形界面

构建并启动原生 macOS 图形界面：

```bash
./run-gui.sh
```

也可以先构建 `.app`：

```bash
./build-gui.sh
open build/ANTICATERKnobControl.app
```

图形界面可以：

- 查看当前前台 App 和 bundle id。
- 添加当前 App 到映射列表。
- 编辑全局默认映射和每个 App 的五个手轮动作。
- 保存到 `config/app-mapping.json`。
- 直接启动 / 停止手轮监听。

如果点击「启动监听」后没有响应，请给 `ANTICATER Knob Control` 这个 App 开启：

```text
系统设置 -> 隐私与安全性 -> 辅助功能
系统设置 -> 隐私与安全性 -> 输入监控
```

## 发布到 GitHub

建议把这个目录作为独立仓库发布：

```bash
cd /Users/kuanyu/Projects/claudecode_learning/anticater-knob-control
git init
git add .
git commit -m "Initial ANTICATER knob control app"
```

创建 GitHub 仓库后添加远程地址：

```bash
git remote add origin git@github.com:YOUR_NAME/anticater-knob-control.git
git branch -M main
git push -u origin main
```

如果使用 GitHub CLI：

```bash
gh repo create anticater-knob-control --public --source=. --remote=origin --push
```

不要提交 `build/` 里的编译产物，也不要提交自己的 `config/app-mapping.json`。仓库里保留 `config/app-mapping.example.json`，让每个用户复制成自己的配置。
