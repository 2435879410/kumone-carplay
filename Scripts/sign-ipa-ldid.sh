#!/bin/bash
# 下载 CI 产物后：把 CarPlay entitlements 用 ldid 预签名进 IPA，供 TrollStore/ESign 直接安装。
# 用法: Scripts/sign-ipa-ldid.sh <unsigned.ipa>
set -euo pipefail

IPA="${1:-}"
if [[ -z "$IPA" || ! -f "$IPA" ]]; then
  echo "用法: $0 <unsigned.ipa>" >&2
  exit 1
fi

LDID="$(pwd)/tools-bin/ldid"
ENT="$(pwd)/CarPlay.entitlements"
OUT="$(cd "$(dirname "$IPA")" && pwd)/$(basename "${IPA%.ipa}")-carplay.ipa"
WORK="$(mktemp -d)"
trap "rm -rf '$WORK'" EXIT

unzip -q "$IPA" -d "$WORK"
APP="$WORK/Payload/KumoneIOS.app"
[[ -d "$APP" ]] || { echo "未找到 Payload/KumoneIOS.app" >&2; exit 1; }

# 给主二进制注入 iOS 14+ CarPlay 音频权限和兼容旧发现路径的权限
"$LDID" -S"$ENT" "$APP/KumoneIOS"
echo "entitlements 注入完成:"
"$LDID" -e "$APP/KumoneIOS" | plutil -p - 2>/dev/null || "$LDID" -e "$APP/KumoneIOS"

(cd "$WORK" && zip -qry "$OUT" Payload)
echo "已生成: $OUT"
