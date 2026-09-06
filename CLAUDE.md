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
