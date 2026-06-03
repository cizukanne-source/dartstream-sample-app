# DartStream Sample App

An end-to-end sample that proves **real users can sign up, sign in, and use the
live DartStream backend** (`dartstream-prod`) across its auth, platform,
experience, and reactive services. It exists to exercise DartStream the way an
actual client does — not with mocks — so regressions in the deployed contracts
show up immediately.

It ships four artifacts:

1. **`bin/smoke.dart`** — a headless Dart CLI that hits all 10 endpoints and
   prints `PASS/FAIL`. Run this first to confirm the environment is healthy.
2. **`bin/auth_deepdive.dart`** — a headless Dart CLI that goes deep on the
   `ds-auth` service alone, exercising **every** auth endpoint (auth, users
   CRUD, sessions, avatar, status transitions, federated routes, providers) and
   printing a `PASS/FAIL/SKIP` table. Use it to verify the full auth surface,
   not just the happy path.
3. **`bin/platform_deepdive.dart`** — the same idea for `ds-platform-services`:
   feature-flags, projects (+ environments, integrations, orchestration),
   api-keys, settings, team, and the middleware/discovery sub-services. CRUD
   paths run as create → read → update → delete so they self-clean; outward ops
   (invitation emails, member-role changes) are gated behind
   `DEEPDIVE_DESTRUCTIVE=1`.
4. **`flutter_client/`** — a Flutter **web** app with a
   [Flame](https://flame-engine.org) "tap-to-score" minigame, a real
   Create-Account / Sign-In flow, and a live response panel per DartStream
   service.

---

## Table of contents

- [How auth works (and why)](#how-auth-works-and-why)
- [Firebase project: it must be `dartstream-prod`](#firebase-project-it-must-be-dartstream-prod)
- [Project layout](#project-layout)
- [Prerequisites](#prerequisites)
- [Configuration & secrets](#configuration--secrets)
- [Running the smoke CLI](#running-the-smoke-cli)
- [Running the auth deep-dive](#running-the-auth-deep-dive)
- [Running the platform deep-dive](#running-the-platform-deep-dive)
- [Running the experience / reactive / persistence deep-dives](#running-the-experience--reactive--persistence-deep-dives)
- [Running the Flutter + Flame client](#running-the-flutter--flame-client)
- [Smoke CLI coverage](#smoke-cli-coverage)
- [Verified end-to-end](#verified-end-to-end-live-dartstream-prod-2026-06-03)
- [Known backend gaps & filed bugs](#known-backend-gaps--filed-bugs)
- [License](#license)

---

## How auth works (and why)

Both artifacts follow the same flow a real DartStream client uses:

```
            ┌─────────────────────────┐        idToken         ┌──────────────────────┐
 email +    │  Firebase Identity      │ ─────────────────────▶ │  DartStream backend  │
 password ─▶│  Toolkit (REST)         │   Bearer <idToken>     │  /api/v1/auth/...    │
            │  signUp / signInWith…   │                        │  verifies token,     │
            └─────────────────────────┘                        │  onboards tenant     │
              client / "user" role                             └──────────────────────┘
              (this sample, web SDK)                             server / "admin" role
                                                                 (firebase_dart_admin_auth_sdk)
```

1. The client authenticates against **Firebase Identity Toolkit** with the
   project's public **web API key** and gets a real Firebase **ID token**.
2. It sends that token (`Authorization: Bearer <idToken>`) to the DartStream
   backend, which **verifies** it and bootstraps the user + tenant.

### Why REST and not `firebase_dart_admin_auth_sdk`?

DartStream's backend uses
[`firebase_dart_admin_auth_sdk`](https://pub.dev/packages/firebase_dart_admin_auth_sdk)
to **verify** ID tokens server-side (in `ds-auth`). That package is a
*server/admin* SDK and is the wrong tool for a browser client because it:

- imports `dart:io`, so it **cannot compile for Flutter web**;
- does **not** list Web as a supported platform; and
- is initialized with privileged **workload-identity / service-account**
  credentials that must never ship inside a browser.

This sample plays the **user/client** role, so it authenticates the way a real
user does — hitting the same Identity Toolkit endpoints the official Firebase
web SDK (FlutterFire) calls under the hood. The resulting ID token is identical
and equally backend-trusted; the lightweight REST path just avoids extra
dependencies. See [`flutter_client/lib/api/firebase_auth.dart`](flutter_client/lib/api/firebase_auth.dart).

---

## Firebase project: it must be `dartstream-prod`

The backend only trusts ID tokens issued by the Firebase project it was
configured against: **`dartstream-prod`**.

| Field | Value |
| --- | --- |
| Project ID | `dartstream-prod` |
| Auth domain | `dartstream-prod.firebaseapp.com` |
| Web app | `Sample-App-Brian-Chebon` |
| Web API key | injected at runtime (see below) |

> ⚠️ **Tokens from any other project are rejected.** A token minted by a
> different Firebase project (e.g. `intellitoggle-prod`) will authenticate fine
> *with Firebase* but the DartStream backend returns **HTTP 500** at
> `/api/v1/auth/signup` because it can't verify a foreign issuer. If signup
> starts 500-ing, check that your `FIREBASE_API_KEY` belongs to
> `dartstream-prod`.

---

## Project layout

```
.
├── bin/smoke.dart                 # headless E2E CLI across all 5 services
├── bin/auth_deepdive.dart         # deep-dive: full ds-auth surface
├── bin/platform_deepdive.dart     # deep-dive: ds-platform-services
├── bin/experience_deepdive.dart   # deep-dive: ds-experience-orchestration
├── bin/reactive_deepdive.dart     # deep-dive: ds-reactive-dataflow
├── bin/persistence_deepdive.dart  # deep-dive: ds-persistence
├── .env.example                   # config template (placeholders only)
├── flutter_client/
│   └── lib/
│       ├── config.dart         # backend hosts; API key read from --dart-define
│       ├── api/
│       │   ├── firebase_auth.dart   # Identity Toolkit REST: signUp / signIn
│       │   └── dartstream.dart      # typed client for the 10 backend contracts
│       ├── state/session.dart       # auth state + onboarding
│       ├── screens/
│       │   ├── login_screen.dart    # Create Account / Sign In toggle
│       │   └── home_screen.dart     # live service panels + game host
│       └── game/tap_game.dart       # Flame tap-to-score minigame
└── README.md
```

---

## Prerequisites

- Dart SDK `^3.6` (Flutter `3.44+` bundles a compatible SDK)
- Flutter `3.44+` (for the web client)
- A Google Chrome install (the client runs on `-d chrome` / web-server)

---

## Configuration & secrets

Copy the template and fill in your local, gitignored `.env`:

```sh
cp .env.example .env
# set FIREBASE_API_KEY (Firebase console > Project settings > dartstream-prod web app)
# plus a test email/password.
set -a && source .env && set +a
```

`.env`:

| Variable | Purpose |
| --- | --- |
| `FIREBASE_API_KEY` | `dartstream-prod` **web** API key |
| `TEST_EMAIL` / `TEST_PASSWORD` | credentials the smoke CLI signs up / in with |
| `API_AUTH`, `API_PLATFORM`, `API_EXPERIENCE`, `API_REACTIVE`, `API_PERSISTENCE` | per-service base URLs (default to the `dev-api*.dartstream.io` hosts) |

### The API key is injected at runtime, never committed

- **Smoke CLI** reads `FIREBASE_API_KEY` from the environment.
- **Flutter client** reads it via `--dart-define=FIREBASE_API_KEY=…`
  (`String.fromEnvironment` in `config.dart`). If it's missing, the login
  screen shows a banner and disables sign-in instead of throwing an opaque
  Firebase error.

> **Note on the web API key:** A Firebase *web* API key is a public project
> identifier, not a secret — it ships inside every web app and is visible in the
> browser's network tab. You cannot hide it in a web client. Real protection
> comes from **API key restrictions** (HTTP-referrer allowlist + allowed APIs)
> in the Google Cloud console and **Firebase App Check**, not from hiding the
> value. We keep it out of the repo as hygiene; the deployed app still exposes
> it by nature. Tracked files (`config.dart`, `.env.example`) carry only
> placeholders — the real value lives solely in your gitignored `.env`.

---

## Running the smoke CLI

```sh
dart pub get
set -a && source .env && set +a
dart run bin/smoke.dart
```

It signs in with `TEST_EMAIL` (auto-signs-up on first run), then walks the 10
contracts below, printing `PASS/FAIL` with HTTP status and a body excerpt so you
can see exactly which contract behaves.

---

## Running the auth deep-dive

Where `smoke.dart` proves the happy path across all five services,
`auth_deepdive.dart` fans out across the **entire `ds-auth` surface** so you can
see exactly which auth features work:

```sh
dart pub get
set -a && source .env && set +a
dart run bin/auth_deepdive.dart
```

It signs in, onboards via `signup`, then exercises:

- **auth** — `login`, `logout`, `me`, `user-status`
- **federated** — `signin/google`, `signin/github`, `signin/microsoft`
- **users** — list, get, update, sessions, avatar (upload/get/delete), and the
  reversible `suspend` / `activate` / `deactivate` transitions
- **providers** — `GET /api/v1/providers`

…and prints a `PASS/FAIL/SKIP` summary table grouped by area.

**Destructive ops are skipped by default.** `DELETE /users/<id>` and
revoke-all-sessions are gated behind `DEEPDIVE_DESTRUCTIVE=1` so a normal run
never bricks the shared test account:

```sh
DEEPDIVE_DESTRUCTIVE=1 dart run bin/auth_deepdive.dart
```

> **Note on auth providers:** DartStream's `AuthProviderType` enumerates 10
> provider SDKs, but only **Firebase** is implemented today; the other nine
> (Auth0, Cognito, Entra ID, Okta, Magic, Fingerprint, Transmit, Stytch, Ping)
> are stubs. This deep-dive therefore proves the Firebase provider end-to-end;
> the federated `signin/*` routes are Firebase-backed.

---

## Running the platform deep-dive

```sh
dart pub get
set -a && source .env && set +a
dart run bin/platform_deepdive.dart
```

It bootstraps a tenant, then exercises `ds-platform-services` end to end:

- **feature-flags** — list, create, get, update, delete
- **projects** — list/create/get/update/archive, plus environments,
  integrations, and orchestration provider resolution
- **api-keys** — list, create, delete
- **settings** — profile + notifications (get/patch)
- **team** — members + invitations (reads); invite/role-change gated behind
  `DEEPDIVE_DESTRUCTIVE=1` (they send email / mutate a real member)
- **middleware** and **discovery** sub-services — full CRUD

CRUD groups create-then-delete so a normal run leaves no clutter in the tenant.

---

## Running the experience / reactive / persistence deep-dives

Same pattern, one per remaining service:

```sh
set -a && source .env && set +a
dart run bin/experience_deepdive.dart    # profiles, cloud-save, inventory, sessions, connectors
dart run bin/reactive_deepdive.dart      # events, streaming, notifications, lifecycle hooks
dart run bin/persistence_deepdive.dart   # database connections, storage configs, logging
```

Each bootstraps a tenant, exercises every endpoint in its service, and prints a
`PASS/FAIL/SKIP` table. CRUD groups self-clean. As of 2026-06-03: experience
11/11 and reactive 29/29 are fully green; persistence has one known
backend bug (logging-config save returns a non-persistent id on the upsert
update path — filed as a SaaS ticket).

---

## Running the Flutter + Flame client

The web API key is HTTP-referrer-restricted and `http://localhost:3000` is on
the allowlist, so **the dev server must run on port 3000**.

```sh
set -a && source .env && set +a   # from the repo root, to load FIREBASE_API_KEY
cd flutter_client
flutter pub get
flutter run -d chrome --web-port=3000 \
  --dart-define=FIREBASE_API_KEY=$FIREBASE_API_KEY
```

Tips:

- It must be a **fresh `flutter run`**, not a hot reload — `--dart-define`
  values are baked in at compile time.
- Run it in an **interactive terminal**; `flutter run` needs a TTY for
  hot-reload and exits immediately otherwise.
- If you prefer, inline the key:
  `--dart-define=FIREBASE_API_KEY=<your-dartstream-prod-web-key>`.

### The login flow

The login screen has a **Create Account / Sign In** toggle taking real
credentials:

- **Create Account** — email, password, and confirm-password, with inline
  validation (valid email, password ≥ 6 chars, passwords match) and friendly
  Firebase error messages (`EMAIL_EXISTS`, weak password, bad credentials, …).
- **Sign In** — email + password for a returning user.

Both paths get a Firebase ID token, then call the backend's onboarding. The
backend's `/api/v1/auth/signup` is **idempotent** — it returns the existing
user for a returning login (with a `/api/v1/auth/login` fallback on 409) — so
the same onboarding call covers both create-account and sign-in.

### What the client does

After login the app is a **navigation shell with one screen per DartStream
service** (NavigationRail on wide screens, a Drawer on narrow):

| Screen | Surface | What you can do |
| --- | --- | --- |
| **Overview** | experience | the Flame "tap-to-score" game + live panels; tapping the coin debounce-writes `cloud-save/snapshot` (500 ms) and posts a `reactive/events/log` milestone every 10th tap |
| **Profile** | auth | the user record + editable display name, the avatar lifecycle (set / view / remove), and session management (revoke one / all) |
| **Feature flags** | platform | list / create / toggle / delete feature flags |
| **Experience** | experience | profile, inventory, active sessions, connector catalog |
| **Reactive** | reactive | log an event + the event log, and CRUD for subscriptions, streaming channels, notification configs, lifecycle hooks |
| **Persistence** | persistence | CRUD for database connections, storage configs, logging configs + a logging-entries panel |

Every screen surfaces backend errors in a SnackBar (it does not hide failures),
and the CRUD screens share one reusable widget
([`resource_crud_section.dart`](flutter_client/lib/widgets/resource_crud_section.dart)).

> Browsers strip `X-User-ID` from the CORS preflight allowlist, so the client
> passes `userId`/`tenantId` as query params on experience calls. See the note
> in [`dartstream.dart`](flutter_client/lib/api/dartstream.dart).

---

## Smoke CLI coverage

`smoke.dart` walks one representative contract per service (the deep-dive CLIs
go far broader — see their sections above):

| # | Method & path | Service | Notes |
| --- | --- | --- | --- |
| 1 | Firebase `signInWithPassword` / `signUp` | Identity Toolkit | yields the ID token |
| 2 | `POST /api/v1/auth/signup` | auth | onboards user + tenant; idempotent |
| 3 | `GET  /api/v1/auth/me` | auth | current user record |
| 4 | `GET  /api/v1/platform/feature-flags` | platform | `{ "flags": [] }` for a new tenant |
| 5 | `GET  /api/v1/experience/profiles/me` | experience | `dartstream-managed` profile |
| 6 | `POST /api/v1/experience/cloud-save/snapshot` | experience | write score (201) |
| 7 | `GET  /api/v1/experience/cloud-save/snapshot` | experience | read back |
| 8 | `GET  /api/v1/experience/inventory/items` | experience | seeded items |
| 9 | `POST /api/v1/reactive/events/log` | reactive | `{ "status": "logged" }` |
| 10 | `GET  /api/v1/reactive/streaming/channels` | reactive | REST channel list (`[]`) |
| 11 | `GET  /api/v1/persistence/database` | persistence | tenant DB connections |

---

## Verified end-to-end (live `dartstream-prod`, 2026-06-03)

- **Smoke CLI:** 11 / 11 PASS across all five services.
- **Per-service deep-dives:** auth full surface PASS; platform 34 / 36;
  experience 11 / 11; reactive 29 / 29; persistence 18 / 1. The two failures are
  filed backend bugs (below).
- **Flutter client:** a real human account signed up, signed in, scored in the
  game, managed flags, browsed experience/reactive/persistence, and edited the
  profile/avatar — with live data in every screen.

---

## Known backend gaps & filed bugs

Found by the deep-dives and filed for the backend QA agent (not sample-app
issues):

- **Feature-flag PATCH/DELETE → 500** (`ds-platform-services`): a single bind
  param is compared against the `uuid` id and the `varchar` flag_key in the same
  WHERE clause, so flags can be created/read but not updated or deleted. Fix:
  `id::text = @flagId OR flag_key = @flagId`.
- **Logging-config save returns a phantom id** (`ds-persistence`): the
  `ON CONFLICT DO UPDATE` upsert returns the freshly-generated id instead of the
  persisted row's id (no `RETURNING`), so a second save for the same provider
  hands back an id that 404s. Fix: add `RETURNING *` and map the returned row.

Other notes:

- Of the 10 `AuthProviderType` SDKs, only **Firebase** is implemented today; the
  other nine are stubs. The federated `signin/*` routes are Firebase-backed.
- Inventory exposes only `GET /items`; `streaming/channels` is REST-only.

---

## License

[MIT](LICENSE) © 2026 Brian Chebon
