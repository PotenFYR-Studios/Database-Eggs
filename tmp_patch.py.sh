#!/usr/bin/env bash
# Use global ARCH_DEB everywhere local arch mapping existed; add musl detection.
f=scripts/install-db-version.sh

# 1) extract_libaio: replace local mapping with global ARCH_DEB
python3 - "$f" <<'PYEOF' 2>/dev/null || sed -i 's/    local arch_deb="amd64"\n    \[ "${ARCH_TYPE}" = "arm64" \] && arch_deb="arm64"/    local arch_deb="${ARCH_DEB}"/' "$f"
import sys, re
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
s = s.replace('''    local arch_deb="amd64"
    [ "${ARCH_TYPE}" = "arm64" ] && arch_deb="arm64"
''', '''    local arch_deb="${ARCH_DEB}"
''')
s = s.replace('''    local arch="amd64"
    [ "${ARCH_TYPE}" = "arm64" ] && arch="arm64"
''', '''    local arch="${ARCH_DEB}"
''')
# 2) libc family detection + postgres target selection
anchor = 'IS_ROOT=0'
libc_block = '''# Libc family: gnu builds need glibc; musl builds target Alpine-like hosts.
if command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; then
    PF_LIBC="musl"
else
    PF_LIBC="gnu"
fi

'''
s = s.replace(anchor, libc_block + anchor, 1)
open(p, 'w', encoding='utf-8', newline='\n').write(s)
print("patched")
PYEOF
bash -n "$f" && echo "syntax OK"
grep -n 'ARCH_DEB}"$\|PF_LIBC=' "$f" | head -8
