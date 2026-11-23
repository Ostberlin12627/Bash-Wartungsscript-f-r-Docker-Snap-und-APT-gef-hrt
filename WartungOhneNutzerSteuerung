#!/bin/bash
#Script muss als root ausgeführt werden, 
#damit eine Wartung Ordnungsgemäß funktioniert.
#sudo chown root:root script.sh
#sudo chmod 700 script.sh

export DEBIAN_FRONTEND=noninteractive

#Festlegung der Speicherorte für temporäre Dateien.
tempupdate=$(mktemp)
tempupgrade=$(mktemp)
tempsnap=$(mktemp)
tempsnapfehler=$(mktemp)
tempdockeralt=$(mktemp)
tempdockerneu=$(mktemp)
datum=$(date +"%Y-%m-%d_%H-%M-%S")
trap 'rm -f "$tempupdate" "$tempupgrade" "$tempsnap" "$tempsnapfehler" "$tempdockeralt" "$tempdockerneu"' EXIT

# Bei Übernahme auf andere Systeme Speicherort prüfen und anpassen.
pfad="/var/scripte/Logs"

# Compose-Dateien als absolute Pfade eintragen, eine pro Zeile.
dockerpfade=(
     "/opt/docker/compose.yaml"
)

systemlog="$pfad/systemlogs${datum}.log"
pfadlog="$pfad/logs${datum}.log"

if [[ "$EUID" -ne 0 ]]; then
    echo "Systemakuallisierung wurde, auf grund fehlender Rechte nicht durchgeführt!"
    exit 1
fi

if ! touch "$pfadlog" "$systemlog"; then
    echo "Logdateien unter $pfad konnten nicht vorbereitet werden." >&2
    exit 1
fi

function ueberschrift () {
    local ueberschrift="$1"
    echo ""
    local trennzeichen="======================================================================================================"
    echo "$trennzeichen"
    echo "========================================== $ueberschrift =========================================="
    echo "$trennzeichen"
    echo ""
}

function systemaktualisierung () {
    local apt_locale phase status=0
    local paketmuster='^(Entpacken von|Unpacking) ([^[:space:]]+) \(([^)]+)\)( (über|over) \(([^)]+)\))?'
    local zeile pakete=0

    apt_locale=$(locale -a 2>/dev/null | grep -im1 '^de_DE\.utf-\?8$') || apt_locale=C

    if ! { : > "$tempupdate" && : > "$tempupgrade"; }; then
        echo "Temporäre APT-Logs konnten nicht vorbereitet werden." >&2
        return 1
    fi

    phase="apt-get update"
    if LC_ALL="$apt_locale" LANGUAGE=de apt-get update --error-on=any \
        > "$tempupdate" 2>&1 </dev/null; then
        phase="apt-get upgrade"
        LC_ALL="$apt_locale" LANGUAGE=de apt-get upgrade -y \
            -o Dpkg::Options::="--force-confdef" \
            -o Dpkg::Options::="--force-confold" \
            > "$tempupgrade" 2>&1 </dev/null || status=$?
    else
        status=$?
    fi

    if ! {
        ueberschrift "apt-get update" && cat "$tempupdate" &&
        if [[ "$phase" == "apt-get upgrade" ]]; then
            ueberschrift "$phase" && cat "$tempupgrade"
        fi
    } >> "$systemlog"; then
        echo "APT-Ausgabe konnte nicht in $systemlog geschrieben werden." >&2
        return 1
    fi

    if ! (
        ueberschrift "Systemaktualisierung" || exit 1
        if (( status != 0 )); then
            printf '%s fehlgeschlagen (Exit-Code %d). Details in %s.\n' \
                "$phase" "$status" "$systemlog"
        else
            while IFS= read -r zeile || [[ -n "$zeile" ]]; do
                if [[ "$zeile" =~ $paketmuster ]]; then
                    if (( pakete == 0 )); then
                        printf '%-40s | %-40s | %s\n' \
                            "Paketname" "Alte Version" "Neue Version" || exit 1
                        pakete=1
                    fi
                    printf '%-40s | %-40s | %s\n' \
                        "${BASH_REMATCH[2]}" "${BASH_REMATCH[6]:-–}" "${BASH_REMATCH[3]}" || exit 1
                fi
            done < "$tempupgrade"
            if (( pakete == 0 )); then
                printf 'APT-Upgrade erfolgreich. Keine Entpackmeldungen erfasst.\n' || exit 1
            fi
        fi
    ) >> "$pfadlog"; then
        echo "Zusammenfassung konnte nicht in $pfadlog geschrieben werden." >&2
        return 1
    fi

    (( status == 0 ))
}

function snapaktuellisierung () {
    local snap_locale alt neu phase status=0

    if ! command -v snap >/dev/null 2>&1; then
        printf 'Snap übersprungen. Der Befehl snap ist nicht verfügbar.\n' >> "$pfadlog"
        return $?
    fi

    [[ -n "$tempsnap" && -n "$tempsnapfehler" ]] || return 1
    : > "$tempsnap" && : > "$tempsnapfehler" || return 1
    snap_locale=$(locale -a 2>/dev/null | grep -im1 '^de_DE\.utf-\?8$') || snap_locale=C

    phase="snap list vor der Aktualisierung"
    if alt=$(LC_ALL=C snap list 2>> "$tempsnapfehler" </dev/null); then
        phase="snap refresh"
        if LC_ALL="$snap_locale" LANGUAGE=de snap refresh \
            > "$tempsnap" 2>> "$tempsnapfehler" </dev/null; then
            phase="snap list nach der Aktualisierung"
            neu=$(LC_ALL=C snap list 2>> "$tempsnapfehler" </dev/null) || status=$?
        else
            status=$?
        fi
    else
        status=$?
    fi

    if ! {
        ueberschrift "Snap-Aktualisierung" &&
        printf 'Vorher\n%s\n' "$alt" &&
        cat "$tempsnap" "$tempsnapfehler" &&
        printf 'Nachher\n%s\n' "$neu"
    } >> "$systemlog"; then
        echo "Snap-Ausgabe konnte nicht in $systemlog geschrieben werden." >&2
        return 1
    fi

    if ! {
        ueberschrift "Snap-Aktualisierung" &&
        if (( status != 0 )); then
            printf '%s fehlgeschlagen (Exit-Code %d). Details in %s.\n' \
                "$phase" "$status" "$systemlog"
        else
            printf '%-25s | %-35s | %-35s | %s\n' \
                "Paketname" "Alte Version" "Neue Version" "Herausgeber" &&
            awk '
                FNR == 1 { next }
                NR == FNR { alt[$1] = $2; next }
                $1 in alt { printf "%-25s | %-35s | %-35s | %s\n", $1, alt[$1], $2, $5 }
            ' <(printf '%s\n' "$alt") <(printf '%s\n' "$neu")
        fi
    } >> "$pfadlog"; then
        echo "Snap-Zusammenfassung konnte nicht in $pfadlog geschrieben werden." >&2
        return 1
    fi

    (( status == 0 ))
}

# Erfasst alle lokalen Docker-Images einschließlich Images ohne Tag.
# Pro Zeile werden Name, OCI-Version (falls vorhanden) und Image-ID gespeichert.
function dockerimages_erfassen () {
    local ziel="$1" liste name image_id version
    : > "$ziel" || return 1

    liste=$(docker image ls --no-trunc --format '{{.Repository}}:{{.Tag}}|{{.ID}}') || return 1
    while IFS='|' read -r name image_id; do
        [[ -n "$image_id" ]] || continue
        # Images ohne Repository/Tag über die eindeutige ID unterscheiden.
        if [[ "$name" == '<none>:<none>' ]]; then
            name="<ohne-tag>@${image_id#sha256:}"
        fi
        version=$(docker image inspect \
            --format '{{index .Config.Labels "org.opencontainers.image.version"}}' \
            "$image_id" 2>/dev/null) || return 1
        if [[ -z "$version" || "$version" == '<no value>' ]]; then
            version='Nicht ermittelbar'
        fi
        printf '%s\t%s\t%s\n' "$name" "$version" "$image_id" >> "$ziel" || return 1
    done <<< "$liste"
}

# Vergleicht die beiden Bestandsaufnahmen nach Imagename und Image-ID.
# Eine geänderte ID bedeutet nicht zwangsläufig eine neue Softwareversion.
function dockerimages_vergleichen () {
    local alte_datei="$1" neue_datei="$2"
    local name version image_id zustand
    local -A alte_version=() alte_id=() neue_version=() neue_id=()

    while IFS=$'\t' read -r name version image_id; do
        [[ -n "$name" ]] || continue
        alte_version["$name"]="$version"
        alte_id["$name"]="$image_id"
    done < "$alte_datei"
    while IFS=$'\t' read -r name version image_id; do
        [[ -n "$name" ]] || continue
        neue_version["$name"]="$version"
        neue_id["$name"]="$image_id"
    done < "$neue_datei"

    ueberschrift 'Docker-Image-Vergleich'
    printf '%-40s | %-22s | %-22s | %s\n' \
        'Imagename' 'Alte Version' 'Neue Version' 'Status'

    # Sortierung sorgt für eine übersichtliche und reproduzierbare Tabelle.
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        if [[ -z "${neue_id[$name]+vorhanden}" ]]; then
            zustand='Entfernt'
            printf '%-40s | %-22s | %-22s | %s\n' \
                "$name" "${alte_version[$name]}" '-' "$zustand"
        elif [[ "${alte_id[$name]}" == "${neue_id[$name]}" ]]; then
            zustand='Unverändert'
            printf '%-40s | %-22s | %-22s | %s\n' \
                "$name" "${alte_version[$name]}" "${neue_version[$name]}" "$zustand"
        else
            zustand='Image-ID geändert'
            printf '%-40s | %-22s | %-22s | %s\n' \
                "$name" "${alte_version[$name]}" "${neue_version[$name]}" "$zustand"
        fi
    done < <(printf '%s\n' "${!alte_id[@]}" | LC_ALL=C sort)

    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        if [[ -z "${alte_id[$name]+vorhanden}" ]]; then
            printf '%-40s | %-22s | %-22s | %s\n' \
                "$name" '-' "${neue_version[$name]}" 'Neu'
        fi
    done < <(printf '%s\n' "${!neue_id[@]}" | LC_ALL=C sort)
}

function dockerupdate () {
    local dockerpfad="$1" schritt status=0

    if [[ ! -f "$dockerpfad" || ! -r "$dockerpfad" ]]; then
        printf 'Docker-Compose-Datei nicht lesbar: %s\n' "$dockerpfad" >> "$pfadlog"
        return 1
    fi

    if ! (
        ueberschrift "Docker-Aktualisierung" || exit 1
        printf 'Compose-Datei: %s\n' "$dockerpfad" || exit 1
        for schritt in stop pull build up; do
            printf '\nDocker Compose: %s\n' "$schritt" || exit 1
            case "$schritt" in
                pull)  docker compose -f "$dockerpfad" pull --ignore-buildable ;;
                build) docker compose -f "$dockerpfad" build --no-cache --pull ;;
                up)    docker compose -f "$dockerpfad" up -d --force-recreate ;;
                *)     docker compose -f "$dockerpfad" "$schritt" ;;
            esac || exit "$?"
        done
    ) >> "$systemlog" 2>&1 </dev/null; then
        status=1
    fi

    if ! {
        ueberschrift "Docker-Aktualisierung" &&
        if (( status == 0 )); then
            printf 'Docker Compose wurde aktualisiert: %s\n' "$dockerpfad"
        else
            printf 'Docker-Aktualisierung fehlgeschlagen: %s. Details in %s.\n' \
                "$dockerpfad" "$systemlog"
        fi
    } >> "$pfadlog"; then
        echo "Docker-Zusammenfassung konnte nicht in $pfadlog geschrieben werden." >&2
        return 1
    fi

    return "$status"
}

ergebnis=0
systemaktualisierung || ergebnis=1
snapaktuellisierung || ergebnis=1

if (( ${#dockerpfade[@]} == 0 )); then
    printf 'Docker übersprungen. Keine Compose-Datei eingetragen.\n' >> "$pfadlog" || ergebnis=1
else
    # Gesamten lokalen Imagebestand erfassen, nicht nur Compose-Images.
    if dockerimages_erfassen "$tempdockeralt"; then
        printf '\nDocker-Images vor der Wartung (Name / Version / Image-ID):\n' >> "$systemlog"
        cat "$tempdockeralt" >> "$systemlog" || ergebnis=1
    else
        printf 'Docker-Image-Bestand vor der Wartung nicht lesbar.\n' >> "$pfadlog"
        ergebnis=1
    fi

    for dockerpfad in "${dockerpfade[@]}"; do
        dockerupdate "$dockerpfad" || ergebnis=1
    done

    if dockerimages_erfassen "$tempdockerneu"; then
        printf '\nDocker-Images nach der Wartung (Name / Version / Image-ID):\n' >> "$systemlog"
        cat "$tempdockerneu" >> "$systemlog" || ergebnis=1
        if [[ -s "$tempdockeralt" ]]; then
            dockerimages_vergleichen "$tempdockeralt" "$tempdockerneu" >> "$pfadlog" || ergebnis=1
        else
            printf 'Docker-Image-Vergleich nicht möglich: Ausgangsbestand fehlt oder war leer.\n' >> "$pfadlog"
            ergebnis=1
        fi
    else
        printf 'Docker-Image-Bestand nach der Wartung nicht lesbar.\n' >> "$pfadlog"
        ergebnis=1
    fi
fi

if [[ -f "$systemlog" && -f "$pfadlog" ]]; then

    if ! echo "Wartungsprotokolle vom Testnotebook" | \
        mutt -s "Systemwartung $datum" \
        -a "$systemlog" "$pfadlog" \
        -- admin@test.local; then
        echo "Fehler: E-Mail-Versand fehlgeschlagen." >&2
        ergebnis=1
    fi
else
    echo "Fehler: Mindestens eine Logdatei fehlt." >&2
    ergebnis=1
fi
exit "$ergebnis"
