#!/bin/bash
# 检查 IPA 是否带 iOS 14+ CarPlay 音频权限
# 用法: Scripts/check-carplay-entitlements.sh <xxx.ipa>
set -euo pipefail

IPA="${1:-}"
if [[ -z "$IPA" || ! -f "$IPA" ]]; then
  echo "用法: $0 <xxx.ipa>" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap "rm -rf '$WORK'" EXIT
unzip -q "$IPA" -d "$WORK"

APP_DIR="$WORK/Payload/KumoneIOS.app"
[[ -d "$APP_DIR" ]] || { echo "未找到 Payload/KumoneIOS.app，请确认是 Kumone 的 IPA" >&2; exit 1; }
BIN="$APP_DIR/KumoneIOS"

echo "=== 1) 签名信息 ==="
codesign -dv "$APP_DIR" 2>&1 | grep -E "Identifier|TeamIdentifier|Signature|Authority=" | head -6 || echo "（无 Apple 代码签名，ldid 伪签名）"
echo

echo "=== 2) 嵌入式描述文件 embedded.mobileprovision ==="
PROF="$APP_DIR/embedded.mobileprovision"
if [[ -f "$PROF" ]]; then
  if security cms -D -i "$PROF" 2>/dev/null | grep -q 'com.apple.developer.carplay-audio'; then
    echo "描述文件含 CarPlay 权限 ✅"
  else
    echo "描述文件不含 CarPlay 权限 ❌（个人免费证书的普遍情况）"
  fi
else
  echo "（无描述文件，ldid/TrollStore 伪签名方式）"
fi
echo

echo "=== 3) 二进制实际 entitlements（最终判定） ==="
ENT="$("$ROOT/tools-bin/ldid" -e "$BIN" 2>/dev/null || true)"
if echo "$ENT" | grep -A1 'com.apple.developer.carplay-audio' | grep -q '<true/>'; then
  echo "✅ 有 iOS 14+ CarPlay 音频权限（com.apple.developer.carplay-audio = true）"
  if echo "$ENT" | grep -A1 'com.apple.developer.playable-content' | grep -q '<true/>'; then
    echo "✅ 同时保留旧式 playable-content 权限"
  fi
  echo "$ENT" | head -20
else
  echo "❌ 没有 com.apple.developer.carplay-audio：iOS 15 车机上不会出现 Kumone"
  echo "   修复：用 Scripts/sign-ipa-ldid.sh 重新预签名，或 ESign 导入 CarPlay.entitlements 后重签。"
fi
