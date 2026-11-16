# Potion Lab — Mechanics Design Doc

> Companion to `FUTURE_FEATURES.md` (Milestone 3). Each mechanic is written so it can be handed to Claude Code as one task: **rules → state/solver impact → generator → JSON → UI → tests**.

---

## 0. Design principles (apply to every mechanic)

1. **Deterministic.** No randomness during play. Every rule depends only on the current state, so the solver can solve the level and give hints.
2. **Everything is in the state.** Timers, counters and flags (e.g. "thaws in 3 moves") must be stored in `GameState`. The solver's canonical key must include them, or it will treat different states as the same.
3. **Readable at a glance.** A player must be able to understand every rule from the flask's look, without reading text. One visual signal per mechanic.
4. **One new idea per chapter.** Introduce it alone in a tutorial level, then combine it with earlier mechanics.
5. **Watch the state space.** Mechanics with counters multiply the number of states. Check solver time after each one and limit the counters (e.g. max 5).
6. **Undo always works.** Undo restores the full state, including all counters and flags.
7. **A move = one pour or one action.** Moves that come from mechanics (thawing, conveyor shifts) happen automatically *after* the player's action, in a fixed order (see §4).

---

## 1. Mechanics catalogue

Difficulty to build: ★ easy · ★★ medium · ★★★ hard (rules + solver + art).
Puzzle depth: how much new thinking it adds for the player.

### A. Access mechanics: control *which* flasks you can use

#### A1. Sealed flasks & rune stones (locks & keys) ★★
- **Theme:** a flask sealed with a glowing rune. A matching *rune stone* is buried in another flask.
- **Rules:** the rune stone is a layer that takes up 1 slot and always moves alone. It can only be poured onto the sealed flask with the matching rune, which unseals it; the stone is used up. Sealed flasks can't be poured from or into. A flask with a stone on top can't receive anything.
- **Variants:**
  - *Multi-rune seal:* needs 2 stones.
  - *Master stone:* opens any seal.
  - *Chain:* flask A holds the stone for B, B holds the stone for C.
- **State/solver:** `Layer.key(id)`, `Bottle.lockedBy`. No counters, so it's cheap.
- **Generator:** place the stone in a non-top position. Make sure some colors are inside the sealed flask, so the seal *matters*.
- **Depth:** forces you to dig a specific flask out early, so you plan around one goal.

#### A2. Corked flasks ★
- **Theme:** a flask with a cork that pops after N total moves (a countdown shown on the cork).
- **Rules:** unusable until `movesMade >= N`, then it opens permanently.
- **State:** a global `moveCount` matters to the rules, so include it in the state while any cork is closed.
- **Depth:** low, but a nice pacing tool: "survive with fewer flasks for a while".

#### A3. Pressure plates / switch flasks ★★
- **Theme:** two flasks are linked by a brass pipe. Filling the switch flask *completely* opens the gate on another flask (or closes it).
- **Rules:** while switch flask S is full with one color, gate G is open. If S stops being complete, G closes again (layers inside stay but can't be used).
- **Depth:** high, because you have to decide whether to "spend" a completed flask on keeping a gate open.

### B. Information mechanics: hide or reveal things

#### B1. Murky potions (hidden layers) ★
- **Theme:** cloudy liquid with a "?".
- **Rules:** a hidden layer is revealed once nothing is above it. Once revealed, it stays revealed.
- **Solver:** knows everything; hiding is a display-only rule. Hints still work, but they spoil the mystery, so maybe limit hints in murky levels.
- **Variant:** *Fog flask*: the whole flask is hidden until you first pour into or out of it.

#### B2. Scrying glass ★★
- **Theme:** a consumable lens (one or two per level) that reveals all hidden layers in one flask.
- **Rules:** using it is an action that counts as a move (or a free resource, decide during tuning).

### C. Constraint mechanics: limit *what* can go where

#### C1. Essence flasks (one-color only) ★
- **Theme:** a flask etched with one color's rune.
- **Rules:** accepts only that color. It may *start* with mixed layers, which you pour out, but can only receive its own color.
- **Depth:** removes "free" storage space, so the player has to plan where things go.

#### C2. Narrow-neck flasks ★
- **Theme:** a thin neck.
- **Rules:** pours in or out **only one layer per move**, even if the run is longer.
- **Depth:** splits runs on purpose, which creates new possibilities (and traps).

#### C3. Wide-mouth cauldron ★★
- **Theme:** a cauldron with bigger capacity (e.g. 6 instead of 4).
- **Rules:** normal rules, larger capacity. The win condition for it: empty, or full with one color.
- **Generator:** mixed capacities in one level, so color counts must still add up. Rule: each color has `standardCapacity` layers, and the cauldron is only ever a "workspace" (it must end empty). Alternatively, define colors with 6 layers. Write down the decision.

#### C4. One-way funnels ★
- **Theme:** a funnel on top (fill only) or a tap at the bottom (drain only).
- **Rules:** *Funnel flask:* can receive, never pour out. *Tap flask:* pours from the **bottom** layer, never receives.
- **Depth:** the tap flask turns the stack upside down, which gives a fresh puzzle feel.

#### C5. Weight/order potions ★★
- **Theme:** each color has a density. Heavy potions sink.
- **Rules:** you can only pour onto a layer of the *same* color **or a heavier** color (instead of only the same color). Win stays the same.
- **Depth:** a different rule set altogether. Good for its own chapter. Needs a density legend in the UI.

### D. Time / reactive mechanics: the board changes after moves

#### D1. Frozen layers ★★
- **Theme:** ice crystal over a layer with a number.
- **Rules:** a frozen layer (and anything below it) can't move. Its counter goes down by 1 after each move; at 0 it thaws. *Variant:* it only thaws when a **fire potion** (a special color) is poured onto it.
- **State:** a counter per frozen layer, so the state space grows. Keep counters ≤ 5 and ≤ 2 frozen layers per level.

#### D2. Bubbling flask (rising layer) ★★
- **Theme:** a flask that bubbles.
- **Rules:** every K moves, the bottom layer moves to the top (the stack rotates). Shown with a ring that fills up.
- **Depth:** timing puzzles where you wait for the right color to come up.

#### D3. Conveyor shelf ★★★
- **Theme:** a rotating shelf holding several flasks.
- **Rules:** every K moves, the flasks on the shelf shift one position (affects which flasks are next to switches and pipes, or which flask is "active").
- **Note:** only meaningful together with position-based mechanics (A3, E1). Later chapter.

#### D4. Evaporation ★★
- **Theme:** a flask with no cork, giving off steam.
- **Rules:** if a flask's top layer is a volatile color and it sits untouched for K moves, that layer evaporates (is removed). The win condition must allow for this: the volatile color's total count shrinks, so "solved" means every *remaining* layer is sorted.
- **Depth:** sometimes you *want* things to evaporate. A strong twist; it needs careful tuning.

### E. Transformation mechanics: colors change

#### E1. Mixing cauldron ★★★
- **Theme:** a cauldron with a recipe card: red + blue → purple.
- **Rules:** pouring color X onto Y inside the cauldron, where (X, Y) is on the recipe, turns **both** layers into Z. Only inside the cauldron; normal flasks follow the normal rules.
- **Generator:** the level must contain the right number of input colors so that the target colors end up with exactly `capacity` layers. Easiest to build "backwards": start from a solved target state and *un-mix*.
- **Solver:** works unchanged as a state search; layer counts per color change during play, so `validate()` must allow for that.

#### E2. Transmutation stone ★★
- **Theme:** a philosopher's-stone layer.
- **Rules:** when it is poured onto a run of color X, it turns the **top layer** below it into the color of the next layer down in the target flask (or a fixed target color, which is simpler). The stone is used up.
- **Depth:** a single powerful action; the puzzle is about *where* to use it.

#### E3. Dye drops ★
- **Theme:** a small drop item.
- **Rules:** a drop of color Z poured onto any top layer recolors that one layer to Z.
- **Note:** simpler and easier to read than E2. Pick one of the two.

### F. Link mechanics: flasks affect each other

#### F1. Twin flasks ★★
- **Theme:** two flasks joined by a silver chain.
- **Rules:** a pour *into* twin A also pours the same layer(s) into twin B if they fit and the colors match; otherwise the pour is illegal.
- **Depth:** forces symmetrical thinking. High depth, small rule.

#### F2. Pressure pipes ★★ (was: overflow pipes; link id `overflow`)
- **Theme:** a brass pipe from flask A's base to flask B's base.
- **Rules:** a pour into A that doesn't fit pushes A's bottom layers, one per extra layer, through the pipe into the bottom of B (while B has room); color never matters. A full A with the poured color on top accepts the pour iff B has room. Both ends plain, one hop (DECISIONS 300).
- **Depth:** frees a buried bottom layer without digging, at the price of burying it in B.

#### F3. Teleport flasks ★★
- **Theme:** two flasks with matching portal swirls.
- **Rules:** pouring into either one puts the layers into the other.
- **Depth:** low on its own, but adds variety to layouts.

### G. Items & resources (player-owned, earned or limited per level)

| Item | Effect | Notes |
|---|---|---|
| **Extra flask** | Adds one empty flask for this level | Classic "rescue" item; good as a reward or (later) a paid item |
| **Undo charges** | Undo limited in challenge modes only | Main path keeps unlimited undo |
| **Swirl stick** | Swaps the top 2 layers of one flask | One per level, in challenge modes |
| **Vanishing dust** | Removes one layer from the board | Changes color totals, so the win condition must allow for it |

Keep items **out of** the hand-made main levels so they stay pure puzzles, and use them in the daily puzzle, challenges and rescue situations.

---

## 2. Special win conditions (for Orders / story mode)

| Goal | Description | Solver change |
|---|---|---|
| **Standard** | Every flask empty or full with one color | — |
| **Order** | Specific flasks must contain specific colors (e.g. the "customer flask" = full red) | Goal check becomes a predicate passed to the solver |
| **Partial order** | Fill N flasks of any colors; leave the rest messy | Easier, good for quick levels |
| **Layered recipe** | One flask must end with an exact layer pattern, e.g. red/red/blue/gold (a "cocktail") | New and interesting; the solver goal is a pattern match |
| **Rescue** | Free all sealed flasks within N moves | Combines A1 with a move limit |
| **Purify** | Get rid of all "cursed" (black) layers using a special disposal cauldron | Needs a "sink" flask that removes layers |

Implementation hint: make the win condition a `Goal` protocol / enum stored in the level JSON, and have the solver call `goal.isSatisfied(state)`.

---

## 3. Chapter plan (suggested)

| Chapter | Theme name | New mechanic | Also uses |
|---|---|---|---|
| 1 | Apprentice Cellar | Basic sorting | — |
| 2 | Rune Vault | A1 Sealed flasks & rune stones | — |
| 3 | Misty Marsh | B1 Murky potions | A1 |
| 4 | Glyph Library | C1 Essence flasks | A1, B1 |
| 5 | Glass Works | C2 Narrow neck + C4 Funnels/taps | C1 |
| 6 | Frost Peak | D1 Frozen layers (+ fire potion variant) | A1, C1 |
| 7 | Bubbling Bog | D2 Bubbling flasks | B1 |
| 8 | Twin Towers | F1 Twin flasks + F2 Pressure pipes | C2 |
| 9 | Alchemist's Hall | E1 Mixing cauldron | everything light |
| 10 | Dragon's Hoard | A3 Switch flasks + combos | all |

Orders/story mode can reuse each chapter's mechanics with the special goals from §2.

---

## 4. Turn order (with several mechanics active)

After every player action:
1. Apply the player's pour/action (including twin/pressure-pipe/teleport effects).
2. Resolve immediate effects: unseal (A1), reveal murky layers (B1), mixing (E1), switch gates (A3).
3. Increase `moveCount`.
4. Run timed effects in a fixed order: corks (A2) → thaw (D1) → bubbling (D2) → evaporation (D4) → conveyor (D3).
5. Run step 2 again (timed effects can reveal or unseal things).
6. Check the goal.

Write this as one `Rules.resolve(afterAction:)` function, so the order is defined in exactly one place.

---

## 5. Implementation architecture (for Claude Code)

- `Layer`: `enum` with cases `.color`, `.key`, `.transmute`, `.dye`, … plus layer flags (`hidden`, `frozen(turns)`).
- `Bottle`: capacity, layers, plus an optional list of `BottleModifier`s (`.sealed(KeyID)`, `.essence(ColorID)`, `.narrowNeck`, `.funnel`, `.tap`, `.cork(turns)`, `.bubbling(every:phase:)`, `.cauldron(recipes)`, …).
- `Link`s at the level level: twins, overflow pipes, teleports, switches.
- `Goal`: `.standard`, `.order([...])`, `.pattern(...)`, …
- Rule checks are split by modifier: each modifier can *veto* or *modify* a pour (`canPour` asks every modifier involved). New mechanic = new modifier + tests, with minimal changes to the core rules.
- The canonical key must include all modifier state, counters, `moveCount` (if any counter depends on it) and link state.
- `levelgen` gets a flag per mechanic (`--sealed 1 --murky 3 --frozen 1:4 …`) and a "must matter" check: re-solve with the mechanic removed, and reject the level if the mechanic changed nothing.

---

## 6. Prioritized shortlist

If you only build six: **A1 Sealed flasks → B1 Murky → C1 Essence → D1 Frozen → F1 Twins → E1 Mixing cauldron.** Together they cover access, information, constraints, time, links and transformation, so each chapter feels different.
