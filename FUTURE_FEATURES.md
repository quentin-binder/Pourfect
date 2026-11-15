# Bottle Sort → Potion Lab — Future Features Roadmap

> Direction chosen: **Potion lab / magic theme** · **Calm main path + optional challenge modes** · Modes: **Daily puzzle, Move-limit/timed challenges, Orders/story mode** · Business model: **hobby, undecided** (keep the options open, build nothing paid yet).
>
> Starts **after** the prototype in `BOTTLE_SORT_PROTOTYPE_SPEC.md` is running. Each milestone is sized to be handed to Claude Code as its own task. Keep the rule from the spec: game logic stays in `BottleSortCore`, and every new mechanic updates **rules + solver + generator + JSON + UI + tests** together.

---

## Milestone 1 — Make the prototype feel good (polish)
Do this before adding content. A sorting game lives or dies on how a single pour feels.
- [ ] Pour animation: the flask lifts, tilts toward the target and pours in a stream, with layers filling smoothly
- [ ] Liquid look: slight wobble/slosh, a highlight on the glass, a gentle glow on potions
- [ ] Haptics: light tap on select, soft thud on pour, success pattern when a flask is completed
- [ ] Sound: glass clink, pour gurgle, a "cork pop" + sparkle when a flask is completed
- [ ] Completed flask: a cork closes it plus a small particle burst
- [ ] Colorblind support: a symbol/rune on each potion color (also fits the magic theme)
- [ ] Settings: sound, music, haptics, colorblind runes on/off

## Milestone 2 — Potion lab theme & main progression
- [ ] Art direction: wizard's workbench background, glass flasks of different shapes, potion palette (12+ distinct colors)
- [ ] Rename in the UI only: bottles → flasks, levels → recipes/chapters (keep the code names neutral)
- [ ] **Chapters / world map:** e.g. Apprentice Cellar → Alchemist Tower → Dragon Vault. Each chapter has ~30 levels and brings in one mechanic
- [ ] Stars per level (moves vs. the solver's minimum) unlock the next chapters
- [ ] Gentle tutorials: one illustrated hint the first time each mechanic appears
- [ ] Generated content: `levelgen` produces packs per chapter with a tuned difficulty curve

## Milestone 3 — New mechanics (one per chapter)
Ordered roughly from easy to hard to build:
1. [ ] **Sealed flasks & keys** (locks & keys from Phase 5 of the spec). Theme: the key is a *rune stone* layer that unseals a flask
2. [ ] **Hidden layers / murky potions:** a layer shows as "?" until it is uncovered
3. [ ] **Single-essence flasks:** a flask marked with one rune only accepts that color
4. [ ] **Frozen layers:** iced potion that thaws after N moves
5. [ ] **One-way funnels:** a flask you can pour into but never out of (or the reverse)
6. [ ] **Mixing cauldron:** pouring two specific colors together creates a third (requires careful solver work)
7. [ ] **Linked flasks:** pouring into one also fills its twin
- For each: rules, solver support, generator option, JSON fields, art, tutorial level, tests

## Milestone 4 — Daily puzzle & streaks
- [ ] Deterministic daily level: seed = date, so everyone gets the same puzzle, offline, with no server
- [ ] Streak counter, calendar view of solved days, "perfect solve" badge
- [ ] Optional later: Game Center leaderboard for the daily (fewest moves, then fastest time)
- [ ] Local notification reminder (opt-in only)

## Milestone 5 — Challenge modes (optional, separate from the calm main path)
- [ ] **Move-limit recipes:** solve within N moves (N = solver minimum + slack). Fail → retry, no penalty
- [ ] **Timed / rush:** as many generated levels as possible in 3 minutes
- [ ] **Perfect brewer:** match the exact solver minimum to earn a gold seal
- [ ] Challenge results kept separate from main-path stars, so the main path stays relaxing

## Milestone 6 — Orders / story mode
- [ ] **Customer orders:** villagers request specific potions ("a full flask of red, a full flask of blue"). The goal is to fill specific target flasks, not just reach any sorted state → needs a new win condition in the rules + solver
- [ ] Light story told through short dialogue between chapters (an apprentice working for an old alchemist)
- [ ] Cosmetic rewards: workbench themes, flask shapes, potion effects

## Milestone 7 — Release readiness
- [ ] App icon, launch screen, App Store screenshots/preview video
- [ ] TestFlight beta with friends, plus analytics on where players get stuck (privacy-friendly, e.g. TelemetryDeck, or just App Store Connect stats)
- [ ] Accessibility pass: VoiceOver labels, Dynamic Type in menus, reduce-motion support
- [ ] iCloud sync of progress (optional)
- [ ] Localization: English + German to start (if relevant)
- [ ] **Business decision point:** before launch, choose between free / paid-once / ads + remove-ads. Keep `HintService` and `ProgressStore` behind protocols so hints or extra packs can become paid later without refactoring

## Ideas parking lot (not planned yet)
- Level editor + share code (the solver verifies each level can be solved)
- Async versus: same puzzle, fewer moves wins
- Seasonal events (Halloween potions, winter frost chapter)
- iPad layout, Mac Catalyst, Apple Watch daily puzzle
- Other themes as skins: sand jars, cargo containers, gems
- Bombs/bonus items, leaking flasks, conveyor shelves

---

## Suggested order
**1 → 2 → 3.1 (keys) → 4 → 3.2–3.4 → 5 → 6 → 7**, with release prep (7) able to start any time after 4 if you want an early TestFlight.
