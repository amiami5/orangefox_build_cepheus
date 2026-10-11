#!/bin/bash
# OrangeFox(fox_12.1) cepheus ビルド
# 使い方: ./build-cepheus.sh [並列数(省略時 6)]
BASE="$(cd "$(dirname "$0")" && pwd)"
cd "$BASE/12.1" || exit 1
export PATH="$BASE/bin:$PATH"   # python -> python3
export ALLOW_MISSING_DEPENDENCIES=true
export LC_ALL=C
export FOX_BUILD_DEVICE=cepheus
source build/envsetup.sh
lunch twrp_cepheus-eng || exit 1
mka -j"${1:-6}" recoveryimage
