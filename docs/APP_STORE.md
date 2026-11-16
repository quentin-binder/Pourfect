# Pourfect – App Store notes

What the project already sets, and what has to be entered by hand in App Store Connect.
Uploads are done by the operator with `scripts/testflight.sh` (see the README, *Release builds*).

## Identity

| Field | Value |
|---|---|
| Name on the store | **Pourfect** (fallback if the name is taken: *Pourfect: Potion Sort*) |
| Bundle id | `dev.qbi.pourfect` (iOS and macOS, one app record = universal purchase) |
| Team | `MVC97L8VQ3` |
| Version / build | `MARKETING_VERSION` 1.0 in the project; the build number is the script's argument (`CURRENT_PROJECT_VERSION`) |
| Platforms | iPhone and iPad (iOS 17+), Mac (macOS 14+, native, sandboxed) |
| Suggested subtitle | *A cozy potion-sorting puzzle* (30 characters max) |

## Store listing (draft, English)

Character limits are App Store Connect's; the counts were checked.

**Name** (30 max): `Pourfect` (8). Fallback if taken: `Pourfect: Potion Sort` (21).

**Subtitle** (30 max): `A cozy potion-sorting puzzle` (28).
Alternatives: `Sort potions, brew wonders` (26), `Pour, sort and brew potions` (27).

**Promotional text** (170 max, can be changed without a new build):

> Ten chapters of solver-checked potion recipes, villagers with special orders and a fresh Daily Brew every day. No ads, no purchases, no account: just pour and think.

**Description** (4000 max):

> Pour colorful potions from flask to flask until every flask holds a single color. Simple to learn, surprisingly deep, and always calm.
>
> Pourfect is a cozy liquid-sorting puzzle set in an alchemist's workshop. Climb from the Apprentice Cellar to the Dragon's Hoard across a painted map, learning a new trick in every chapter.
>
> 421 POTION RECIPES
> • 421 recipes in ten chapters and three Challenge books (Challenger, Expert, Master)
> • Every recipe is checked by a solver, so each one can be finished
> • Earn up to three stars, and a gold seal for a perfect solve
>
> A NEW MECHANIC IN EVERY CHAPTER
> • Sealed flasks that open with a rune-stone key
> • Murky potions that hide what lies beneath
> • Glyph flasks that take only their own color
> • Narrow necks, funnels and taps
> • Frozen layers that wait for the thaw
> • Bubbling flasks that lift their bottom layer to the top
> • Chained twins and pressure pipes
> • A cauldron that brews two ingredients into a new potion
> • Switch flasks that lift a gate
>
> VILLAGERS AND A STORY
> Villagers stop by the workshop with special orders: a certain potion in a certain flask, or a layered recipe poured just so. A short story follows the apprentice from chapter to chapter, all the way to the dragon.
>
> EVERY DAY SOMETHING NEW
> • Daily Brew: one fresh puzzle a day, with a calendar and a streak
> • Rush: solve as many recipes as you can against the clock
> • Random Brew: endless generated puzzles with your own settings
>
> MAKE THE LAB YOURS
> Unlock workshop themes (Forest Hut, Frost Lab, Dragon's Lair), flask shapes and potion effects as you play.
>
> PLAYS THE WAY YOU LIKE
> • Undo, hints and restarts whenever you need them; no timers outside Rush
> • Color runes for players who tell colors apart less easily, Reduce Motion and VoiceOver support
> • Works fully offline
> • iPhone, iPad and Mac
>
> No ads. No in-app purchases. No account. No data collected.

**Keywords** (100 max, comma-separated, no spaces; words already in the name and subtitle are left out because they are indexed anyway):

```
water,sort,liquid,color,bottle,brain,logic,relax,alchemy,witch,daily,flask,offline,casual,cozy,mind
```
(99 characters)

**What's new in this version** (version 1.0):

> Welcome to Pourfect! Ten chapters of potion recipes, villager orders, the Daily Brew, Rush and Lab Style themes. Happy pouring.

**URLs** (placeholders; replace before submitting):

| Field | Value |
|---|---|
| Support URL (required) | `https://example.com/pourfect/support` |
| Marketing URL (optional) | `https://example.com/pourfect` |
| Privacy policy URL (required) | `https://example.com/pourfect/privacy` |
| Copyright | `2026 <developer name>` |

A support page can be a single page with a contact form or address; the developer's own e-mail is not written into the repository.

**App Privacy answers:** "Do you or your third-party partners collect data from this app?" → **No** → the label shows **Data Not Collected**. (Details in *App Privacy* below.)

**Age rating answers** (all → 4+):

| Question | Answer |
|---|---|
| Cartoon or fantasy violence | None |
| Realistic violence | None |
| Prolonged graphic or sadistic realistic violence | None |
| Profanity or crude humor | None |
| Mature or suggestive themes | None |
| Horror or fear themes | None |
| Medical or treatment information | None |
| Alcohol, tobacco or drug use or references | None |
| Simulated gambling | None |
| Sexual content or nudity | None |
| Contests | None |
| Unrestricted web access | No |
| Gambling | No |
| User-generated content / messaging | No |
| In-app purchases / advertising | No |
| Parental controls, age assurance | No (not needed) |

## Screenshots

See *Screenshots* at the end of this file.

## Category

- **Primary: Games > Puzzle.** The game is a liquid-sorting puzzle with 421 solver-checked recipes, daily puzzles and a timed mode.
- **Secondary (optional): Games > Family** or **Games > Casual**. Family fits the gentle story and the absence of ads and purchases.

## Age rating (questionnaire notes)

Every content question can be answered **None / No**, which gives the lowest rating (4+):

- Violence (cartoon, fantasy or realistic): none. The dragon is sleeping scenery on the map and in the last chapter; nothing is attacked or hurt.
- Profanity, horror, mature or suggestive themes, alcohol/tobacco/drugs: none. The "potions" are coloured liquids; nothing is drunk.
- Medical information, gambling, simulated gambling, contests: none. Stars, gold seals and the Rush best are local scores, not prizes.
- User-generated content, chat, unrestricted web access: none. The app has no networking at all.
- In-app purchases, ads, accounts: none.

## App Privacy ("nutrition label")

- **Data Not Collected.** The app does no networking, has no analytics, no third-party SDKs and no accounts. Progress, settings and daily results stay in the app's UserDefaults on the device.
- Privacy manifest: `Pourfect/PrivacyInfo.xcprivacy` (no tracking, no tracking domains, no collected data types; the only required-reason API is UserDefaults, reason `CA92.1`, the app's own data).
- A **privacy policy URL** is still required by App Store Connect for every app. A one-paragraph page is enough ("Pourfect collects no personal data …").

## Export compliance

`ITSAppUsesNonExemptEncryption = NO` is in the generated Info.plist (build setting `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption`), so TestFlight and review do not ask the encryption question for each build. The app uses no encryption of its own.

## Content rights and art

- All painted art (workbench, map, chapter scenes, portraits, villagers, themes, app icon) was generated with FLUX 1.1 [pro] Ultra by Black Forest Labs through Replicate; character cut-outs used Bria's background-removal model. Both are offered for commercial use; see `Art/README.md`, *Licensing*. **Re-read the current terms of Black Forest Labs, Bria and Replicate before submitting.**
- Sounds are synthesized in code; fonts are Apple system fonts. No third-party code.
- Content-rights question ("Does your app contain, show or access third-party content?"): answer **No** if the generated art is considered the developer's own output under those terms; otherwise **Yes, and I have the rights**.
- The About page (Settings → About Pourfect) carries the version, build and these credits.

## Release build size (iOS, Release, build 2, 2026-11-16)

| Item | Size |
|---|---|
| `Pourfect.app` (universal, before App Store thinning) | 16.3 MB |
| Unsigned `.ipa` (zip of `Payload/`) | 14.5 MB |
| `Assets.car` | 13.3 MB |
| Executable (arm64) | 2.9 MB |
| Level JSON files (13) | ~0.3 MB |
| dSYM (not shipped) | 19 MB |

Largest assets (compiled sizes): chapter map 1.27 MB (1344 × 3136 JPEG), the 1024 px app icon 1.0 MB (stored once for iPhone and once for iPad; thinning keeps one), landscape workbench/theme backgrounds 0.57–0.85 MB each (2752 × 1536, the iPad Pro 13" landscape width), portrait backgrounds 0.41–0.66 MB (1179 × 2752), chapter vignettes 0.23–0.43 MB (1024², shown full screen behind the recipe list), story portraits ~0.19 MB each (512 px, shown up to 270 pt). The six villager portraits were downscaled from 512 to 256 px in R8 (they are shown at 58 pt at most): −0.9 MB. Nothing else is oversized for how it is drawn. App Store thinning will deliver roughly 13–14 MB to a single device.

## To do in App Store Connect (operator)

1. Create the app record: platform iOS (add macOS later for a universal purchase), name, primary language English, bundle id `dev.qbi.pourfect`, SKU of your choice.
2. Category Games > Puzzle; age rating questionnaire as above; App Privacy: Data Not Collected; privacy policy URL; support URL; copyright line.
3. Run `scripts/testflight.sh <build>` on a Mac signed in to the team in Xcode (Settings → Accounts). The first export creates the distribution certificate and the App Store profile automatically (`-allowProvisioningUpdates`).
4. TestFlight: add internal testers; external testing needs a short Beta App Review (test information: "No login needed").
5. Screenshots (6.9" iPhone, 13" iPad, Mac): six per device, see *Screenshots* below. Upload the captioned set (or the raw set) in the order 01–06. Every file must be opaque: run `swift scripts/appstore-flatten.swift <files>` on raw captures first (Mac window captures have transparent rounded corners; simulator captures carry an unused alpha channel).
6. Mac build (optional, same record): the Mac Info.plist carries `LSApplicationCategoryType` = `public.app-category.puzzle-games` (required for a Mac upload, ITMS-90242); archive with `-destination 'generic/platform=macOS'` and the same export options; the Mac app is sandboxed (`ENABLE_APP_SANDBOX`) with no other entitlements (the template's unused *User Selected Files* entitlement was removed in R8).

## Screenshots

Six per device, in this order, each as a raw capture and a captioned version (caption band in the system serif, parchment and gold on the launch-screen brown, made with `scripts/appstore-caption.swift`):

| # | Shot | Caption | Sub-line |
|---|---|---|---|
| 01 | Chapter 1, recipe 13 mid-pour | Pour. Sort. Relax. | 421 solver-checked recipes |
| 02 | Chapter map | Ten chapters to explore | From the cellar to the dragon's hoard |
| 03 | Chapter 9 (Alchemist's Hall), recipe 13: a pour next to the cauldron | A new trick in every chapter | Brew new potions in the cauldron |
| 04 | Chapter 9, recipe 31: Pip's order card and ticket | Brew for the villagers | Special orders and a cozy story |
| 05 | Daily Brew with calendar and streaks | A fresh brew every day | Daily Brew, streaks and Rush |
| 06 | Dragon's Lair theme, conical flasks, mid-pour | Make the lab yours | Unlock themes, flasks and effects |

| Device | Size | Source |
|---|---|---|
| iPhone 6.9" | 1320 × 2868 | iPhone 18 Pro Max simulator, status bar 9:41 / full battery, locale en_US |
| iPad 13" | 2064 × 2752 | iPad Pro 13-inch (M5) simulator, same status bar |
| Mac | 2880 × 1800 | Debug Mac app, window set to 1120 × 700 pt with `-LPWindowSize 1120x700` (the built-in display is too small for a 1440 × 900 pt window). Raw = the 2240 × 1400 window capture scaled to 2880 × 1800 (same 16:10 aspect) and flattened (its transparent corners filled); captioned = the window drawn at its own size under the band. |

The 36 PNGs are about 155 MB together (painted backgrounds compress poorly), so they are **not committed**; regenerate them with the launch arguments below. All captures use `-LPSkipTutorials 1 -LPUnlockAll 1` (and on the Mac `-ApplePersistenceIgnoreState YES -LPWindowSize 1120x700`):

```
01  -LPOpenChapter 1 -LPOpenLevel 13 -LPDemoMoves 4 -LPSlowMotion 3     (capture during a pour)
02  -LPMapAnchor 0.55
03  -LPOpenChapter 9 -LPOpenLevel 13 -LPDemoMoves 3 -LPSlowMotion 3
04  -LPOpenChapter 9 -LPOpenLevel 31
05  -LPDailySeedResults 40 -LPOpenDaily 1                                (Mac: add -AppleLocale en_US -AppleLanguages '(en)')
06  -LPOpenChapter 1 -LPOpenLevel 21 -LPDemoMoves 3 -LPSlowMotion 3 -settings.theme dragonLair -settings.flaskShape conical -settings.potionEffect starburst
```

Simulator status bar: `xcrun simctl status_bar <id> override --time 9:41 --batteryState discharging --batteryLevel 100 --cellularBars 4 --wifiBars 3`.
Flatten (drop alpha, fill transparent corners with the launch brown): `swift scripts/appstore-flatten.swift RAW.png ...`.
Caption: `swift scripts/appstore-caption.swift RAW.png OUT.png "Headline" "Sub-line"` (`CAPTION_SIZE=2880x1800` for the Mac window shots).
