# Screenshot copy provenance

The headlines, sublines and three privacy facts are the exact supplied brief, recorded in `frames.json` and `make_es.py`. Spanish inside the phones uses the app's `es` catalog values. The app says **Saltos de tijera** inside the exercise screen; the supplied marketing subline deliberately retains **jumping jacks**.

| Surface | Catalog keys / source |
| --- | --- |
| Hook | `home.appsPaused`, `home.earnMore.walk`, `pushups.name`, `squats.name`; composed shield heading below |
| Push-up camera | `pushups.challenge.reps %lld`, `pushups.guidance.lower_body`; counter formatted as 7 / 10 |
| Walking | `home.availableTime`, `home.toSpendOnYourApps`, `home.useMinutes`, `earn.stepsToday %@`, `home.minutesEarnedCount %lld`, `home.impact.skipped %lld`, `earn.nextReward %lld %lld`, `dashboard.streak %lld` |
| Exercises | `earn.title`, `earn.chooseHowToEarn`, `earn.source.steps`, `earn.stepsToday %@`, `exercise.entry.title`, `pushups.name`, `squats.name`, `lunges.name`, `jumping_jacks.name`, `squats.challenge.reps %lld`, `squats.guidance.lower_hips` |
| Shield | `shield.detail.eyebrow.almost`, `shield.detail.headline.almost %lld`, `shield.detail.support.almost %lld`, `shield.detail.progress %@ %@`, `shield.detail.reward %lld`, `shield.detail.remaining %lld %lld`, `shield.detail.action.pushups`, `shield.detail.action.update` |
| Sessions | `session.chooseDuration`, `home.useMinutes`, `session.available`, `session.after`, `session.customDuration`, `session.clockDisclaimer`, `session.start %lld` |
| Schedule | `blocking.title`, `blocking.schedule.section`, `blocking.schedule.toggle`, `blocking.schedule.start`, `blocking.schedule.end`, `blocking.schedule.footer`, `strictMode.section`, `strictMode.activeUntil`, `strictMode.extend`, `strictMode.footer` |
| Outcome | `impact.period.today`, `impact.title`, `impact.metric.*`, `impact.reclaimed.footnote`, `share.challenge`, existing share/done actions and streak formatting |
| Friends | `friends.eyebrow`, `friends.title`, `friends.list`, `friends.status.noUpdate`, `friends.invite`, `friends.squads`, `friends.squad.week`, `friends.squad.goalDays %lld`, `friends.squad.join` |

## Composed or adapted strings

These are not new app localizations. They exist only in the screenshot sources.

| EN | ES | Reason |
| --- | --- | --- |
| Apps locked until you earn time | Apps bloqueadas hasta que ganes tiempo | Hook heading requested by the brief; Spanish composed to match |
| Move together | Muévanse juntos | Fictional weekly squad name; the app displays user-created squad names verbatim |
| / 10 push-ups | / 10 flexiones | Existing compact counter suffix, adapted from the localized rep count |
| / 10 squats | / 10 sentadillas | New compact counter suffix, adapted from the localized rep count |

Existing screenshot callout copy retained outside the phones (not new product features):

| EN | ES |
| --- | --- |
| On-device / rep counting | Conteo / en tu iPhone |
| No video / ever saved | Sin video / nunca se guarda |
| Apps unlocked / +10 min earned | Apps desbloqueadas / +10 min ganados |
| Apps locked / until you earn time | Apps bloqueadas / hasta que ganes tiempo |
| 10 min session / then apps lock again | Sesión de 10 min / y se vuelve a bloquear |
| 12-day streak / Keep it going | Racha de 12 días / Sigue así |

The walking callout now uses **+40 min earned / +40 min ganados**, correcting the previous inconsistent +30 total. The existing session summary uses **3 apps / 3 seleccionadas**. Numeric labels are illustrative values formatted from app strings. Saturday/Sábado, the weekday initials and Sunday 07:00/domingo 07:00 represent calendar values. Sam, Alex/Álex and Maya are sample names, with streaks 12, 8 and 6; their weekly scores are 4/7, 3/7 and 2/7 days. Friends' streaks can remain visible from yesterday while today's status says no update, as in `FriendsView`.

## Presentation choices

- The hook combines the blocked-bench scene with the requested three earning routes. It is an editorial composition of existing features, not a pixel-for-pixel native screen.
- The exercise frame expands the earning entry into the four available exercise names and shows a photorealistic squat camera inset using `src/squat.png`. This AI-generated photograph matches the existing push-up image; it is not a claimed live camera capture.
- The ongoing friend challenge is the real weekly squad model. There is no invented accept/decline workflow or pending-challenge state.
- The old camera encouragement was replaced with the real `pushups.guidance.lower_body` string, **Lower a little more / Baja un poco más**.
- The supplied privacy claims are preserved verbatim. Friends does share opted-in progress summaries (including steps and earned minutes), as described by `friends.setup.shares`; review that scope when interpreting the broad privacy marketing copy.
