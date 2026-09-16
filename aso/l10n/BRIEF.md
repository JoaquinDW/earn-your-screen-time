# Earnit — in-app translation brief

Earnit is an iOS app that **blocks distracting apps until you earn screen time**
by walking (steps from Apple Health), running a focused study session, or doing
push-ups counted by the phone. Earned minutes are spent in deliberate 5/10/15
minute sessions, after which the block returns automatically.

Register: second person, direct, calm. Not cheerful, not scolding, never
gamified-shouty. The app deliberately avoids guilt and red warnings. Match the
address form already used in the shipped Spanish (informal "tú"), i.e. the
locale's normal informal-but-respectful consumer register.

## NEVER translate — output byte-identical
`Earnit`, `Earnit Pro`, `EARNIT PRO`, `Apple Health`, `Apple Account`,
`App Store`, `iPhone`, `iOS`, `Face ID`, `Live Activity`, `Dynamic Island`,
any URL, any email address.

**`Screen Time`**: when it names the *iOS system feature* (permissions,
authorization, settings), use **Apple's own official localized name** for that
feature in your language (e.g. de "Bildschirmzeit", ja "スクリーンタイム",
fr "Temps d'écran"). When it means screen time in general, translate normally.

## Format specifiers — a mistake here is a crash, not a typo
- Reproduce every `%@`, `%lld`, `%d`, `%.1f` exactly: same count, same types.
- If your language needs a different word order than English, you MUST convert
  to positional form (`%1$@`, `%2$lld`). Positional reordering is correct and
  expected — the shipped Spanish already does this.
- Never add a specifier to a string that has none. Never drop one.
- `%%` is a literal percent sign; keep it as `%%`.

## Sense glossary — the app's meaning, not the common one
| Term | Meaning HERE |
|---|---|
| earn / earned | to acquire screen-time minutes through physical or study effort. **Never** money, wages or financial earnings. |
| balance | the stock of unspent screen-time minutes, like a wallet balance. Not equilibrium, not physical balance. |
| spend | to consume earned minutes by opening a session. |
| session | one deliberate 5/10/15-minute window in which blocked apps open. |
| shield | the iOS blocking screen shown over a restricted app. The blocking sense, never a coat of arms. |
| blocked / locked / restricted | apps made unavailable by Screen Time. |
| resting apps | apps currently blocked/paused — "resting", not asleep, not broken. |
| steps | walking steps from a pedometer. Never stages or instructions. |
| rate | how many minutes you get per N steps — an exchange/conversion rate, not interest. |
| journey (30-day) | a 30-day progress path through the programme. Not travel. |
| streak | consecutive days of meeting the goal. |
| claim | to collect a reward already earned but not yet credited. |
| reps | push-up repetitions. |
| ledger | the running daily record of minutes earned and spent. |
| plan | TWO senses — check each string: (a) the user's personalised 30-day step plan; (b) the subscription tier. Translate each with its own correct word. |
| Progress / Home / Earn / Settings | tab names in the bottom bar. Keep them short — these render in a tab bar. |
| goal | the daily step target. Not a sports goal. |

## Frequency labels
`Monthly` / `Yearly` on the paywall are **adverbial billing frequencies**
("billed monthly"), never the bare nouns "Month"/"Year" — those collide with
duration labels elsewhere on the same screen.

## Enum groups — members must stay distinct from each other
1. Tab bar: Home / Earn / Progress / Settings
2. Session lengths: 5 / 10 / 15 minutes
3. Onboarding step bands: 2,500–5,000 / 5,000–7,500 / 7,500–10,000 / 10,000+
   — **localise digit separators** to your language's convention
     (de "2.500–5.000", fr "2 500–5 000", en "2,500–5,000").
4. Earning methods: Walk / Study / Push-ups

## Other rules
- ALL-CAPS English strings stay emphatic in cased scripts; in CJK, caps do not
  exist — render them as normal text.
- Sentence-final punctuation follows YOUR language: Greek uses `;` for a
  question mark, CJK uses `。` and `？`, Thai ends sentences with no mark.
  Do not blindly copy the English full stop.
- Keep strings roughly the English length — these are phone UI labels. German
  and Russian compounds especially must not double the width of a button.
- The `es` field in the input is the **shipped Spanish**. Use it to understand
  the intended sense and to stay consistent with vocabulary the app already
  ships. Do not copy its wording blindly.
