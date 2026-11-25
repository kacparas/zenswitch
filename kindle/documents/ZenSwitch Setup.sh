#!/bin/sh
# Name: ZenSwitch Setup
# Author: ZenSwitch
# DontUseFBInk
#
# One-time setup, tapped from the Kindle library after copying ZenSwitch onto the Kindle.
# Makes your current KOReader the first user ("Main"), creates its launcher, then
# removes this setup entry. Add more users later from KOReader: ZenSwitch users > Add user.
ZS=/mnt/us/zenswitch
say() { for f in /mnt/us/koreader/fbink /var/local/kmc/bin/fbink; do [ -x "$f" ] && { "$f" -q -m -y 10 "$1" >/dev/null 2>&1; return; }; done; eips 1 10 "$1" >/dev/null 2>&1; }
if [ ! -f /mnt/us/koreader/reader.lua ]; then say "ZenSwitch: KOReader not found in /mnt/us/koreader"; exit 1; fi
if [ ! -f "$ZS/zenswitch.sh" ]; then say "ZenSwitch: copy the zenswitch folder to the Kindle first"; exit 1; fi
[ -f "$ZS/profiles.conf" ] || printf '%s\n' "# ZenSwitch users (see profiles.conf.example)" "Main|/mnt/us/koreader" >"$ZS/profiles.conf"
sh "$ZS/make-launchers.sh" >/dev/null 2>&1
rm -f "/mnt/us/documents/ZenSwitch Setup.sh"
say "ZenSwitch ready: open 'Main' in your library"
