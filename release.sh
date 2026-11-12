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
- Correction : le détourage fonctionne aussi sur les photos avec un canal de transparence opaque.
- La carte « Détourer » reste centrée sous l'image (au-dessus si elle est trop basse), avec barre de progression et pourcentage.
<!-- notes:en -->
## $VERSION
- Fix: background removal now also works on photos with an opaque alpha channel.
- The "Cut out" card stays centered under the image (above it if too low), with a progress bar and percentage.
<!-- notes:es -->
## $VERSION
- Corrección: el recorte también funciona con fotos que tienen un canal alfa opaco.
- La tarjeta «Recortar» queda centrada bajo la imagen (encima si está muy abajo), con barra de progreso y porcentaje.
<!-- notes:it -->
## $VERSION
- Correzione: il ritaglio funziona anche sulle foto con canale alfa opaco.
- La scheda «Ritaglia» resta centrata sotto l'immagine (sopra se troppo in basso), con barra di avanzamento e percentuale.
NOTES_EOF
  NOTES_ARGS=(--notes-file "$NOTES_FILE")
else NOTES_ARGS=(--notes "$NOTES"); fi

git tag "$TAG" && git push -q origin "$TAG"
gh release create "$TAG" "$DIST/$ASSET" "$DIST/$ASSET.sha256" --title "mPDF $VERSION" "${NOTES_ARGS[@]}"
echo "✓ https://github.com/starbudweiser/mPDF/releases/tag/$TAG"
