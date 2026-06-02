# DartStream Sample App

An end-to-end sample that proves **real users can sign up, sign in, and use the
live DartStream backend** (`dartstream-prod`) across its auth, platform,
experience, and reactive services. It exists to exercise DartStream the way an
actual client does — not with mocks — so regressions in the deployed contracts
show up immediately.

It ships two artifacts:

1. **`bin/smoke.dart`** — a headless Dart CLI that hits all 10 endpoints and
   prints `PASS/FAIL`. Run this first to confirm the environment is healthy.
2. **`flutter_client/`** — a Flutter **web** app with a
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
- [Running the Flutter + Flame client](#running-the-flutter--flame-client)
- [Endpoint contracts](#endpoint-contracts)
- [Verified end-to-end](#verified-end-to-end)
- [Known backend gaps](#known-backend-gaps)
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
├── bin/smoke.dart              # headless E2E CLI (pure Dart + http)
├── .env.example                # config template (placeholders only)
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

### What the home screen does

After login it runs `profile`, `feature-flags`, `inventory`, `cloud-save`, and
`streaming/channels` in parallel, renders a live response panel for each, then
mounts the Flame game. Tapping the coin:

- increments the score (Flame state),
- debounce-writes `cloud-save/snapshot` (500 ms), and
- on every 10th tap, posts `reactive/events/log` with
  `event_type=flame.score.milestone`.

> Browsers strip `X-User-ID` from the CORS preflight allowlist, so the client
> passes `userId`/`tenantId` as query params on experience calls. See the note
> in [`dartstream.dart`](flutter_client/lib/api/dartstream.dart).

---

## Endpoint contracts

| # | Method & path | Service | Notes |
| --- | --- | --- | --- |
| 1 | Firebase `signInWithPassword` / `signUp` | Identity Toolkit | yields the ID token |
| 2 | `POST /api/v1/auth/signup` | auth | onboards user + tenant; idempotent |
| 3 | `GET  /api/v1/auth/me` | auth | current user record |
| 4 | `GET  /api/v1/platform/feature-flags` | platform | `{ "flags": [] }` today |
| 5 | `GET  /api/v1/experience/profiles/me` | experience | `dartstream-managed` profile |
| 6 | `POST /api/v1/experience/cloud-save/snapshot` | experience | write score (201) |
| 7 | `GET  /api/v1/experience/cloud-save/snapshot` | experience | read back |
| 8 | `GET  /api/v1/experience/inventory/items` | experience | seeded items |
| 9 | `POST /api/v1/reactive/events/log` | reactive | `{ "status": "logged" }` |
| 10 | `GET  /api/v1/reactive/streaming/channels` | reactive | REST channel list (`[]`) |

---

## Verified end-to-end

- **Smoke CLI:** 10 / 10 PASS against live `dartstream-prod`.
- **Create-account → sign-in round trip:** verified that a returning user
  signing in resolves a session (userId + tenantId) — this confirmed the
  backend signup is idempotent.
- **Flutter client:** a real, human-created account
  (`dartstreame2e@gmail.com`) signed up, signed in, scored in the game, and saw
  live data in every panel — cloud-save writes, reactive milestone events,
  profile, and inventory (`starter-sword ×1`, `coin ×250`).

---

## Known backend gaps

- No `leaderboard` endpoint yet (roadmap Phase 2); not tested.
- Inventory exposes only `GET /items` — no write loop to test.
- `streaming/channels` is REST-only; no WebSocket upgrade yet.

---

## License

[MIT](LICENSE) © 2026 Brian Chebon
