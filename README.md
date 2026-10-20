# thumbs-out

A small macOS menu bar app that keeps your Mac awake while AI coding agents are running commands,
like Amphetamine but automatic. Named after the people walking around with half-open MacBooks so
their agents keep running.

What it watches, in three tiers:

| Tier | Entries | Default |
|------|---------|---------|
| **Agents** | Claude Code (CLI, npm, Claude desktop app's Code tab, IDE extensions), ChatGPT / Codex, Antigravity / Gemini CLI, Cursor (app + `cursor-agent`), Windsurf, Kiro, GitHub Copilot CLI, OpenCode, Aider, Goose, Amp, Factory Droid, Qwen Code, Crush | On |
| **Editors & terminals** | VS Code (Copilot, Cline and other extensions), Zed, Warp | Off: every command typed in them counts too |
| **Local models** | Ollama, LM Studio | Off: counted as busy while generating, by CPU use |

The list is a data-driven catalog in `Sources/ThumbsOutCore/Agent.swift`; supporting a new agent is
one entry (process names, app bundle, CLI names). Commands are credited to the innermost agent, so
Claude Code running inside VS Code counts as Claude Code, and an idle agent session sitting in a
terminal doesn't count as a running command.

## How it works

Every few seconds thumbs-out looks at the process tree under each agent:

- **Command shells** (`zsh -c …`, `bash -lc …`) exist only while a command is running. That's how
  Claude Code and Codex run commands.
- **Interactive shells** (Antigravity's terminal) count when they have a child process, meaning a
  command is running in the terminal.
- **MCP servers** and other long-lived helpers (`npx`, `uvx`, anything with `mcp` in its arguments,
  prompt helpers like `gitstatusd`) are skipped so they don't keep the Mac awake forever.

While anything is running, it holds an IOKit `PreventUserIdleSystemSleep` assertion (or
`PreventUserIdleDisplaySleep` if you choose to keep the display on). That's the same mechanism
Amphetamine and `caffeinate` use. After the last command it waits for a **grace period** (5 minutes
by default) so the Mac stays awake while the agent thinks between commands.

## First launch

A five-step welcome window: what thumbs-out does, which agents it found (and whether to watch
each), the grace period, lid-closed mode and launch at login. It shows once; Settings › General ›
**Show Welcome Again…** reopens it.

Agents are found by looking for their apps (`/Applications`, `~/Applications`, and Launch Services
by bundle ID) and command-line tools (`claude`, `codex`, `agy` in `~/.local/bin`, Homebrew,
`/usr/local/bin`, npm, bun and nvm locations). Each agent shows as **Working**, **Running**,
**Installed** or **Not found**. Agents installed later are picked up automatically.

## Menu bar panel

- **Status header**: whether the Mac is being kept awake and why, plus the master switch
- **Time kept awake**: the current stretch, today and the last 7 days
- **Agents**: each agent with its app icon, what it's running, and a status dot (pulses while working)
- **Grace period meter**: snaps to 0m, 1, 2, 5, 10, 15, 20, 30 min, 1h, 2h, 4h; while a grace period
  counts down, the time left shows as an amber bar
- **Stay awake with lid closed**: lid-closed mode switch and what closing the lid would do right now
- **Other apps keeping it awake**: everything else holding a keep-awake lock (same data as
  `pmset -g assertions`), collapsed by default
- **Keep awake manually…**: 15 minutes, 1, 2 or 5 hours, or until you stop it; Settings and Quit

## Lid-closed mode

Power assertions don't survive closing the lid. Apple's docs say the system "may still sleep for
lid close". The only switch that stops lid sleep is the system-wide, root-only `SleepDisabled`
setting (`pmset -a disablesleep 1`).

Lid-closed mode is off by default. Turning it on the first time asks for your admin password once and installs
`/etc/sudoers.d/thumbs-out`. That rule lets your account run exactly two commands without a
password: `pmset -a disablesleep 0` and `pmset -a disablesleep 1`. After that, thumbs-out turns lid
sleep off only while it's keeping the Mac awake, and turns it back on:

- when agents finish and the grace period ends,
- when the battery drops below a threshold (20% by default),
- when you quit,
- within about 5 seconds if the app crashes or is killed (a small watchdog process),
- on the next launch, if a previous run left it off.

It never turns off a `SleepDisabled` that something else turned on. **Remove Lid-Closed Setup…** in Settings
turns lid sleep back on and deletes the rule. A closed MacBook running agents gets warm, so don't
put it in a bag with poor airflow.

## Settings

One scrolling page: **Agents** (found/covered, watch toggles, scan again), **Keeping Awake**
(master switch, grace period meter, display), **Lid Closed** (switch, battery threshold, removal),
**Time Kept Awake** (today, 7 and 30 days, all time, longest stretch, reset), **Detection** (poll
interval, ignored processes) and **General** (launch at login, show welcome again).

Awake time is counted between detection ticks while thumbs-out holds its lock; gaps longer than
about two poll intervals (the Mac slept anyway) aren't counted. Daily totals are kept for 30 days.

## Build and run

Requires macOS 14+ and Xcode (Swift 6).

```bash
./scripts/build-app.sh            # builds build/thumbs-out.app
./scripts/build-app.sh --install  # also copies it to /Applications and launches it
swift test                        # runs the core tests
swift build && .build/debug/ThumbsOut --render-snapshots /tmp/snaps   # PNGs of every screen (debug only)
```

For **Launch at login** to work reliably, install the app to `/Applications` first. macOS may ask
you to approve it under System Settings › General › Login Items.

Check what it's doing:

```bash
pmset -g assertions | grep thumbs-out
pmset -g | grep -i sleepdisabled
```

## Compatibility

| | Status |
|---|---|
| **macOS** | 14 Sonoma or later (both slices are built with `minos 14.0`). Going lower would mean replacing the Observation framework and other macOS 14 APIs; macOS 13 and older no longer get Apple security updates. |
| **Apple Silicon** | Native. Developed and tested on an M4 Pro, macOS 26. |
| **Intel Macs** | Universal binary. All tests pass as Intel code under Rosetta, and the Intel build launches and renders there. Not yet run on real Intel hardware. macOS 26 Tahoe is the last release for Intel Macs. |
| **Rosetta** | If the Intel build runs on Apple Silicon, CPU times from the kernel stay in native ticks while the reported timebase is 1/1; thumbs-out detects translation and corrects for it. |
| **Desktop Macs** (mini, Studio, iMac, Pro) | No lid is detected (no `AppleClamshellState`), so lid-closed mode is hidden everywhere and skipped in onboarding. No battery means no battery threshold. Not yet tested on desktop hardware. |
| **MacBook Air** | Fanless, so it heats up faster with the lid closed. Same heat warning applies. |

Macs that run macOS 14: MacBook Air and MacBook Pro 2018 and later, Mac mini 2018+, iMac 2019+,
iMac Pro, Mac Pro 2019+ and Mac Studio.

## Limitations

- In Antigravity, *any* command running in its integrated terminal counts, including ones you
  started yourself.
- Cloud-only agents (ChatGPT agent mode, Codex cloud tasks) run on remote servers, so there's no
  local process to detect.
- Without lid-closed mode, closing the lid sleeps the Mac unless it's in Apple's clamshell mode
  (power adapter plus external display).

## Project layout

```
Sources/ThumbsOutCore/   pure logic: agent detection, keep-awake and lid policies, sudoers rule (unit-tested)
Sources/ThumbsOut/       menu bar app: libproc, IOKit assertions and power state, lid controller, SwiftUI
Tests/                   Swift Testing suites for the core
scripts/build-app.sh     packages the SwiftPM binary into a signed .app
```
