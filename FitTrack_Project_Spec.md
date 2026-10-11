# FitTrack: Gym Workout Tracker

**Platform:** Mobile (iOS + Android) · **Stack:** Flutter (Dart), Firebase Authentication, Cloud Firestore
**Document status:** Build-ready spec v1.0 (MVP)

---

## 1. Overview

FitTrack is a mobile app where users create an account, build a weekly gym schedule (Push, Pull, Leg, Upper Body, Lower Body, or custom days), see today's workout the moment they open the app, and check off exercises as they complete them.

**Core loop:** open app → see today's workout → do it → mark complete → see progress.

### 1.1 Goals

| # | Goal | How we know it's met |
|---|------|----------------------|
| G1 | Secure authentication | Users can register, log in, reset password, log out; data is only readable by its owner |
| G2 | Easy schedule creation | A user can create a workout day and assign it to weekdays in under 2 minutes |
| G3 | Clear "today" view | Dashboard shows today's workout (or a rest-day state) with no extra taps |
| G4 | Progress tracking | Users can mark exercises/workouts complete and see their history and streak |

### 1.2 Non-goals for MVP

Keeping these out keeps the first build small and shippable:

- Social features, sharing, leaderboards
- Exercise video library or AI-generated plans
- Wearable / HealthKit / Google Fit integration
- Payments or subscriptions
- Web or tablet-optimized layouts

(See [Section 13](#13-roadmap-beyond-mvp) for what comes later.)

### 1.3 Target user

Gym-goers who follow a split routine (e.g., Push/Pull/Legs) and currently track it in notes apps or spreadsheets. They want something fast to use between sets, with large tap targets and minimal typing.

---

## 2. User Stories & Acceptance Criteria

### Authentication
- **US-1** As a new user, I can register with email and password.
  - Validates email format and password (min 8 chars).
  - Shows clear errors for "email already in use" and weak password.
  - On success, user lands on the Dashboard.
- **US-2** As a returning user, I can log in and stay logged in between app launches.
- **US-3** As a user who forgot my password, I can request a reset email.
- **US-4** As a user, I can log out from Profile and am returned to Login.

### Workout schedule
- **US-5** I can create a workout day with a name, category, and a list of exercises (name, sets, reps, optional weight, optional notes).
- **US-6** I can assign a workout day to one or more weekdays.
- **US-7** I can edit or delete a workout day (delete asks for confirmation).
- **US-8** I can reorder exercises within a workout day.
- **US-9** I can start from a template (Push, Pull, Legs, Upper, Lower) so I'm not starting from a blank screen.

### Today & tracking
- **US-10** On the Dashboard I see today's workout(s) and its exercises, or a rest-day message with a shortcut to the schedule.
- **US-11** I can tick off individual exercises while training.
- **US-12** I can tap "Complete Workout" to save it to my history (even if not every exercise was ticked).
- **US-13** I can see a history of completed workouts and my current weekly streak.
- **US-14** I can undo a completion made by mistake (same day).

### Profile
- **US-15** I can view and edit my display name, and see my email.
- **US-16** I can choose weight units (kg / lb).
- **US-17** I can delete my account and all my data.

---

## 3. Feature Specification

### 3.1 Authentication (Login & Registration)
- Email + password via Firebase Authentication.
- Auth state drives routing: signed out → Login; signed in → Home.
- Password reset via `sendPasswordResetEmail`.
- Friendly error mapping (don't show raw Firebase codes):

| Firebase code | Message shown |
|---|---|
| `invalid-email` | Enter a valid email address. |
| `user-not-found` / `wrong-password` / `invalid-credential` | Email or password is incorrect. |
| `email-already-in-use` | An account with this email already exists. |
| `weak-password` | Password must be at least 8 characters. |
| `network-request-failed` | No connection. Check your internet and try again. |
| `too-many-requests` | Too many attempts. Try again later. |

- *Optional post-MVP:* Google / Apple sign-in.

### 3.2 Dashboard (Home)
- Greeting + today's date.
- **Today card:** workout name, category chip, exercise count, progress bar (e.g., 3/6 done), and a primary **Start / Continue** button.
- **Rest-day state:** "Rest day. Nothing scheduled." plus a button to the Schedule.
- **Multiple workouts in one day:** shown as stacked cards.
- **Completed state:** card shows a check and the completion time.
- **Weekly strip:** Mon–Sun dots showing scheduled vs completed days.
- **Streak:** consecutive weeks where all scheduled workouts were completed.

### 3.3 Workout Schedule
- Weekly view (Mon–Sun) listing the workout assigned to each day.
- Tap a day to assign, change, or clear its workout.
- "My Workouts" list of all created workout days with a **+ New Workout** button.
- Categories: `push`, `pull`, `legs`, `upper`, `lower`, `custom`.

### 3.4 Workout Details
- Header: name, category, assigned days.
- Exercise list with sets × reps and weight.
- **Edit mode:** add, remove, reorder (drag handle), edit exercise fields.
- **Session mode** (when started from the Dashboard): checkbox per exercise, optional per-set weight/reps override, a running timer, and a **Complete Workout** button.

### 3.5 Workout Tracking
- A *log* is created when the user taps Complete Workout.
- Logs store a **snapshot** of the workout (name + exercises as performed), so editing a plan later never rewrites history.
- One log per workout per date (deterministic ID prevents accidental duplicates).
- History screen: reverse-chronological list, grouped by week, tap for details.

### 3.6 Profile
- Display name (editable), email (read-only).
- Units toggle (kg/lb).
- Log out, Delete account (re-authentication required).
- App version.

---

## 4. Screens & Navigation

### 4.1 Screen list

| Screen | Route | Auth required |
|---|---|---|
| Splash / auth gate | `/` | No |
| Login | `/login` | No |
| Registration | `/register` | No |
| Forgot Password | `/forgot-password` | No |
| Home Dashboard | `/home` | Yes |
| Workout Schedule | `/schedule` | Yes |
| Workout Details (view/edit) | `/workouts/:id` | Yes |
| Workout Editor (create) | `/workouts/new` | Yes |
| Active Session | `/workouts/:id/session` | Yes |
| History | `/history` | Yes |
| Profile | `/profile` | Yes |

### 4.2 Navigation structure

```
Auth flow (signed out)
 ├─ Login ──► Registration
 │     └────► Forgot Password
 
Main app (signed in) — bottom navigation bar
 ├─ Home ──► Active Session
 ├─ Schedule ──► Workout Details ──► Workout Editor
 ├─ History ──► Log Details
 └─ Profile
```

Use `go_router` with a redirect that reads auth state so deep links and back-navigation behave correctly.

### 4.3 UX requirements
- Light and dark theme (follow system).
- Minimum 48×48 dp tap targets; session screen designed for one-handed use.
- Every async screen has loading, empty, and error states.
- Form validation on blur and on submit; keyboard-aware layouts.
- Works offline for reads and writes (Firestore persistence), syncing when back online.

---

## 5. Data Model (Cloud Firestore)

All user data lives under the user's own document, so security rules are simple and queries are cheap.

```
users/{uid}
  ├─ workouts/{workoutId}
  └─ logs/{logId}
```

### 5.1 `users/{uid}`

| Field | Type | Notes |
|---|---|---|
| `displayName` | string | |
| `email` | string | Copy of auth email |
| `units` | string | `"kg"` or `"lb"` (default `"kg"`) |
| `weeklySchedule` | map | `{ "1": ["workoutId"], ... "7": [] }` — ISO weekday 1 (Mon) to 7 (Sun) → list of workout IDs |
| `createdAt` | timestamp | Server timestamp |
| `updatedAt` | timestamp | |

> Storing the weekday mapping on the user document makes "what's today's workout?" a single read. Alternative: store `weekdays: [1,3,5]` on each workout and query with `array-contains`. Pick one and keep it consistent; the spec assumes `weeklySchedule`.

### 5.2 `users/{uid}/workouts/{workoutId}`

| Field | Type | Notes |
|---|---|---|
| `name` | string | e.g., "Push Day A" |
| `category` | string | `push`, `pull`, `legs`, `upper`, `lower`, `custom` |
| `exercises` | array of map | See below; array order = display order |
| `archived` | bool | Soft delete (keeps old logs valid) |
| `createdAt` / `updatedAt` | timestamp | |

**Exercise object**

| Field | Type | Notes |
|---|---|---|
| `id` | string | Client-generated UUID |
| `name` | string | Required |
| `sets` | int | 1–20 |
| `reps` | int | 1–100 |
| `weight` | number? | Optional, in the user's unit |
| `restSeconds` | int? | Optional |
| `notes` | string? | Optional |

### 5.3 `users/{uid}/logs/{logId}`

Document ID: `{yyyy-MM-dd}_{workoutId}` (e.g., `2026-10-10_abc123`) so a workout can only be logged once per day.

| Field | Type | Notes |
|---|---|---|
| `workoutId` | string | Reference to the plan |
| `workoutName` | string | Snapshot |
| `category` | string | Snapshot |
| `date` | string | `yyyy-MM-dd` in the user's local time (used for queries and streaks) |
| `completedAt` | timestamp | |
| `durationSeconds` | int? | From the session timer |
| `exercises` | array of map | Snapshot: `name`, `sets`, `reps`, `weight`, `completed` (bool) |
| `notes` | string? | |

### 5.4 Indexes & queries

| Query | Index |
|---|---|
| History, newest first | `logs` ordered by `date` desc (single-field, automatic) |
| Logs in a date range (week strip, streak) | `logs` where `date` >= start and <= end (single-field) |
| Today's workouts | Read `users/{uid}` → `weeklySchedule[todayWeekday]` → fetch those workouts |

---

## 6. Security Rules

Users can only read and write their own data, and writes are validated.

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    function isOwner(uid) {
      return request.auth != null && request.auth.uid == uid;
    }

    match /users/{uid} {
      allow read, write: if isOwner(uid);

      match /workouts/{workoutId} {
        allow read: if isOwner(uid);
        allow create, update: if isOwner(uid)
          && request.resource.data.name is string
          && request.resource.data.name.size() > 0
          && request.resource.data.name.size() <= 60
          && request.resource.data.exercises is list
          && request.resource.data.exercises.size() <= 50;
        allow delete: if isOwner(uid);
      }

      match /logs/{logId} {
        allow read, write: if isOwner(uid);
      }
    }
  }
}
```

**Other security requirements**
- Enable **Firebase App Check** before public release.
- Never commit `google-services.json` / `GoogleService-Info.plist` with production keys to a public repo.
- Require recent login (re-authentication) before account deletion.
- Account deletion must remove the user's Firestore subcollections (use a Cloud Function or client-side batched delete) and then the auth user.

---

## 7. Architecture

### 7.1 Recommended approach
- **State management:** Riverpod (`flutter_riverpod`) — testable and works well with Firebase streams.
- **Navigation:** `go_router`.
- **Pattern:** Feature-first folders with a thin repository layer between the UI and Firebase.

### 7.2 Folder structure

```
lib/
├─ main.dart
├─ app.dart                    # MaterialApp.router, theme
├─ core/
│  ├─ router/app_router.dart
│  ├─ theme/
│  ├─ utils/                   # date helpers, validators
│  └─ widgets/                 # shared buttons, loaders, error views
├─ features/
│  ├─ auth/
│  │  ├─ data/auth_repository.dart
│  │  ├─ presentation/         # login, register, forgot password screens
│  │  └─ providers.dart
│  ├─ dashboard/
│  ├─ schedule/
│  │  ├─ data/workout_repository.dart
│  │  ├─ domain/workout.dart, exercise.dart
│  │  └─ presentation/
│  ├─ session/                 # active workout + logging
│  ├─ history/
│  └─ profile/
└─ firebase_options.dart
```

### 7.3 Packages

| Package | Purpose |
|---|---|
| `firebase_core`, `firebase_auth`, `cloud_firestore` | Backend |
| `flutter_riverpod` | State management |
| `go_router` | Routing |
| `freezed` + `json_serializable` (optional) | Immutable models |
| `intl` | Date formatting |
| `uuid` | Exercise IDs |
| `flutter_test`, `mocktail`, `fake_cloud_firestore`, `firebase_auth_mocks` | Testing |

### 7.4 Key logic

**Determine today's workout**
```dart
// ISO weekday: Monday = 1 ... Sunday = 7 (matches DateTime.weekday)
final today = DateTime.now().weekday;
final ids = user.weeklySchedule[today.toString()] ?? [];
// ids empty -> rest day
```

**Create a log (idempotent)**
```dart
final dateKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
final logId = '${dateKey}_$workoutId';
await logsRef.doc(logId).set(log.toMap()); // set() = safe to retry
```

**Weekly streak:** a week counts when every scheduled workout in that Mon–Sun range has a matching log. Streak = consecutive completed weeks ending with the current or previous week.

---

## 8. Validation Rules

| Field | Rule |
|---|---|
| Email | Valid format |
| Password | ≥ 8 characters |
| Display name | 1–40 characters |
| Workout name | 1–60 characters |
| Exercise name | 1–60 characters |
| Sets | Integer 1–20 |
| Reps | Integer 1–100 |
| Weight | ≥ 0, max 2 decimal places |
| Exercises per workout | 1–50 |

---

## 9. Error Handling & Edge Cases

- **Offline:** Firestore persistence is on by default on mobile; show a subtle "Offline" banner and queue writes.
- **Deleted workout still scheduled:** Remove its ID from `weeklySchedule` in the same batched write that archives it.
- **Editing a workout mid-session:** Session uses a copy loaded at start; edits don't affect the active session.
- **Timezone / midnight:** Compute the date key from local time when the session *starts*, so a workout finished after midnight still counts for the day it began.
- **Duplicate completion:** Deterministic log ID makes repeated taps safe. Show "Already completed today" with an Undo option.
- **Empty states:** No workouts yet → onboarding card with template buttons. No history yet → friendly prompt.
- **Session interrupted (app killed):** Persist in-progress ticks locally (e.g., `shared_preferences`) and restore on next launch.

---

## 10. Testing Plan

| Level | Scope |
|---|---|
| Unit | Validators, date/weekday helpers, streak calculation, model serialization |
| Repository | Auth and workout repositories against fakes (`fake_cloud_firestore`, `firebase_auth_mocks`) |
| Widget | Login/Register forms, Dashboard states (workout / rest day / completed), Workout Editor |
| Integration | Register → create workout → assign to today → complete → appears in history |
| Security rules | Firebase Emulator tests: user A cannot read/write user B's data; unauthenticated denied |
| Manual | iOS + Android devices, dark mode, offline mode, small screens |

---

## 11. Milestones

| Phase | Deliverables | Rough effort |
|---|---|---|
| **0. Setup** | Flutter project, Firebase project (dev + prod), `flutterfire configure`, theme, router skeleton, CI (analyze + test) | 1–2 days |
| **1. Auth** | Login, Register, Forgot Password, auth gate, Profile with logout | 3–4 days |
| **2. Workouts** | Data models, repository, Workout Editor, My Workouts list, templates | 4–5 days |
| **3. Schedule & Dashboard** | Weekly schedule assignment, Today card, rest-day state, weekly strip | 3–4 days |
| **4. Tracking** | Active session, completion + logging, undo, History | 4–5 days |
| **5. Polish** | Streak, units, empty/error states, dark mode, account deletion, security rules + tests | 3–4 days |
| **6. Release** | App Check, icons/splash, store listings, TestFlight / Play internal testing | 3–5 days |

*Estimates assume a single developer working full-time and will vary with experience.*

---

## 12. Definition of Done (MVP)

- [ ] User can register, log in, reset password, and log out
- [ ] User can create, edit, archive, and reorder exercises in workout days (with templates)
- [ ] User can assign workouts to weekdays
- [ ] Dashboard correctly shows today's workout or a rest day
- [ ] User can tick exercises, complete a workout, and undo
- [ ] History and weekly streak display correctly
- [ ] Firestore rules deployed and verified with emulator tests
- [ ] Works offline; no crashes on a fresh install or after sign-out/sign-in
- [ ] Passes `flutter analyze` with no warnings; core unit and widget tests pass

---

## 13. Roadmap Beyond MVP

1. Google / Apple sign-in
2. Per-set logging with weight/rep history and personal records
3. Exercise library with muscle groups and search
4. Progress charts (volume, weight over time, body measurements)
5. Rest timer with notifications and workout reminders
6. Export data (CSV)
7. Wearable / Health app integration
8. Shareable workout plans

---

## 14. Open Questions

Decide these before or during Phase 0:

1. **Exact schedule model:** weekday-based (assumed here) or a rotating cycle (e.g., Push → Pull → Legs → Rest regardless of weekday)?
2. **Multiple workouts per day:** supported in this spec. Is that wanted, or should it be one per day?
3. **Granularity of tracking:** exercise-level ticks (MVP) or per-set weight/reps logging?
4. **App name & branding:** is "FitTrack" final? (Check store availability; the name is common.)
5. **Target platforms:** both iOS and Android at launch, or Android first?
6. **Monetization:** free, ads, or paid tier later? This affects whether to plan for subscriptions early.
