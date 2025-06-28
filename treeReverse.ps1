# Speichere dieses Skript als treeReverse.ps1

# --- Hilfe-Funktion ---
Function Show-Help {
    Write-Host "`n"
    Write-Host "---------------------------------------------------------"
    Write-Host "Verzeichnisstruktur aus 'tree'-Output erstellen"
    Write-Host "---------------------------------------------------------"
    Write-Host "Dieses Skript erstellt eine Verzeichnis- und Dateistruktur"
    Write-Host "basierend auf der textuellen Ausgabe des 'tree'-Befehls."
    Write-Host "`n"
    Write-Host "Verwendung:"
    Write-Host "  Führen Sie das Skript in dem Verzeichnis aus, in dem die"
    Write-Host "  Struktur erstellt werden soll."
    Write-Host "`n"
    Write-Host "  Geben Sie die 'tree'-Ausgabe als mehrzeiligen String über die Pipeline ein:"
    Write-Host 'Beispiel: "
├── your_dir
│   └── your_file.dart
" | treeReverse'
    Write-Host "`n"
    Write-Host "Oder geben Sie die 'tree'-Ausgabe als einzelnes, mehrzeiliges Argument ein (empfohlen):"
    Write-Host 'Beispiel: treeReverse @"
├── your_dir
│   └── your_file.dart
"@'
    Write-Host "`n"
    Write-Host "Komplettes Beispiel für die Eingabe über die Pipeline:"
    Write-Host 'PS> "
├── src
│   ├── pages
│   │   └── home_page.dart
│   │   └── another_page.dart
│   └── components
│       └── button.dart
└── main.dart
" | treeReverse'
    Write-Host "`n"
    Write-Host "Komplettes Beispiel für die direkte Argumentübergabe:"
    Write-Host 'PS> treeReverse @"
├── src
│   ├── pages
│   │   └── home_page.dart
│   │   └── another_page.dart
│   └── components
│       └── button.dart
└── main.dart
"@'
    Write-Host "`n"
    Write-Host "Optionen:"
    Write-Host "  --help, -h       Zeigt diese Hilfe an."
    Write-Host "---------------------------------------------------------"
    Write-Host "`n"
}

# Überprüfe, ob Hilfe angefordert wurde
if ($args.Count -gt 0) {
    $firstArg = $args[0].ToLower()
    if ($firstArg -eq '--help' -or $firstArg -eq '-h') {
        Show-Help
        exit 0 # Skript beenden, nachdem die Hilfe angezeigt wurde
    }
}

# --- Rest des Skripts ---

# Prüfe, ob Input über die Pipeline übergeben wurde
$treeOutput = ""
if ($Input) {
    $treeOutput = $Input | Out-String
}
# Wenn kein Pipeline-Input, prüfe, ob es direkt als Argument übergeben wurde
elseif ($args.Count -eq 1) {
    $treeOutput = $args[0]
} else {
    Write-Error "Bitte geben Sie die tree-Ausgabe über die Pipeline oder als einzelnes mehrzeiliges Argument an. Verwenden Sie --help für weitere Informationen."
    exit 1
}

# Wenn $treeOutput nach der Prüfung immer noch leer ist (z.B. wenn nur --help da war, aber das wurde oben abgefangen)
if ([string]::IsNullOrEmpty($treeOutput)) {
    Write-Error "Es wurde keine tree-Ausgabe zum Verarbeiten bereitgestellt. Verwenden Sie --help für weitere Informationen."
    exit 1
}

# Initialisiere eine dynamische Liste für Pfadkomponenten, die RemoveAt unterstützt
$currentPathComponents = [System.Collections.Generic.List[string]]::new()
$previousLevel = -1 # Um die Einrückung zu verfolgen

$treeOutput -split "`n" | ForEach-Object {
    $line = $_

    # Entferne führende Leerzeichen und Tabs am Anfang, aber behalte die Strukturzeichen vorerst
    $trimmedLine = $line.Trim() # Trim entfernt führende/nachfolgende Whitespaces

    # Ignoriere leere Zeilen
    if ([string]::IsNullOrEmpty($trimmedLine)) {
        return
    }

    # Spezieller Fall: Wenn die erste Zeile nur "." ist, ignorieren wir sie oder behandeln sie als Wurzel.
    if ($trimmedLine -eq '.') {
        $currentPathComponents.Clear() # Setze Pfadkomponenten zurück
        $previousLevel = 0
        return
    }

    # --- Schritt 1: Bestimme das Level und extrahiere den Roh-Inhalt ---
    $level = 0
    $content = ""
    
    # Eine robustere Level-Berechnung, die die Einrückung berücksichtigt:
    if ($line -match '^(?<indent>[\s│]*)(?<sym>├──|└──|)(?<name>.*)$') {
         $indent = $Matches.indent
         $sym = $Matches.sym
         $name = $Matches.name.Trim()
         $pipeCount = ($indent | Select-String -Pattern '│' -AllMatches).Matches.Count
         
         $level = $pipeCount # Basislevel durch Zählung der Pipes

         if ($sym -ne '') {
             $level = $pipeCount + 1 # Z.B. "├──" ist Level 1, "│   ├──" ist Level 2
         } elseif ($pipeCount -gt 0 -and $sym -eq '') {
             # Dies ist ein "│   " Block ohne Symbol, sollte auf dem gleichen Level bleiben
             # Die $level ist bereits durch $pipeCount korrekt gesetzt.
         } else {
             # Dies ist die Root-Ebene ohne Symbole (z.B. "posts" wenn es direkt nach "." kommt)
             $level = 0
         }

         $content = $name # Aktualisiere content mit dem Namen ohne Symbole
    } else {
         # Fallback für Zeilen, die nicht dem Muster folgen (z.B. die erste Ebene "posts" ohne Symbole)
         $level = 0
         $content = $line.Trim()
    }

    # --- Schritt 2: Aktualisiere die Pfadkomponenten basierend auf dem Level ---
    # Entferne überschüssige Komponenten, wenn wir auf einer höheren Ebene sind
    while ($currentPathComponents.Count -gt $level) {
        $currentPathComponents.RemoveAt($currentPathComponents.Count - 1)
    }

    # Füge die aktuelle Komponente hinzu.
    # Wichtig: Hier nutzen wir den $content, der den reinen Namen enthält.
    # Füge die Komponente nur hinzu, wenn sie nicht leer ist.
    if (-not [string]::IsNullOrEmpty($content)) {
        $currentPathComponents.Add($content)
    }


    # --- Schritt 3: Konstruiere den vollständigen relativen Pfad und erstelle Elemente ---
    $fullPath = $currentPathComponents -join '\' # Für Windows-Pfade '\' oder '/' sind beide ok

    # Prüfe, ob es sich um eine Datei oder ein Verzeichnis handelt
    # Die Heuristik ist, zu schauen, ob ein Punkt im Namen ist.
    if ($content -like '*.*') {
        # Es ist wahrscheinlich eine Datei

        # Erstelle das übergeordnete Verzeichnis, falls es nicht existiert
        $dirName = Split-Path -Path $fullPath -Parent
        if (-not (Test-Path -Path $dirName -PathType Container)) {
            #Write-Host "Erstelle Verzeichnis: $dirName" # Debugging-Ausgabe
            New-Item -ItemType Directory -Path $dirName -Force | Out-Null
        }
        # Erstelle die leere Datei
        #Write-Host "Erstelle Datei: $fullPath" # Debugging-Ausgabe
        New-Item -ItemType File -Path $fullPath -Force | Out-Null

        # Wichtig: Entferne die Datei wieder aus den Pfadkomponenten,
        # da sie kein Verzeichnis ist, unter dem weitere Elemente liegen könnten.
        if ($currentPathComponents.Count -gt 0) {
            $currentPathComponents.RemoveAt($currentPathComponents.Count - 1)
        }
    } else {
        # Es ist ein Verzeichnis
        #Write-Host "Erstelle Verzeichnis: $fullPath" # Debugging-Ausgabe
        New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
    }

    $previousLevel = $level # Aktualisiere das vorherige Level für den nächsten Schleifendurchlauf
}

Write-Host "Verzeichnisstruktur erfolgreich erstellt."
