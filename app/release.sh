#!/usr/bin/env bash
# Builds the public release: a universal (Apple Silicon + Intel) app signed with Developer ID, in a classic
# drag-to-Applications DMG, notarized by Apple and stapled. Output: app/build/release/DeployedYet.dmg
#
#   app/release.sh                # the real thing
#   app/release.sh --no-notarize  # everything but Apple's check, for trying it out
#
# One-time setup: a "Developer ID Application" certificate in your Keychain, notary credentials saved with
#   xcrun notarytool store-credentials deployedyet --apple-id <you> --team-id WX67M3Z25T
# and the Sparkle update key (already made: login Keychain, account "deployedyet"; its public half is in Project.swift).
# The first run asks permission for your terminal to control Finder (it lays out the DMG window).
set -euo pipefail
cd "$(dirname "$0")"
export TUIST_SKIP_UPDATE_CHECK=1

TEAM=WX67M3Z25T
IDENTITY="Developer ID Application"
PROFILE=deployedyet # notarytool keychain profile
VOLUME="Deployed Yet?"
OUT=build/release # its own folder: clearing it never touches the Debug build in build/debug
APP=$OUT/DerivedData/Build/Products/Release/DeployedYet.app
DMG=$OUT/DeployedYet.dmg # same name every release, so releases/latest/download/DeployedYet.dmg always works
APPCAST=$OUT/appcast.xml # attached next to the DMG; the app reads releases/latest/download/appcast.xml
SPARKLE_BIN=$OUT/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin
NOTARIZE=1
[[ "${1:-}" == "--no-notarize" ]] && NOTARIZE=0

step() { printf '\n\033[1m%s\033[0m\n' "$*"; }
fail() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

step "Checking signing and notary setup"
# Sign by fingerprint: once there are two Developer ID certificates (say, after renewing), the name alone is ambiguous.
IDS=$(security find-identity -v -p codesigning | awk -v team="($TEAM)" '/"Developer ID Application:/ && index($0, team) {print $2}')
[[ -n "$IDS" ]] || fail "No \"$IDENTITY\" certificate for team $TEAM. Create one in Xcode → Settings → Apple Accounts → Manage Certificates."
SIGN_ID=${SIGN_ID:-$IDS}
[[ "$SIGN_ID" != *$'\n'* ]] || fail "Several Developer ID certificates; pick one with SIGN_ID=<fingerprint> app/release.sh:
$(security find-identity -v -p codesigning | grep "Developer ID Application")"
if (( NOTARIZE )); then
  xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
    || fail "No notary credentials named \"$PROFILE\". Run: xcrun notarytool store-credentials $PROFILE --apple-id <you> --team-id $TEAM"
fi

step "Building a universal Release app"
rm -rf "$OUT"
tuist generate --no-open
# Hardened runtime and a secure timestamp are required for notarization; get-task-allow (debugging) must not ship.
tuist xcodebuild build -scheme DeployedYet -configuration Release -derivedDataPath "$OUT/DerivedData" -quiet \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$SIGN_ID" DEVELOPMENT_TEAM="$TEAM" \
  ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS="--timestamp" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")
# Sparkle only offers a higher CFBundleVersion, so a release that forgot the bump would never reach anyone.
[[ "$BUILD" =~ ^[0-9]{1,18}$ ]] || fail "Invalid local CFBundleVersion: $BUILD"
FEED_XML=$(curl -fsSL --connect-timeout 10 --max-time 30 https://github.com/someguy9/deployedyet/releases/latest/download/appcast.xml) \
  || fail "Could not download the live appcast; release blocked."
LIVE=$(printf '%s' "$FEED_XML" | xmllint --nonet --xpath "string((/rss/channel/item)[1]/*[local-name()='version' and namespace-uri()='http://www.andymatuschak.org/xml-namespaces/sparkle'][1])" - 2>/dev/null) \
  || fail "Could not parse the live appcast; release blocked."
[[ "$LIVE" =~ ^[0-9]{1,18}$ ]] || fail "Invalid build number in the live appcast; release blocked."
(( 10#$BUILD > 10#$LIVE )) || fail "CFBundleVersion is $BUILD but the live release is build $LIVE. Bump it in Project.swift."

# Xcode signs Sparkle.framework but leaves its helpers (the installer and updater it launches) with Sparkle's own
# signature. Re-sign them inside out with ours, then the app, so notarization and library validation pass.
SPARKLE=$APP/Contents/Frameworks/Sparkle.framework/Versions/B
sign() { codesign --force --sign "$SIGN_ID" --options runtime --timestamp "$@"; }
sign "$SPARKLE/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
sign "$SPARKLE/Autoupdate"
sign "$SPARKLE/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign --preserve-metadata=entitlements,requirements "$APP"

step "Checking the app's signature"
codesign --verify --deep --strict "$APP"
SIGNATURE=$(codesign -dvv "$APP" 2>&1) # -dvv: only two v's list the certificate authorities
grep -q "Authority=$IDENTITY" <<<"$SIGNATURE" || fail "Not signed with $IDENTITY."
grep -q "flags=0x10000(runtime)" <<<"$SIGNATURE" || fail "Hardened runtime is off."
! codesign -d --entitlements - "$APP" 2>/dev/null | grep -q get-task-allow || fail "get-task-allow would block notarization."
ARCHS=$(lipo -archs "$APP/Contents/MacOS/DeployedYet")
[[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]] || fail "Not universal: $ARCHS"
echo "Deployed Yet? $VERSION, $ARCHS, signed with $IDENTITY ($TEAM), hardened runtime"

step "Making the DMG"
STAGE=$OUT/dmg
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
swift dmg-background.swift "$OUT/bg.png" "$OUT/bg@2x.png"
tiffutil -cathidpicheck "$OUT/bg.png" "$OUT/bg@2x.png" -out "$STAGE/.background/background.tiff" >/dev/null 2>&1
hdiutil create -quiet -srcfolder "$STAGE" -volname "$VOLUME" -fs HFS+ -format UDRW -ov "$OUT/rw.dmg"
MOUNT=$(hdiutil attach "$OUT/rw.dmg" -readwrite -noverify -noautoopen 2> >(grep -v deprecated >&2) | awk -F'\t' '/\/Volumes\//{print $NF}')
DISK=$(basename "$MOUNT") # "Deployed Yet? 1" if an older copy was still mounted
# The window: icon view, no toolbar, the app on the left and Applications on the right, over the background.
osascript <<EOF
tell application "Finder"
  tell disk "$DISK"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 840, 548}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "DeployedYet.app" of container window to {170, 190}
    set position of item "Applications" of container window to {470, 190}
    close
    open
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF
# The disk icon goes in after Finder: its layout pass deletes .VolumeIcon.icns.
cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT"
sync
hdiutil detach "$MOUNT" -quiet
hdiutil convert "$OUT/rw.dmg" -quiet -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -f "$OUT/rw.dmg"
codesign --sign "$SIGN_ID" --timestamp "$DMG"
codesign --verify "$DMG"

if (( NOTARIZE )); then
  step "Notarizing (usually a few minutes)"
  RESULT=$(xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait --output-format json)
  STATUS=$(plutil -extract status raw -o - - <<<"$RESULT")
  if [[ "$STATUS" != "Accepted" ]]; then
    ID=$(plutil -extract id raw -o - - <<<"$RESULT")
    xcrun notarytool log "$ID" --keychain-profile "$PROFILE" >&2 || true
    fail "Notarization: $STATUS"
  fi
  step "Stapling and checking Gatekeeper"
  xcrun stapler staple -q "$DMG"
  xcrun stapler validate -q "$DMG"
  spctl -a -t open --context context:primary-signature -v "$DMG"

  step "Writing the update feed"
  # Signs the stapled DMG with the key in Keychain (macOS may ask to allow generate_appcast the first time).
  FEED=$OUT/feed
  mkdir -p "$FEED"
  cp "$DMG" "$FEED/"
  "$SPARKLE_BIN/generate_appcast" --account deployedyet \
    --download-url-prefix "https://github.com/someguy9/deployedyet/releases/download/v$VERSION/" \
    --link https://deployedyet.com "$FEED"
  mv "$FEED/appcast.xml" "$APPCAST"
  rm -rf "$FEED"
  grep -q "sparkle:edSignature" "$APPCAST" || fail "The appcast has no update signature."
else
  step "Skipped notarizing (--no-notarize): Gatekeeper will warn on other Macs until this runs for real"
fi

step "Done"
echo "$DMG  ($(du -h "$DMG" | cut -f1 | tr -d ' '), sha256 $(shasum -a 256 "$DMG" | cut -c1-16)…)"
if (( NOTARIZE )); then # an if, so --no-notarize still exits 0
  echo "Publish: gh release create v$VERSION app/$DMG app/$APPCAST --title \"Deployed Yet? $VERSION\" --generate-notes"
  echo "Then redeploy the site so it shows $VERSION: bun run --cwd site deploy"
fi
