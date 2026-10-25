# Celah

**There's something living in your notch.**

Celah (Indonesian for *the gap*) turns the MacBook notch into a board for vibe coders. Hover the notch:
- It stretches into a black lip, and a little creature in its chin looks at your cursor.
- A paper tray prints out of the gap with your instruments on it.

▶ **[Watch the 60-second film and download](https://arifinrio95.github.io/celah/)**

```bash
curl -fsSL https://raw.githubusercontent.com/arifinrio95/celah/main/install.sh | bash
```

Or download `Celah.zip` from the [latest release](https://github.com/arifinrio95/celah/releases/latest), unzip, and move `Celah.app` to Applications. Requirements:
- macOS 14 Sonoma or newer.
- Apple silicon.
- A MacBook with a notch. On other displays it sits at the top of the screen.

## What's on the board

| Module | What it does |
|---|---|
| **Keep Awake** | Like Amphetamine, for agents. Options: stay awake, or stay awake **with the lid closed**, so your coding agent keeps running in your bag. Durations are until off, 1, 2 or 4 hours. It turns itself off below 15% battery or when the Mac runs hot. |
| **AI Usage** | Claude and ChatGPT/Codex limits, as jelly bars that fill up, with reset times. Click to open the app. |
| **Qur'an** | One verse at a time (Uthmani script and Indonesian translation). Your place is saved. ⤢ opens **Mushaf Mode**, a big reading window that can go full screen. It has Ayah and Surah modes, all 114 surahs, adjustable script size, and arrow-key navigation. |
| **Prayer times** | Countdown to the next prayer and the day drawn as a sky arc. Calculated locally with Kemenag parameters, for 27 Indonesian cities or GPS. |
| **Tasks** | Projects with Backlog, To Do, In Progress and Done. Tick a task and it moves to the next lane. A full Kanban window is one click away. |
| **Clipboard** | History of text and images. Search, pin, click to copy back. Password-manager items are skipped. |
| **Music** | Spotify and Apple Music. The record slides out of the sleeve and spins while it plays. |
| **Record** | Records a meeting: system audio and your microphone, as two files. Then hand the folder to Claude Code (session pre-filled) or Codex. |
| **System** | CPU, RAM and storage as three rings. **Apps** opens every running app with its CPU and memory, helpers counted in, heaviest first (sort by memory or CPU). It has a two-step **Force Quit**. |
| **Mirror** | The notch is where the camera is, so Celah can be a mirror. A mirrored live view with an optional ring light. The camera runs only while the mirror is open. |

Settings let you:
- Pick which modules sit on the board (the grid re-flows).
- Switch between **Porcelain** (paper under the black notch) and **Ink** (smoked glass).
- Choose a city and set reminders.
- Pick how eagerly the board opens: instantly on hover, after 0.3, 0.6 or 1 second of hover, or only on click.

Nothing is drawn under the camera: buttons and labels stay on either side of the creature.

## Permissions and privacy

Celah runs entirely on your Mac. It has no account, no analytics, and no server of its own.

| Asks for | Why |
|---|---|
| Automation (Spotify, Music) | play, pause, next track |
| Notifications | prayer reminders |
| Location (optional) | prayer times by GPS instead of a city |
| Microphone, Screen & System Audio Recording | only when you press Record |
| Camera | only while the Mirror is open |
| Accessibility (optional) | auto-paste from the clipboard history |
| Administrator password, once | lid-closed Keep Awake. It installs `/etc/sudoers.d/celah-pmset`, which allows exactly `pmset -a disablesleep 0/1`. Delete that file to revoke. |

**AI usage**: Celah reads tokens that are already on your Mac and sends each one only to its own provider:
- Claude Code's sign-in from your Keychain (`Claude Code-credentials`), sent to `api.anthropic.com`.
- Codex's `~/.codex/auth.json`, sent to `chatgpt.com`.

If Claude shows "not signed in", run `claude auth login` once.

The app is ad-hoc signed, not notarized:
- `install.sh` removes the quarantine flag for you.
- If you install by hand and macOS refuses to open it, right-click Celah.app › Open.

## Build from source

```bash
./build.sh --install --run     # release build → ~/Applications/Celah.app, then launch
./build.sh --debug             # quick build into build/Celah.app
./build.sh --zip               # build/Celah.zip for a release
```

You need the Xcode Command Line Tools (`swiftc`). There is no Xcode project: `build.sh` compiles `Sources/**` directly.

CLI flags on a running instance:
- `--pin`: keep the board open.
- `--quran`: Mushaf Mode.
- `--tasks`: Kanban window.
- `--meetings`: recorded meetings.
- `--settings`: settings window.
- `--diag`: prints what every service sees, then exits.

```
Sources/App        app delegate, settings, data hub
Sources/Notch      panel, hover state machine, notch geometry
Sources/UI         Design.swift (tokens, cards), Creature.swift (the face), board, modules, Mushaf Mode
Sources/Services   stats, AI usage, music, prayer, Qur'an, clipboard, tasks, keep awake, recorder
```

## Credits

- Qur'an text (Uthmani) and Indonesian translation from [api.alquran.cloud](https://alquran.cloud).
- Prayer-time math after PrayTimes.org.
- Fonts: Amiri Quran (SIL OFL).
- The film was made in three.js. Its source lives in a separate project.

MIT © Rio Arifin
