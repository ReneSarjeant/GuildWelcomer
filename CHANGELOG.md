# Changelog

## 1.1.2 - 2026-10-09

- Defer guild welcome messages while the player is in combat, preventing WoW: Forever from blocking the protected chat call.
- Send each deferred welcome once after `PLAYER_REGEN_ENABLED`, while preserving pending-greeting duplicate suppression.
- Discard deferred welcomes when the guild roster state is reset so stale callbacks cannot greet after a guild or character change.
- Added an offline Lua 5.1 regression for the reported combat path across modern, legacy, and mixed API modes. Live WoW: Forever confirmation remains pending.

## 1.1.1 - 2026-09-27

- Fixed a duplicate-greeting path reported in TBC: guild updates for the same guild now preserve pending greetings and duplicate suppression.
- Invalidate delayed greeting preparation and send callbacks when the roster state is reset, preventing stale greetings after guild changes.
- Offline Lua 5.1 regressions reproduce the duplicate with the previous code and pass with the fix, including modern/legacy APIs, Forever names, coordination, and language settings. In-game confirmation of this fix remains pending.

## 1.1.0 - 2026-09-20

- Promoted to Release following author-confirmed in-game testing on WoW: Forever.

- Resolve the current guild key when reading or changing the greeting language, avoiding stale roster state after a guild change or during startup.
- Treat an empty guild realm as unavailable and fall back to the player realm. Do not save a language when the guild or realm is missing.
- Only confirm a language change after it has been stored in the current session.
- Known Forever beta issue: users report SavedVariables failing to load after restart or /reload, causing settings to revert. This release does not fix that client-loading issue. Check /gw and reapply your language (for example /gw DE) after an affected login or reload.
- Offline Lua 5.1 persistence, compatibility, and Forever name regressions passed; the live Forever persistence failure remains unresolved.

## 1.0.13-alpha.2 - 2026-09-18

- Added Forever first-name/surname handling across roster identities, self detection, greeting cooldowns, and addon coordination.
- Use both name components for player identity and greeting placeholders; never merge different name boundaries or shorten identity through Ambiguate.
- Manual greetings accept a full name; a first name alone is accepted only when exactly one guild member matches. Ambiguity feedback is localized in all seven languages.
- VIP greetings recognize exact first names or surnames, with first-name matches taking priority. Name fragments also recognize surnames without matching across the boundary between both components.
- System-join player links resolve through their full player identity. Incomplete Forever identities are ignored instead of guessing a surname.
- Fixed escaped guild-join format placeholders so system-join detection works again.
- Added a dedicated Camelot manifest for Forever (Interface 16001).
- Offline Lua 5.1 regressions cover surname variants and two coordinated clients with the same first name; live Forever testing remains pending.

## 1.0.13-alpha - 2026-09-18

- Added initial WoW: Forever beta support for client 1.60.1 (Interface 16001).
- Guild-roster refreshes now prefer C_GuildInfo.GuildRoster, with a fallback for older clients.
- Guild greetings now prefer C_ChatInfo.SendChatMessage, with a fallback for older clients.
- Protected system messages are ignored before text matching; roster-based join detection remains available.
- Alpha release: Forever login, real guild joins, and multi-client coordination still require in-game testing.

## 1.0.12 - 2026-09-13

- Restored automatic roster-based join detection for clients that do not reliably deliver guild-join system messages to addons.
- Added a five-second login baseline and rejected incomplete roster snapshots so existing or offline members are not mistaken for new joins.
- Corrected 204 German greeting strings to use proper umlauts instead of awkward `ae`, `oe`, and `ue` spellings where appropriate.
- Added `Bär` and `Baer` name aliases to the existing localized bear greeting pool.

## 1.0.11 - 2026-09-01

- Reworked hundreds of English, German, Spanish, Russian, French, Swedish, and Dutch greetings so they sound natural instead of literally translated.
- Expanded localized name-based greetings to cover 53 name fragments and aliases across all seven languages.
- Added German name greetings for `Himmel`, `Sturm`, and `Falke`, including “Willkommen in deinem neuen Horst”.
- Fixed existing guild members being welcomed again after login or character changes when an incomplete roster update briefly made them appear new.
- Automatic welcomes now require WoW's guild-join system message; the delayed roster lookup remains in place to recover member details safely.

## 1.0.10 - 2026-08-19

- Updated the TBC Anniversary interface metadata from `20505` to `20506`.
- Synchronized the addon version across every supported client TOC.

## 1.0.9 "Bookworm Edition" - 2026-08-07

- Added a new VIP greeting category with 43 hand-written references for 49 exact character names and aliases.
- VIP name matches now receive their dedicated greeting with 100% priority over generic, generated, class-based, and ordinary name-based pools.
- Added complete VIP localization for English, German, Spanish, Russian, French, Swedish, and Dutch.
- Corrected spelling, grammar, and phrasing across the supplied English greetings while preserving their name-based jokes and references.
- VIP matching is exact, so `Gon` gets the red carpet without accidentally promoting every `Dragon` to VIP.

## 1.0.8 "My Hime Edition" - 2026-07-31

- Exactly one coordinated addon client now greets each new guild member; all non-selected clients stay silent.
- Added 28 localized name-based greetings for names containing `Hammer`, including MC Hammer, Hammer Drop, hammer-down, and paladin Judgement jokes.
- Added 22 localized princess greetings for names containing `Hime` — for anime nerds ^^.

## 1.0.7 - 2026-07-22

- Expanded the short welcome used by non-selected clients from one fixed line to six friendly variations per supported language.
- Short welcomes now avoid immediate repetition while remaining free of jokes, class references, and personalized name lines.

## 1.0.6 - 2026-07-22

- Added localized debug output when another addon user is selected for the personalized greeting.
- The debug message identifies the selected speaker and confirms that the local client will use the short welcome.

## 1.0.5 - 2026-07-21

- Paladin greetings now reference the Blood Knights instead of the Silver Hand when sent by a Horde character.
- Added faction-appropriate Blood Knight wording for every supported language.

## 1.0.4 - 2026-07-21

- Changed non-selected clients to send only a short localized welcome without any additional joke or generic-pool text.

## 1.0.3 - 2026-07-21

- Added guild-wide coordination between GuildWelcomer clients.
- The highest active addon version now sends the personalized greeting; other active clients use the generic welcome pool.
- Clients on the same highest version rotate the personalized greeting between them.
- Clients configured as `OFF` are excluded from speaker selection.

## 1.0.2 - 2026-07-18

- Added a whole lot more name-based greetings, including much stronger cat, nya, meow, purr, kitten, and flirty name coverage.
- Expanded non-English name pools so English-looking names trigger more themed lines across localized clients.
- Increased the overall amount of chaos, banter, and suspiciously pettable energy.

## 1.0.1 - 2026-07-18

- Fixed a timing issue where some new guild members could join without triggering a welcome message.
- Added a delayed roster fallback after guild join system messages to recover missed greetings more reliably.
- Cleaned up the internal join-tracking flow for this fallback path.

## 1.0.0 - 2026-07-17

- First public release of GuildWelcomer.
- Added multilingual welcome support for `EN`, `DE`, `ES`, `RU`, `FR`, `SW`, `NL`, and `OFF`.
- Added large generic, class-based, and name-based greeting pools with banter-heavy variants.
- Added delayed guild greetings, repetition cooldowns, and manual greetings via `/gw <PlayerName>`.
- Added localized slash-command feedback and debug output for every supported client language.
- Refactored addon data and runtime logic into separate modules for easier maintenance.
- Disabled automatic WHO-based race lookups to avoid protected-call issues in live gameplay.
