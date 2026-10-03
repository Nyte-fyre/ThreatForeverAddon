# Findings: threat data on WoW: Forever

Status: **solo and dungeon probes done (2026-10-03).** Still untested: `boss1-5` (no boss fight captured).

## Client

| | |
|---|---|
| Build | 1.60.1.70205 (Oct 2 2026), Interface 16001, `WOW_PROJECT_ID` 18 |
| Secret values | active (`issecretvalue` present, `Combat` restriction true in combat) |
| Combat log | `CombatLogGetCurrentEventInfo` does not exist. No Omen-style estimation. |

## What's readable depends on the unit token

In combat, solo and in a 5-man dungeon (ThreatProbe 0.1-0.2):

| Mob token | Status 0-3 | %, threat value, tanking | Notes |
|---|---|---|---|
| `target` | readable | **readable** | also while not tanking (4-65% seen), and for every `partyN` |
| `focus` | readable | **readable** | also while targeting the tank, and for every `partyN` |
| `nameplateN` | readable | secret (display only) | |
| `targettarget` | secret | secret | the healer case: targeting the tank |
| `party1-4target` | secret | secret | the tank's target is not reachable |
| `mouseover` | secret | secret | |
| `boss1-5` | *untested* | *untested* | |

Secret values can still be **displayed**: `StatusBar:SetValue`, `FontString:SetText` and `SetFormattedText("%d%%")` all accept them.

## Identity in instances

- Open world: mob names and GUIDs readable.
- Dungeon: `UnitName` and `UnitGUID` are **secret**, and `UnitIsUnit(nameplateN, "target")` errors or returns a secret.
- **Workaround that works:** `C_NamePlate.GetNamePlateForUnit("target")` / `("focus")` returns the nameplate frame, and comparing frames finds the matching `nameplateN`: 17/17 target samples and 18/18 focus samples matched. Healer Threat uses this to merge the target/focus row with its nameplate row.

## Other details

- `scaledPercent` hits 100 when you take aggro. It can go above 100 for a non-tank with status 1 (e.g. 227%). While tanking, `rawPercent` reads 255 (a cap).
- `threatValue` is in display units (healer: 10-260 per pull; tank: 100-670).
- `UNIT_THREAT_LIST_UPDATE` / `UNIT_THREAT_SITUATION_UPDATE` fire with readable unit tokens.
- `C_Secrets.ShouldUnitThreat*BeSecret` aren't reliable to gate on. Check each value with `issecretvalue`.
- `C_DamageMeter` has no threat data.

## What this means for a healer

- **Put focus on the main mob** (`/focus`). You get exact % and the early warning while you keep the tank targeted.
- Every other mob with a nameplate shows a bar, and warns once you pass the tank (status 1) or take aggro.
- Without focus or an enemy target, only the nameplate warnings are available.
