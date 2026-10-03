# Healer Threat

Warns you before you pull aggro in WoW: Forever. Healer-first: it shows only the mobs you're gaining threat on.

## Install

Copy the `HealerThreat` folder into
`World of Warcraft\_classic_beta_\Interface\AddOns\` (the beta path; the launch path may differ), then `/reload`.
Turn on enemy nameplates (default key `V`). Most of the data comes from them.

## What it can do on this client

| Mob | What you get |
|---|---|
| Your **target** or **focus** | Exact threat %, color by threshold, early warning at your threshold (default 80%) |
| Any other mob with a **nameplate** | Threat bar and %, plus a warning when you pass the tank or take aggro |

**Healer tip:** keep the tank targeted and `/focus` the main mob. Focus gives exact numbers; targeting the tank doesn't (the tank's target is secret).

Warnings: a sound and a red frame flash when a mob's state rises. They're off when solo, because solo you always tank (setting: *Warn when solo*).

## What it can't do

- **No early warning on mobs that aren't your target or focus.** The client keeps their exact % secret from addons. The addon can show that % on the bar but can't compare it to a threshold. For those mobs it warns only once you're past the tank.
- No threat from the combat log (the client doesn't give addons the combat log), and no prediction.
- No full raid threat table: it shows your own threat only.
- `mouseover` threat is secret and not used.

## Settings

`/hthreat` opens Options > AddOns > Healer Threat: enable, sound, flash, warn when solo, full list (for tanks and DPS), hide out of combat, warning threshold, healer-view threshold, max rows, scale, lock/unlock, test rows, reset position.

Commands: `/hthreat on | off | toggle | lock | unlock | test | reset | help`.

## Repo

- `HealerThreat/`: the addon
- `ThreatProbe/`: diagnostic addon (`/tprobe`). Re-run it after patches; see `FINDINGS.md`.
- `tests/smoke.py`: mocked test (`python tests/smoke.py`, needs `lupa`)
