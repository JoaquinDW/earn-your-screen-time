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
