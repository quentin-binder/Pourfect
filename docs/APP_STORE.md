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

## Category

- **Primary: Games > Puzzle.** The game is a liquid-sorting puzzle with hand-made recipes, daily puzzles and a timed mode.
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
5. Screenshots (6.9" iPhone, 13" iPad, Mac) — produced separately.
6. Mac build (optional, same record): archive with `-destination 'generic/platform=macOS'` and the same export options; the Mac app is sandboxed (`ENABLE_APP_SANDBOX`) with no other entitlements (the template's unused *User Selected Files* entitlement was removed in R8).
