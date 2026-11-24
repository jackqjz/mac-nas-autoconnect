"""Build a self-contained macOS installer; requires Xcode tools only on the builder."""
import base64
import hashlib
import io
from pathlib import Path
import subprocess
import tarfile

root = Path(__file__).resolve().parent
for binary, source, frameworks in [
    ('mount-share', 'mount-share.c', ['CoreFoundation', 'NetFS']),
    ('network-listener', 'network-listener.m', ['AppKit', 'SystemConfiguration']),
]:
    output = str(root / 'package' / binary)
    args = ['xcrun', 'clang', '-O2', '-Wall', '-Wextra', '-arch', 'arm64', '-arch', 'x86_64',
            '-mmacosx-version-min=11.0']
    if source.endswith('.m'):
        args.append('-fobjc-arc')
    for framework in frameworks:
        args.extend(['-framework', framework])
    subprocess.run([*args, str(root / 'src' / source), '-o', output], check=True)
    subprocess.run(['codesign', '--force', '--sign', '-', output], check=True)
    subprocess.run(['codesign', '--verify', '--strict', '--all-architectures', output], check=True)
buffer = io.BytesIO()
with tarfile.open(fileobj=buffer, mode='w:gz') as archive:
    for path in sorted((root / 'package').iterdir()):
        archive.add(path, arcname=path.name)
payload = buffer.getvalue()
digest = hashlib.sha256(payload).hexdigest()
header = '''#!/bin/bash
# Company NAS Auto Connect 2.2.0. No sudo, no password in this installer.
set -euo pipefail
umask 077
if [[ "$(/usr/bin/uname -s)" != Darwin || "$EUID" = 0 ]]; then
    printf '请在 Mac 的普通登录会话中运行，不要使用 sudo。\\n' >&2; exit 1
fi
TEMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/company-nas-install.XXXXXX")
trap '/bin/rm -rf "$TEMP_DIR"' EXIT
/usr/bin/awk '/^__PAYLOAD_BELOW__$/{found=1;next} found{print}' "$0" | /usr/bin/base64 -D > "$TEMP_DIR/payload.tgz"
actual=$(/usr/bin/shasum -a 256 "$TEMP_DIR/payload.tgz" | /usr/bin/awk '{print $1}')
if [[ "$actual" != "PAYLOAD_HASH" ]]; then
    printf '安装包校验失败，请重新获取。\\n' >&2; exit 1
fi
/usr/bin/tar -xzf "$TEMP_DIR/payload.tgz" -C "$TEMP_DIR"
/bin/bash "$TEMP_DIR/install.sh" "$@"
exit 0
__PAYLOAD_BELOW__
'''.replace('PAYLOAD_HASH', digest)
installer = root / 'install-nas.command'
installer.write_text(header + base64.encodebytes(payload).decode('ascii'))
installer.chmod(0o755)
sha = hashlib.sha256(installer.read_bytes()).hexdigest()
checksums = [f'{sha}  install-nas.command\n']
control = (root / 'package/control.sh').read_text()
for filename, mode in [('pause-nas.command', 'pause'), ('resume-nas.command', 'resume'), ('uninstall-nas.command', 'uninstall')]:
    target = root / filename
    target.write_text(control.replace('MODE=${1:-help}', f'MODE={mode}'))
    target.chmod(0o755)
    checksums.append(f'{hashlib.sha256(target.read_bytes()).hexdigest()}  {filename}\n')
(root / 'SHA256SUMS.txt').write_text(''.join(checksums))
print(f'Installer: {installer}\nBytes: {installer.stat().st_size}\nSHA256: {sha}')
