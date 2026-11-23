Das Wartungsscript wurde von mir wärend meiner Umschulung zum Fachinformatiker für Systemintegration geschrieben.
Mit dem Script ohne GUI ist es möglich eine Wartung durchzuführen die Docker, Apt und Snap Aktuallisiert und anschießend 2 Logs per Mail versendet.
Zum einen werden die Orginalen Logs versendet, also das was in der Konsole angezeigt werden würde.
Zum anderen werden die selbst erstellten logs verschickt die auf Lesbarkeit ausgelegt sin.
Da dies mein erstes Bash script ist und ich Linux hauptsächlich aus eingenen Exprimente kenne, decken die Eigenen Logs nicht alle Fehler ab.


#Damit das Script ordnunggemäß funktioniert, müssen die Rechte an den Dateien Angepasst werden


#Dateiinhaber auf root übertragen

sudo chown root:root script.sh

#Nur Root darf die Datei ausführen, lesen und bearbeiten

sudo chmod 700 script.sh
