# 手轮控制台

把 `ANTICATER_MINI` 蓝牙手轮变成 macOS 上的应用快捷控制器。

你可以为不同 App 配置不同动作。例如：

- 浏览器里旋转切换标签页
- Cursor / VS Code 里旋转切换编辑器
- Photoshop 里旋转调整画笔
- DaVinci Resolve 里旋转移动时间线
- 全局默认状态下控制音量、媒体播放

支持 5 个手轮动作：

```text
左旋
右旋
按下
按住左旋
按住右旋
```

## 系统要求

- macOS
- ANTICATER_MINI 手轮
- Xcode Command Line Tools

如果没有安装 Xcode Command Line Tools，可以运行：

```bash
xcode-select --install
```

## 下载和运行

克隆仓库：

```bash
git clone https://github.com/dreamug/anticater-knob-control.git
cd anticater-knob-control
```

启动图形界面：

```bash
./run-gui.sh
```

这个命令会自动构建并打开 `手轮控制台.app`。

也可以手动构建：

```bash
./build-gui.sh
open build/ANTICATERKnobControl.app
```

## 第一次使用

1. 打开 `手轮控制台`
2. 点击右上角「启动监听」
3. 如果 macOS 弹出权限提示，请允许
4. 如果没有弹窗，请手动打开权限

需要开启：

```text
系统设置 -> 隐私与安全性 -> 辅助功能
系统设置 -> 隐私与安全性 -> 输入监控
```

把 `手轮控制台` 加进去后，重新打开 App 或再次点击「启动监听」。

## 配置应用动作

左侧会显示：

- 全局默认
- 已配置应用
- 发现的应用

使用方式：

1. 在「发现的应用」里搜索你要配置的 App
2. 点击应用，把它加入配置列表
3. 在右侧查看当前 App、设备状态和最近动作
4. 为 5 个手轮动作设置行为
5. 点击「保存配置」

如果想快速开始，可以在右侧的「快速模板」里选择：

```text
浏览器
写代码
媒体
设计
剪辑
```

然后点击「应用到当前配置」。如果你正在使用某个 App，也可以点击「为当前应用创建并套用」，自动给当前激活的 App 建立配置。

动作类型：

```text
快捷键：发送组合键，例如 ⌘ + ⇧ + P
按键：发送单个按键或媒体键
鼠标：点击当前鼠标位置
滚动：发送滚轮滚动
命令：执行 shell 命令
无动作：忽略这个手势
```

配置会保存到：

```text
config/app-mapping.json
```

仓库里提供了示例配置：

```text
config/app-mapping.example.json
```

## 录制组合键

在某个动作旁边点击「录制组合键」，然后直接按下你想绑定的快捷键。

例如：

```text
Command + Shift + P
Control + Tab
Command + [
```

界面会自动填入对应组合键。

## 菜单栏使用

启动图形界面后，菜单栏会出现一个手轮图标。你可以在菜单里快速：

```text
启动监听
停止监听
打开主窗口
退出应用
```

## 常见问题

### 点击「启动监听」后没有反应

请检查权限：

```text
系统设置 -> 隐私与安全性 -> 辅助功能
系统设置 -> 隐私与安全性 -> 输入监控
```

开启后重新启动 App。

### 手轮动作仍然改变系统音量或亮度

如果没有成功独占设备，macOS 可能仍会收到原本的媒体键事件。请确认：

- 没有同时打开官方 ANTICATER 配置软件
- 已给 `手轮控制台` 输入监控权限
- 重新点击「启动监听」

### 找不到某个 App

点击「刷新发现」，或手动输入该 App 的 bundle id 后点击「添加」。

## 开发者工具

仓库里还保留了一些诊断脚本：

```bash
./run-hid-probe.sh
./run-input-probe.sh
./run-knob-monitor.sh
./run-knob-mapper.sh
```

普通用户只需要使用：

```bash
./run-gui.sh
```
