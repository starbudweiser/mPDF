// mPDF — textes de l'interface (français d'abord, anglais, espagnol, italien ; mêmes clés dans chaque table).
import Foundation

enum L {
    static let lang: String = {
        let code = String((Locale.preferredLanguages.first ?? "en").prefix(2))
        return tables[code] != nil ? code : "en"
    }()

    static func t(_ key: String, _ args: CVarArg...) -> String {
        let s = tables[lang]?[key] ?? tables["en"]?[key] ?? key
        return args.isEmpty ? s : String(format: s, arguments: args)
    }

    static let tables: [String: [String: String]] = ["fr": fr, "en": en, "es": es, "it": it]

    private static let fr: [String: String] = [
        "menu.about": "À propos de mPDF", "menu.hide": "Masquer mPDF", "menu.hideOthers": "Masquer les autres", "menu.showAll": "Tout afficher", "menu.quit": "Quitter mPDF",
        "menu.go": "Aller", "menu.file": "Fichier", "menu.open": "Ouvrir…", "menu.recent": "Ouvrir récent", "menu.clearRecent": "Effacer le menu", "menu.close": "Fermer", "menu.save": "Enregistrer", "menu.saveAs": "Enregistrer sous…", "menu.print": "Imprimer…",
        "menu.edit": "Édition", "menu.undo": "Annuler", "menu.redo": "Rétablir", "menu.copy": "Copier", "menu.selectAll": "Tout sélectionner", "menu.find": "Rechercher", "menu.findNext": "Résultat suivant", "menu.findPrev": "Résultat précédent",
        "menu.view": "Présentation", "menu.toolbar": "Afficher / masquer la barre d'outils", "menu.sidebar": "Panneau des pages", "menu.panelLeft": "Pages à gauche", "menu.panelRight": "Pages à droite", "menu.notesPanel": "Panneau des notes", "menu.zoomIn": "Agrandir", "menu.zoomOut": "Réduire", "menu.actualSize": "Taille réelle", "menu.fitWidth": "Ajuster à la largeur", "menu.fitPage": "Ajuster à la page",
        "menu.single": "Une page", "menu.continuous": "Défilement continu", "menu.twoUp": "Deux pages", "menu.twoUpContinuous": "Deux pages en continu", "menu.rotateLeft": "Pivoter à gauche", "menu.rotateRight": "Pivoter à droite",
        "menu.nextPage": "Page suivante", "menu.prevPage": "Page précédente", "menu.firstPage": "Première page", "menu.lastPage": "Dernière page", "menu.goToPage": "Aller à la page…", "menu.back": "Retour", "menu.forward": "Avance",
        "menu.fullScreen": "Plein écran", "menu.presentation": "Présentation plein écran", "menu.tools": "Outils", "menu.window": "Fenêtre", "menu.minimize": "Placer dans le Dock", "menu.zoom": "Agrandir la fenêtre", "menu.bringAll": "Tout ramener au premier plan",
        "menu.checkUpdates": "Rechercher les mises à jour…",
        "tool.hand": "Main (déplacer)", "tool.highlight": "Surligner", "tool.underline": "Souligner", "tool.strike": "Barrer", "tool.note": "Note", "tool.text": "Zone de texte",
        "tb.sidebar": "Barre latérale", "tb.search": "Rechercher", "tb.nav": "Pages", "tb.zoom": "Zoom", "tb.tools": "Outils", "tb.display": "Affichage",
        "side.thumbs": "Pages", "side.outline": "Sommaire", "side.empty": "Pas de sommaire dans ce document.",
        "notes.title": "Notes", "notes.empty": "Aucune note. Surlignez du texte ou ajoutez une note.", "notes.delete": "Supprimer", "notes.edit": "Modifier le texte…",
        "note.prompt": "Texte de la note", "note.ok": "OK", "note.cancel": "Annuler", "note.page": "p. %d",
        "kind.highlight": "Surlignage", "kind.underline": "Soulignement", "kind.strike": "Barré", "kind.note": "Note", "kind.text": "Texte", "kind.other": "Annotation",
        "page.of": "Page %d sur %d", "page.goto.title": "Aller à la page", "page.goto.info": "Numéro de page (1 à %d)",
        "pw.title": "Document protégé", "pw.info": "Saisissez le mot de passe de « %@ ».", "pw.open": "Ouvrir", "pw.wrong": "Mot de passe incorrect.",
        "err.read": "Impossible de lire ce PDF.", "search.results": "%d résultat(s)", "search.none": "Aucun résultat",
        "about.version": "Version %@", "about.tagline": "Lecteur PDF rapide et léger pour macOS.", "about.author": "Starbudweiser & Claude Code (Anthropic)", "about.license": "Licence MIT. © 2026 Starbudweiser.", "about.warranty": "Fourni en l'état, sans garantie.",
        "unsaved.title": "Enregistrer les modifications de « %@ » ?", "unsaved.info": "Vos annotations seront perdues si vous ne les enregistrez pas.",
        "tool.select": "Sélection", "tool.pen": "Stylo", "tool.rect": "Rectangle", "tool.ellipse": "Ellipse", "tool.arrow": "Flèche", "tool.check": "Coche ✓", "tool.cross": "Croix ✗", "tb.more": "Plus d'outils", "menu.insertImage": "Insérer une image…", "menu.insertPDF": "Insérer des pages depuis un fichier…", "menu.blankPage": "Insérer une page vierge", "menu.duplicatePage": "Dupliquer la page", "menu.deletePage": "Supprimer la page", "menu.pagesMenu": "Pages", "pm.insertFile": "Insérer un PDF ou une image ici…", "pm.blank": "Page vierge après", "pm.duplicate": "Dupliquer", "pm.delete": "Supprimer la page", "drop.placeHere": "Placer l'image ici", "drop.before": "Insérer avant la page %d", "drop.after": "Insérer après la page %d", "drop.newPageBefore": "Nouvelle page avant la page %d", "drop.newPageAfter": "Nouvelle page après la page %d", "kind.shape": "Forme", "kind.ink": "Dessin", "kind.image": "Image",
        "menu.settings": "Réglages…", "settings.title": "Réglages", "settings.cutout": "Détourer automatiquement les images importées", "settings.auto": "Installer automatiquement les mises à jour", "settings.check": "Rechercher les mises à jour",
        "tb.text": "Texte", "tb.eraser": "Gomme", "tb.image": "Image", "fmt.font": "Police", "fmt.size": "Taille", "fmt.bold": "Gras", "fmt.italic": "Italique", "wo.text": "Écrire du texte ici", "wo.image": "Placer une image ici…", "wo.delete": "Supprimer la gomme", "tool.whiteout": "Gomme (masquer, puis écrire par-dessus : double-clic)",
        "wo.textShort": "Écrire",
        "tb.pages": "Pages", "tb.select": "Sélection", "tb.hand": "Main", "tb.check": "Coche", "tb.highlight": "Surligner", "tb.pen": "Stylo", "tb.shapes": "Formes", "tb.notes": "Notes",
    ]

    private static let en: [String: String] = [
        "menu.about": "About mPDF", "menu.hide": "Hide mPDF", "menu.hideOthers": "Hide Others", "menu.showAll": "Show All", "menu.quit": "Quit mPDF",
        "menu.go": "Go", "menu.file": "File", "menu.open": "Open…", "menu.recent": "Open Recent", "menu.clearRecent": "Clear Menu", "menu.close": "Close", "menu.save": "Save", "menu.saveAs": "Save As…", "menu.print": "Print…",
        "menu.edit": "Edit", "menu.undo": "Undo", "menu.redo": "Redo", "menu.copy": "Copy", "menu.selectAll": "Select All", "menu.find": "Find", "menu.findNext": "Find Next", "menu.findPrev": "Find Previous",
        "menu.view": "View", "menu.toolbar": "Show / Hide Toolbar", "menu.sidebar": "Pages Panel", "menu.panelLeft": "Pages on Left", "menu.panelRight": "Pages on Right", "menu.notesPanel": "Notes Panel", "menu.zoomIn": "Zoom In", "menu.zoomOut": "Zoom Out", "menu.actualSize": "Actual Size", "menu.fitWidth": "Fit Width", "menu.fitPage": "Fit Page",
        "menu.single": "Single Page", "menu.continuous": "Continuous Scroll", "menu.twoUp": "Two Pages", "menu.twoUpContinuous": "Two Pages Continuous", "menu.rotateLeft": "Rotate Left", "menu.rotateRight": "Rotate Right",
        "menu.nextPage": "Next Page", "menu.prevPage": "Previous Page", "menu.firstPage": "First Page", "menu.lastPage": "Last Page", "menu.goToPage": "Go to Page…", "menu.back": "Back", "menu.forward": "Forward",
        "menu.fullScreen": "Full Screen", "menu.presentation": "Presentation Mode", "menu.tools": "Tools", "menu.window": "Window", "menu.minimize": "Minimize", "menu.zoom": "Zoom", "menu.bringAll": "Bring All to Front",
        "menu.checkUpdates": "Check for Updates…",
        "tool.hand": "Hand (move)", "tool.highlight": "Highlight", "tool.underline": "Underline", "tool.strike": "Strike Through", "tool.note": "Note", "tool.text": "Text Box",
        "tb.sidebar": "Sidebar", "tb.search": "Search", "tb.nav": "Pages", "tb.zoom": "Zoom", "tb.tools": "Tools", "tb.display": "Display",
        "side.thumbs": "Pages", "side.outline": "Outline", "side.empty": "This document has no outline.",
        "notes.title": "Notes", "notes.empty": "No notes. Highlight text or add a note.", "notes.delete": "Delete", "notes.edit": "Edit Text…",
        "note.prompt": "Note text", "note.ok": "OK", "note.cancel": "Cancel", "note.page": "p. %d",
        "kind.highlight": "Highlight", "kind.underline": "Underline", "kind.strike": "Strike", "kind.note": "Note", "kind.text": "Text", "kind.other": "Annotation",
        "page.of": "Page %d of %d", "page.goto.title": "Go to Page", "page.goto.info": "Page number (1 to %d)",
        "pw.title": "Protected document", "pw.info": "Enter the password for “%@”.", "pw.open": "Open", "pw.wrong": "Wrong password.",
        "err.read": "Unable to read this PDF.", "search.results": "%d result(s)", "search.none": "No results",
        "about.version": "Version %@", "about.tagline": "A fast, lightweight PDF reader for macOS.", "about.author": "Starbudweiser & Claude Code (Anthropic)", "about.license": "MIT License. © 2026 Starbudweiser.", "about.warranty": "Provided as is, without warranty.",
        "unsaved.title": "Save changes to “%@”?", "unsaved.info": "Your annotations will be lost if you don't save them.",
        "tool.select": "Select", "tool.pen": "Pen", "tool.rect": "Rectangle", "tool.ellipse": "Ellipse", "tool.arrow": "Arrow", "tool.check": "Check ✓", "tool.cross": "Cross ✗", "tb.more": "More Tools", "menu.insertImage": "Insert Image…", "menu.insertPDF": "Insert Pages from File…", "menu.blankPage": "Insert Blank Page", "menu.duplicatePage": "Duplicate Page", "menu.deletePage": "Delete Page", "menu.pagesMenu": "Pages", "pm.insertFile": "Insert PDF or Image Here…", "pm.blank": "Blank Page After", "pm.duplicate": "Duplicate", "pm.delete": "Delete Page", "drop.placeHere": "Place Image Here", "drop.before": "Insert Before Page %d", "drop.after": "Insert After Page %d", "drop.newPageBefore": "New Page Before Page %d", "drop.newPageAfter": "New Page After Page %d", "kind.shape": "Shape", "kind.ink": "Drawing", "kind.image": "Image",
        "menu.settings": "Settings…", "settings.title": "Settings", "settings.cutout": "Automatically remove the background of imported images", "settings.auto": "Install updates automatically", "settings.check": "Check for Updates",
        "tb.text": "Text", "tb.eraser": "Eraser", "tb.image": "Image", "fmt.font": "Font", "fmt.size": "Size", "fmt.bold": "Bold", "fmt.italic": "Italic", "wo.text": "Write text here", "wo.image": "Place an image here…", "wo.delete": "Delete eraser", "tool.whiteout": "Eraser (hide, then write over it: double-click)",
        "wo.textShort": "Write",
        "tb.pages": "Pages", "tb.select": "Select", "tb.hand": "Hand", "tb.check": "Check", "tb.highlight": "Highlight", "tb.pen": "Pen", "tb.shapes": "Shapes", "tb.notes": "Notes",
    ]

    private static let es: [String: String] = [
        "menu.about": "Acerca de mPDF", "menu.hide": "Ocultar mPDF", "menu.hideOthers": "Ocultar otros", "menu.showAll": "Mostrar todo", "menu.quit": "Salir de mPDF",
        "menu.go": "Ir", "menu.file": "Archivo", "menu.open": "Abrir…", "menu.recent": "Abrir reciente", "menu.clearRecent": "Borrar menú", "menu.close": "Cerrar", "menu.save": "Guardar", "menu.saveAs": "Guardar como…", "menu.print": "Imprimir…",
        "menu.edit": "Edición", "menu.undo": "Deshacer", "menu.redo": "Rehacer", "menu.copy": "Copiar", "menu.selectAll": "Seleccionar todo", "menu.find": "Buscar", "menu.findNext": "Resultado siguiente", "menu.findPrev": "Resultado anterior",
        "menu.view": "Visualización", "menu.toolbar": "Mostrar / ocultar barra de herramientas", "menu.sidebar": "Panel de páginas", "menu.panelLeft": "Páginas a la izquierda", "menu.panelRight": "Páginas a la derecha", "menu.notesPanel": "Panel de notas", "menu.zoomIn": "Ampliar", "menu.zoomOut": "Reducir", "menu.actualSize": "Tamaño real", "menu.fitWidth": "Ajustar al ancho", "menu.fitPage": "Ajustar a la página",
        "menu.single": "Una página", "menu.continuous": "Desplazamiento continuo", "menu.twoUp": "Dos páginas", "menu.twoUpContinuous": "Dos páginas continuas", "menu.rotateLeft": "Girar a la izquierda", "menu.rotateRight": "Girar a la derecha",
        "menu.nextPage": "Página siguiente", "menu.prevPage": "Página anterior", "menu.firstPage": "Primera página", "menu.lastPage": "Última página", "menu.goToPage": "Ir a la página…", "menu.back": "Atrás", "menu.forward": "Adelante",
        "menu.fullScreen": "Pantalla completa", "menu.presentation": "Presentación a pantalla completa", "menu.tools": "Herramientas", "menu.window": "Ventana", "menu.minimize": "Minimizar", "menu.zoom": "Zoom", "menu.bringAll": "Traer todo al frente",
        "menu.checkUpdates": "Buscar actualizaciones…",
        "tool.hand": "Mano (mover)", "tool.highlight": "Resaltar", "tool.underline": "Subrayar", "tool.strike": "Tachar", "tool.note": "Nota", "tool.text": "Cuadro de texto",
        "tb.sidebar": "Barra lateral", "tb.search": "Buscar", "tb.nav": "Páginas", "tb.zoom": "Zoom", "tb.tools": "Herramientas", "tb.display": "Visualización",
        "side.thumbs": "Páginas", "side.outline": "Índice", "side.empty": "Este documento no tiene índice.",
        "notes.title": "Notas", "notes.empty": "Sin notas. Resalte texto o añada una nota.", "notes.delete": "Eliminar", "notes.edit": "Editar texto…",
        "note.prompt": "Texto de la nota", "note.ok": "Aceptar", "note.cancel": "Cancelar", "note.page": "p. %d",
        "kind.highlight": "Resaltado", "kind.underline": "Subrayado", "kind.strike": "Tachado", "kind.note": "Nota", "kind.text": "Texto", "kind.other": "Anotación",
        "page.of": "Página %d de %d", "page.goto.title": "Ir a la página", "page.goto.info": "Número de página (1 a %d)",
        "pw.title": "Documento protegido", "pw.info": "Introduzca la contraseña de «%@».", "pw.open": "Abrir", "pw.wrong": "Contraseña incorrecta.",
        "err.read": "No se puede leer este PDF.", "search.results": "%d resultado(s)", "search.none": "Sin resultados",
        "about.version": "Versión %@", "about.tagline": "Lector de PDF rápido y ligero para macOS.", "about.author": "Starbudweiser & Claude Code (Anthropic)", "about.license": "Licencia MIT. © 2026 Starbudweiser.", "about.warranty": "Se proporciona tal cual, sin garantía.",
        "unsaved.title": "¿Guardar los cambios de «%@»?", "unsaved.info": "Sus anotaciones se perderán si no las guarda.",
        "tool.select": "Selección", "tool.pen": "Lápiz", "tool.rect": "Rectángulo", "tool.ellipse": "Elipse", "tool.arrow": "Flecha", "tool.check": "Marca ✓", "tool.cross": "Cruz ✗", "tb.more": "Más herramientas", "menu.insertImage": "Insertar imagen…", "menu.insertPDF": "Insertar páginas desde un archivo…", "menu.blankPage": "Insertar página en blanco", "menu.duplicatePage": "Duplicar página", "menu.deletePage": "Eliminar página", "menu.pagesMenu": "Páginas", "pm.insertFile": "Insertar PDF o imagen aquí…", "pm.blank": "Página en blanco después", "pm.duplicate": "Duplicar", "pm.delete": "Eliminar página", "drop.placeHere": "Colocar la imagen aquí", "drop.before": "Insertar antes de la página %d", "drop.after": "Insertar después de la página %d", "drop.newPageBefore": "Nueva página antes de la página %d", "drop.newPageAfter": "Nueva página después de la página %d", "kind.shape": "Forma", "kind.ink": "Dibujo", "kind.image": "Imagen",
        "menu.settings": "Ajustes…", "settings.title": "Ajustes", "settings.cutout": "Recortar automáticamente el fondo de las imágenes importadas", "settings.auto": "Instalar las actualizaciones automáticamente", "settings.check": "Buscar actualizaciones",
        "tb.text": "Texto", "tb.eraser": "Borrador", "tb.image": "Imagen", "fmt.font": "Fuente", "fmt.size": "Tamaño", "fmt.bold": "Negrita", "fmt.italic": "Cursiva", "wo.text": "Escribir texto aquí", "wo.image": "Colocar una imagen aquí…", "wo.delete": "Eliminar borrador", "tool.whiteout": "Borrador (ocultar y escribir encima: doble clic)",
        "wo.textShort": "Escribir",
        "tb.pages": "Páginas", "tb.select": "Selección", "tb.hand": "Mano", "tb.check": "Marca", "tb.highlight": "Resaltar", "tb.pen": "Lápiz", "tb.shapes": "Formas", "tb.notes": "Notas",
    ]

    private static let it: [String: String] = [
        "menu.about": "Informazioni su mPDF", "menu.hide": "Nascondi mPDF", "menu.hideOthers": "Nascondi altri", "menu.showAll": "Mostra tutto", "menu.quit": "Esci da mPDF",
        "menu.go": "Vai", "menu.file": "File", "menu.open": "Apri…", "menu.recent": "Apri recente", "menu.clearRecent": "Cancella menu", "menu.close": "Chiudi", "menu.save": "Salva", "menu.saveAs": "Salva come…", "menu.print": "Stampa…",
        "menu.edit": "Modifica", "menu.undo": "Annulla", "menu.redo": "Ripeti", "menu.copy": "Copia", "menu.selectAll": "Seleziona tutto", "menu.find": "Trova", "menu.findNext": "Risultato successivo", "menu.findPrev": "Risultato precedente",
        "menu.view": "Vista", "menu.toolbar": "Mostra / nascondi barra degli strumenti", "menu.sidebar": "Pannello pagine", "menu.panelLeft": "Pagine a sinistra", "menu.panelRight": "Pagine a destra", "menu.notesPanel": "Pannello note", "menu.zoomIn": "Ingrandisci", "menu.zoomOut": "Riduci", "menu.actualSize": "Dimensioni reali", "menu.fitWidth": "Adatta alla larghezza", "menu.fitPage": "Adatta alla pagina",
        "menu.single": "Pagina singola", "menu.continuous": "Scorrimento continuo", "menu.twoUp": "Due pagine", "menu.twoUpContinuous": "Due pagine continue", "menu.rotateLeft": "Ruota a sinistra", "menu.rotateRight": "Ruota a destra",
        "menu.nextPage": "Pagina successiva", "menu.prevPage": "Pagina precedente", "menu.firstPage": "Prima pagina", "menu.lastPage": "Ultima pagina", "menu.goToPage": "Vai alla pagina…", "menu.back": "Indietro", "menu.forward": "Avanti",
        "menu.fullScreen": "Schermo intero", "menu.presentation": "Presentazione a schermo intero", "menu.tools": "Strumenti", "menu.window": "Finestra", "menu.minimize": "Riduci a icona", "menu.zoom": "Zoom", "menu.bringAll": "Porta tutto in primo piano",
        "menu.checkUpdates": "Verifica aggiornamenti…",
        "tool.hand": "Mano (sposta)", "tool.highlight": "Evidenzia", "tool.underline": "Sottolinea", "tool.strike": "Barra", "tool.note": "Nota", "tool.text": "Casella di testo",
        "tb.sidebar": "Barra laterale", "tb.search": "Cerca", "tb.nav": "Pagine", "tb.zoom": "Zoom", "tb.tools": "Strumenti", "tb.display": "Vista",
        "side.thumbs": "Pagine", "side.outline": "Indice", "side.empty": "Questo documento non ha un indice.",
        "notes.title": "Note", "notes.empty": "Nessuna nota. Evidenzia del testo o aggiungi una nota.", "notes.delete": "Elimina", "notes.edit": "Modifica testo…",
        "note.prompt": "Testo della nota", "note.ok": "OK", "note.cancel": "Annulla", "note.page": "p. %d",
        "kind.highlight": "Evidenziazione", "kind.underline": "Sottolineatura", "kind.strike": "Barrato", "kind.note": "Nota", "kind.text": "Testo", "kind.other": "Annotazione",
        "page.of": "Pagina %d di %d", "page.goto.title": "Vai alla pagina", "page.goto.info": "Numero di pagina (da 1 a %d)",
        "pw.title": "Documento protetto", "pw.info": "Inserisci la password di «%@».", "pw.open": "Apri", "pw.wrong": "Password errata.",
        "err.read": "Impossibile leggere questo PDF.", "search.results": "%d risultato/i", "search.none": "Nessun risultato",
        "about.version": "Versione %@", "about.tagline": "Lettore PDF veloce e leggero per macOS.", "about.author": "Starbudweiser & Claude Code (Anthropic)", "about.license": "Licenza MIT. © 2026 Starbudweiser.", "about.warranty": "Fornito così com'è, senza garanzia.",
        "unsaved.title": "Salvare le modifiche a «%@»?", "unsaved.info": "Le annotazioni andranno perse se non le salvi.",
        "tool.select": "Selezione", "tool.pen": "Penna", "tool.rect": "Rettangolo", "tool.ellipse": "Ellisse", "tool.arrow": "Freccia", "tool.check": "Spunta ✓", "tool.cross": "Croce ✗", "tb.more": "Altri strumenti", "menu.insertImage": "Inserisci immagine…", "menu.insertPDF": "Inserisci pagine da un file…", "menu.blankPage": "Inserisci pagina vuota", "menu.duplicatePage": "Duplica pagina", "menu.deletePage": "Elimina pagina", "menu.pagesMenu": "Pagine", "pm.insertFile": "Inserisci PDF o immagine qui…", "pm.blank": "Pagina vuota dopo", "pm.duplicate": "Duplica", "pm.delete": "Elimina pagina", "drop.placeHere": "Colloca l'immagine qui", "drop.before": "Inserisci prima della pagina %d", "drop.after": "Inserisci dopo la pagina %d", "drop.newPageBefore": "Nuova pagina prima della pagina %d", "drop.newPageAfter": "Nuova pagina dopo la pagina %d", "kind.shape": "Forma", "kind.ink": "Disegno", "kind.image": "Immagine",
        "menu.settings": "Impostazioni…", "settings.title": "Impostazioni", "settings.cutout": "Rimuovi automaticamente lo sfondo delle immagini importate", "settings.auto": "Installa automaticamente gli aggiornamenti", "settings.check": "Verifica aggiornamenti",
        "tb.text": "Testo", "tb.eraser": "Gomma", "tb.image": "Immagine", "fmt.font": "Carattere", "fmt.size": "Dimensione", "fmt.bold": "Grassetto", "fmt.italic": "Corsivo", "wo.text": "Scrivi testo qui", "wo.image": "Inserisci un'immagine qui…", "wo.delete": "Elimina gomma", "tool.whiteout": "Gomma (nascondi e scrivi sopra: doppio clic)",
        "wo.textShort": "Scrivi",
        "tb.pages": "Pagine", "tb.select": "Selezione", "tb.hand": "Mano", "tb.check": "Spunta", "tb.highlight": "Evidenzia", "tb.pen": "Penna", "tb.shapes": "Forme", "tb.notes": "Note",
    ]
}
