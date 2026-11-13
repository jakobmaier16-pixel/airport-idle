# Master Plan — Building the App Professionally

> Status: Draft v1 · 2026-11-06
> Purpose: how we get from the proof of concept (POC) to a releasable App Store app. This is about *process and order*. The game itself is described in `game_design.md`.

---

## 1. Where we are

- A working **POC** exists: it runs on a real phone and many mechanics already work (airlines, loans, weather, tiers, …).
- We are roughly **1% of the way** to a finished game. The POC proved that the idea can be built. It is not the foundation of the final app.
- The design direction is now clear (see `game_design.md`): *the airport is the game; idle supports it.*

**The main risk of the next phase is adding more small features to the POC.** The professional approach is the opposite: stop adding, decide, build a solid foundation, then add features in a controlled order.

---

## 2. Principles

1. **Decide big things first, details later.** Details that are not needed now go in the parking lot (§8).
2. **Foundation before features.** Architecture, saving and performance are cheap to get right early and very expensive to fix late.
3. **Prove it in a vertical slice.** Before building all content, build a small, polished piece of the real game and test whether it is fun.
4. **Small, finished steps.** Every task ends with something that runs, is tested and is saved in version control.
5. **Test on real devices, with real people.** Every milestone runs on the oldest supported iPhone and on an iPad, and is played by someone who is not us.
6. **Docs stay in sync.** If a decision changes, the doc changes the same day.

---

## 3. The documents we keep

| Document | Answers | Changes |
|---|---|---|
| `docs/game_design.md` | *What* is the game? Decisions and direction only. Short. | When a decision is made |
| `docs/prototype_reference.md` | What does the POC do *today*? Numbers, tables, rules. Not final. | Only for reference |
| `docs/tech_architecture.md` | *How* is it built? Structure, data, saving, performance. | With each technical decision |
| `docs/roadmap.md` | *When / in what order?* Now / Next / Later backlog. | Every week |
| `CLAUDE.md` | Rules for Claude Code in this project | When rules change |

---

## 4. Phases

Each phase ends with a **gate**: a clear question we must answer "yes" to before moving on.

### Phase 0 — Decide (now, ~days)
- Finish the design doc (v0.4) with the decisions made so far.
- Move the detailed old doc to `prototype_reference.md`.
- Write the **vertical slice scope** (§5).
- **Gate:** is the design direction clear enough that two people would build the same game from it?

### Phase 1 — Foundation (technical)
Done *before* more features:
- **Prototype audit.** Review the existing code and sort each part into **keep / refactor / rewrite**. Likely keep: ideas, numbers, tests. Likely rewrite: anything tangled between simulation and drawing.
- **Architecture** (`tech_architecture.md`):
  - Simulation is separate from rendering. Passengers are data; only drawing depends on the camera.
  - Content is data, not code: buildings, airlines, upgrade steps live in data files, so balancing never needs code changes.
  - A versioned **save system**: save on every change, on going to the background, with a 30 s safety save, plus a timestamp for offline income. Old saves can be upgraded.
  - Clear folder structure and naming rules.
- **Performance budget:** a target frame rate per device (for example 60 fps on iPad, at least 30 fps on the oldest supported iPhone) and a memory limit. We measure against it, not by feel.
- **Version control:** the project in Git with a private GitHub repository, small commits, a branch per feature.
- **Automated tests** for the simulation (queues, zone rules, economy), run before every merge.
- **Gate:** can we change a building's numbers and the save format without breaking anything?

### Phase 2 — Vertical slice
One small piece of the **real** game, at near-final quality, about 30 minutes of play:
- one airport with entrance → check-in → security → gate → plane
- automatic zones from buildings
- top-down view and a manager view with one area
- statistics panel with a bottleneck finder
- one service (power)
- one upgrade ladder (security) with one real technology step visible in 3D: more lanes → fast track → CT scanners
- one milestone: reaching the first tier unlocks something new, to test the milestone, upgrade and rebuild moment
- near-final look, sound and UI feel for this slice

**Gate (the most important in the project):** let 5–10 people outside our circle play it on their own phone. Do they understand it, enjoy it, and want to continue? If not, fix the core before building more.

### Phase 3 — Core systems (alpha)
Build in this order, each as its own milestone with a gate and a playtest:
1. Building system and zone rules (full)
2. Passenger journey: departures, arrivals, baggage, transfers
3. Staff and experience
4. Economy: income, costs, loan and restructuring
5. Services (total capacity): power, water, fuel, waste, fire, police
6. Airlines and deals
7. Tiers and milestones
8. Realism systems: schedule, delays, weather, night curfew, seasons

**Gate:** is the whole loop playable for several hours without breaking?

### Phase 4 — Content, balance, polish (beta)
- All buildings, airlines and upgrade steps, in the final art style
- Balancing the economy and pace, using real play data
- Tutorial (the fictional Memmingen-style airport)
- UI and UX polish, sound, music
- Performance and battery on all supported devices
- **Gate:** can a new player play 2+ hours without help and without a crash?

### Phase 5 — Release preparation
- **TestFlight** beta with real testers
- **Paid Apple Developer Program.** Free-account builds expire after 7 days and cannot go to the App Store.
- App Store requirements: icon, screenshots, description, age rating, privacy policy, App Privacy answers
- Crash reporting
- **Gate:** Apple approves the app.

### Phase 6 — After launch
Fix bugs, watch feedback, plan updates. Evaluate Android only then, as agreed.

---

## 5. Vertical slice: scope rules

- Included: only what the loop needs to be fun. Everything else waits.
- Not included: airlines negotiation, weather, loans, seasons, tutorial.
- Rule: if it is not in the list in Phase 2, it is not in the slice.

---

## 6. How we work day to day with Claude Code

For every task:
1. **Spec** it in 3–5 lines: goal, what is *not* included, how we know it is done.
2. **Plan** first for anything bigger than a small change, and read the plan before code is written.
3. **Build** in a small step; tests for logic.
4. **Run** on a device or the simulator; check the frame rate.
5. **Commit** with a clear message. One task, one commit.
6. **Update docs** if a decision or structure changed.

Other rules:
- No new features while refactoring.
- New ideas go to the parking lot, not into the code.
- Don't build a detail until it is in the Now column of the roadmap.
- Before a big change, ask Claude Code to explain the risks first.

---

## 7. Quality gates (every milestone)

- Runs on the oldest supported iPhone and on an iPad
- Frame rate and memory within budget
- Tests pass
- A save from the previous milestone still loads
- Played by at least one person who is not the developer

---

## 8. Parking lot (decided later)

Starting airport · day/night lighting · pause and speed controls · optional 120 Hz smooth mode (polish phase) · upgrade-in-progress details · incident handling in first person · lounge model · cargo model · reputation formula · exact tier thresholds · second terminal details · Android · online features. · save size with 1,000 passengers (~1 MB per save): round/cap stored paths if device tests show stutter

---

## 9. Decision log (so far)

| Topic | Decision |
|---|---|
| Devices | iPhone **and** iPad are both main devices; landscape only |
| Android | Not a focus now; revisit later if there is an easy way |
| Scope | No multiplayer, no multiple airports, English only |
| Feel | Thoughtful, clever, powerful (free to demolish), collector, architect |
| Zones | Automatic from buildings; the security building is the border |
| First-person view | Enjoy the airport, walk around, inspect and upgrade stations and staff. Incidents come much later |
| Top-down view | Understand the airport and passenger flow, place buildings, read statistics, enjoy |
| Tiers | 4 tiers as built (Regional → National → International → Hub) |
| Time | Day length as built (96 real minutes); clock starts at 06:00 on day 1 and runs 24 h |
| Offline | Average profit of the last ~10 min; 4 h of income after 36 h or more away |
| Saving | Every change, on background, 30 s safety save, with timestamp |
| Services | Total capacity (fire and police need to be close enough) |
| Upgrades | Real technology steps, visible in 3D |
| Bankruptcy | Loan and restructuring, no game over |
| Money | No ads, no in-app purchases for now |
| Vertical slice | Adds one milestone (first tier) and the security ladder up to CT scanners, visible in 3D |
| Test devices | iPhone 13 Pro (the weaker one) and iPad Air M1; stricter budget on the 13 Pro to keep headroom for older phones |
| Minimum supported iPhone | Open: decide before TestFlight |
| Frame rate | Capped at 60 fps on iPhone and iPad; optional 120 Hz smooth mode parked for the polish phase |
| Slice milestone | Reaching the first tier unlocks new land and the CT scanner step |
| Agent workflow | Lead, builder, reviewer, performance agents; branch + pull request per task; tests in GitHub Actions (2026-11-13) |
| Merging | For the first days the lead may merge or reject pull requests on its own (2026-11-13) |

---

## 10. Risks

| Risk | Answer |
|---|---|
| Scope too big | Vertical slice first; parking lot; small steps |
| Performance on older iPhones | Budget from day one; passengers as data; test on real devices |
| Touch controls too fiddly | Early playtests, especially on iPhone |
| Fun not proven | Phase 2 gate with outside players |
| Legal | Only fictional airlines, airports and brands |
| Rework from the POC | Prototype audit before any new feature |

---

## 11. Next steps

1. Apply the decisions to `game_design.md` (v0.4) and move the old doc to `prototype_reference.md`.
2. Run the **prototype audit** with Claude Code (keep / refactor / rewrite).
3. Write `tech_architecture.md`.
4. Set up Git and a GitHub repository, if not done already.
5. Write the **vertical slice scope** and the first roadmap.
6. Optional: let 2–3 people try the POC to get a baseline.

> Note: the project description lists in-app purchases as a secondary *learning* goal, while the current decision is no purchases. If you want to learn that process, one tiny optional purchase (for example a "supporter" item) can be added in Phase 5. It's your call, later.
