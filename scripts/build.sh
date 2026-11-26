#!/usr/bin/env bash
#
#  build.sh —— 无 Xcode 工程，直接用 clang 交叉编译 iOS arm64 App，打成未签名 IPA
#
#  用法：
#    bash scripts/build.sh                     # 全部 target
#    TARGETS="PiPOverlay" bash scripts/build.sh
#    MIN_IOS=14.0 bash scripts/build.sh
#
#  产物：
#    build/<Target>.ipa          未签名，Sideloadly / AltStore / esign 重签后装机
#    build/<Target>/Payload/...  .app 本体
#    build/SHA256SUMS.txt
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build"
MIN_IOS="${MIN_IOS:-15.0}"
TARGETS="${TARGETS:-PiPOverlay HUDKeepAlive ScreenShield HUDMenu}"

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANG="$(xcrun --sdk iphoneos -f clang)"

echo "== toolchain =="
"$CLANG" --version | head -2
echo "SDK: $SDK"
echo "min iOS: $MIN_IOS"
echo

# ---- DIAG: dump available PiP content source initializers ----
echo "== PiP ContentSource API =="
CSH=$(grep -rl 'interface AVPictureInPictureControllerContentSource' "$SDK/System/Library/Frameworks/AVKit.framework/Headers/" 2>/dev/null | head -1)
echo "CSH=$CSH"
[ -n "$CSH" ] && grep -n -E '^\-|init|ContentViewController|VideoCall|sourceView|@interface' "$CSH" | head -80 || true
echo

rm -rf "$OUT"
mkdir -p "$OUT"

FRAMEWORKS=(
  UIKit Foundation AVKit AVFoundation
  CoreVideo CoreMedia CoreGraphics QuartzCore
)

for T in $TARGETS; do
  SRC="$ROOT/targets/$T"
  if [ ! -d "$SRC" ]; then
    echo "!! skip $T (no such target dir)"
    continue
  fi

  APP="$OUT/$T/Payload/$T.app"
  mkdir -p "$APP"

  # ---- Info.plist：把 Xcode 变量换成实际值 ----
  cp "$SRC/Info.plist" "$APP/Info.plist"
  PB=/usr/libexec/PlistBuddy
  "$PB" -c "Set :CFBundleExecutable $T" "$APP/Info.plist"
  "$PB" -c "Set :CFBundleName $T" "$APP/Info.plist" || true
  "$PB" -c "Set :MinimumOSVersion $MIN_IOS" "$APP/Info.plist" || true
  plutil -lint "$APP/Info.plist" >/dev/null

  # ---- 收集源文件 ----
  SRCS=()
  while IFS= read -r f; do SRCS+=("$f"); done < <(find "$SRC" -maxdepth 1 -name '*.m' | sort)
  SRCS+=("$ROOT/common/main.m")
  echo "== $T : ${#SRCS[@]} sources =="

  FW=()
  for f in "${FRAMEWORKS[@]}"; do FW+=(-framework "$f"); done

  "$CLANG" \
    -target "arm64-apple-ios$MIN_IOS" \
    -isysroot "$SDK" \
    -fobjc-arc \
    -O2 -DNDEBUG \
    -Wall -Wno-unused-variable -Wno-deprecated-declarations \
    -I "$SRC" \
    "${FW[@]}" \
    "${SRCS[@]}" \
    -o "$APP/$T"

  chmod 755 "$APP/$T"

  # ---- 结构校验：必须是 iOS arm64 Mach-O 可执行文件 ----
  file "$APP/$T"
  if ! file "$APP/$T" | grep -q 'Mach-O 64-bit executable arm64'; then
    echo "!! $T binary is not arm64 Mach-O"; exit 1
  fi
  if ! otool -l "$APP/$T" | grep -q 'LC_BUILD_VERSION'; then
    echo "!! $T missing LC_BUILD_VERSION (platform not iOS)"; exit 1
  fi

  # ---- 打包 ----
  ( cd "$OUT/$T" && zip -qry "../$T.ipa" Payload )
  ls -lh "$OUT/$T.ipa"
  echo
done

# ---- 摘要 ----
( cd "$OUT" && shasum -a 256 ./*.ipa | tee SHA256SUMS.txt )

# ---- 构建信息 ----
{
  echo "built_at : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "runner   : $(uname -sm)"
  echo "xcode    : $(xcodebuild -version | tr '\n' ' ')"
  echo "sdk      : $(xcrun --sdk iphoneos --show-sdk-version)"
  echo "min_ios  : $MIN_IOS"
  echo "clang    : $("$CLANG" --version | head -1)"
} > "$OUT/build-info.txt"
cat "$OUT/build-info.txt"
