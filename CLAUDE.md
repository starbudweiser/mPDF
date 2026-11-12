# mPDF

Lecteur et éditeur PDF rapide pour macOS (Swift, AppKit, PDFKit).

- Interface : suivre le design system Socle — https://claude.ai/artifact/TkNj2Y6SQGZwT6EyME92Ah (copie locale : /Volumes/SKYRIM/TOOLS/DESIGN/Socle).
- Build de développement : `DEV=1 ./build_app.sh` (« mPDF DEV.app », bundle id `fr.stephan.mpdf.dev`). Version locale installée : `./build_app.sh`.
- Release (notarisation + GitHub) : `./release.sh` ; jamais sans demande explicite.
- `Sources/Updater.swift`, `UpdaterView.swift`, `Socle.swift` sont des fichiers communs (synchronisés par `_tools/sync_shared.sh` et `Socle/sync_apps.sh`) : ne pas les modifier ici.
- Quatre langues (fr, en, es, it), mêmes clés dans `Sources/L10n.swift`.
