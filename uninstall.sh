#!/bin/bash

set -euo pipefail

label="com.local.KeyRemapping"
user_id="$(id -u)"
if [[ "$user_id" == "0" ]]; then
    echo "错误：请以普通登录用户运行，不要使用 sudo。" >&2
    exit 1
fi

install_home="${KEYREMAPPING_INSTALL_HOME:-$HOME}"
app_dir="$install_home/Library/Application Support/KeyRemapping"
plist_target="$install_home/Library/LaunchAgents/$label.plist"
timestamp="$(date +%Y%m%d-%H%M%S)"
archive_dir="$install_home/Library/Application Support/KeyRemapping Removed/$timestamp"
service_target="gui/$user_id/$label"

/bin/launchctl bootout "$service_target" 2>/dev/null || true
mkdir -p "$archive_dir"

if [[ -f "$plist_target" ]]; then
    mv "$plist_target" "$archive_dir/$label.plist"
fi
if [[ -d "$app_dir" ]]; then
    mv "$app_dir" "$archive_dir/KeyRemapping"
fi

echo "监听服务已卸载，原文件已移动到："
echo "$archive_dir"
echo
echo "当前映射可能持续到注销、重启或键盘服务重建。"
echo "如需立即清除所有 hidutil 映射，可手动运行："
echo "/usr/bin/hidutil property --set '{\"UserKeyMapping\":[]}'"
