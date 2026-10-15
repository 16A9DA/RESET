# RE:SET AI

Personal health, fitness, nutrition, sleep and recovery app for iPhone. Phone collects data. Rules turn it into daily guidance. AI helps interpret food and chat.

## Overview

Native SwiftUI app, local first. No account. Works without a wearable. Built for someone who works about eight hours, attends university, wants to lose body fat and keep muscle, and drinks energy drinks.

Status, stated plainly:

* Written and unit tested on a Mac without Xcode. The iOS app was never built in Xcode, never run in a simulator, never run on an iPhone.
* Core logic is tested: 162 Swift tests in `ResetCore`, 25 pytest tests for the backend.
* App and widget targets pass an approximate type check (`scripts/typecheck-app.sh`). That script swaps SwiftData for a stub and uses Mac Catalyst frameworks. It is not a build.
* AI features were never run against a live model. Anthropic request shapes were checked against current docs. The OpenAI and compatible adapters follow the documented Chat Completions format and are covered by stub tests only (see section 7).
* Nutrition clients (USDA, Open Food Facts barcode, Open Food Facts text search) were checked against live responses.

Expect a few Xcode build errors on first open. Fix or report them.

## Assumptions

* No age, sex or fitness level assumed. Starting values 103 kg and 188 cm are editable defaults.
* Without age, calorie estimates show "Estimate unavailable". Entering own maintenance calories unlocks them.
* Without sex, a general midpoint of the Mifflin St Jeor constants is used and labeled.
* Activity multiplier already covers habitual walking and training. Logged workouts are never added on top.
* Deficit defaults to 15 percent, capped at 500 kcal, never below resting energy or 1200 kcal.
* Protein defaults to 1.6 g per kg of target weight (or current weight). Adjustable.
* Water goal starts near 30 ml per kg, clamped 1.5 to 3.5 L. Adjustable, or off with the fluid restriction setting.
* Bundle id `com.reset.ai` is a placeholder. Change it.
* Minimum iOS 17 (SwiftData, CLMonitor, Observation).

## 1. What the app does

Five tabs: Today, Activity, Nutrition, Insights, Coach. Settings and profile open from Today.

* Today: one priority sentence, nine quick actions, recovery, sleep, energy, steps, activity, water, caffeine, food, work and university hours, upcoming reminders, workout, timeline. Missing data reads "Not recorded", "Permission required" or "Estimate unavailable". Nothing is invented.
* Work and university time: geofenced places, estimated presence kept apart from confirmed time, breaks, manual timer, review list, editor, day, week, month totals.
* Activity: steps and distance from Health or the motion sensor, weekly chart, imported workouts, walk timer, manual workouts, no double counting of overlapping reports.
* Food: describe in words, photograph, search USDA and Open Food Facts, scan barcode, manual entry, saved meals, recents. Estimates stay labeled. Duplicate guard. Edit and delete.
* Meal ideas: a What to eat card suggests meals for the slot, place (cafeteria, home, quick) and time you have, using remaining calories and protein, your diet words and allergies. Works with no AI. Portions are typical estimates.
* Purchases: paste receipt text, photograph a receipt, or send text through a Shortcut. Items wait as drafts until you say you ate them. Prices, totals and card numbers are stripped and never stored. Optional rules only prefill the food box.
* Widget: small and medium home screen widget with today's water, calories and protein, and plus buttons for water.
* Calories and protein: Mifflin St Jeor, moderate capped deficit, balance against maintenance, weight log and trend, maintenance suggestion from own data, option to turn calorie counting off.
* Water: quick buttons, custom amounts, goal, reminders inside waking hours, notification actions, Siri and Shortcuts action.
* Caffeine: drinks catalog with source notes, saved drinks, daily total, estimated remaining range, late cutoff reminder, symptom safety message.
* Meals: slots from wake and bed times and your own pattern. "Have you eaten recently?" asks, never assumes. Neutral evening summary.
* Sleep: bedtime from wake time, wind down, manual log with quality, optional Health import, trend.
* Workouts: strength, walking, mobility, rest. Chosen by recovery, symptoms, time, equipment, level, recent sessions. Missed gym suggests a kind walk. Load only rises after completed sessions.
* Recovery: transparent rule based indicator with reasons. Not a measurement.
* Coach: chat that reads your data through a fixed tool set. Works partly offline for simple questions.
* Insights: cautious pattern cards with observation counts. Export to JSON and CSV.
* Privacy: what stays local, what AI use sends, granular deletion, full reset.

## 2. Architecture

```
RESET.xcodeproj      hand written project, synchronized folders, local package
RESET/               iOS app target
  App/               entry point, tab router
  Models/            SwiftData models, session adapters
  Services/          location, Health, notifications, Keychain, AI config
  Features/          Today, Activity, Nutrition, Insights, Coach, Sleep, Time, Recovery, Settings, Onboarding
  Intents/           Log water and Add purchase text Shortcuts
RESETWidgets/        home screen widget extension
Shared/              code compiled into both the app and the widget
ResetCore/           Swift package, no platform dependencies
  Sources/           energy, sessions, activity, food, nutrition clients, AI providers, caffeine,
                     hydration, meal timing, sleep, recovery, workouts, insights, coach, reminders
  Tests/             Swift Testing suites
backend/             optional FastAPI proxy
scripts/             test runner, approximate type check
```

Rule: arithmetic, timestamps, totals and validation live in `ResetCore` and are tested. The app maps stored records to core values and renders them. Language models only interpret text and photos, and chat.

Widget data flow: the app publishes a small snapshot into an App Group. The widget only reads it. Button taps are queued there and turned into water records the next time the app opens, so the widget never touches the database.

Model deviations from the spec list: `WorkSession` and `UniversitySession` are one `TrackedSession` with a category. `EnergyCheckIn` and `FatigueCheckIn` are one `CheckIn` with a kind. `NutritionEstimate` is the `Nutrition` value inside each `FoodItem`. `DailySummary` is computed on demand so it never goes stale.

## 3. Open in Xcode

Needs Xcode 16 or newer on a Mac.

```
open RESET.xcodeproj
```

1. Select the RESET target, Signing and Capabilities, choose your Team.
2. Change the bundle identifier to something unique.
3. Confirm the HealthKit capability is present. The entitlement file is `RESET/RESET.entitlements`.
   Add the App Groups capability to BOTH the RESET and RESETWidgets targets with the group `group.com.reset.ai`. If you change the bundle id, change the group in `Shared/WidgetShared.swift` and in both entitlement files, and set the widget bundle id to `<app id>.widgets`. Without it the app works and the widget shows "Open RE:SET".
4. Confirm Background Modes shows Location updates and Background fetch.
5. Add an app icon in an asset catalog. None is included.
6. Build for an iPhone or the simulator.

The project file is hand written and untested. If Xcode rejects it, create a new iOS App project named RESET (SwiftUI, SwiftData off), delete its generated sources, drag the `RESET` folder in, add `ResetCore` as a local package, and copy `Info.plist` keys and the entitlements across.

Core tests without Xcode:

```
scripts/test-core.sh
```

With Xcode: `cd ResetCore && swift test`.

## 4. Location permissions

Usage strings are in `RESET/Info.plist`. Flow: open Today, Settings, Places and location, add a place by tapping the map or using the current location. The app asks for While Using first, then Always when a place is saved. Always is what lets iOS wake the app for arrivals.

* Denied or restricted: the Places screen explains and offers Open Settings. Manual timer and editing keep working.
* Location Services off: shown on the same screen.
* Only region monitoring is used. No continuous GPS, no route history. Place events are pruned after 30 days.

## 5. HealthKit

Entitlement and usage strings are included. In the Activity tab press Connect Apple Health. The app reads steps, walking and running distance, workouts, sleep and body mass. It writes only walks you time in the app.

* Health denied: steps fall back to the iPhone motion sensor. Sleep stays manual.
* Health does not reveal which types you denied. If a card shows no data, check Settings, Health, Data Access.
* HealthKit is unavailable on iPad and some simulators.

## 6. Notifications

Allow them in Settings, Reminders, or when first prompted. Nine categories, each with its own switch: water, meals, bedtime, wake, late caffeine, movement, walk, workout prep, check-in. Water, meals, bedtime and caffeine are on by default. The rest are off.

* Water and meal notifications have actions: Log 250 ml, Snooze, Not hungry, Eating later.
* Reminders stay inside waking hours, keep minimum gaps, and are not repeated when missed.
* "Wake up" is a notification, not an alarm. Keep your alarm app.
* Denied permission: Settings explains and links to iOS Settings.

## 7. AI credentials

Open Settings, AI and data sources. Keys go into the iOS Keychain on the phone. Nothing is stored in source, the bundle or UserDefaults.

Pick one of four providers. Each keeps its own key and model, so you can switch freely. Save and test connection sends one tiny request and reports problems in plain words.

* Anthropic: key plus model. Default model id `claude-sonnet-5-5`, editable. Uses the Messages API.
* OpenAI: key plus a model name you choose. No default is supplied, because OpenAI model names change and the model must accept images and tools. The app sends `max_completion_tokens` (OpenAI deprecated `max_tokens`). Some reasoning models reject function tools; if the coach or Test fails, try a non reasoning model.
* Other OpenAI compatible (xAI and similar): base URL, key, model. Sends `max_tokens`. xAI documents a `/v1/responses` API on its main reference page, which this option does not use. Confirm the endpoint, model and image support with your provider.
* RE:SET backend proxy: URL and token. Recommended for anything beyond personal testing, because the provider key then stays on your server. The server supports Anthropic and OpenAI.

Backend setup:

```
cd backend
cp .env.example .env     # set AI_PROVIDER, the provider key and model, and PROXY_TOKENS
uv run uvicorn app.main:app --host 0.0.0.0 --port 8000
```

The server reads `backend/.env`, then the repository root `.env`, and never prints values. It accepts the common misspelling `ANTROPIC_API_KEY` with a warning. For OpenAI set `OPENAI_API_KEY` and `OPENAI_MODEL`. `PROXY_TOKENS` is required, otherwise the server refuses requests.

Serve it over HTTPS (reverse proxy or a platform that terminates TLS). The app accepts http only for testing.

Without any key, manual logging, barcode, USDA search and all non AI features work. The coach answers simple data questions locally (water, calories left, protein, steps, work hours, bedtime).

## 8. Nutrition data

* USDA FoodData Central: text search and AI lookups. Free key from fdc.nal.usda.gov, added in Settings. Without one the shared `DEMO_KEY` is used, limited to about 30 requests per hour per IP. Public domain data.
* Open Food Facts: barcode lookup through API v2, and text search through Search-a-licious (search.openfoodfacts.org), because API v2 has no full text search. Products without nutrition data are skipped. Reads are rate limited. Data licence ODbL, attribution shown in the app. Branded AI items check this database first.
* AI estimates are used only when no database match exists, and are labeled "AI estimate, not from a database".
* Branded product values should be checked against the label. Cafeteria portions are always estimates.

## 9. Install on an iPhone

1. Connect the iPhone, enable Developer Mode (Settings, Privacy and Security).
2. In Xcode choose the device, then Run.
3. Trust the developer profile in Settings, General, VPN and Device Management if asked.
4. A free Apple ID works but the install expires after seven days.

## 10. Works offline

Logging food manually, saved meals, recents, water, caffeine, sleep, check-ins, weights, workouts, recovery, timeline, insights, export, work and university tracking, geofence events, step reading, meal and water reminders already scheduled, coach answers to simple data questions.

## 11. Needs external credentials or services

* AI food description, food photo analysis, coach conversation: provider key or proxy.
* USDA search at a reasonable rate: free USDA key.
* Barcode lookup and product text search: internet, no key.
* Proxy: your own server and shared token.

## 12. Needs a physical device and permissions

* Geofence arrivals and departures: real iPhone, Always location.
* Steps and sleep import: Health permission, real iPhone for useful data.
* Camera meal photos, receipt photos and barcode scanning: real iPhone, camera permission. The simulator has no camera.
* Notifications: permission. Delivery timing is easiest to judge on a device.
* Siri, Shortcuts and the home screen widget: device with the app installed and the App Groups capability enabled.

Nothing in this repository has been verified on a physical iPhone.

## 13. iOS background limitations

* Region monitoring events can arrive late, be coalesced, or be missed, for example after a reboot, low power mode, or if Always permission is revoked. Times are estimates. Missed exits become "Needs review" sessions, never silently dropped.
* Being inside a place does not prove you were working. Detected time is labeled an estimate until you confirm or edit it.
* iOS runs no app code when a notification fires. The app plans the next day or two ahead, up to 60 requests, and replans when opened, after logging, and during best effort background refresh. Refresh timing is up to iOS.
* Phone step counts miss activity when the phone is not carried.
* The phone cannot detect sleep. Sleep is what you enter or what other devices write to Health.
* Force quitting the app stops background launches until it is opened again.

## 14. Remaining setup and known gaps

Setup:

* Open in Xcode, set Team and bundle id, add an app icon, build, fix any errors.
* Add AI key or proxy. Add a free USDA key.
* Add places, grant Always location, connect Health, allow notifications.

Not implemented:

* Share sheet extension target. The Shortcuts route (Add purchase text with Show in Share Sheet) covers sharing text without a separate extension.
* Phone based sleep detection. Deliberately omitted because it is unreliable.
* Meal ideas are a fixed catalog with typical portions, not personalised recipes. Ask the coach with AI on for something freer.
* Automated UI tests. Only core and backend logic is tested.

Known risks:

* Hand written project file, now with two targets (app and widget). Untested: SwiftData macros, `CLMonitor` event handling, Health queries, notification actions, widget refresh and App Group sharing on real hardware.
* AI JSON replies are validated strictly, but real model behavior was not observed. Expect prompt tuning.
* Caffeine values in the drinks catalog come from public secondary sources and are marked "typical, check your can".

Not medical advice. Calories, energy use, recovery, sleep and food photo results are estimates. Seek medical care for chest pain, fainting, severe palpitations or breathing trouble.
