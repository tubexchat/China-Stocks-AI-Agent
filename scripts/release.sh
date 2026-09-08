#!/usr/bin/env bash
# 用法: scripts/release.sh archive | export-appstore | export-devid | notarize <app-or-dmg>
set -euo pipefail; cd "$(dirname "$0")/.."
ARCHIVE=build/Axblade.xcarchive

# 导出前先确认 archive 在:否则 xcodebuild 的报错很难看懂。
need_archive() {
  [ -d "$ARCHIVE" ] || { echo "找不到 $ARCHIVE,先跑:$0 archive"; exit 2; }
}

case "${1:-}" in
  archive) xcodegen generate >/dev/null
    mkdir -p build
    # 全量日志留一份:失败时最后 5 行几乎不会是真正的编译/签名报错。
    xcodebuild archive -project Axblade.xcodeproj -scheme Axblade -configuration Release \
      -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" -allowProvisioningUpdates \
      | tee build/archive.log | tail -5 ;;
  export-appstore) need_archive
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist ExportOptions/AppStore.plist \
      -exportPath build/appstore -allowProvisioningUpdates ;;
  export-devid) need_archive
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist ExportOptions/DeveloperID.plist \
      -exportPath build/devid -allowProvisioningUpdates ;;
  notarize)
    [ -n "${2:-}" ] || { echo "usage: $0 notarize <app-or-dmg>"; exit 2; }
    xcrun notarytool submit "$2" --keychain-profile AC_NOTARY --wait && xcrun stapler staple "$2" ;;
  *) echo "usage: $0 archive|export-appstore|export-devid|notarize <path>"; exit 2 ;;
esac
