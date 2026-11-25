#!/bin/sh
#
# ZenSwitch: start one of several KOReader profiles, and hop between them
# without bringing the Amazon UI back up in between.
#
# Usage (normally from a scriptlet in /mnt/us/documents, one per profile; see make-launchers.sh):
#   zenswitch.sh [--kual] [--asap|--framework_stop] <profile name from profiles.conf>
#
# This is a trimmed copy of KOReader's own platform/kindle/koreader.sh (FW 5.x /
# upstart only). The only real change is in the restart loop at the bottom: when
# KOReader restarts (exit code 85) and the zenswitch plugin has written the name of
# another profile to /var/tmp/zenswitch.next, we cd into that profile's folder and
# start its reader.lua instead. The Kindle UI stays paused the whole time.
#
# Nothing here touches the system partition. To uninstall, delete this folder
# and the two scriptlets.

export LC_ALL="en_US.UTF-8"

# Run from a copy in /var/tmp (same vfat+fuse reasons as koreader.sh).
if [ "$(dirname "${0}")" != "/var/tmp" ]; then
    ZS_HOME="$(CDPATH='' cd "$(dirname "$0")" && pwd -P)"
    export ZS_HOME
    cp -pf "${0}" /var/tmp/zenswitch.sh
    chmod 777 /var/tmp/zenswitch.sh
    exec /var/tmp/zenswitch.sh "$@"
fi

# When the Amazon UI is stopped (lean mode), the process that launched us from the
# library goes away and may signal us. Never let that kill the launcher: it is the one
# that has to bring the Amazon UI back at the end.
trap ':' TERM HUP

ZS_CONF="${ZS_HOME}/profiles.conf"
ZS_RUNLOG="${ZS_HOME}/last-run.log"
: >"${ZS_RUNLOG}" 2>/dev/null
ZS_NEXT_FILE="/var/tmp/zenswitch.next"
export ZENSWITCH_CONF="${ZS_CONF}"
export ZENSWITCH_NEXT_FILE="${ZS_NEXT_FILE}"

# profiles.conf, one profile per line:
#   Name|/path/to/koreader                       (own KOReader copy; data lives in it)
#   Name|/path/to/koreader|/path/to/data-folder  (shared KOReader; own data folder via KO_HOME)
# zs_profile_line prints everything after "Name|" for the given name.
zs_profile_line() {
    [ -f "${ZS_CONF}" ] || return 1
    while IFS='|' read -r zs_n zs_d || [ -n "${zs_n}" ]; do
        zs_d="$(echo "${zs_d}" | tr -d '\r')"
        case "${zs_n}" in '' | '#'*) continue ;; esac
        if [ "${zs_n}" = "${1}" ]; then
            echo "${zs_d}"
            return 0
        fi
    done <"${ZS_CONF}"
    return 1
}

# KOReader install folder of a profile
zs_profile_dir() {
    zs_l="$(zs_profile_line "${1}")" || return 1
    echo "${zs_l%%|*}"
}

# Data folder of a profile (empty: the install folder itself holds the data)
zs_profile_home() {
    zs_l="$(zs_profile_line "${1}")" || return 1
    case "${zs_l}" in *'|'*) echo "${zs_l#*|}" ;; *) echo "" ;; esac
}

zs_valid_dir() {
    [ -n "${1}" ] && [ -f "${1}/reader.lua" ] && [ -f "${1}/libkohelper.sh" ]
}

# Make a profile the active one. KOReader runs from its install folder; its settings,
# reading progress, history and caches go to KO_HOME when the profile has a data folder.
zs_use_profile() {
    export ZENSWITCH_PROFILE="${1}"
    export KOREADER_DIR="${2}"
    if [ -n "${3}" ]; then
        # KOReader also loads plugins from $KO_HOME/plugins. Keep it as an (empty) folder:
        # a data folder must not carry its own copies of the installed plugins.
        mkdir -p "${3}/plugins" || return 1
        export KO_HOME="${3}"
    else
        unset KO_HOME
    fi
    ZS_LOGDIR="${KO_HOME:-${KOREADER_DIR}}"
    UNPACK_DIR="${KOREADER_DIR%/*}"
    cd "${KOREADER_DIR}" || return 1
    cp -pf "${KOREADER_DIR}/fbink" /var/tmp/fbink 2>/dev/null
    chmod 777 /var/tmp/fbink 2>/dev/null
    # we keep at most 500KB worth of crash log
    if [ -e "${ZS_LOGDIR}/crash.log" ]; then
        tail -c 500000 "${ZS_LOGDIR}/crash.log" >"${ZS_LOGDIR}/crash.log.new"
        mv -f "${ZS_LOGDIR}/crash.log.new" "${ZS_LOGDIR}/crash.log"
    fi
    return 0
}

if [ "${1}" = "--kual" ]; then
    shift 1
    FROM_KUAL="yes"
else
    FROM_KUAL="no"
    export EIPS_NO_SLEEP="yes"
fi

export STOP_FRAMEWORK="no"
if [ "${1}" = "--framework_stop" ]; then
    shift 1
    STOP_FRAMEWORK="yes"
    NO_SLEEP="no"
elif [ "${1}" = "--asap" ]; then
    shift 1
    NO_SLEEP="yes"
    export EIPS_NO_SLEEP="yes"
else
    NO_SLEEP="no"
fi

# Lean mode: stop the Amazon UI (lab126_gui) for the whole session instead of pausing it.
# Toggled from the plugin (Tools > Profiles > Lean mode); takes effect on the next start.
export ZENSWITCH_LEAN_FILE="${ZS_HOME}/lean"
if [ -f "${ZENSWITCH_LEAN_FILE}" ] && [ "${STOP_FRAMEWORK}" = "no" ]; then
    STOP_FRAMEWORK="yes"
    NO_SLEEP="no"
fi

START_PROFILE="${1}"
[ $# -gt 0 ] && shift 1
START_DIR="$(zs_profile_dir "${START_PROFILE}")"
START_HOME="$(zs_profile_home "${START_PROFILE}")"

# Bail out *before* touching anything if the profile is unknown/broken.
if ! zs_valid_dir "${START_DIR}"; then
    echo "zenswitch: unknown profile '${START_PROFILE}' or no KOReader in '${START_DIR}' (check ${ZS_CONF})"
    for f in /var/tmp/fbink /mnt/us/koreader/fbink; do
        if [ -x "${f}" ]; then
            "${f}" -q -m -y -3 "ZenSwitch: profile '${START_PROFILE}' not found, check /mnt/us/zenswitch/profiles.conf" >/dev/null 2>&1
            break
        fi
    done
    rm -f /var/tmp/zenswitch.sh
    exit 1
fi

zs_use_profile "${START_PROFILE}" "${START_DIR}" "${START_HOME}" || exit 1

PROC_KEYPAD="/proc/keypad"
PROC_FIVEWAY="/proc/fiveway"
[ -e "${PROC_KEYPAD}" ] && echo unlock >"${PROC_KEYPAD}"
[ -e "${PROC_FIVEWAY}" ] && echo unlock >"${PROC_FIVEWAY}"

# shellcheck source=/dev/null
. "${KOREADER_DIR}/libkohelper.sh"

logmsg() {
    if [ "${INIT_TYPE}" = "upstart" ]; then
        f_log I zenswitch wrapper "" "${1}"
    fi
    echo "$(date '+%H:%M:%S') ${1}" >>"${ZS_RUNLOG}" 2>/dev/null
    echo "${1}"
}

if [ "${INIT_TYPE}" != "upstart" ]; then
    logmsg "zenswitch only supports FW 5.x, use the normal KOReader launcher"
    rm -f /var/tmp/zenswitch.sh
    exit 1
fi

export AWESOME_STOPPED="no"
export CVM_STOPPED="no"
export VOLUMD_STOPPED="no"
PILLOW_HARD_DISABLED="no"
PILLOW_SOFT_DISABLED="no"
PASSCODE_DISABLED="no"

TOGGLED_SERVICES="stored webreader kfxreader kfxview todo tmd rcm archive scanner otav3 otaupd"
if [ -f "/etc/upstart/statusbar.conf" ]; then
    TOGGLED_SERVICES="${TOGGLED_SERVICES} statusbar"
fi

if [ "${FROM_KUAL}" = "yes" ]; then
    logmsg "Hush now . . ."
    if [ "${NO_SLEEP}" = "no" ]; then
        usleep 250000
    fi
    if [ "$(nice)" = "5" ]; then
        logmsg "Be nice!"
        renice -n -5 $$
    fi
fi

# Handle a pending KOReader OTA update for the *active* profile.
ko_update_check() {
    # KOReader downloads updates into its data folder (KO_HOME when set)
    NEWUPDATE="${KO_HOME:-${KOREADER_DIR}}/ota/update.tar.xz"
    if [ -f "${NEWUPDATE}" ]; then
        # KOReader's update archive always unpacks into "<parent>/koreader". If this
        # profile's folder is named something else, unpacking would overwrite the
        # *other* profile, so refuse and leave the update file alone.
        if [ "${KOREADER_DIR##*/}" != "koreader" ]; then
            logmsg "Skipping OTA update for ${KOREADER_DIR}: folder is not named 'koreader'"
            eips_print_bottom_centered "Update skipped: folder must be named koreader" 1
            return 0
        fi
        logmsg "Updating KOReader . . ."
        /var/tmp/fbink -c
        eips_print_bottom_centered "Updating KOReader" 3
        cp "${KOREADER_DIR}/ota/package.index" /tmp/
        export FBINK_NAMED_PIPE="/tmp/koreader.fbink"
        rm -f "${FBINK_NAMED_PIPE}"
        FBINK_PID="$(/var/tmp/fbink --daemon 1 %KOREADER% -q -y -6 -P 0)"
        exec 3<>"${FBINK_NAMED_PIPE}"
        cp -pf "${KOREADER_DIR}/unpack" /var/tmp/
        (cd "${UNPACK_DIR}" && /var/tmp/unpack -X "${NEWUPDATE}" >&3)
        fail=$?
        kill -TERM "${FBINK_PID}"
        rm -f /var/tmp/unpack
        if [ "${fail}" -eq 0 ]; then
            (cd "${UNPACK_DIR}" && grep -xvFf "${KOREADER_DIR}/ota/package.index" /tmp/package.index | xargs -r rm -vf)
            logmsg "Update successful :)"
            eips_print_bottom_centered "Update successful :)" 2
            eips_print_bottom_centered "KOReader will start momentarily . . ." 1
        else
            logmsg "Update failed :( (${fail})"
            eips_print_bottom_centered "Update failed :(" 2
            eips_print_bottom_centered "KOReader may fail to function properly" 1
        fi
        rm -f /tmp/package.index "${NEWUPDATE}"
        exec 3>&-
        rm -f "${FBINK_NAMED_PIPE}"
        unset FBINK_NAMED_PIPE FBINK_PID
        sync
        cp -pf "${KOREADER_DIR}/fbink" /var/tmp/fbink 2>/dev/null
    fi
}

export STARDICT_DATA_DIR="data/dict"
export EXT_FONT_DIR="/usr/java/lib/fonts;/mnt/us/fonts;/var/local/font/mnt;/mnt/us/linkfonts/fonts"

logmsg "Setting up IPTables rules . . ."
iptables -A INPUT -i wlan0 -p udp --dport 8134 -j ACCEPT

if [ -f "/var/local/system/userpasswdenabled" ]; then
    logmsg "Disabling system passcode . . ."
    rm -f "/var/local/system/userpasswdenabled"
    PASSCODE_DISABLED="yes"
fi

if [ "${STOP_FRAMEWORK}" = "yes" ]; then
    logmsg "Stopping the framework . . ."
    trap "" TERM
    stop lab126_gui
    usleep 1250000
    trap ':' TERM HUP
    # Amazon cloud/content services that keep running without the UI (download queue,
    # transfer manager, archive/content managers). KOReader does not need them.
    LEAN_STOPPED=""
    for job in todo tmd rcm archive; do
        if status "${job}" 2>/dev/null | grep -q "start/"; then
            stop "${job}" >/dev/null 2>&1 && LEAN_STOPPED="${LEAN_STOPPED} ${job}"
        fi
    done
    logmsg "Lean mode: stopped${LEAN_STOPPED}"
fi

version() { echo "$@" | awk -F. '{ printf("%d%03d%03d\n", $1,$2,$3); }'; }

if [ "${STOP_FRAMEWORK}" = "no" ]; then
    cat /dev/fb0 >/var/tmp/koreader-fb.dump
    FW_VERSION="$(grep '^Kindle 5' /etc/prettyversion.txt 2>&1 | sed -n -r 's/^(Kindle)([[:blank:]]*)([[:digit:]\.]*)(.*?)$/\3/p')"
    if [ "$(version "${FW_VERSION}")" -ge "$(version "5.6.5")" ]; then
        PILLOW_HARD_DISABLED="yes"
        logmsg "Disabling pillow . . ."
        lipc-set-prop com.lab126.pillow disableEnablePillow disable
        if [ "$(version "${FW_VERSION}")" -ge "$(version "5.7.2")" ]; then
            # (koreader.sh only resizes the title bar with wmctrl below FW 5.12.4; a PW5 is always newer.)
            logmsg "Stopping awesome . . ."
            killall -STOP awesome
            AWESOME_STOPPED="yes"
        fi
    else
        logmsg "Hiding the status bar . . ."
        lipc-set-prop com.lab126.pillow interrogatePillow '{"pillowId": "default_status_bar", "function": "nativeBridge.hideMe();"}'
        PILLOW_SOFT_DISABLED="yes"
    fi
    if [ "${NO_SLEEP}" = "no" ] && [ "${AWESOME_STOPPED}" = "no" ]; then
        usleep 250000
        if [ "${FROM_KUAL}" = "yes" ]; then
            usleep 2500000
        fi
    fi
    for job in ${TOGGLED_SERVICES}; do
        stop "${job}"
    done
fi

if [ -e "/etc/upstart/volumd.conf" ]; then
    logmsg "Stopping volumd . . ."
    killall -STOP volumd
    VOLUMD_STOPPED="yes"
fi

# ---- USB drive mode without the Amazon UI ----
# KOReader runs from /mnt/us, so the drive can only be shared with a computer after
# reader.lua has exited. The plugin asks for this by writing "@usb" to the next-file.
# We let volumd (the Kindle's USB/storage daemon, paused while KOReader runs) handle
# one USB session, wait until the computer ejects the drive, then pause volumd again
# and restart the same profile. The Kindle UI stays paused throughout.
zs_mounted() { grep -q ' /mnt/us ' /proc/mounts; }
zs_say() {
    /var/tmp/fbink -q -c >/dev/null 2>&1
    /var/tmp/fbink -q -m -y 12 "${1}" >/dev/null 2>&1
    [ -n "${2}" ] && /var/tmp/fbink -q -m -y 14 "${2}" >/dev/null 2>&1
}
zs_usb_mode() {
    if [ "${VOLUMD_STOPPED}" != "yes" ]; then
        logmsg "USB mode: volumd not managed here, skipping"
        return 0
    fi
    cd / || return 1
    sync
    logmsg "USB mode: resuming volumd"
    zs_say "USB mode: connect the USB cable now" "(already plugged in? unplug and plug it in again)"
    killall -CONT volumd
    zs_i=0
    while zs_mounted && [ "${zs_i}" -lt 120 ]; do
        usleep 500000
        zs_i=$((zs_i + 1))
    done
    if zs_mounted; then
        logmsg "USB mode: no USB connection after 60s"
        zs_say "No computer connected" "Going back to ${ZENSWITCH_PROFILE} . . ."
        killall -STOP volumd
        sleep 2
        cd "${KOREADER_DIR}" || return 1
        return 0
    fi
    logmsg "USB mode: drive shared with computer"
    zs_say "USB drive mode" "Eject the Kindle on your computer to go back to ${ZENSWITCH_PROFILE}"
    while ! zs_mounted; do
        sleep 1
    done
    # Give volumd a moment to finish remounting before we pause it again.
    sleep 3
    killall -STOP volumd
    # The Kindle framework reacts to USB plug-out by bringing back its own UI
    # (status bar, home screen). Give it a moment, then hide it again so the
    # restarted profile isn't covered by the Amazon home screen.
    sleep 3
    if [ "${PILLOW_HARD_DISABLED}" = "yes" ]; then
        lipc-set-prop com.lab126.pillow disableEnablePillow disable
    fi
    if [ "${AWESOME_STOPPED}" = "yes" ]; then
        killall -STOP awesome
    fi
    for job in ${TOGGLED_SERVICES}; do
        stop "${job}" >/dev/null 2>&1
    done
    logmsg "USB mode: drive back, restarting ${ZENSWITCH_PROFILE}"
    zs_say "Starting ${ZENSWITCH_PROFILE} . . ."
    cd "${KOREADER_DIR}" || return 1
    return 0
}

logmsg "Starting KOReader (profile ${ZENSWITCH_PROFILE}) . . ."
if [ "${FROM_KUAL}" = "yes" ]; then
    eips_print_bottom_centered "Starting ${ZENSWITCH_PROFILE} . . ." 1
fi

rm -f "${ZS_NEXT_FILE}"
RETURN_VALUE=85
while [ "${RETURN_VALUE}" -eq 85 ]; do
    # ---- the actual profile switch ----
    if [ -f "${ZS_NEXT_FILE}" ]; then
        NEXT_PROFILE="$(head -n 1 "${ZS_NEXT_FILE}" | tr -d '\r')"
        rm -f "${ZS_NEXT_FILE}"
        NEXT_DIR="$(zs_profile_dir "${NEXT_PROFILE}")"
        NEXT_HOME="$(zs_profile_home "${NEXT_PROFILE}")"
        if [ "${NEXT_PROFILE}" = "@usb" ]; then
            zs_usb_mode || break
        elif zs_valid_dir "${NEXT_DIR}"; then
            logmsg "Switching to profile ${NEXT_PROFILE} (${NEXT_DIR})"
            zs_use_profile "${NEXT_PROFILE}" "${NEXT_DIR}" "${NEXT_HOME}" || break
        else
            logmsg "Can't switch to '${NEXT_PROFILE}' ('${NEXT_DIR}'), restarting current profile"
        fi
    fi

    ko_update_check

    # KOReader compares /var/tmp/koreader.sh with ./koreader.sh on startup and nags
    # for a full exit if they differ. Point it at this profile's own script (it is
    # only hashed, never run, while we're in charge).
    cp -pf "${KOREADER_DIR}/koreader.sh" /var/tmp/koreader.sh 2>/dev/null

    ./reader.lua "$@" >>"${ZS_LOGDIR}/crash.log" 2>&1
    RETURN_VALUE=$?
    # Extra args (e.g. a book path) only apply to the first start.
    set --
done

rm -f "${ZS_NEXT_FILE}"

# ---- teardown: identical to koreader.sh ----
if pidof reader.lua >/dev/null 2>&1; then
    logmsg "Sending a SIGTERM to stray KOreader processes . . ."
    killall -TERM reader.lua
fi

if [ "${VOLUMD_STOPPED}" = "yes" ]; then
    logmsg "Resuming volumd . . ."
    killall -CONT volumd
fi

if [ "${STOP_FRAMEWORK}" = "yes" ]; then
    logmsg "Restarting framework . . ."
    /var/tmp/fbink -q -c >/dev/null 2>&1
    /var/tmp/fbink -q -m -y 12 "Starting Kindle home . . ." >/dev/null 2>&1
    /var/tmp/fbink -q -m -y 14 "(this takes about a minute)" >/dev/null 2>&1
    for job in ${LEAN_STOPPED}; do
        start "${job}" >/dev/null 2>&1
    done
    cd / || true
    start lab126_gui >>"${ZS_RUNLOG}" 2>&1
    # Make sure it really came up (it can take a while, or need a second nudge).
    zs_i=0
    while ! status lab126_gui 2>/dev/null | grep -q "start/running" && [ "${zs_i}" -lt 45 ]; do
        sleep 2
        zs_i=$((zs_i + 1))
        if [ "${zs_i}" -eq 15 ] || [ "${zs_i}" -eq 30 ]; then
            logmsg "lab126_gui not up yet ($(status lab126_gui 2>&1)), starting again"
            start lab126_gui >>"${ZS_RUNLOG}" 2>&1
        fi
    done
    logmsg "Amazon UI: $(status lab126_gui 2>&1)"
    # Bring the home screen to the front once the framework is up.
    sleep 5
    lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home >/dev/null 2>&1
fi

if [ "${STOP_FRAMEWORK}" = "no" ]; then
    for job in ${TOGGLED_SERVICES}; do
        start "${job}"
    done
    if [ "${AWESOME_STOPPED}" = "yes" ]; then
        logmsg "Resuming awesome . . ."
        killall -CONT awesome
    fi
    if [ "${PILLOW_HARD_DISABLED}" = "yes" ]; then
        logmsg "Enabling pillow . . ."
        cat /var/tmp/koreader-fb.dump >/dev/fb0
        rm -f /var/tmp/koreader-fb.dump
        lipc-set-prop com.lab126.pillow disableEnablePillow enable
        lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home
    fi
    if [ "${PILLOW_SOFT_DISABLED}" = "yes" ]; then
        logmsg "Restoring the status bar . . ."
        cat /var/tmp/koreader-fb.dump >/dev/fb0
        rm -f /var/tmp/koreader-fb.dump
        lipc-set-prop com.lab126.pillow interrogatePillow '{"pillowId": "default_status_bar", "function": "nativeBridge.showMe();"}'
        lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home
    fi
fi

logmsg "Restoring IPTables rules . . ."
iptables -D INPUT -i wlan0 -p udp --dport 8134 -j ACCEPT

if [ "${PASSCODE_DISABLED}" = "yes" ]; then
    logmsg "Restoring system passcode . . ."
    touch "/var/local/system/userpasswdenabled"
fi

rm -f /var/tmp/koreader.sh /var/tmp/fbink /var/tmp/zenswitch.sh

exit ${RETURN_VALUE}
