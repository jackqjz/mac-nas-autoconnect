#!/bin/sh
set -eu
umask 077
BASE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
read -r HOST NAS_MAC GATEWAY GATEWAY_MAC SHARE < "$BASE/network.conf"

status() {
    previous=$(/bin/cat "$BASE/status" 2>/dev/null || true)
    if [ "$previous" != "$1" ]; then
        printf '%s\n' "$1" > "$BASE/status"
        /bin/date '+%Y-%m-%d %H:%M:%S %z' > "$BASE/status-updated"
    fi
}
clear_retry() {
    if [ -f "$BASE/retry-state" ]; then /bin/rm -f "$BASE/retry-state"; fi
}
mounted() {
    /sbin/mount -t smbfs | /usr/bin/grep -F "@$HOST/$SHARE on " >/dev/null
}
outside() { clear_retry; status outside-company-network; exit 0; }
backoff() {
    failures=$((failures + 1))
    delay=60
    n=1
    while [ "$n" -lt "$failures" ] && [ "$delay" -lt 900 ]; do
        delay=$((delay * 2)); n=$((n + 1))
    done
    if [ "$delay" -gt 900 ]; then delay=900; fi
    # Avoid retrying credentials rapidly when the saved password is out of date.
    if [ "$1" = authentication-or-mount-error ] && [ "$delay" -lt 600 ]; then delay=600; fi
    printf '%s %s\n' "$failures" "$((now + delay))" > "$BASE/retry-state"
    status "$1"
}

# All checks before nc read local kernel/DHCP/ARP state only.
# An existing SMB mount is left to macOS; never force unmount an open file.
if mounted; then clear_retry; status connected; exit 0; fi
iface=$(/sbin/route -n get "$HOST" 2>/dev/null | /usr/bin/awk '/interface:/{print $2}')
case "$iface" in en[0-9]*) ;; *) outside ;; esac
if ! /sbin/ifconfig "$iface" 2>/dev/null | /usr/bin/grep -q 'status: active'; then outside; fi
router=$(/usr/sbin/ipconfig getoption "$iface" router 2>/dev/null || true)
if [ -z "$router" ]; then status waiting-for-network; exit 75; fi
if [ "$router" != "$GATEWAY" ]; then outside; fi
router_mac=$(/usr/sbin/arp -n -i "$iface" "$GATEWAY" 2>/dev/null | /usr/bin/awk '{print $4}')
case "$router_mac" in ""|"(incomplete)"|entry) status waiting-for-network; exit 75 ;; esac
if [ "$router_mac" != "$GATEWAY_MAC" ]; then outside; fi

now=$(/bin/date +%s)
failures=0; retry_after=0
if [ -f "$BASE/retry-state" ]; then
    read -r failures retry_after < "$BASE/retry-state" || true
    case "$failures:$retry_after" in *[!0-9:]*|:|*:) failures=0; retry_after=0 ;; esac
fi
if [ "$now" -lt "$retry_after" ]; then exit 0; fi

if ! /usr/bin/nc -G 2 -z "$HOST" 445 >/dev/null 2>&1; then
    backoff nas-unreachable; exit 0
fi
actual_mac=$(/usr/sbin/arp -n -i "$iface" "$HOST" 2>/dev/null | /usr/bin/awk '{print $4}')
if [ "$actual_mac" != "$NAS_MAC" ]; then backoff nas-identity-mismatch; exit 0; fi

nas_user=$(/bin/cat "$BASE/username")
case "$nas_user" in ''|*[!a-zA-Z0-9_.-]*) status invalid-username; exit 1 ;; esac
if "$BASE/mount-share" "$nas_user" "smb://$HOST/$SHARE" > "$BASE/last-mount-result" 2>&1 && mounted; then
    clear_retry; status connected
else
    backoff authentication-or-mount-error
fi
