# Findings: threat data on WoW: Forever

Status: **solo probe done (2026-10-03).** Group/dungeon probe still pending; rows marked *pending* need it.

## Client

| | |
|---|---|
| Build | 1.60.1.70205 (Oct 2 2026), Interface 16001, `WOW_PROJECT_ID` 18 |
| Secret values | active (`issecretvalue` present, `Combat` restriction true in combat) |
| Combat log | `CombatLogGetCurrentEventInfo` does not exist. No Omen-style estimation. |

## The key result: secrecy depends on the unit token

Same mob (Ferocious Grizzled Bear), same fight, in combat:

| Mob token | `UnitThreatSituation` (status 0-3) | `UnitDetailedThreatSituation` (tanking, status, %, value) |
|---|---|---|
| `target` | **readable** | **readable**: real numbers, math works (9/9 samples) |
| `nameplateN` | **readable** (19/19) | secret (19/19) |
| `mouseover` | secret | secret |
| `focus`, `bossN` | *pending* (not set in the solo test) | *pending* |
| `targettarget` (mob via a friendly target) | *pending* (no hostile one in the solo test) | *pending* |

Secret values can still be **displayed**: `StatusBar:SetValue`, `FontString:SetText` and `SetFormattedText("%d%%")` all accepted a secret threat percent. They can't be compared, so no addon-side threshold check on them.

## Other details

- Values seen while tanking: `scaledPercent` 100, `rawPercent` **255** (a cap, not a real percent), `threatValue` in display units (0 → 56 → 67 → 186 → 282 over the fight, not Classic's x100 scale).
- `UNIT_THREAT_LIST_UPDATE` (20 fires, 19 in combat) and `UNIT_THREAT_SITUATION_UPDATE` (4) fire, with readable unit tokens (`target`, `nameplate1`, `player`, `targettarget`).
- `GetThreatStatusColor`, `UnitThreatPercentageOfLead`, `C_CurveUtil` exist.
- `C_Secrets.ShouldUnitThreat*BeSecret` aren't reliable to gate on (error for `target`, true for nameplates). Check each returned value with `issecretvalue` instead.
- `C_DamageMeter` has no threat data.
- Blizzard's own threat options are present: `threatWarning` = 3, `threatShowNumeric` = 0 (target-frame threat % is off).

## What this allows

| Data | Use |
|---|---|
| Exact threat % on your **target** | Real meter + warning at a threshold (80-90%), sound |
| Status 0-3 on **every mob with a nameplate** | Per-mob warning list: color-coded, sound when status rises |
| Secret % on nameplate mobs | Can be shown as a bar/text, but cannot trigger a threshold warning |

## Still to verify in a dungeon (with a tank)

- Non-tanking numbers on `target` (is % below 100 readable when you are not tanking?)
- `focus` and `boss1-5` tokens: readable like `target`, or secret like nameplates?
- Healer case: mob reached via `targettarget` while targeting the tank.
- Healing threat across several mobs (nameplate status changing on mobs you never hit).
