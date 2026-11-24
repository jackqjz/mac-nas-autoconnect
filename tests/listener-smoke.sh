#!/bin/bash
# Exercise the real main run loop with synthetic callback and wake notifications.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap '[[ -z ${child:-} ]] || kill "$child" 2>/dev/null || true; rm -rf "$work"' EXIT
cat > "$work/test.m" <<'OBJC'
#define main listenerMain
#import "network-listener.m"
#undef main
int main(int argc, const char *argv[]) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        changed(NULL,NULL,NULL);
        changed(NULL,NULL,NULL);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [NSWorkspace.sharedWorkspace.notificationCenter postNotificationName:NSWorkspaceDidWakeNotification object:nil];
    });
    return listenerMain(argc,argv);
}
OBJC
xcrun clang -fobjc-arc -I"$root/src" "$work/test.m" -framework SystemConfiguration -framework AppKit -o "$work/test"
cat > "$work/probe" <<'SH'
date +%s >> "$(dirname "$0")/calls"
SH
"$work/test" "$work/probe" &
child=$!
sleep 15
[[ $(wc -l < "$work/calls") -eq 3 ]]
echo "Verified startup check, coalesced network callbacks, and wake check."
