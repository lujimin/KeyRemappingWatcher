# KeyRemappingWatcher

一个轻量的 macOS 原生键盘映射监听器，将标准 HID `F20` 映射为 `Fn / Globe`。

它不使用定时轮询。程序常驻等待系统事件，仅在以下时机调用一次 `hidutil`：

- 登录启动 10 秒后；
- 新键盘 HID 服务出现 2 秒后；
- Mac 从睡眠唤醒 5 秒后。

## 兼容性

- macOS 11 或更高版本；
- Apple Silicon 与 Intel（附带 Universal 2 可执行文件）；
- USB、蓝牙、2.4G 接收器等标准 HID 键盘；
- 不依赖 Homebrew、Karabiner-Elements 或其他第三方运行库。

程序监听 HID Usage Page 1、Usage 6，也就是标准键盘服务，因此不依赖具体连接方式或厂商。映射本身全局设置 F20 → Fn；内置 Mac 键盘通常不产生 F20，所以不会实际受到影响。

## 一键安装

在 Finder 中双击：

```text
安装.command
```

也可以在 Terminal 中运行：

```bash
cd KeyRemappingWatcher
./install.sh
```

请使用普通登录用户运行，不要使用 `sudo`。

安装器会动态读取当前用户主目录，因此不会写死用户名。它会：

1. 备份已有配置和程序；
2. 安装 Universal 2 可执行文件与源码；
3. 根据当前用户路径生成 LaunchAgent；
4. 对程序进行本机 ad-hoc 签名；
5. 加载服务并等待首次映射；
6. 输出当前映射状态。

## 安装位置

```text
~/Library/Application Support/KeyRemapping/KeyRemappingWatcher
~/Library/Application Support/KeyRemapping/KeyRemappingWatcher.m
~/Library/LaunchAgents/com.local.KeyRemapping.plist
~/Library/Logs/KeyRemappingWatcher.log
```

## 重装系统

重装系统前保存整个 `KeyRemappingWatcher` 项目目录。重装完成后，直接双击 `安装.command` 即可。用户名发生变化也没关系，安装器会重新生成正确路径。

运行预编译程序不需要 Xcode。只有重新构建时才需要安装 Xcode Command Line Tools。

新系统会清除隐私权限。如果服务正常运行但映射没有生效，请检查“系统设置 → 隐私与安全性 → 输入监控”，并根据系统提示重新授权。

## 查看状态

```bash
launchctl print gui/$(id -u)/com.local.KeyRemapping
hidutil property --get UserKeyMapping
tail -f ~/Library/Logs/KeyRemappingWatcher.log
```

正常情况下，`launchctl print` 会显示：

```text
state = running
runs = 1
last exit code = (never exited)
```

## 从源码构建

```bash
make clean all
```

生成文件：

```text
bin/KeyRemappingWatcher
```

构建结果同时包含 `arm64` 和 `x86_64`。

## 卸载

在 Finder 中双击：

```text
卸载.command
```

或者运行：

```bash
./uninstall.sh
```

卸载器不会立即删除程序和配置，而是将它们移动到：

```text
~/Library/Application Support/KeyRemapping Removed/<时间戳>/
```

已经写入的映射可能持续到注销、重启或键盘服务重建。卸载脚本会显示立即清除映射的可选命令。

## 项目结构

```text
KeyRemappingWatcher/
├── bin/KeyRemappingWatcher
├── resources/com.local.KeyRemapping.plist
├── src/KeyRemappingWatcher.m
├── install.sh
├── uninstall.sh
├── 安装.command
├── 卸载.command
├── Makefile
└── README.md
```

## 工作原理

监听器通过 IOKit 监听标准键盘 HID 服务，通过 `NSWorkspaceDidWakeNotification` 监听系统唤醒。收到事件后会进行短暂防抖，再通过 `posix_spawn` 直接运行系统自带的 `/usr/bin/hidutil`。

它没有使用社区方案中的 `LaunchEvents + hidutil` 组合，避免因 XPC 事件未被消费而导致 LaunchAgent 被反复拉起。
