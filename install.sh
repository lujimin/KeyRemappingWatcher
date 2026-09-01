#!/bin/bash

set -euo pipefail

label="com.local.KeyRemapping"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_binary="$script_dir/bin/KeyRemappingWatcher"
source_code="$script_dir/src/KeyRemappingWatcher.m"
plist_template="$script_dir/resources/com.local.KeyRemapping.plist"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "错误：这个安装器只能在 macOS 上运行。" >&2
    exit 1
fi

user_id="$(id -u)"
if [[ "$user_id" == "0" ]]; then
    echo "错误：请以普通登录用户运行，不要使用 sudo。" >&2
    exit 1
fi

install_home="${KEYREMAPPING_INSTALL_HOME:-$HOME}"
skip_launch="${KEYREMAPPING_SKIP_LAUNCH:-0}"
app_dir="$install_home/Library/Application Support/KeyRemapping"
launch_agents_dir="$install_home/Library/LaunchAgents"
logs_dir="$install_home/Library/Logs"
watcher_target="$app_dir/KeyRemappingWatcher"
source_target="$app_dir/KeyRemappingWatcher.m"
plist_target="$launch_agents_dir/$label.plist"
log_target="$logs_dir/KeyRemappingWatcher.log"
launch_domain="gui/$user_id"
service_target="$launch_domain/$label"
timestamp="$(date +%Y%m%d-%H%M%S)"
backup_dir="$install_home/Library/Application Support/KeyRemapping Backups/$timestamp"

if [[ ! -f "$source_binary" ]]; then
    echo "没有找到预编译程序，尝试从源码构建……"
    /usr/bin/make -C "$script_dir" all
fi

for required_file in "$source_binary" "$source_code" "$plist_template"; do
    if [[ ! -f "$required_file" ]]; then
        echo "错误：项目文件缺失：$required_file" >&2
        exit 1
    fi
done

stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/KeyRemappingInstall.XXXXXX")"
cleanup() {
    case "$stage_dir" in
        "${TMPDIR:-/tmp}"/KeyRemappingInstall.*)
            rm -rf -- "$stage_dir"
            ;;
    esac
}
trap cleanup EXIT

staged_plist="$stage_dir/$label.plist"
cp "$plist_template" "$staged_plist"
/usr/bin/plutil -insert ProgramArguments.0 -string "$watcher_target" "$staged_plist"
/usr/bin/plutil -replace StandardOutPath -string "$log_target" "$staged_plist"
/usr/bin/plutil -replace StandardErrorPath -string "$log_target" "$staged_plist"
/usr/bin/plutil -lint "$staged_plist"

mkdir -p "$app_dir" "$launch_agents_dir" "$logs_dir" "$backup_dir"

had_old_binary=0
had_old_source=0
had_old_plist=0

if [[ -f "$watcher_target" ]]; then
    cp -p "$watcher_target" "$backup_dir/KeyRemappingWatcher"
    had_old_binary=1
fi
if [[ -f "$source_target" ]]; then
    cp -p "$source_target" "$backup_dir/KeyRemappingWatcher.m"
    had_old_source=1
fi
if [[ -f "$plist_target" ]]; then
    cp -p "$plist_target" "$backup_dir/$label.plist"
    had_old_plist=1
fi

if [[ "$skip_launch" != "1" ]]; then
    /bin/launchctl bootout "$service_target" 2>/dev/null || true
fi

/usr/bin/install -m 0755 "$source_binary" "$watcher_target"
/usr/bin/install -m 0644 "$source_code" "$source_target"
/usr/bin/install -m 0644 "$staged_plist" "$plist_target"
/usr/bin/xattr -d com.apple.quarantine "$watcher_target" 2>/dev/null || true
/usr/bin/codesign --force --sign - "$watcher_target"

/usr/bin/plutil -lint "$plist_target"
/usr/bin/codesign --verify --verbose=1 "$watcher_target"
/usr/bin/lipo "$watcher_target" -verify_arch x86_64 arm64

if [[ "$skip_launch" == "1" ]]; then
    echo "安装文件验证成功（测试模式未加载 LaunchAgent）。"
    echo "安装根目录：$install_home"
    exit 0
fi

if ! /bin/launchctl bootstrap "$launch_domain" "$plist_target"; then
    echo "新 LaunchAgent 加载失败，正在恢复安装前文件……" >&2

    if [[ "$had_old_binary" == "1" ]]; then
        cp -p "$backup_dir/KeyRemappingWatcher" "$watcher_target"
    fi
    if [[ "$had_old_source" == "1" ]]; then
        cp -p "$backup_dir/KeyRemappingWatcher.m" "$source_target"
    fi
    if [[ "$had_old_plist" == "1" ]]; then
        cp -p "$backup_dir/$label.plist" "$plist_target"
        /bin/launchctl bootstrap "$launch_domain" "$plist_target" 2>/dev/null || true
    fi
    exit 1
fi

echo "LaunchAgent 已加载，等待首次映射……"
sleep 2

if ! /bin/launchctl print "$service_target" >/dev/null; then
    echo "错误：LaunchAgent 加载后未保持运行。请检查日志：$log_target" >&2
    exit 1
fi

echo
echo "安装成功。"
echo "程序：$watcher_target"
echo "源码：$source_target"
echo "配置：$plist_target"
echo "日志：$log_target"

if [[ "$had_old_binary" == "1" || "$had_old_source" == "1" || "$had_old_plist" == "1" ]]; then
    echo "安装前文件备份：$backup_dir"
fi

echo
echo "当前映射："
/usr/bin/hidutil property --get UserKeyMapping || true
