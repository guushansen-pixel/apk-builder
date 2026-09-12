# apk-builder

Werkzeug zum Bauen von Android-APKs aus Web-Inhalten. Die gesamte Toolchain
liegt self-contained in `toolchain\` - auf dem Rechner ist ausserhalb dieses
Ordners nichts Android-bezogenes installiert.

## Befehle

```powershell
.\setup.ps1                                          # Toolchain installieren (einmalig)
.\doctor.ps1                                         # Installation pruefen
.\new-app.ps1 -Name X -PackageId com.daniel.x        # Projekt erzeugen
.\build-apk.ps1 -App X                               # Debug-APK -> out\
.\build-apk.ps1 -App X -Release                      # signierte Release-APK
```

Es gibt keine Testsuite; `doctor.ps1` plus ein Build der Demo-App ist die
Verifikation.

## Zweite Build-Faehigkeit: Godot (seit 2026-09)

Neben dem WebView-Pfad (oben) baut dieses Projekt auch Godot-Projekte zu
Android-APKs - fuer Spiele, die mehr Grafikleistung brauchen als ein
HTML5-Canvas (siehe `hopper\godot\`, Migration von der WebView-Version).
Teilt sich denselben Android-SDK-Root und Keystore mit dem WebView-Pfad;
nichts wird ersetzt, beide Pfade bleiben unabhaengig nutzbar.

```powershell
.\setup-godot.ps1                                    # Godot-Editor + Exportvorlagen installieren
.\new-godot-app.ps1 -Name X -PackageId com.daniel.x.godot -ProjectRoot <pfad-zum-godot-projekt>
.\build-godot-apk.ps1 -ProjectRoot <pfad> -AppName X          # Debug-APK -> out\
.\build-godot-apk.ps1 -ProjectRoot <pfad> -AppName X -Release # signierte Release-APK
```

- **Sprache: GDScript, kein Mono/C#** - vermeidet eine zusaetzliche
  .NET-Runtime im Export; fuer die bisherigen Projekte nicht noetig.
- **Kein `new-app.ps1`-Aequivalent fuer Web-Content**: das Godot-Projekt
  (Szenen/Skripte) gehoert dem jeweiligen Spiele-Repo, nicht apk-builder -
  `new-godot-app.ps1` erzeugt/aktualisiert nur `export_presets.cfg` (und mit
  `-Bootstrap` ein minimales Testprojekt fuer den Toolchain-Check).
- **`export_presets.cfg` wird von Hand erzeugt, nie per Editor-GUI** - ich
  (Claude Code) kann keine native GUI-App bedienen, nur den Browser-Tab.
  Die Feldstruktur (gegen eine bekannte Godot-4-CI-Vorlage,
  `abarichello/godot-ci`, abgeglichen) funktioniert **bestaetigt** end-to-end
  mit Godot 4.7.2 (Phase-0-Testbuild, debug + release, 2026-09-12). Falls ein
  kuenftiges Godot-Update die Feldnamen aendert und der Export deshalb
  fehlschlaegt: einmaliger manueller Schritt noetig (Editor oeffnen,
  Project -> Export -> Android-Preset neu anlegen, Datei committen) - danach
  bleibt wieder alles skriptbar.
  - **Zwei Stolperfallen dabei gefunden**: (1) `Set-Content -Encoding utf8`
    schreibt in Windows PowerShell 5.1 IMMER ein UTF-8-BOM voraus - Godots
    ConfigFile-Parser ueberliest das nicht und erkennt dann in der ganzen
    Datei **keinen einzigen Preset** (kein Fehler beim Schreiben, nur
    "Invalid export preset name" beim Export). Alle generierten Godot-Dateien
    (`project.godot`, `.gd`, `.tscn`, `export_presets.cfg`) muessen deshalb
    mit `-Encoding ascii` geschrieben werden (Inhalt ist ohnehin reines
    ASCII). (2) `rendering/textures/vram_compression/import_etc2_astc=true`
    muss in `project.godot` gesetzt sein, sonst bricht der Android-Export mit
    "ETC2/ASTC texture compression is required" ab.
- **Keystore**: Release-Builds nutzen denselben `keys\release.jks` wie die
  WebView-Apps (wird bereits fuer mehrere unabhaengige Apps geteilt).
  Zugangsdaten gehen als `GODOT_ANDROID_KEYSTORE_RELEASE_PATH/_USER/_PASSWORD`
  Umgebungsvariablen in den Export, nie in `export_presets.cfg` - die Datei
  ist damit gefahrlos committable. **Bestaetigt funktionsfaehig**: der
  Phase-0-Testbuild wurde tatsaechlich mit dem geteilten Keystore signiert
  (Zertifikat-DN identisch mit den WebView-Apps), nicht mit Godots eigenem
  Auto-Debug-Key.
- **JDK 17 vs. 21 - GEKLAERT**: das gemeinsame JDK 21 (oben, WebView-Pfad)
  funktioniert **ohne Einschraenkung** auch fuer Godots Android-Export
  (Phase-0-Testbuild debug+release erfolgreich). Kein zweites JDK 17 noetig -
  `-UseJdk17`/`jdk-choice.txt` bleiben nur als Fallback fuer den Fall, dass
  ein KUENFTIGES Godot-Update das aendert.
- **NDK - GEKLAERT**: wird fuer einen reinen GDScript-Export (kein Custom
  Build/keine GDExtension, `gradle_build/use_gradle_build=false`) NICHT
  gebraucht - der Phase-0-Testbuild lief erfolgreich durch, ohne dass NDK
  je installiert wurde. `setup-godot.ps1 -WithNdk` bleibt nur fuer den Fall
  eines spaeteren Custom Builds (natives Plugin/GDExtension) reserviert.
- **`gradle_build/use_gradle_build=false`** im Bootstrap-Preset: nutzt Godots
  vorgefertigtes Android-Exportbinary statt eines vollen Gradle-Unterprojekts
  - der einfachste, am wenigsten fehleranfaellige Pfad. Nur auf `true`
  umstellen, wenn ein Feature wirklich einen Custom Build braucht (z.B.
  natives Plugin/GDExtension) - das braucht dann vermutlich auch das NDK.
- **Self-contained mode**: eine leere `._sc_`-Datei neben `godot.exe` sorgt
  dafuer, dass Godot Editor-Einstellungen (inkl. Exportvorlagen) unter
  `toolchain\godot\editor_data\` ablegt statt in `%APPDATA%` - gleiche
  "nichts ausserhalb des Projektordners"-Philosophie wie beim Rest der
  Toolchain.

## Struktur

- `lib\versions.ps1` - **einziger** Ort fuer Versionen und Download-URLs
- `lib\env.ps1` - setzt JAVA_HOME/ANDROID_HOME/GRADLE_USER_HOME, nur pro Session
- `templates\webview\` - Projektvorlage mit `{{PLATZHALTERN}}`
- `templates\sample-www\` - Demo-Web-App fuer Testbuilds
- `apps\` - generierte Projekte (nicht von Hand anlegen)
- `out\` - fertige APKs
- `keys\`, `toolchain\` - gitignored

## Konventionen

- Versionen werden **nur** in `lib\versions.ps1` geaendert, nie im Template
  hartkodiert. Das Template zieht sie ueber Platzhalter.
- Beim Anheben von AGP immer die Kompatibilitaetsmatrix pruefen
  (AGP -> Gradle -> JDK -> Build-Tools), Quelle steht als Kommentar in
  `versions.ps1`.
- Downloads werden immer gegen SHA-256 geprueft. Beim JDK kommt der Checksum
  live von der Adoptium-API mit.
- Das Template bleibt **abhaengigkeitsfrei** (kein androidx, kein Kotlin).
  Wer Bibliotheken braucht, legt ein zweites Template an, statt dieses
  aufzublaehen.
- Skripte laufen unter Windows PowerShell 5.1: kein `&&`, kein Ternary,
  kein `??`.
- **Native Programme nie direkt aufrufen**, sondern immer ueber `Invoke-Native`
  (Ausgabe durchreichen) oder `Get-NativeOutput` (Ausgabe als Text) aus
  `lib\env.ps1`. Begruendung siehe unten.

## Bekannte Stolperstellen

- **"Force Dark" faerbt die App um.** Ab Android 10 invertiert das System
  Apps mit hellem Theme, sobald der dunkle Modus aktiv ist - die Seite blitzt
  erst hell auf und wird dann schwarz. Das Template schaltet das an *beiden*
  Stellen ab: `android:forceDarkAllowed=false` im Theme und
  `setForceDark(FORCE_DARK_OFF)` am WebView. Eine der beiden allein reicht je
  nach Android-Version nicht. Nur mit Geraet im dunklen Modus zu bemerken.
- **`touch-action` beschraenkt Nachkommen.** `touch-action: none` auf `body`
  verhindert das Scrollen in *allen* Kindelementen, auch wenn diese selbst
  `pan-y` setzen. In Web-Apps gehoert die Sperre auf die Spielflaeche, nicht
  auf `body`, sonst lassen sich eigene Menues auf dem Geraet nicht scrollen.
- **`navigator.vibrate()` braucht `android.permission.VIBRATE`.** Ohne diese
  Berechtigung im Manifest tut die Vibration API in einer Android-WebView
  still gar nichts - kein Fehler in der Konsole, kein Effekt am Geraet, im
  Desktop-Browser aber unauffaellig, weil dort ohnehin nichts vibriert. Das
  Template setzt die Berechtigung deshalb seit IntervalTimer (Sept. 2026)
  fest (nicht ueber `-Online` gesteuert): VIBRATE ist eine "normale"
  Berechtigung ohne Laufzeit-Dialog und ohne Netzwerkbezug, kostet also
  offline-Apps nichts.

- **stderr-Falle in PowerShell 5.1.** PS 5.1 verpackt jede stderr-Zeile eines
  nativen Programms in einen ErrorRecord; bei `$ErrorActionPreference='Stop'`
  wird daraus ein terminierender Fehler - auch bei Exitcode 0. Genau daran ist
  das Setup beim ersten Lauf gescheitert: `sdkmanager` warnt vor seiner eigenen
  Deprecation, und das Skript brach ab, obwohl das Tool sauber durchlief.
  `keytool`, `aapt2`, `adb`, `java -version` und Gradle verhalten sich genauso.
  Deshalb bewerten `Invoke-Native`/`Get-NativeOutput` ausschliesslich den
  Exitcode. `$?` ist hier ebenfalls unbrauchbar.
- **`sdkmanager` luegt beim Exitcode.** Es beendet sich mit 0, auch wenn es
  Pakete stillschweigend uebersprungen hat ("Skipping following packages as the
  license is not accepted"). Der Erfolg wird deshalb auf der Platte geprueft,
  nicht am Exitcode. Dieselbe Vorsicht gilt fuer die Lizenzannahme: dass
  `--licenses` durchlief, heisst nichts - entscheidend ist, ob Dateien in
  `<sdk>\licenses\` liegen.
- **`Start-Process -ArgumentList` quotet nicht.** PS 5.1 fuegt die Liste roh
  mit Leerzeichen zusammen. `--sdk_root=D:\claude code projects\...` zerfaellt
  damit in drei Argumente, das Zielprogramm druckt seine Hilfe und liefert
  Exitcode 1. `Invoke-NativeWithStdinFile` quotet deshalb selbst (inkl.
  Verdoppeln abschliessender Backslashes). Bei `&` tritt das Problem nicht auf.
- **stdin erreicht `sdkmanager.bat` nicht ueber die Pipeline.** PS 5.1 reicht
  gepipte Eingaben nicht zuverlaessig durch den Batch-Wrapper an den
  Java-Prozess weiter; sdkmanager sieht sofort EOF und lehnt still ab. Deshalb
  laeuft die Lizenzannahme ueber `Invoke-NativeWithStdinFile`, das per
  `Start-Process -RedirectStandardInput` ein echtes Datei-Handle anhaengt.
- **`sdkmanager` ist deprecated**, funktioniert aber (v22.0). Nachfolger ist
  `android sdk` aus derselben cmdline-tools-Ausgabe. Bewusst *nicht* migriert:
  die neue `android`-CLI ist ein Bootstrapper, der sich beim ersten Start
  selbst auf die neueste Version nachlaedt, und sendet per Default
  Nutzungsmetriken an Google (`--no-metrics` schaltet das ab). Beides passt
  nicht zu einem Werkzeug, dessen Zweck gepinnte, reproduzierbare Versionen
  sind. Bei einer spaeteren Migration diese beiden Punkte zuerst klaeren.

- Der Projektpfad enthaelt Leerzeichen (`claude code projects`). `setup.ps1`
  testet, ob `sdkmanager` damit klarkommt, und legt sonst automatisch eine
  Junction unter `%LOCALAPPDATA%\apk-builder-sdk` an. Der Pfad steht dann in
  `toolchain\sdk-path.txt` und wird von `env.ps1` bevorzugt.
- Der erste Gradle-Build laedt AGP und Abhaengigkeiten (~1 GB) und dauert
  entsprechend. Alles Weitere kommt aus `toolchain\gradle-home`.
