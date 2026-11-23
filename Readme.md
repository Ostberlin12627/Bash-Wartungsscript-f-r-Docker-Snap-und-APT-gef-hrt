Die beiden Wartungsskripte wurden von mir während meiner Umschulung zum Fachinformatiker für Systemintegration geschrieben.
Mit der script.sh ohne GUI ist es möglich, eine Wartung durchzuführen, die Docker, APT und Snap aktualisiert und anschließend 2 Logs per Mail versendet.
Zum einen werden die originalen Logs versendet, also das, was in der Konsole angezeigt werden würde.
Zum anderen werden die selbst erstellten Logs verschickt, die auf Lesbarkeit ausgelegt sind.

Da dies mein erstes Bash-Skript ist und ich Linux hauptsächlich aus eigenen Experimenten kenne, decken die eigenen Logs nicht alle Fehler ab.

Das andere Skript, systemscript_mit_Menu.sh, beinhaltet dieselben Funktionen wie das Skript ohne GUI, allerdings ist es notwendig, dass ein Administrator es steuert. Außerdem werden alle Ausgaben auf der Konsole angezeigt und statt der Systemlogs (Konsolenausgabe) gibt es einen Link zu den originalen Logs.
Damit `script.sh` ordnungsgemäß funktioniert, müssen die Rechte an der Datei angepasst werden.

### Dateieigentümer auf root übertragen

`sudo chown root:root script.sh`

### Nur root darf die Datei ausführen, lesen und bearbeiten

`sudo chmod 700 script.sh`

### Menügeführtes Skript

Bei `systemscript_mit_Menu.sh` reicht es aus, die Datei ausführbar zu machen.

`chmod +x systemscript_mit_Menu.sh`
