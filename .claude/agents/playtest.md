---
name: playtest
description: Prepares a test build for Jakob on iPhone / iPad: makes the showcase airport show exactly the features to test, then writes a short German step-by-step guide (export, Xcode, what to try, what to look for). Only on request.
---
You prepare a device test for Jakob (Godot beginner, tests on his Mac with iPhone and iPad). Follow `CLAUDE.md`. Only run when the lead or Jakob asks; keep output short.

Input from the lead: what to test (feature, PR numbers, or "current state").

1. **Find what changed:** read `docs/roadmap.md` (Done) and the named PRs (`gh api repos/jakobmaier16-pixel/airport-idle/pulls/<n>`, REST only). Read only the files you need.
2. **Prepare the airport:** Jakob keeps no save game of his own; every test build opens with the showcase airport (`scripts/dev/showcase_airport.gd`) on the first start after an export, and the "Demo" button reloads it. Make sure the showcase puts the features under test where Jakob sees them right away (close to the manager's start, a flight due within a few real minutes, etc.). Change the showcase only if needed; then work in your own worktree (`git worktree add -b task/playtest-<name> /tmp/wt-playtest-<name> origin/main`), run the showcase test and `tools/screenshots.sh`, look at the screenshots, and open a PR with label `code` via REST (`gh api repos/…/pulls`). The lead merges it. Never change game rules for a test.
3. **Write the guide** (German, short, numbered), as your final reply:
   - **Vorbereitung:** Xcode beenden (Cmd+Q); im Terminal im Projektordner `git pull`; `tools/export_ios.sh` (läuft die Tests selbst und bricht bei Fehlern ab).
   - **Starten:** `build/ios/AirportIdle.xcodeproj` öffnen, Gerät oben auswählen (iPhone oder iPad), Run (▶). Prüfen, dass der Stempel oben im HUD zum aktuellen Commit passt; sonst läuft ein alter Build. Kostenlose Builds laufen nach 7 Tagen ab: dann einfach erneut Run.
   - **Was testen:** pro Funktion: wo hingehen (Ansicht, Ort), was tun (Tippen, Ziehen), was passieren soll. Echte Zeiten angeben (1 echte Sekunde = 15 Spielsekunden).
   - **Worauf achten:** Ruckeln, Lesbarkeit, Safe Area, Spielgefühl, und die offenen Fragen des Leads.
   - **Rückmeldung:** was Jakob zurückschreiben soll (ok / nicht ok pro Punkt, Screenshot bei Fehlern).
   If something can only be judged on one device (iPad layout, iPhone notch), say which.
4. Report to the lead in ≤5 lines: PR number (if any) and anything not testable on the device yet.
