#!/bin/sh
# Builds native/build/ooz.dll from the ooz sources in third_party/ooz
# (https://github.com/zao/ooz, revision ff5aeb9). Run from Git Bash.
# The small replacement in ooz_shim is used instead of the simde submodule.
set -e
here="$(cd "$(dirname "$0")" && pwd)"
# g++ (MinGW-w64) must be on the PATH; set MINGW_BIN to its folder otherwise.
[ -n "$MINGW_BIN" ] && export PATH="$MINGW_BIN:$PATH"
mkdir -p "$here/build"
cd "$here/../third_party/ooz"
g++ -O2 -std=c++17 -w -shared -static -DOOZ_DYNAMIC -DOOZ_BUILD_DLL=1 \
    -I "$here/ooz_shim" -o "$here/build/ooz.dll" kraken.cpp bitknit.cpp lzna.cpp
echo "gebaut: $here/build/ooz.dll"
