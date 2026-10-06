# PlotLine bugs found by tests

Bugs the new automated tests turned up. **None are fixed yet.** Each one has a test that's
disabled (marked `@Disabled("Known bug: BUGS.md #N")`) so CI stays green. Fix the bug, delete
the `@Disabled` line, and the test guards against it coming back.

General issues and improvements are in [AUDIT.md](AUDIT.md).

| # | Area | Bug | Test |
|---|---|---|---|
| 1 | Budget / all saving | Data with accents or emoji gets cut off when saved | `BudgetSpendingFeatureTest.nonAsciiCategories` |
| 2 | Calendar | Event invites aren't limited to friends | none yet |
| 3 | Calendar | Placeholder string added to every invite list | none yet |
| 4 | Goals | Editing a weekly goal with a due date always fails | `GoalsFeatureTest.editWeeklyGoal` |

---

## 1. Data with accents or emoji gets cut off when saved

**What happens:** saving a budget with a category like `Café ☕` or `🍕 Food` stores a broken file, and the budget can't be read back.

**Why:** `S3Service.uploadFile(key, stream, contentLength)` sends exactly `contentLength` bytes to S3. Almost every caller passes `json.length()`, the number of *characters*, but accents and emoji take 2–4 bytes each, so the end of the JSON is dropped. 18 call sites go through `uploadFile` (budgets, subscriptions, spending, costs, portfolio, watchlist, recurring charges, category overrides...).

**Fix:** in `S3Service.uploadFile`, read the stream into bytes and upload those (`RequestBody.fromBytes`), ignoring the passed length. That fixes every caller at once. Or pass `json.getBytes(UTF_8).length` everywhere.

**Test:** `BudgetSpendingFeatureTest.nonAsciiCategories` (the in-memory S3 used in tests stores only the declared length, like real S3).

## 2. Calendar event invites aren't limited to friends

**What happens:** `CalendarService.createEvent` adds a pending invite to the calendar of anyone listed in `invitedFriends`, whether or not they're friends. Anyone can spam invites onto a stranger's calendar.

**Fix:** only invite usernames on the creator's friend list (skip or reject the rest).

## 3. Placeholder string added to every invite list

**What happens:** `createEvent` appends the literal string `"c-123-creator-user-c-987"` to `invitedFriends` and counts friends invited as `size() - 1` for the "friends invited" trophy. The placeholder is saved with the event and sent to the app.

**Fix:** track the creator in its own field and drop the placeholder.

## 4. Editing a weekly goal with a due date always fails

**What happens:** `PUT /api/goals/{username}/{taskId}` returns 500 "Failed to update goal." for any goal that has a due date, so editing goals in the app fails.

**Why:** `WeeklyGoalsService.updateGoalInS3` reads the saved goals with a plain `new ObjectMapper()` (line ~198). Adding and completing goals use one with `JavaTimeModule` registered, but this one can't read the `LocalDate` due date and throws `InvalidDefinitionException: Java 8 date/time type java.time.LocalDate not supported by default`.

**Fix:** add `objectMapper.registerModule(new JavaTimeModule());` in `updateGoalInS3` (and ideally share one configured `ObjectMapper` across the service).

