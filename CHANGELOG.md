# Changelog

Chrome Upkeep 1.0.0 to 1.3.0 were built on game version 2.31; from 1.4.0 the mod is for 2.5. Chrome Clinic started on 2.5. No version of either part has a written in-game test record.

## Chrome Upkeep 1.8.2, Chrome Clinic 1.2.2 - 2026-11-26
### Fixed
- The Chrome Clinic window read the canister count from a script field of the wear system. CET 1.38.1 returns nil for such fields, so "Nanobot canisters" always showed 0. Chrome Upkeep 1.8.2 adds a `NanoCount()` getter; Clinic 1.2.2 uses it, with the raw field as a fallback.

## Chrome Upkeep 1.8.1, Chrome Clinic 1.2.1 - 2026-11-25
### Changed
- The ripper takes components of other qualities, by market value: each quality first uses its own components, then lower qualities (rounded up), then higher ones (whole units only, so nothing is overpaid); the rest is bought at market price. "Repairs use your components" off buys everything, as before.
- Repair time follows the wear: 10 minutes setup per visit, 3 minutes per body system, and per implant 60 minutes x (wear / 100)^2, capped at 16 hours per visit; all times x "Repair time (%)". A nearly intact implant is a short recalibration, a worn-out one a rebuild.
- Clinic window: a row shows that system's own time; the setup is added once in the totals.

## Chrome Upkeep 1.8.0, Chrome Clinic 1.2.0 - 2026-11-25
### Changed
- Nanobot canisters reworked as maintenance swarms: 10,000 eddies list price (follows "Repair price (%)"), up to 5 carried (more from an older save are kept), 60 points of repair per canister, worst system first, up to 60 % (which ends malfunctions), at 20 points per game hour per system. Feedstock is twice the ripper's materials for the same points, by market value, from any quality.
- "Repair price (%)" also scales the number of components the ripper uses, not only the eddies.
### Added
- Setting "Repair time (%)" (25 to 200, default 100) for the repair time in the chair. "Surgery time (%)" still covers only installing and removing implants.
- Clinic window: canister price and carry limit come from the script; a dose shows its duration and says when one canister is not enough.

Compile: 0 errors on 2.5. Not yet play-tested.

## Chrome Upkeep 1.7.2 - 2026-11-23
### Fixed
- The regeneration and buff-duration floors follow other mods' modifiers that come and go (for example Dark Future's hydration effects); before, stamina regeneration could drop below -100 %.
- The arm stamina penalty reaches its full +160 %: the TweakXL file lowers the floor of the three arm stamina-cost stats from -1 to -2.

## Chrome Clinic 1.1.3 - 2026-11-23
### Fixed
- "Hide at this ripper" no longer hides the window at every ripperdoc.
- Leaving a ripperdoc no longer folds the window while it is pinned or the overlay is open.

## Chrome Upkeep 1.7.1 - 2026-11-23
### Fixed
- Worn nervous-system chrome no longer switches off the slow time of Synaptic Accelerator, Reflex Recorder and Grenade Spotter.

## Chrome Upkeep 1.7.0 - 2026-11-22
### Changed
- Graded penalties on all 11 systems: they start below 80 % and grow in 5 % steps. New penalties for optics, circulatory system, immune system, skeleton and hands.
### Added
- Malfunctions from 60 % down, dead systems below 10 %, setting "Penalty strength (%)".

## Chrome Clinic 1.1.2 - 2026-11-22
### Changed
- The window expands when you reach a ripperdoc and folds back when you leave.

## Chrome Clinic 1.1.1 - 2026-11-22
### Removed
- Clinic focus (restoring it expanded every collapsed CET window).

This version's notes were reconstructed after its files had been overwritten.

## Chrome Upkeep 1.6.1 - 2026-11-22
### Fixed
- A ripperdoc repair ends at 100 %, not 99.5 %.

## Chrome Upkeep 1.6.0 and Chrome Clinic 1.1.0 - 2026-11-22
### Changed
- Repairs use the components in your bag first and charge only for the missing ones (setting "Repairs use your components").

## Chrome Upkeep 1.5.0 and Chrome Clinic 1.0.0 - 2026-11-20
### Added
- Repairs priced from parts: materials at market price plus the ripperdoc's fee.
- The Chrome Clinic window for repairs at the ripperdoc.
- Nanobot canisters.
### Removed
- Do-it-yourself field maintenance (replaced by the nanobot canisters).

## Chrome Upkeep 1.4.0 - 2026-11-17
### Changed
- Port to game version 2.5 and Dark Future 3.0.

## Chrome Upkeep 1.3.0 - 2026-11-07
### Added
- "Treat injuries" button in the ripperdoc cyberware screen.

## Chrome Upkeep 1.2.1 - 2026-11-06
### Fixed
- A complication on an implant removal no longer sets the condition of an empty system.
- Loading a save drops an unfinished ripperdoc visit instead of charging it to the loaded save.

## Chrome Upkeep 1.2.0 - 2026-11-06
### Added
- Clinic quality and surgical complications.

## Chrome Upkeep 1.1.0 - 2026-11-06
### Added
- Do-it-yourself field maintenance.
- Worn chrome lengthens cyberware cooldowns and shortens cyberware buffs (stat floors lowered).
### Fixed
- End of a ripperdoc visit.

## Chrome Upkeep 1.0.0 - 2026-11-06
- First version: wear per body system, worn and failing penalties, servicing at a ripperdoc.
