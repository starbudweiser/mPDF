#!/bin/zsh
# Publie une version : compile, notarise (Apple), zippe puis crée la release GitHub.
# Usage : ./release.sh [--notes "texte"]   — la version vient de CFBundleShortVersionString (Resources/Info.plist).
set -euo pipefail
cd "$(dirname "$0")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
TAG="v$VERSION"
DIST="$PWD/dist"
NOTES=""
[ "${1:-}" = "--notes" ] && NOTES="${2:-}"
git diff --quiet && git diff --cached --quiet || { echo "Modifications non commitées : commiter avant la release." >&2; exit 1; }
! git rev-parse "$TAG" >/dev/null 2>&1 || { echo "La version $TAG existe déjà." >&2; exit 1; }
git fetch -q origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "Pas synchronisé avec origin/main (push manquant)." >&2; exit 1; }

NO_INSTALL=1 NO_OPEN=1 ./build_app.sh
rm -rf "$DIST"
DIST="$DIST" /Volumes/SKYRIM/TOOLS/MAC/_tools/notarize_app.sh mPDF.app
ASSET="mPDF-$VERSION-macOS.zip"
mv "$DIST/mPDF.zip" "$DIST/$ASSET"
(cd "$DIST" && shasum -a 256 "$ASSET" > "$ASSET.sha256")

if [ -z "$NOTES" ]; then
  NOTES_FILE="$DIST/notes.md"
  cat > "$NOTES_FILE" <<NOTES_EOF
<!-- notes:fr -->
## $VERSION
- Nouveau : une image sélectionnée propose « Détourer » (et « Image d'origine »), calcul en arrière-plan.
- Barre d'outils : icônes et boutons de fenêtre bien centrés.
<!-- notes:en -->
## $VERSION
- New: a selected image offers "Cut out" (and "Original"), computed in the background.
- Toolbar: icons and window buttons properly centered.
<!-- notes:es -->
## $VERSION
- Novedad: una imagen seleccionada ofrece «Recortar» (y «Original»), calculado en segundo plano.
- Barra de herramientas: iconos y botones de ventana bien centrados.
<!-- notes:it -->
## $VERSION
- Novità: un'immagine selezionata offre «Ritaglia» (e «Originale»), calcolato in background.
- Barra degli strumenti: icone e pulsanti della finestra ben centrati.
NOTES_EOF
  NOTES_ARGS=(--notes-file "$NOTES_FILE")
else NOTES_ARGS=(--notes "$NOTES"); fi

git tag "$TAG" && git push -q origin "$TAG"
gh release create "$TAG" "$DIST/$ASSET" "$DIST/$ASSET.sha256" --title "mPDF $VERSION" "${NOTES_ARGS[@]}"
echo "✓ https://github.com/starbudweiser/mPDF/releases/tag/$TAG"
