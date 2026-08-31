#!/bin/bash

script_dir="$(cd "$(dirname "$0")" && pwd)"
"$script_dir/uninstall.sh"
status=$?

echo
read -r -p "按回车键关闭此窗口……"
exit "$status"
