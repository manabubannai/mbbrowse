#!/bin/zsh
# 両版(v1/v2)をDeveloper ID署名+hardened runtime→公証→ステープル→zip まで
# リリースタグ: v1.1.0 (dist/Mado.zip, dist/Mado-pro.zip)
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="Developer ID Application: Manabu Bannai (4WRDD55WT2)"
PROFILE="${NOTARY_PROFILE:-notary}"
mkdir -p dist

sign_notarize() {
  local app="$1" zipname="$2"
  echo "==> 署名: $app"
  codesign --force --deep --options runtime --timestamp \
    --sign "$IDENTITY" "$app"
  local zip="dist/$zipname"
  rm -f "$zip"
  ditto -c -k --keepParent "$app" "$zip"
  echo "==> 公証: $zip"
  xcrun notarytool submit "$zip" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$app"
  rm -f "$zip"
  ditto -c -k --keepParent "$app" "$zip"
  spctl -a -vv "$app" 2>&1 | head -3 || true
  echo "✅ 完成: $zip"
}

sign_notarize "v1-classic/Mado.app" "Mado.zip"
sign_notarize "v2-pro/Mado Pro.app" "Mado-pro.zip"
echo "全完了 (タグ v1.1.0 でリリースに添付する)"
