#!/bin/bash
# Dump Info.plists, entitlements, codesign details and provisioning of an .app and its embedded .appex.
APP="$1"
echo "=================== $APP"
ls -la "$APP" | head -50
echo "--- PlugIns:"; ls -la "$APP/PlugIns" 2>&1
for B in "$APP" "$APP"/PlugIns/*.appex; do
  [ -d "$B" ] || continue
  echo; echo "########## $B"
  echo "--- Info.plist"; plutil -p "$B/Info.plist"
  echo "--- files"; ls -la "$B"
  echo "--- codesign -dvvv"; codesign -dvvv "$B" 2>&1
  echo "--- entitlements"; codesign -d --entitlements - --xml "$B" 2>/dev/null | plutil -p - 2>&1
  if [ -f "$B/embedded.mobileprovision" ]; then
    echo "--- embedded.mobileprovision"
    security cms -D -i "$B/embedded.mobileprovision" > /tmp/prof.plist 2>/dev/null
    for k in Name AppIDName TeamIdentifier ExpirationDate ProvisionsAllDevices; do
      echo "$k: $(/usr/libexec/PlistBuddy -c "Print :$k" /tmp/prof.plist 2>/dev/null | tr '\n' ' ')"
    done
    echo "Entitlements:"; /usr/libexec/PlistBuddy -c "Print :Entitlements" /tmp/prof.plist 2>/dev/null
  else
    echo "--- (no embedded.mobileprovision)"
  fi
  if [ -f "$B/Assets.car" ]; then
    echo "--- Assets.car names"; xcrun assetutil --info "$B/Assets.car" 2>/dev/null | grep -E '"(Name|RenditionName|Idiom|Scale|PixelWidth|PixelHeight|AssetType)"' | paste - - - - - - 2>/dev/null | head -60
  fi
  echo "--- binary"; EXE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$B/Info.plist"); file "$B/$EXE"; otool -l "$B/$EXE" | grep -A4 LC_BUILD_VERSION | head -6
done
