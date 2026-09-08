#!/usr/bin/env bash
# 打包 AShareAgent.dmg(本地与 CI 共用)。
#
# 用法:
#   scripts/package-dmg.sh [--build N] [--identity "<签名身份>"|-] [--entitlements <plist>] [--out <dir>]
#                          [--notary-key <p8> --notary-key-id <id> --notary-issuer <uuid>]
# 产物(默认 build/dmg/):
#   AShareAgent-<version>-<build>.dmg   AShareAgent-latest.dmg   latest.json
#
# - --identity 默认 "-"(ad-hoc:可运行,但 Gatekeeper 需右键打开);传 "Developer ID Application: …" 则正式签名
# - --entitlements 默认 Axblade/App/Axblade.entitlements(不含 Sign in with Apple:该权限需要描述文件,
#   只有 archive/export 流程或提供了 Developer ID 描述文件时才带上)
# - 公证(任一即可):--notary-key/--notary-key-id/--notary-issuer(ASC API Key),
#   或 --notary-apple-id/--notary-password/--notary-team-id(App 专用密码),
#   或本机钥匙串里已有 `xcrun notarytool store-credentials AC_NOTARY`(本地打包自动使用)
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD="${CURRENT_PROJECT_VERSION:-1}"
IDENTITY="-"
ENTITLEMENTS="Axblade/App/Axblade.entitlements"
OUT="build/dmg"
PREBUILT_APP=""
NOTARY_KEY=""; NOTARY_KEY_ID=""; NOTARY_ISSUER=""
NOTARY_APPLE_ID=""; NOTARY_PASSWORD=""; NOTARY_TEAM_ID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --app) PREBUILT_APP="$2"; shift 2 ;;      # 直接用已构建(例如已公证)的 .app,跳过构建/重签
    --build) BUILD="$2"; shift 2 ;;
    --identity) IDENTITY="$2"; shift 2 ;;
    --entitlements) ENTITLEMENTS="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --notary-key) NOTARY_KEY="$2"; shift 2 ;;
    --notary-key-id) NOTARY_KEY_ID="$2"; shift 2 ;;
    --notary-issuer) NOTARY_ISSUER="$2"; shift 2 ;;
    --notary-apple-id) NOTARY_APPLE_ID="$2"; shift 2 ;;      # 或用 Apple ID + App 专用密码公证
    --notary-password) NOTARY_PASSWORD="$2"; shift 2 ;;
    --notary-team-id) NOTARY_TEAM_ID="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

VERSION="$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([0-9.]*\)"\{0,1\}.*/\1/p' project.yml | head -1)"
[ -n "$VERSION" ] || { echo "读不到 MARKETING_VERSION" >&2; exit 1; }
DERIVED="build/DerivedData-dmg"
STAGE="build/dmg-stage"
rm -rf "$DERIVED/Build/Products/Release" "$STAGE" && mkdir -p "$OUT" "$STAGE"

if [ -n "$PREBUILT_APP" ]; then
  echo "== using prebuilt app: $PREBUILT_APP"
  APP="$PREBUILT_APP"
  BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
else
echo "== xcodegen"; xcodegen generate >/dev/null
echo "== build Release (version $VERSION build $BUILD, identity: $IDENTITY)"
if [ "$IDENTITY" = "-" ]; then
  SIGN_ARGS=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= CODE_SIGNING_ALLOWED=YES)
else
  SIGN_ARGS=(CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE_SPECIFIER=)
fi
xcodebuild build -project Axblade.xcodeproj -scheme Axblade -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED" \
  CURRENT_PROJECT_VERSION="$BUILD" CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS" \
  ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS="--timestamp=none" \
  "${SIGN_ARGS[@]}" 2>&1 | grep -E "error:|warning: .*(sign|entitle)|BUILD (SUCCEEDED|FAILED)" | tail -5
APP="$DERIVED/Build/Products/Release/AShareAgent.app"
[ -d "$APP" ] || { echo "构建产物不存在:$APP" >&2; exit 1; }

if [ "$IDENTITY" != "-" ]; then
  # 正式签名要带安全时间戳(公证必需);构建时先关掉时间戳再统一重签,避免离线构建失败
  echo "== re-sign with timestamp"
  codesign --force --deep --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
fi
fi  # PREBUILT_APP
codesign --verify --deep --strict "$APP"
echo "== signature: $(codesign -dvv "$APP" 2>&1 | grep -E "^Authority=" | head -1 || echo adhoc)"

DMG_NAME="AShareAgent-$VERSION-$BUILD.dmg"
echo "== hdiutil → $OUT/$DMG_NAME"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$OUT/$DMG_NAME"
hdiutil create -volname "AShareAgent" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$OUT/$DMG_NAME" >/dev/null
if [ "$IDENTITY" != "-" ]; then
  codesign --force --timestamp --sign "$IDENTITY" "$OUT/$DMG_NAME"
fi

NOTARIZED=false        # DMG 容器已公证(下载后双击 DMG 无警告)
APP_NOTARIZED=false    # 里面的 app 已公证并 staple(拖出/解压后双击无警告)
if xcrun stapler validate "$APP" >/dev/null 2>&1; then APP_NOTARIZED=true; fi
if [ -n "$NOTARY_KEY" ] && [ -n "$NOTARY_KEY_ID" ] && [ -n "$NOTARY_ISSUER" ] && [ "$IDENTITY" != "-" ]; then
  echo "== notarize dmg"
  xcrun notarytool submit "$OUT/$DMG_NAME" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait
  xcrun stapler staple "$OUT/$DMG_NAME"
  NOTARIZED=true; APP_NOTARIZED=true
elif [ -n "$NOTARY_APPLE_ID" ] && [ -n "$NOTARY_PASSWORD" ] && [ -n "$NOTARY_TEAM_ID" ] && [ "$IDENTITY" != "-" ]; then
  echo "== notarize dmg (Apple ID + app-specific password)"
  xcrun notarytool submit "$OUT/$DMG_NAME" --apple-id "$NOTARY_APPLE_ID" --password "$NOTARY_PASSWORD" --team-id "$NOTARY_TEAM_ID" --wait
  xcrun stapler staple "$OUT/$DMG_NAME"
  NOTARIZED=true; APP_NOTARIZED=true
elif [ "$IDENTITY" != "-" ] && xcrun notarytool history --keychain-profile AC_NOTARY >/dev/null 2>&1; then
  echo "== notarize dmg (keychain profile AC_NOTARY)"
  xcrun notarytool submit "$OUT/$DMG_NAME" --keychain-profile AC_NOTARY --wait
  xcrun stapler staple "$OUT/$DMG_NAME"
  NOTARIZED=true; APP_NOTARIZED=true
fi

cp -f "$OUT/$DMG_NAME" "$OUT/AShareAgent-latest.dmg"
SHA="$(shasum -a 256 "$OUT/$DMG_NAME" | awk '{print $1}')"
SIZE="$(stat -f %z "$OUT/$DMG_NAME")"

# 同时出一个 ZIP:zip 不是"容器",Gatekeeper 只评估里面的 app(已公证则双击即用),不受 DMG 是否公证影响
ZIP_NAME="AShareAgent-$VERSION-$BUILD.zip"
echo "== ditto → $OUT/$ZIP_NAME"
rm -f "$OUT/$ZIP_NAME"; ditto -c -k --keepParent "$APP" "$OUT/$ZIP_NAME"
cp -f "$OUT/$ZIP_NAME" "$OUT/AShareAgent-latest.zip"
ZIP_SHA="$(shasum -a 256 "$OUT/$ZIP_NAME" | awk '{print $1}')"
ZIP_SIZE="$(stat -f %z "$OUT/$ZIP_NAME")"
SIGNED=$([ "$IDENTITY" != "-" ] && echo true || echo false)
COMMIT="${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}"
cat > "$OUT/latest.json" <<JSON
{"version":"$VERSION","build":$BUILD,"file":"$DMG_NAME","sha256":"$SHA","size":$SIZE,
 "zip_file":"$ZIP_NAME","zip_sha256":"$ZIP_SHA","zip_size":$ZIP_SIZE,
 "signed":$SIGNED,"notarized":$NOTARIZED,"app_notarized":$APP_NOTARIZED,"min_macos":"14.0","arch":"arm64",
 "commit":"$COMMIT","published_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
JSON
echo "== done"; cat "$OUT/latest.json"; ls -la "$OUT"
