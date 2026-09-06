# apk-builder

Baut aus einem Ordner mit HTML/CSS/JS eine installierbare Android-APK -
ohne Android Studio, ohne systemweite Installation, ohne Adminrechte.

Die komplette Toolchain (JDK, Android SDK, Gradle) liegt in `toolchain\`
innerhalb dieses Projekts. Zum Entfernen genuegt es, den Ordner zu loeschen.

## Einmalig einrichten

```powershell
.\setup.ps1
```

Laedt JDK 21 (Temurin), Gradle und die Android SDK command line tools,
prueft jeden Download per SHA-256 und installiert Platform 36 sowie
Build-Tools 36.0.0. Dauer: je nach Leitung 10-20 Minuten, ca. 4 GB.
Der Lauf ist idempotent - abgebrochene Setups einfach erneut starten.

Danach jederzeit pruefbar:

```powershell
.\doctor.ps1
```

## App erzeugen und bauen

```powershell
.\new-app.ps1 -Name Notizen -PackageId com.daniel.notizen -WebRoot C:\web\notizen
.\build-apk.ps1 -App Notizen
```

Die fertige APK landet in `out\`. Ohne `-WebRoot` wird eine Demo-Seite
eingebettet, mit der sich der Build testen laesst.

## Befehle

| Befehl | Zweck |
|---|---|
| `.\setup.ps1` | Toolchain installieren (einmalig) |
| `.\setup.ps1 -Force` | Komponenten neu installieren |
| `.\doctor.ps1` | Installation und Versionen pruefen |
| `.\new-app.ps1 -Name X -PackageId com.y.x` | Projekt aus Template erzeugen |
| `.\new-app.ps1 ... -Online` | App bekommt die INTERNET-Berechtigung |
| `.\build-apk.ps1 -App X` | Debug-APK bauen |
| `.\build-apk.ps1 -App X -Release` | signierte Release-APK bauen |
| `.\build-apk.ps1 -App X -Install` | zusaetzlich per adb aufs Geraet |
| `.\build-apk.ps1 -App X -Clean` | vorher aufraeumen |

## Wie die App gebaut ist

Das Template `templates\webview` ist ein natives Android-Projekt mit einer
einzigen Java-Klasse, die einen WebView auf `assets/www/index.html` zeigt.

Bewusste Entscheidungen:

- **Keine Abhaengigkeiten** - kein androidx, kein Kotlin. Das haelt den Build
  schnell, die APK klein und erspart die Versions-Kompatibilitaetsmatrix.
- **Offline per Default** - ohne `-Online` hat die App keine
  INTERNET-Berechtigung und kann gar nicht nach Hause telefonieren.
- **Externe Links** oeffnen im Browser statt im WebView.
- **Launcher-Icon als Vector Drawable** - keine PNGs, kein Bildwerkzeug noetig.

## Signierung

`-Release` erzeugt beim ersten Mal `keys\release.jks` mit einem zufaelligen
Passwort und legt es in `keys\signing.properties` ab. Beides ist per
`.gitignore` ausgeschlossen.

**Den Ordner `keys\` sichern.** Geht der Keystore verloren, lassen sich
bereits installierte Apps nicht mehr per Update ersetzen.

## Grenzen

- Zielt auf Web-Apps im WebView. Fuer Kamera, Sensoren oder Hintergrunddienste
  braucht es natives Android - dafuer waere ein zweites Template noetig.
- Erzeugt APKs, keine AABs. Fuer den Play Store waere `bundleRelease` zu
  ergaenzen.
- Windows-only (PowerShell).

## Was nicht im Repo landet

`toolchain\`, `keys\`, `out\` und `apps\` sind per `.gitignore` ausgeschlossen.
Generierte Projekte unter `apps\` sind jederzeit mit `new-app.ps1`
reproduzierbar. Wer eine App darueber hinaus weiterentwickelt, gibt ihr nach
Workspace-Konvention einen eigenen Ordner mit eigenem Repo, statt sie hier
liegen zu lassen.
