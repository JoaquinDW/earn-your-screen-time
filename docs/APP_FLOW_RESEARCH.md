# App flow research — October 2026

Appllama was used to review the home, focus, rewards, app-selection, and unlock journeys of revenue-ranked screen-time apps. Screen references below are durable Appllama IDs; their image URLs expire.

| App | Screens studied | Pattern relevant to Earnit |
| --- | --- | --- |
| BePresent (`1644737181`) | Home `oth_b5td4`, `oth_48xsx`, `oth_w1rw4`; focus `oth_jcgx7`, `oth_pmj7g`, `oth_c24fd`, `oth_jhl03`; app lists `oth_jcuvd`, `oth_olv1y`, `oth_irbex` | A clear daily status and primary action lead into a short configuration sheet. The active state shows a large timer and an explicit exit. |
| Opal (`1497465230`) | Dashboard `oth_jsci1`, `oth_gbmxf`, `oth_fftm0`, `oth_ostgu`; timer `oth_og7u1`, `oth_kescp`, `oth_bxcas`, `oth_81yhu`, `oth_7sj6g`, `oth_hmfqx`, `oth_p2341`, `oth_9chg9` | The timer setup keeps duration, blocked apps, and Start close together. The active timer is a distinct state, not an ambiguous status badge. |
| Forest (`866450515`) | Timer `oth_f0nwr`, `oth_nuoj5`, `oth_yl3ki`, `oth_ulvsr`, `oth_rgq2f` | A single large readout and one main action give the daily loop a clear center. |
| Blockin (`1659162950`) | Unlock `oth_fvvnr`, `oth_p7mcc`, `oth_labqk`, `oth_n2e7p`, `oth_1j55k`; Home `oth_419cq`, `oth_ghr9v`; setup `oth_ma0cy`, `oth_gxb7q`, `oth_iorl8`, `oth_b6k6z`, `oth_j6uak`, `oth_f17mr` | Unlock is presented as a deliberate choice with an explicit duration and completion state. |
| AppBlock (`1515753232`) | Insights `oth_t0fig`, `oth_lmr4b`, `oth_adguk`, `oth_bluy4`, `oth_e1iw9` | Progress views prioritize a large total and a small number of supporting measures. |
| BePresent (`1644737181`) | Onboarding `onb_j1heb`, `onb_92b26`; paywall `pay_npknu` | Questions keep Back beside progress at the top. The permission step explains its purpose before requesting access. The paywall pairs plan choices with the trial timeline and purchase action. |
| Opal (`1497465230`) | Onboarding `onb_t4sye`; paywall `pay_2ztwr` | One focused question appears per step. The paywall shows trial timing, plan options, and a clear action in one journey. |
| Pushscroll (`6741765734`) | Paywall `pay_3vrws` | A compact plan choice and prominent subscription action make the price decision easy to find. |

## What we applied

- Home makes the next action depend on the actual state: earn when empty, choose apps when none are selected, and use minutes when both credit and selection are ready.
- The next step milestone remains visible, with a direct route to the earning methods.
- The access sheet previews the balance after the chosen duration and names the number of affected apps before the user starts the wall-clock window.
- The existing Study to Earn journey is reachable from the earning screen, with the same Pro gate as the service.
- Peer tabs crossfade instead of sliding as if they were navigation destinations.
- Onboarding keeps Back and progress in a fixed header; the opening illustration now makes one concrete earn-rate promise.
- The Apple Health estimate path says where to connect later, and the Earn screen offers that connection before showing step rewards.
- The paywall keeps the purchase action and selected plan terms visible, shows both plans together, and shows a trial timeline only when StoreKit confirms eligibility.
- Trial-eligible plans state that the first three days have no charge, identify the price after the trial, and say when to cancel to avoid that charge.

We retained Earnit's dark illustrated scenes and cobalt action color. A new mascot or video would introduce a second visual language without improving the earn-to-unlock decision.

## Widgets and notifications — October 2026

Second Appllama pass, for retention: in 1.2.2–1.3.0 almost nobody returned on a second day.

| App | Screens studied | Pattern relevant to Earnit |
| --- | --- | --- |
| BePresent (`1644737181`) | Widget `onb_a9gaj`; notifications `onb_i2lf0` | One screen: "Put your streak on your home screen", a large preview of the real small widget, "Add the widget" / "Not now". The notification primer shows a sample push ("Opening Instagram for 5 min") behind the system alert. |
| Duolingo (`570060128`) | Widget `onb_l7pig`; reminder `onb_4gjdy`; notifications `onb_yzz8f`, `onb_v2a21` | The widget is offered right after the notification step. Both are framed as "I'll remind you / cheer you on", with the widget preview as the picture. |
| Bend (`1513988468`), Hybrid Calisthenics (`6444292787`) | `onb_6k9c0`, `onb_bvpi6`; `onb_trjs5` | The widget's one number is the streak. The screen has an "Add widget" button and a skip option. Bend asks for the reminder time just before. |
| One Year Journal (`6740510762`), Moonlitt (`6444718902`), I am (`874656917`) | `onb_d900e`; `oth_1p8av`; `onb_7kzzy`, `oth_hg30b` | iOS cannot add a widget for you, so the "Add" action becomes numbered steps: hold the Home Screen, tap Edit → Add Widget, search for the app. |
| AppBlock (`1515753232`) | `onb_iwz9b`, `onb_t2qoa` | "We'll notify you when it matters", with three stacked sample pushes about blocks and progress, and "You can change this anytime in Settings". |
| Jomo (`1609960918`), Blockin (`1659162950`), Forest (`866450515`) | `onb_nq886`, `oth_qlmn9`; `onb_hc5g0`; `onb_l0wqy` | Sample pushes name the moment ("Unlock ending soon!", "5 minutes left until Instagram is blocked"). "No spam, just useful reminders." Jomo keeps reminders next to the daily goal in settings. |
| Lyfta (`6443740936`), 5 Minute Journal (`1062945251`), Rosebud (`6451135127`) | `onb_75y11`; `onb_9a4dh`; `onb_vdwff` | The person picks the reminder time during onboarding, with a toggle and time pill. |

Not in the library: Brick, Clearspace, Roots, Stepz. No widget screens from Opal, AppBlock, one sec, Forest, StepsApp or Pedometer++.

### What we applied

- The onboarding notification step shows Earnit's three real notifications ("+5 min earned", steps left to today's goal at the chosen time, "1 minute left") and a time picker for the daily walk reminder.
- New notifications: minutes earned while the app is closed (HealthKit background delivery, at most hourly), and a daily walk reminder worded from today's actual progress. The reminder is skipped once the goal is met and is adjustable in Settings. When it is on, it replaces the day-1 inactivity nudge.
- A wallet widget for the Home Screen (small and medium) and the Lock Screen (circular, rectangular and inline). It shows minutes ready, steps to the next reward, the streak, and a countdown during an unlock.
- The widget is offered once, after the first minutes are earned, so the preview shows a real number. The preview is the actual widget view, followed by numbered add steps. It can also be opened again from Settings.
