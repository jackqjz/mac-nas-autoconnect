#!/bin/bash
# Manage only this user's CompanyNASAutoMount task and its known program files.
set -euo pipefail
if [[ "$EUID" = 0 ]]; then printf '请不要使用 sudo。\n' >&2; exit 1; fi
LABEL='local.company-nas.automount'
BASE="$HOME/Library/Application Support/CompanyNASAutoMount"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
TARGET="gui/$UID/$LABEL"
MODE=${1:-help}
if [[ -L "$BASE" || -L "$PLIST" ]]; then
    printf '检测到配置路径是符号链接，未进行修改，请管理员检查。\n' >&2; exit 1
fi
stop_task() {
    /bin/launchctl bootout "$TARGET" >/dev/null 2>&1 || true
    if /bin/launchctl print "$TARGET" >/dev/null 2>&1; then
        printf '任务仍在运行，已停止后续文件删除，请联系管理员。\n' >&2; exit 1
    fi
}
case "$MODE" in
    pause)
        if [[ ! -f "$PLIST" ]]; then printf '未安装自动连接任务，无需暂停。\n'; exit 0; fi
        /bin/launchctl disable "$TARGET"
        stop_task
        printf '自动连接已关闭，重启或重新登录后也不会自行启动。\n可用 resume 恢复。当前 NAS 连接保持不变。\n'
        ;;
    resume)
        if [[ ! -f "$PLIST" || ! -f "$BASE/reconnect.sh" ]]; then
            printf '未找到完整安装，请重新运行安装包。\n' >&2; exit 1
        fi
        /bin/launchctl enable "$TARGET"
        if ! /bin/launchctl print "$TARGET" >/dev/null 2>&1; then
            /bin/launchctl bootstrap "gui/$UID" "$PLIST"
        fi
        /bin/launchctl print "$TARGET" >/dev/null
        printf '自动连接已恢复，已开始监听网络变化。\n'
        ;;
    uninstall)
        stop_task
        # Reset the disabled override so a future intentional reinstall works.
        /bin/launchctl enable "$TARGET" >/dev/null 2>&1 || true
        /bin/rm -f -- "$PLIST" "$PLIST.new"
        # Enumerate known generated files; never recursively delete arbitrary content.
        for name in network-listener mount-share mount-share.c reconnect.sh uninstall.sh control.sh username network.conf version \
                    status status-updated last-mount-result retry-after retry-state README.md; do
            /bin/rm -f -- "$BASE/$name"
        done
        if [[ -d "$BASE" ]] && ! /bin/rmdir "$BASE" 2>/dev/null; then
            printf '后台任务及已知程序文件已移除；目录中另有文件，已保留：\n%s\n' "$BASE"
        else
            printf '已完全卸载本机自动连接服务：后台任务、程序、配置和状态文件均已移除。\n'
        fi
        printf '未删除 NAS 文件、NAS 账号、钥匙串密码或下载的安装包；当前 NAS 连接保持不变。\n'
        ;;
    status)
        if /bin/launchctl print "$TARGET" >/dev/null 2>&1; then
            printf '自动连接：已启用\n'
            [[ ! -f "$BASE/status" ]] || /bin/cat "$BASE/status"
        elif [[ -f "$PLIST" ]]; then
            printf '自动连接：已安装但未运行（已暂停或尚未加载）\n'
        else
            printf '自动连接：未安装或已卸载\n'
        fi
        ;;
    *)
        printf '用法：/bin/bash control.sh pause|resume|uninstall|status\n'
        ;;
esac
