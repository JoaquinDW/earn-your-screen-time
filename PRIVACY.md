# Privacy Policy

Last updated: October 27, 2026

Earnit processes step counts on your device to calculate movement goals and screen-time credit. Raw HealthKit history is not sent to our servers or included in analytics. If you turn on Friends, a daily summary is shared as described below.

App selections are represented by opaque Apple Family Controls tokens and remain in the app's local App Group storage. Earnit cannot derive or upload the identity of selected apps from those tokens.

Subscription purchases are processed by Apple and managed through RevenueCat. Those providers process purchase and subscription information under their own privacy policies.

Study to Earn uses the camera only when you choose to scan study material. The photo is processed on your device with Apple's Vision framework and is not uploaded or saved by Earnit. The text extracted from the photo is sent to our Supabase backend and to OpenAI to generate and evaluate one study question. Your typed answer is sent to OpenAI for evaluation but is not stored in Earnit's database. OpenAI is instructed not to store API responses, although OpenAI may process or retain API data according to the data controls and legal obligations that apply to our account.

While a Study to Earn session is active, Supabase temporarily stores the extracted text, a generated reference answer, and evaluation criteria. This content is deleted when the session succeeds, is abandoned, or expires. Supabase retains an anonymous account identifier, entitlement status, session status and timestamps, and reward transaction records to enforce subscription access, daily limits, and duplicate protection. Earnit links the same anonymous identifier to RevenueCat for entitlement verification.

Pushups to Earn uses the rear camera only during a challenge. Apple Vision detects body-joint positions and counts repetitions entirely on the iPhone. Earnit does not record or save video, images, or body landmarks, and none of that camera data is uploaded. Supabase receives only the challenge target, completed repetition count, completion time, detector version, and anonymous session identifiers. It stores exercise session and reward transaction records to enforce Pro access, the UTC daily reward cap, expiry, and duplicate protection.

Friends is optional and off until you set it up. When you do, Supabase stores the display name you choose, a random invite code, and, for today and yesterday, your movement goal, step total, minutes earned and streak. People you add as friends, and members of squads you join, see your display name and those daily numbers; if you leave "Tell friends when I miss my goal" on, your friends are told once when a finished day falls short of your goal. Nudges, cheers and these notices are stored for delivery. If you allow notifications, your device's push token is stored so they can reach you through Apple Push Notification service. Earnit never shares which apps you protect or how you spend your minutes. "Stop using Friends" deletes your profile, friendships, squad memberships, shared days and notices from our server.

Product analytics must not contain raw HealthKit samples, Family Controls tokens, app names, bundle identifiers, health identifiers, study photos, extracted study text, learner answers, generated questions, answer keys, exercise camera frames, or body landmarks. Study and Pushups analytics use only operational events and coarse, non-identifying values such as challenge size or detector state.

Earnit uses Meta App Events to measure advertising performance, app launches, onboarding completion, and subscription conversions. Meta may process device, advertising, app-interaction, and purchase-event data for measurement and attribution. On supported Apple devices, Earnit asks for App Tracking Transparency permission before enabling access to the advertising identifier. Declining this permission does not limit app functionality; privacy-preserving attribution may still occur through Apple's SKAdNetwork.

Earnit uses PostHog for product analytics, to understand which onboarding screens people complete or abandon and how features like Study to Earn and Pushups to Earn are used. PostHog is not linked to your name, email, or Apple ID; it identifies your device with a randomly generated anonymous identifier. Only the same manually reviewed, privacy-safe events described above are sent, together with app lifecycle events (installed, opened, backgrounded, updated, with the app version) and crash reports (the error type and the app's stack trace, used to fix crashes). PostHog's automatic screen-recording and interaction-capture features are turned off, so no screen content, taps, or camera data reach it. The same anonymous identifier is shared with RevenueCat so that subscription events (a trial starting, converting, renewing or being cancelled) can be reported to PostHog for the same anonymous device.

You can revoke Health, Screen Time, and Camera permissions in iOS Settings. You can manage or cancel your subscription in App Store settings.

Questions about this policy can be submitted through the support contact listed on Earnit's App Store page.
