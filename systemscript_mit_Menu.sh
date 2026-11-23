#!/bin/bash

#####################################################################################################################
#
# Titel: SystemWartung
# Autor: David Würzberg
# Datum: 04.11.2026
#
#####################################################################################################################

echo "Für dieses Programm sind Administrative Rechte notwendig"
sudo -v

#Festlegung der Speicherorte für temporäre Dateien.
tempupdate=$(mktemp)
tempupgrade=$(mktemp)
tempsnap=$(mktemp)
tempsnapfehler=$(mktemp)

#Löscht die temporären Dateien erst beim Beenden des Programms (auch bei Abbruch mit Strg + C).
#Bis dahin bleiben sie erhalten und werden bei jedem Durchlauf überschrieben.
trap 'rm -f "$tempupdate" "$tempupgrade" "$tempsnap" "$tempsnapfehler"' EXIT

#Speicherort der Logdatei. Bei einem anderen Benutzer oder System muss der Pfad angepasst werden.
#Die Logdatei wird beim Programmstart angelegt, falls sie noch nicht existiert.
#Außerdem wird ein Fehler ausgegeben, wenn nicht ausreichend Schreibrechte vorhanden sind.
pfadlog="/home/rayano/logs.log"

#Speicherort der Datei mit den Sprüchen für die Wartezeit. Sie liegt im selben Ordner wie das Script.
#Fehlt die Datei oder ist sie leer, wird stattdessen ein Standardtext angezeigt.
pfadsprueche="$(dirname "$0")/sprueche.txt"

#Erstellt eine Liste von Sprüchen, um die Wartezeit zu überbrücken.
function ladebalken() {
spruecheliste=()
if [[ -s "$pfadsprueche" ]] && [[ -f "$pfadsprueche" ]]; then
	mapfile -t spruecheliste < <(shuf -n 20 "$pfadsprueche")
else
	for (( i=0; i<20; i++ )); do
		spruecheliste+=("Please hold the line ...")
	done
	   
fi
maxindex=$((${#spruecheliste[@]} -1))
verwendete_indexe=()
}

#Prüft, ob der Prozess noch läuft. Die Ausgaben gehen mit >&2 auf die Konsole und nicht ins Log.
function processstatus () { 

if kill -0 "$1" 2>/dev/null; then
	zufallsspruch "$maxindex"
	return 1
else
	echo "Der Prozess ist beendet" >&2
	return 0
fi
}

#Wählt einen zufälligen Spruch aus und vermeidet Redundanzen.
function zufallsspruch () {
sleep 5
indexauswahl=$(shuf -i 0-"$1" -n 1)
    if [[ "${#verwendete_indexe[@]}" -eq 0 ]]; then
	echo "" >&2
    else
	for index in "${verwendete_indexe[@]}"; do
		if [[ "$index" == "$indexauswahl" ]]; then
		echo "Ich arbeite noch!" >&2
		return

		fi
	done
fi

verwendete_indexe+=("$indexauswahl")
echo "${spruecheliste[$indexauswahl]}" >&2
}

touch "$pfadlog" || {
    echo "Fehler: Die Logdatei kann nicht angelegt werden: $pfadlog" >&2
    echo "Bitte Schreibrechte prüfen oder den Pfad im Script anpassen." >&2
    exit 1
}

#Schreibt eine Leerzeile, das aktuelle Datum und eine Leerzeile an den Anfang eines neuen Logeintrags.
function logkopf () {
    echo ""
    date
    echo ""
}

#Liest die Version eines Images aus dem Label "org.opencontainers.image.version".
#Parameter 1 ($1): Imagename. Fehlt das Label, wird "Nicht ermittelbar" ausgegeben.
function imageversion () {
    local version

    version=$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' "$1" 2>/dev/null)

    if [[ -z "$version" || "$version" == "<no value>" ]]; then
        version="Nicht ermittelbar"
    fi

    echo "$version"
}

#Liest den Hashwert (die eindeutige ID) eines Images aus.
#Ändert sich der Hashwert, wurde das Image durch eine neuere Version ersetzt.
#Parameter 1 ($1): Imagename.
function imagehash () {
    local hash

    hash=$(docker image inspect --format '{{.Id}}' "$1" 2>/dev/null)

    if [[ -z "$hash" ]]; then
        hash="Nicht ermittelbar"
    fi

    echo "$hash"
}


#Aktualisiert die Images einer Docker-Compose-Datei und gibt eine Tabelle mit alten und neuen Versionen aus.
#Parameter 1 ($1): Vollständiger Pfad zur Compose-Datei, z. B. /opt/docker/compose.yaml
#Parameter 2 ($2): Art der Aktualisierung (1 = normal mit Cache, 2 = vollständig ohne Cache)
#Hinweis: Eine Fehlerbehandlung für die Docker-Befehle ist noch nicht vorhanden.
#Schlägt ein Schritt fehl, läuft die Funktion weiter, und die Tabelle zeigt dann "Unverändert".
function dockerwartung () {

    #Variablen, die nur in dieser Funktion gelten.
    local i dockerpfad imagename imageAversion imageAhash imageNhashs imageNversion
    local imageA Ahash imageN Nhash status

    #Prüft, ob die Compose-Datei existiert, damit nicht alle Docker-Befehle einzeln scheitern.
    if [[ ! -f "$1" ]]; then
        echo "Fehler: Die Datei wurde nicht gefunden: $1" >&2
        echo "Bitte den vollständigen Pfad angeben, z. B. /opt/docker/compose.yaml" >&2
        return 1
    fi

    #Ordner der Compose-Datei ermitteln.
    dockerpfad=$(dirname "$1")

    #Speichert die Imagenamen, die verwendet werden.
    mapfile -t imagename < <(docker image ls --format '{{.Repository}}:{{.Tag}}')

    #Speichert die alten Versionen.
    mapfile -t imageAversion < <(
        for imageA in "${imagename[@]}"; do
            imageversion "$imageA"
        done
    )

    #Speichert die alten Hashwerte.
    mapfile -t imageAhash < <(
        for Ahash in "${imagename[@]}"; do
            imagehash "$Ahash"
        done
    )

    #Wechselt in den Ordner der Compose-Datei. Existiert er nicht, wird die Funktion beendet.
    cd "$dockerpfad" || {
        echo "Fehler: Der Ordner konnte nicht geöffnet werden: $dockerpfad" >&2
        return 1
    }

    #Die Ausgaben der Docker-Befehle erscheinen über >&2 auf der Konsole und nicht im Log.
    case "$2" in
        #Normale Aktualisierung (mit Cache)
        1)
            docker compose -f "$1" stop >&2
            docker compose -f "$1" pull >&2
            docker compose -f "$1" build --pull >&2
            docker compose -f "$1" up -d >&2
            ;;
        #Vollständige Aktualisierung (ohne Cache)
        2)
            docker compose -f "$1" stop >&2
            docker compose -f "$1" pull >&2
            docker compose -f "$1" build --no-cache --pull >&2
            docker compose -f "$1" up -d --force-recreate >&2
            ;;

        *)
            echo "Fehlerhafte Eingabe, keine Aktualisierung durchgeführt. Bitte 1 oder 2 eingeben." >&2
            return 1
            ;;
    esac

    #Speichert die neuen Hashwerte.
    mapfile -t imageNhashs < <(
        for Nhash in "${imagename[@]}"; do
            imagehash "$Nhash"
        done
    )

    #Speichert die neuen Imageversionen.
    mapfile -t imageNversion < <(
        for imageN in "${imagename[@]}"; do
            imageversion "$imageN"
        done
    )

    #Tabelle aufbauen und zusammenführen.
    printf "%-40s | %-30s | %-30s | %s\n" \
        "Imagename" "Alte Version" "Neue Version" "Veränderung erkannt"
    echo "============================================================================================================================"

    i=0
    while (( i < ${#imagename[@]} )); do

        if [[ "${imageAhash[i]}" == "${imageNhashs[i]}" ]]; then
            status="Unverändert"
        else
            status="Geändert"
        fi
        printf "%-40s | %-30s | %-30s | %s\n" \
            "${imagename[i]}" "${imageAversion[i]}" "${imageNversion[i]}" "$status"

        ((i+=1))
    done
}

#Gibt eine Überschrift zwischen zwei Trennlinien aus.
function ueberschrift () {

    local ueberschrift="$1"
    echo ""
    local trennzeichen="======================================================================================================"
    echo "$trennzeichen"
    echo "========================================== $ueberschrift =========================================="
    echo "$trennzeichen"
    echo ""
}

#Aktualisiert die APT-Paketlisten und installierten Pakete und gibt eine Auswertung aus.
#Rückgabewert: 0 = erfolgreich, 1 = Fehler.
function systemaktualisierung () {

    #Variablen, die nur in dieser Funktion gelten.
    local pakete fehlerliste index paket2 paketname neueversion1 neueversion alteversion1 alteversion anfang fehler ergebnis

    #Ergebnis der Funktion: 0 = erfolgreich, 1 = Fehler.
    ergebnis=0

    #Aktualisiert die Paketlisten. Die Ausgabe wird live auf der Konsole angezeigt (>&2)
    #und zusätzlich in einer temporären Datei gespeichert, damit sie bei einem Fehler ins Log übernommen werden kann.
    sudo apt-get update --error-on=any 2>&1 | tee "$tempupdate" >&2

    #Bei einer Pipe (|) liefert $? den Status von tee, nicht den von apt-get.
    #${PIPESTATUS[0]} enthält den Status des ersten Befehls der Pipe und muss direkt nach der Pipe gelesen werden.
    if [[ "${PIPESTATUS[0]}" -eq 0 ]]; then

        #Bei erfolgreicher Paketlistenaktualisierung wird das System aktualisiert.
        sudo apt-get upgrade -y 2>&1 | tee "$tempupgrade" >&2

        if [[ "${PIPESTATUS[0]}" -eq 0 ]]; then

            {
                ueberschrift "Systemaktualisierung"
                #Aufbau der Tabelle: %-XXs legt die Mindestbreite in Zeichen fest (linksbündig).
                printf "%-40s | %-40s | %s\n" \
                    "Paketname" "Alte Version" "Neue Version"

                echo "______________________________________________________________________________________________"

                #Speichert alle Zeilen, die mit "Entpacken von" beginnen, in einem Array.
                #grep sucht nach den entsprechenden Zeilen.
                mapfile -t pakete < <(grep '^Entpacken von ' "$tempupgrade")

                #Durchläuft das Array und extrahiert Paketnamen sowie Versionsnummern.
                #Die Werte werden in Variablen gespeichert und anschließend tabellarisch ausgegeben.
                for index in "${pakete[@]}"; do
                    paket2="${index#Entpacken von }"
                    paketname="${paket2%% (*}"
                    neueversion1="${paket2#*(}"
                    neueversion="${neueversion1%%)*}"
                    alteversion1="${neueversion1#*(}"
                    alteversion="${alteversion1%%)*}"

                    printf "%-40s | %-40s | %s\n" \
                        "$paketname" "$alteversion" "$neueversion"

                #Beendet die Schleife
                done

            }

        else
            {
                #Bei fehlgeschlagener Systemaktualisierung wird die ursprüngliche Fehlermeldung ausgegeben.
                ergebnis=1
                ueberschrift "Fehler beim Aktualisieren des Systems"
                cat "$tempupgrade"
            }
        fi

    else
        {
            #Bei fehlgeschlagener Paketlistenaktualisierung wird ein Fehlerbericht erstellt.
            ergebnis=1
            ueberschrift "Fehlerbericht"

            #Aufbau der Tabelle: %-XXs legt die Mindestbreite in Zeichen fest (linksbündig).
            printf "%-70s | %s\n" "Quelle" "Fehlergrund"

            echo "______________________________________________________________________________________________"
            #Speichert alle Zeilen mit passenden APT-Fehlermeldungen in einem Array.
            #Suchparameter "Fehlschlag beim Holen von", [EW] findet Zeilen mit "E:" (Fehler) und "W:" (Warnung).
            mapfile -t fehlerliste < <(grep '^[EW]: Fehlschlag beim Holen von ' "$tempupdate")

            #Durchläuft das Array und extrahiert die benötigten Fehlerinformationen.
            #Die Werte werden in Variablen gespeichert und anschließend tabellarisch ausgegeben.
            for index in "${fehlerliste[@]}"; do
                anfang="${index#*von }"
                fehler="${anfang%%Tem*}"

                printf "%-70s | %s\n" \
                    "$fehler" "Quelle nicht gefunden oder erreichbar"
            done

        }
    fi

    return "$ergebnis"
}

#Aktualisiert die installierten Snap-Pakete und gibt eine Tabelle mit alten und neuen Versionen aus.
#Rückgabewert: 0 = erfolgreich, 1 = Fehler.
function snapaktualisierung () {

    #Variablen, die nur in dieser Funktion gelten.
    local snap snapneu snaps snapse paketname alteversion herausgeber neueversion paketnameneu snap_pid snapstatus

    #Speichert den aktuellen Zustand der installierten Snap-Pakete in einer temporären Datei.
    snap list > "$tempsnap"

    #snap läuft im Hintergrund (&). Die Ausgabe wird in einer temporären Datei gespeichert,
    #damit sie bei einem Fehler ins Log übernommen werden kann.
    #Währenddessen werden Sprüche auf der Konsole angezeigt (siehe processstatus).
    sudo snap refresh > "$tempsnapfehler" 2>&1 &
	snap_pid=$!
	ladebalken
	until processstatus "$snap_pid"; do
		:
	done
	
    #wait liefert den Rückgabewert des Hintergrundprozesses (0 = erfolgreich).
    #Er wird sofort gespeichert, weil $? sonst vom nächsten Befehl überschrieben wird.
    wait "$snap_pid"
    snapstatus=$?

    if [[ "$snapstatus" -ne 0 ]]; then
        #Bei fehlgeschlagener Snap-Aktualisierung wird die ursprüngliche Fehlermeldung protokolliert.
        #Die Funktion wird mit dem Fehlerstatus 1 beendet.
        ueberschrift "Fehler"
        cat "$tempsnapfehler"

        return 1
    fi

    ueberschrift "Snap-Aktualisierung"

    #Aufbau der Tabelle: %-XXs legt die Mindestbreite in Zeichen fest (linksbündig).
    printf "%-34s | %-37s | %-37s | %s\n" \
        "Paketname" "Alte Version" "Neue Version" "Herausgeber"

    echo "_____________________________________________________________________________________________________________________"

    #Speichert die Snap-Paketlisten vor und nach der Aktualisierung in zwei Arrays.
    #awk überspringt mit NR > 1 jeweils die erste Zeile (Tabellenüberschrift).
    #Die zweite Liste enthält die neue Version, der restliche Inhalt ist identisch.
    mapfile -t snap < <(awk 'NR > 1' "$tempsnap")
    mapfile -t snapneu < <(snap list | awk 'NR > 1')

    #Verschachtelte for-Schleifen zum Vergleichen der alten und neuen Snap-Paketlisten.
    #Die äußere Schleife durchläuft die alte Liste, die innere Schleife die neue Liste.
    for snaps in "${snap[@]}"; do

        #Extrahiert Paketname, alte Version und Herausgeber. Beispiel: $1 steht für Spalte 1.
        paketname=$(echo "$snaps" | awk '{print $1}')
        alteversion=$(echo "$snaps" | awk '{print $2}')
        herausgeber=$(echo "$snaps" | awk '{print $5}')

        for snapse in "${snapneu[@]}"; do

            #Extrahiert Paketname und neue Version aus der neuen Liste.
            #$1 und $2 stehen für die jeweiligen Spalten der Paketliste.
            neueversion=$(echo "$snapse" | awk '{print $2}')
            paketnameneu=$(echo "$snapse" | awk '{print $1}')

            #Vergleicht die Paketnamen der alten und neuen Liste.
            #Bei Übereinstimmung werden die Werte anschließend tabellarisch ausgegeben.
            if [[ "$paketname" == "$paketnameneu" ]]; then

                #Gibt die zugeordneten Paketinformationen entsprechend der definierten Tabellenformatierung aus.
                printf "%-34s | %-37s | %-37s | %s\n" \
                    "$paketname" "$alteversion" "$neueversion" "$herausgeber"
            fi
        done
    done
}

#Zeigt wahlweise das selbst erstellte Protokoll oder das originale APT-Protokoll des Systems an.
#Die Funktion läuft in einer Schleife, bis im Menü "Zurück zum Hauptmenü" gewählt wird.
function logs_anzeigen () {

    #Variablen, die nur in dieser Funktion gelten.
    local ologs logauswahl

    #Speicherort des originalen APT-Protokolls.
    ologs="/var/log/apt/history.log"

    while true; do
        echo ""
        echo "Docker-Änderungen werden, soweit möglich, ausschließlich in den eigenen Logs gespeichert."
        echo "Welche Logs sollen angezeigt werden?
                1) Selbst erstellte Logs
                2) Originale Logs
                3) Zurück zum Hauptmenü"
        echo ""

        #Endet die Eingabe (z. B. Strg + D), wird zum Hauptmenü zurückgekehrt, statt endlos zu wiederholen.
        read -r -p "Eingabe: " logauswahl || return 0

        case "${logauswahl,,}" in

            1)
                #Prüft, ob die Logdatei existiert, damit keine technische Fehlermeldung von cat erscheint.
                if [[ -f "$pfadlog" ]]; then
                    cat "$pfadlog"
                else
                    echo "Die Logdatei wurde nicht gefunden: $pfadlog"
                fi
                ;;

            2)
                if [[ -f "$ologs" ]]; then
                    cat "$ologs"
                else
                    echo "Die Logdatei wurde nicht gefunden: $ologs"
                fi
                ;;

            3)
                return 0
                ;;

            *)
                echo "Die Eingabe ist ungültig! Bitte 1, 2 oder 3 eingeben."
                ;;
        esac
    done
}

#Ab hier läuft das eigentliche Programm. Alles davor sind Funktionen, die hier verwendet werden.
#Das Programm läuft, bis es über das Menü beendet wird.
while true; do
    echo ""
    echo "Hinweis:"
    echo "Originale Logs finden sich unter"
    echo "/var/log/apt/history.log"
    echo "Das Passwort für erweiterte Rechte kann angefordert werden"
    echo ""
    echo ""
    echo "Wähle aus dem Menü:
=================================================
1) System aktualisieren
2) Drittanbieter-Software aktualisieren (Snap)
3) Docker aktualisieren
4) Logs auslesen
0) Programm beenden"
    echo ""

    #Nur die angezeigten Menüpunkte können ausgewählt werden.
    #Endet die Eingabe (z. B. Strg + D), wird das Programm beendet, statt endlos zu wiederholen.
    read -r -p "Eingabe " input || exit 0

    #Die Ausgaben der Funktionen werden ins Log umgeleitet.
    #Die Meldungen für die Konsole stehen deshalb hier und nicht in den Funktionen.
    case "${input,,}" in
        "1")
            logkopf >> "$pfadlog"
            echo "System wird aktualisiert"
            if systemaktualisierung >> "$pfadlog"; then
                echo "System wurde aktualisiert, hier die Auswertung:"
            else
                echo "Fehler bei der Systemaktualisierung, hier der Fehlerbericht:"
            fi
            cat "$pfadlog"
            echo "Zurück zum Menü"
            ;;
        "2")
            logkopf >> "$pfadlog"
            echo "Drittanbieter-Software wird aktualisiert"
            if snapaktualisierung >> "$pfadlog"; then
                echo "Snap-Aktualisierung erfolgreich, hier die Auswertung:"
            else
                echo "Fehler bei der Snap-Aktualisierung, hier der Fehlerbericht:"
            fi
            cat "$pfadlog"
            echo "Zurück zum Menü"
            ;;
        "3")
            read -r -p "Wo liegt die Docker yaml/yml Datei? Gib den Pfad mit / an. Beispiel: /opt/docker/compose.yaml " composepfad
            echo "Hinweis: Bei einem vollständigen Neubau werden alle Dockerfile-Build-Schritte"
            echo "ohne Cache ausgeführt und die Basis-Images auf Aktualisierungen geprüft."
            echo ""
            echo "Wie möchtest du die Images aktualisieren?
        1) Normale Aktualisierung (mit Cache)
        2) Vollständige Aktualisierung (ohne Cache)"
            read -r -p "Eingabe " dockerauswahl

            logkopf >> "$pfadlog"
            ueberschrift "Dockeraktualisierung" >> "$pfadlog"

            #Die Tabelle erscheint über tee auf der Konsole und wird gleichzeitig an das Log angehängt.
            dockerwartung "$composepfad" "$dockerauswahl" | tee -a "$pfadlog"

            #PIPESTATUS muss direkt nach der Pipe gelesen werden.
            if [[ "${PIPESTATUS[0]}" -eq 0 ]]; then
                echo "Docker-Aktualisierung abgeschlossen, zurück zum Menü"
            else
                echo "Docker-Aktualisierung nicht durchgeführt, zurück zum Menü"
            fi
            ;;
        "4")
            logs_anzeigen
            ;;
        "0")
            echo ""
            echo "Das Programm wird beendet"
            exit 0
            ;;
        *)
            echo ""
            echo "Die Eingabe ist ungültig. Bitte eine der angezeigten Zahlen eingeben."
            ;;
    esac
done
