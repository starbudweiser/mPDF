#!/bin/zsh
# Construit mPDF.app. DEV=1 : édition de développement « mPDF DEV.app » (bundle id …dev), dans le dossier du projet, non installée.
# Sinon : signature locale stable (_tools/sign_app.sh) et installation dans ~/Applications/Applications Personnelles.
set -euo pipefail
cd "$(dirname "$0")"
if [ -n "${DEV:-}" ]; then APP="mPDF DEV.app"; ID="fr.stephan.mpdf.dev"; NAME="mPDF DEV"; else APP="mPDF.app"; ID="fr.stephan.mpdf"; NAME="mPDF"; fi
rm -rf "$APP" build; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -parse-as-library -module-name mPDF -target $arch-apple-macos14 -o build/mPDF-$arch Sources/*.swift
done
lipo -create build/mPDF-arm64 build/mPDF-x86_64 -output "$APP/Contents/MacOS/mPDF"
cp assets/mPDF.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$APP/Contents/Info.plist"
for l in Resources/*.lproj; do cp -R "$l" "$APP/Contents/Resources/"; done
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $ID" -c "Set :CFBundleName $NAME" -c "Set :CFBundleDisplayName $NAME" "$APP/Contents/Info.plist"
rm -rf build
SIGN="/Volumes/SKYRIM/TOOLS/MAC/_tools/sign_app.sh"
if [ -x "$SIGN" ]; then "$SIGN" "$APP"; else codesign --force --deep -s - "$APP"; fi
if [ -z "${DEV:-}" ] && [ -z "${NO_INSTALL:-}" ]; then
  DEST="$HOME/Applications/Applications Personnelles"; mkdir -p "$DEST"
  rm -rf "$DEST/$APP"; ditto "$APP" "$DEST/$APP"; echo "Installée : $DEST/$APP"
fi
echo "OK : $APP"
[ -n "${NO_OPEN:-}" ] || open -g "$APP"
