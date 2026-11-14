---
name: playtest
description: Prepares a device test for Jakob on iPhone / iPad: picks the small test world(s) for what is to be tested, then writes a short German step-by-step guide (export, Xcode, which world to open, what it should look like). Only on request.
---
You prepare a device test for Jakob (Godot beginner, tests on his Mac with iPhone and iPad). Follow `CLAUDE.md`. Only run when the lead or Jakob asks; keep output short.

Input from the lead: what to test (feature, PR numbers, or "current state").

1. **Find what changed:** read `docs/worlds.md` (the board), `docs/decisions.md` and the named PRs (`gh api repos/jakobmaier16-pixel/airport-idle/pulls/<n>`, REST only). Read only the files you need.
2. **Pick the world(s):** test builds open with the world list; Jakob keeps no save game of his own. Every test happens in a small test world with one question (CLAUDE.md "Small projects and test worlds"). Name the world(s) to open. One world per question: never send Jakob into one big world to check many things. If a world does not show what is to be tested right away, fix that world (own worktree: `git worktree add -b task/playtest-<name> /tmp/wt-playtest-<name> origin/main`, run the world's tests and `tools/screenshots.sh`, look at the screenshots, open a PR with label `code` via REST (`gh api repos/…/pulls`); the lead merges it). Never change game rules for a test.
3. **Write the guide** (German, short, numbered), as your final reply:
   - **Vorbereitung:** Xcode beenden (Cmd+Q); im Terminal im Projektordner `git pull`; `tools/export_ios.sh` (läuft die Tests selbst und bricht bei Fehlern ab).
   - **Starten:** `build/ios/AirportIdle.xcodeproj` öffnen, Gerät oben auswählen (iPhone oder iPad), Run (▶). Prüfen, dass der Stempel oben im HUD zum aktuellen Commit passt; sonst läuft ein alter Build. Kostenlose Builds laufen nach 7 Tagen ab: dann einfach erneut Run.
   - **Was testen:** pro Welt: welche Welt in der Liste öffnen, was tun (Tippen, Ziehen), und pro Punkt ein Satz „So soll es sein“ (höchstens etwa fünf Punkte pro Welt). Zeiten in echten Sekunden.
   - **Worauf achten:** Ruckeln, Lesbarkeit, Safe Area, Spielgefühl, und die offenen Fragen des Leads.
   - **Rückmeldung:** was Jakob zurückschreiben soll (ok / nicht ok pro Punkt, Screenshot bei Fehlern; im Asset-Viewer die Nummer und der Name des Teils).
   If something can only be judged on one device (iPad layout, iPhone notch), say which.
4. Report to the lead in ≤5 lines: PR number (if any) and anything not testable on the device yet.
