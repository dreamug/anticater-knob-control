# 路线图

## 阶段 1：确认输入事件

目标：弄清楚手轮左旋、右旋、按下到底发出了什么。

可选办法：

- 打开 `/Applications/ANTICATER.app` 查看是否能配置旋转和按下。
- 用 `tools/input-probe.swift` 观察它发出的键盘、鼠标、滚轮事件。
- 如果普通工具看不到，就写 HID probe 小程序监听 `ANTICATER_MINI`。

## 阶段 2：做最小后台

目标：先让它在不同 App 里触发不同快捷键。

后台需要做三件事：

- 监听手轮输入。
- 获取当前前台 App 的 bundle id。
- 根据 `config/app-mapping.example.json` 执行动作。

## 阶段 3：稳定体验

目标：让它日常可用。

要补齐：

- 菜单栏状态图标。
- 配置热重载。
- 输入防抖和连续旋转节流。
- 开机自启。
- 权限检测提示。

## 技术选型建议

优先级从稳到灵活：

1. 官方 `ANTICATER.app` 配置输入 + 自己写分发后台。
2. Hammerspoon：开发最快，但需要安装额外 App。
3. Swift macOS 后台：最适合长期使用，可以直接调用系统 API。
4. Node + native HID：开发方便，但原生依赖和权限会更烦一点。

小野建议先走第 1 条：先确认官方 App 能不能把输入改成稳定快捷键，再写一个 Swift 或 Hammerspoon 版本的小后台。
