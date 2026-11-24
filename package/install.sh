#!/bin/bash
set -euo pipefail
umask 077
SOURCE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LABEL='local.company-nas.automount'
BASE="$HOME/Library/Application Support/CompanyNASAutoMount"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
if [[ "$(/usr/bin/uname -s)" != Darwin || "$EUID" = 0 ]]; then
    printf '请在自己的 Mac 账号中运行，不要使用 sudo。\n' >&2; exit 1
fi
config=${1:-}
if [[ ! -f "$config" ]]; then printf '请提供公司的网络配置文件。\n' >&2; exit 1; fi
read -r host nas_mac router router_mac share extra < "$config"
ipv4='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
mac='^([a-f0-9]{1,2}:){5}[a-f0-9]{1,2}$'
path='^([a-zA-Z0-9._~-]|%[[:xdigit:]]{2})+$'
if [[ ! $host =~ $ipv4 || ! $router =~ $ipv4 || ! $nas_mac =~ $mac || ! $router_mac =~ $mac || ! $share =~ $path || -n $extra ]]; then
    printf '网络配置格式无效。\n' >&2; exit 1
fi
nas_user=${2:-}
if [[ -z "$nas_user" ]]; then read -r -p '请输入你自己的 NAS 登录名（由管理员分配）：' nas_user; fi
if [[ -z "$nas_user" || ${#nas_user} -gt 32 || "$nas_user" = *[!a-zA-Z0-9_.-]* ]]; then
    printf '登录名限 1–32 个英文字母、数字、点、横线或下划线。\n' >&2; exit 1
fi
/bin/mkdir -p "$BASE" "$HOME/Library/LaunchAgents"
/bin/chmod 700 "$BASE"
# An existing copy is replaced only after the payload was unpacked and verified.
/bin/launchctl bootout "gui/$UID/$LABEL" >/dev/null 2>&1 || true
for name in mount-share network-listener reconnect.sh uninstall.sh control.sh; do
    /bin/cp "$SOURCE/$name" "$BASE/$name"
    /bin/chmod 700 "$BASE/$name"
done
printf '%s %s %s %s %s\n' "$host" "$nas_mac" "$router" "$router_mac" "$share" > "$BASE/network.conf"
printf '%s\n' "$nas_user" > "$BASE/username"
printf '%s\n' '2.2.0' > "$BASE/version"
/bin/rm -f "$BASE/retry-state" "$BASE/retry-after"
# plutil writes paths without interpolating them into XML or shell code.
/usr/bin/plutil -create xml1 "$PLIST.new"
/usr/bin/plutil -insert Label -string "$LABEL" "$PLIST.new"
/usr/bin/plutil -insert ProgramArguments -json '[]' "$PLIST.new"
/usr/bin/plutil -insert ProgramArguments.0 -string "$BASE/network-listener" "$PLIST.new"
/usr/bin/plutil -insert ProgramArguments.1 -string "$BASE/reconnect.sh" "$PLIST.new"
/usr/bin/plutil -insert RunAtLoad -bool YES "$PLIST.new"
/usr/bin/plutil -insert KeepAlive -json '{"SuccessfulExit":false}' "$PLIST.new"
/usr/bin/plutil -insert LimitLoadToSessionType -string Aqua "$PLIST.new"
/usr/bin/plutil -insert ProcessType -string Background "$PLIST.new"
/usr/bin/plutil -insert LowPriorityIO -bool YES "$PLIST.new"
/usr/bin/plutil -lint "$PLIST.new" >/dev/null
/bin/mv "$PLIST.new" "$PLIST"
/bin/launchctl enable "gui/$UID/$LABEL"
/bin/launchctl bootstrap "gui/$UID" "$PLIST"
printf '\n已安装：已启用网络变化监听，登录和唤醒时也会检查。\n账号：%s\n' "$nas_user"
printf '首次使用：请在访达连接 公司 NAS，用自己的账号登录并勾选记住密码。\n'
printf '已经保存过密码的电脑不需要重复登录。后台不读取或保存明文密码。\n'
printf '卸载命令：/bin/bash "$HOME/Library/Application Support/CompanyNASAutoMount/uninstall.sh"\n'
printf '状态文件：%s/status\n' "$BASE"
