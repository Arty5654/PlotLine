# PlotLine audit: issues to fix

Findings from a full review of the iOS app and backend (2026-10-05). Each item says what's wrong, where, and how to fix it.
Tick items off as they're fixed. Priorities: **P0** security, **P1** broken or App Store blocker, **P2** looks wrong, **P3** cleanup.

How this was checked: code review, compiler warnings from a clean build, and the backend test suite. Signed-in screens were **not** viewed running (sign-up needs a real SMS code against the live server), so the dark-mode items come from the code. A debug-only screen preview mode would make visual checks possible.

---

## Pending setup (not code)

- [ ] **Sign in with Apple key on Fly.** Create a Sign in with Apple key (developer.apple.com → Keys), then:
  `fly secrets set APPLE_TEAM_ID=98PZUNW9C3 APPLE_KEY_ID=<id> APPLE_PRIVATE_KEY="$(cat AuthKey_<id>.p8)"`
  Until then, deleting an Apple account skips revoking Apple's access, which App Review may flag.
- [ ] **Deploy backend + app together.** The server now requires login tokens, so older app builds stop working against it.

---

## 1. Security (P0)

- [ ] **1. Server doesn't validate usernames at sign-up.**
  `backend/.../controller/AuthController.java` (`/auth/signup`) only rejects blank usernames. Storage keys are `users/<username>/...`, so a username like `bob/grocery` lands inside bob's folder, and deleting that account wipes `users/bob/grocery/` (bob's grocery lists).
  **Fix:** enforce `^[A-Za-z0-9]{3,30}$` on the server for every account-creating path (signup, Google, Apple). Apple sign-up already checks letters/numbers. Google derives the username from the email prefix and should be checked too.

- [ ] **2. No server-side password or email rules.**
  Same endpoint. The app enforces 8+ chars with upper/lower/number, but the API accepts anything.
  **Fix:** mirror `AuthViewModel.passwordRules` and the email regex on the server.

- [ ] **3. No rate limiting.**
  Sign-in can be brute-forced. `/sms/send-verification` is public (needed for password reset) and can be spammed to run up the Twilio bill.
  **Fix:** per-IP and per-account limits (e.g. Bucket4j) on `/auth/signin`, `/auth/*-signin`, `/auth/change-password*`, `/sms/*`. Consider Twilio Verify fraud guard / geo permissions.

- [ ] **4. Free trial can be restarted forever.**
  `PaymentController.claim` writes a fresh 30-day trial on every call unless the plan is `lifetime`.
  **Fix:** record `trialUsedAt` and refuse a second trial. Better: make App Store purchases the source of truth (see #5).

---

## 2. Broken or likely broken (P1)

- [ ] **5. Purchases never reach the server.**
  `PaymentAPI.syncAppleEntitlement` calls `/api/payments/apple/sync`, which doesn't exist; `StoreKitManager` uses `try?`, so the failure is silent. Nothing in the app is gated behind the subscription either, so the plan display is cosmetic.
  **Fix:** decide the paid features, add the sync endpoint (verify the signed transaction, or use App Store Server Notifications v2), and gate features on the server's status. Add a `.storekit` config file for local testing.

- [ ] **6. Widgets require iOS 26.1; the app supports iOS 18.2+.**
  `IPHONEOS_DEPLOYMENT_TARGET = 26.1` on the widget target. Users on iOS 18–25 get no widgets.
  **Fix:** lower the widget target to 18.2 unless it uses 26-only APIs.

- [ ] **7. Shared server-wide files lose concurrent updates.**
  `email-index.json`, `all-users.json` and `friends-feed/posts.json` are single files that are read, changed and rewritten on every update. Two at once means one is lost. The feed file also grows forever and is fully loaded on every feed view.
  **Fix:** one object per entry (e.g. `email-index/<email>.json`, `feed/<user>/<postId>.json`), or move these to a database (DynamoDB/Postgres).

- [ ] **8. Cold starts.**
  `backend/fly.toml` has `min_machines_running = 0`, so the first request after idle waits for the JVM and Spring to boot (often several seconds); sign-in feels broken.
  **Fix:** `min_machines_running = 1`, or a lighter startup.

- [ ] **9. Silent failures.**
  61 `catch` blocks only `print`, and 48 network calls use `try?`. Users see empty screens instead of errors.
  **Fix:** a shared error banner/toast and a pass through the main flows (budget, nutrition, grocery, goals, calendar, friends).

- [ ] **10. Calendar data race.**
  `ViewModels/CalendarViewModel.swift:358-366` mutates `colorIdx` / `newCalendars` from parallel tasks. Swift 6 will reject it.
  **Fix:** collect results from a `TaskGroup` and assign on the main actor.

---

## 3. App Store blockers (P1)

- [ ] **11. iPad orientation settings fail upload validation.**
  `TARGETED_DEVICE_FAMILY = "1,2"`, portrait only, without `UIRequiresFullScreen`.
  **Fix:** iPhone-only (`TARGETED_DEVICE_FAMILY = 1`). This is simplest, since the layouts aren't designed for iPad. The other option is proper iPad support.

- [x] **12. No privacy policy link in the app.** Done 2026-10-05. The backend serves `/terms` and `/privacy` (drafts in `backend/src/main/resources/legal/`), sign-up requires agreeing, and the links are on the welcome screen and in Profile.
  **Still to do:** fill in the highlighted placeholders (legal name, contact email, state), have a lawyer review, and put `<backend URL>/privacy` in App Store Connect. To change the terms later, edit the HTML and bump `LegalController.TERMS_VERSION`; everyone is asked to accept again.

- [x] **13b. Universal links use a different Team ID than the app.** Fixed 2026-10-05: Xcode now signs with the paid team `B96JRFHC45`, matching the universal-links file.
  `AppleAppSiteAssociationController.java` serves `TEAM_ID = "B96JRFHC45"`, but Xcode signs with `DEVELOPMENT_TEAM = 98PZUNW9C3`. If they don't match, `/invite` links and the Plaid OAuth redirect won't open the app.
  **Fix:** set it to the Team ID in developer.apple.com → Membership details (the one Xcode uses).

- [ ] **13. Permission text is incomplete or unused.**
  The camera description only mentions receipts, but the camera is also used for barcode scanning and food photos. `NSLocationAlwaysAndWhenInUseUsageDescription` is present, but only when-in-use location is used.
  **Fix:** broaden the camera text; remove the "always" location key.

---

## 4. Look and feel, light/dark (P2)

- [ ] **14. Invisible text in dark mode.**
  `Views/FriendProfileView.swift:270`: "No Trophies Yet!" is `.black` on a translucent gray box. **Fix:** `.secondary`.
- [ ] **15. White boxes in dark mode.**
  `Views/ContentView.swift:288` (dashboard "Due Today / Billed" badges) and `Views/ProfileView.swift:324` (the "Saved!" popup) use `Color.white`. **Fix:** `Color(.secondarySystemBackground)` or `.regularMaterial`.
- [ ] **16. White tab bar in dark mode.**
  `PlotLineApp.swift` sets the global tab bar background to white in dark mode (Investing and Grocery tabs). **Fix:** use the default/dark appearance; adjust icon colors if contrast was the original problem.
- [ ] **17. Two design languages.**
  41 of 66 screens don't use the shared card style. Profile is the most dated: 300pt-wide fields, capsule buttons, fixed-size Avenir fonts that ignore the user's text size setting. Others: Friends*, Calendar/Day, Goals, Subs, Payment, Stock*, TrophyHall, Meals, Chat.
  **Fix:** restyle these onto the shared components (see `Views/AuthComponents.swift` for the newest pattern).
- [ ] **18. Style tokens are duplicated 17 times.**
  `private enum PLColor / PLSpacing / CardModifier` is copied into 17 files. **Fix:** one shared `DesignSystem.swift`.
- [ ] **19. Fixed-size popup.**
  `Views/GroceryItemInfoView.swift:234` is `.frame(width: 360, height: 520)` and clips with larger text sizes or on an iPhone SE. **Fix:** flexible width, scroll if needed.

---

## 5. Code health (P3)

- [ ] **20. Deprecated APIs.** 31 old-style `onChange { _ in }`, 6 `NavigationLink(isActive:)` (`ContentView`, `ActiveGroceryListView`), 33 `NavigationView` (including sheets inside `NavigationStack`, which causes odd titles and back buttons).
- [ ] **21. Dead code.** `PlaidView`, `SpendingPeriodView`, `ReactionBubble`, `WatchlistView` (commented out of `InvestmentHomeView`), backend `OCRService` (Mac-only path; receipts use GPT-4o) and the `tess4j` dependency.
- [ ] **22. Repo junk.** Duplicate `PlotLineWidgets/` at the repo root (Xcode uses `PlotLine/PlotLineWidgets/`), `backend/target 2/`, tracked `.DS_Store`.
- [x] **23. CI only runs grocery tests.** Done 2026-10-05, see "Testing" below. `.github/workflows/grocery-tests.yml` runs `Grocery*Test`. Add the auth, security, deletion and Apple tests (`./mvnw test` minus `BackendApplicationTests`, which needs real env vars).
- [ ] **24. Logging.** 223 `System.out.println`/`printStackTrace`. **Fix:** SLF4J with levels.
- [ ] Other compiler warnings: unreachable `catch` in `DietaryRestrictionsAPI.swift:93`, non-Sendable capture in `MealsAPI.swift:58`, main-actor mutations in the Google sign-in callback (`AuthViewModel.swift` ~188-202), unused results.

---

## 6. Feature ideas

- **First-run checklist:** budget quiz → link bank → first goal → add friends.
- **Server push notifications** (none today): friend requests, shared list and calendar invites, weekly "you've spent X of your budget" recap.
- **Student loan / debt payoff planner:** payoff date, avalanche vs. snowball.
- **Savings goals + emergency fund tracker** tied to the budget, plus a simple net-worth view.
- **First-job tools:** paycheck to take-home calculator, 401(k) match explainer, rent affordability check.
- **Roommate expense splitting** (Splitwise-style) on the friends system, alongside shared grocery lists.
- **Face ID app lock** and hiding balances in the app switcher.
- **Apple Health integration** for nutrition and activity.
- **Siri shortcuts and interactive widgets:** "log $12 lunch", log a food, check off a goal from the widget.
- **Export my data (CSV)**, alongside account deletion.
- **In-app support / feedback link.**

Suggested order: 1–4 → 5, 11–13 → 14–16 → 9 → the rest.

---

## Testing

**CI:** `.github/workflows/tests.yml` runs on every PR (and each new commit on it), on pushes to `main`, and manually from the Actions tab.
- **Backend job (Ubuntu):** runs **all** Java tests (`./mvnw test`) with throwaway dummy env vars. Storage is in-memory and OpenAI/Twilio/Plaid are faked, so no real secrets are needed and nothing touches production.
- **iOS job (macOS, free for public repos):** builds the app with placeholder settings (the real `Config.xcconfig` stays gitignored) and runs the Swift unit tests on the newest iPhone simulator.
- **Report job:** posts one "Test results" comment per PR, with pass/fail per area for backend and iOS, failing tests listed, and known-bug skips. It updates in place on each push. The summary logic is in `.github/scripts/test_summary.py`.
- Replaces the old `grocery-tests.yml`.

| Area | Backend | iOS |
|---|---|---|
| Sign in / sign up / Apple / Google / terms / phone gate / deletion / security | ✅ 79 | ✅ 8 |
| Calendar (events, invites, sharing, approvals) | ✅ 9 | ✅ 4 |
| Budget / spending / subscriptions / receipts / recurring charges / Plaid | ✅ 11 (+1 known bug) | ✅ 6 |
| Investing (portfolio, rating, watchlist) | ✅ 5 | ✅ 4 |
| Nutrition / meals / dietary restrictions | ✅ 6 | ✅ 5 |
| Friends / requests / goal feed / chat | ✅ 5 | ✅ 4 |
| Profile / trophies / membership | ✅ 5 | ✅ 2 |
| Goals (weekly + long-term) | ✅ 3 (+1 known bug) | ✅ 2 |
| Grocery lists | ✅ 50 | ✅ 2 |
| App startup | ✅ 1 | |

Totals: **backend 176 tests (174 pass, 2 skipped as known bugs), iOS 37 tests.**

**Where things live**
- Backend feature tests: `backend/src/test/java/com/plotline/backend/features/`. These boot the whole backend against in-memory S3 and go through the real login and ownership checks. Shared helpers are in `FeatureTestBase`.
- iOS unit tests: `PlotLine/PlotLineTests/`, one file per area.

**Changes made to make this work**
- `S3Service`, `WeeklyGoalsService`, `LongTermGoalsService`, `FriendsFeedService`, `S3TokenStore` and `S3PlaidCursorStore` now use the shared S3 client from `AWSConfig` instead of each building their own. Production behavior is the same.
- **Fresh clones couldn't build the app** (found by rehearsing CI on a clean copy):
  - The widget's `Info.plist` was gitignored by `**/Info.plist`; there's now an exception for it.
  - `Preview Content/Preview Assets.xcassets` was an empty folder git couldn't store; it now has the standard `Contents.json`.
- Test doubles behave like real S3: 404 with a `NoSuchKey` error code, and only the declared content length is stored.

**Not covered:** iOS UI tests (screen tapping), Google sign-in against Google's real token check, Plaid flows that need a real bank link, widgets, and notifications.

### Bugs found while writing tests
Tracked separately in [BUGS.md](BUGS.md) and not fixed yet (on hold until the CI work is done).
