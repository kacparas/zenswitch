# ZenSwitch

KOReader profiles for a shared jailbroken Kindle. Each person gets their own settings,
reading progress, highlights, history and home folder. Switching takes a few seconds and
doesn't go through the Amazon home screen.

Also included:
- **USB drive mode** from inside KOReader.
- **Lean mode**, which stops the Amazon UI while you're in KOReader to free about 115 MB of memory.

## Requirements
- Kindle on firmware 5.x, jailbroken, with KOReader in `/mnt/us/koreader`.
- Tested on a Paperwhite 5 (FW 5.19.2) with KOReader v2026.07.1.
- zenOS and KUAL are optional. ZenSwitch doesn't include zenOS. If you want the zenOS look,
  install it separately from https://github.com/xZenLabs/zen-os.

## Install
1. Download a zip from [Releases](https://github.com/kacparas/zenswitch/releases/latest):
   **ZenSwitch** on its own, or **ZenSwitch + zenOS**, which also includes zenOS (it
   updates itself from About → Updates). Unzip it. Plug in the Kindle and copy the three
   folders to the root of the Kindle drive. Let them merge with the existing folders. When
   you're done, the drive has these:
   - `zenswitch/`
   - `documents/ZenSwitch Setup.sh`
   - `koreader/plugins/zenswitch.koplugin/`

   Then eject the Kindle.
2. In the Kindle library, tap **ZenSwitch Setup**. Your current KOReader becomes the user
   **Main**, and a **Main** launcher appears in the library.
3. Open **Main** and go to **Tools → Profiles (ZenSwitch)**. Rename Main, and add the other users.

## Use
Everything is in **Tools → Profiles (ZenSwitch)**:

- **Switch to …**: restarts KOReader as the other user. You can also bind *Switch to next
  profile* to a gesture.
- **Add user…**: choose *Start fresh*, or *Copy my current settings* to copy the look
  without the reading data. The new user gets the following:
  - a data folder in `/mnt/us/zenswitch/profiles/<Name>/`
  - a home folder `/mnt/us/<Name>/`
  - a launcher in the library
- **Rename / Remove a user…**: removing moves the user's data folder and launcher to
  `/mnt/us/zenswitch/removed/`. Books are never deleted.
- **USB drive mode**: closes KOReader and shares the drive. KOReader reopens after you
  eject and unplug, or after 60 s if no cable is connected.
- **Lean mode**: a toggle that takes effect the next time you open a profile from the
  library. It stops the Amazon UI and its content services instead of pausing them. The
  trade-off is that going back to the Kindle home screen takes about a minute instead of
  being instant.

With zenOS, you can add launcher tiles for *Switch to next profile*, *ZenSwitch users*
and *USB drive mode*.

## How it works
`zenswitch/zenswitch.sh` is a trimmed copy of KOReader's `platform/kindle/koreader.sh`
with a restart loop added. To switch, the plugin writes the next profile's name to
`/var/tmp/zenswitch.next` and restarts KOReader. The launcher then starts the new profile
with its own `KO_HOME`. All profiles share one KOReader install. `profiles.conf`
(see `profiles.conf.example`) also supports one full KOReader copy per profile.

## Uninstall
Delete these:
- `/mnt/us/zenswitch/`
- the profile launchers in `/mnt/us/documents/`
- `/mnt/us/koreader/plugins/zenswitch.koplugin/`

Nothing on the system partition is changed.

## Limits
- Kindle FW 5.x only.
- Switching restarts KOReader, which takes a few seconds.
- Only KOReader is profile-aware. The Kindle's own reader and Amazon sync are not.

## License
AGPL-3.0, like KOReader. `zenswitch.sh` is derived from KOReader's `koreader.sh`
(© the KOReader contributors, https://github.com/koreader/koreader).
