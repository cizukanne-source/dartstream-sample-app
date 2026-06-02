# DartStream Sample App

Two end-to-end artifacts that exercise the live **DartStream** backend
(`dartstream-prod`) across its auth, platform, experience, and reactive
services:

1. **`bin/smoke.dart`** — a headless Dart CLI that hits all 10 endpoints with
   `PASS/FAIL` output. Run this first to confirm the environment is healthy.
2. **`flutter_client/`** — a Flutter web app with a [Flame](https://flame-engine.org)
   "tap-to-score" minigame embedded. Exercises the same contracts inside a real
   client UI, with a live response panel per DartStream service.

Authentication goes straight to Firebase Identity Toolkit (REST) using the
project's **web** API key; the resulting ID token is then exchanged with the
DartStream backend.

## Prerequisites

- Dart SDK `^3.6` (Flutter `3.44+` bundles a compatible SDK)
- Flutter `3.44+` (for the web client)

## Configuration

Credentials and base URLs live in environment variables for the CLI and in
[`flutter_client/lib/config.dart`](flutter_client/lib/config.dart) for the
client.

```sh
cp .env.example .env
# edit .env: set FIREBASE_API_KEY (Firebase console > Project settings > web app)
# plus a test email/password. .env is gitignored.
set -a && source .env && set +a
```

The Firebase web API key is **not committed** — it's injected at run time from
your environment (`FIREBASE_API_KEY`). The smoke CLI reads it from the
environment directly; the Flutter client takes it via `--dart-define` (below).

> **Note on the API key:** A Firebase *web* API key is a public project
> identifier, not a secret — it ships inside any web app and is visible in the
> browser. Real protection comes from **API key restrictions** (HTTP-referrer +
> allowed APIs) in the Google Cloud console and **Firebase App Check**, not from
> hiding the value. We keep it out of the repo as hygiene, but the deployed app
> still exposes it by nature.

## Headless smoke CLI

```sh
dart pub get
dart run bin/smoke.dart
```

### Steps the CLI runs

1. Firebase password sign-in (REST). Auto sign-up on first run.
2. `POST {API_AUTH}/api/v1/auth/signup` with the Firebase `idToken`.
3. `GET  {API_AUTH}/api/v1/auth/me`.
4. `GET  {API_PLATFORM}/api/v1/platform/feature-flags`.
5. `GET  {API_EXPERIENCE}/api/v1/experience/profiles/me`.
6. `POST {API_EXPERIENCE}/api/v1/experience/cloud-save/snapshot` (write score).
7. `GET  {API_EXPERIENCE}/api/v1/experience/cloud-save/snapshot` (read back).
8. `GET  {API_EXPERIENCE}/api/v1/experience/inventory/items`.
9. `POST {API_REACTIVE}/api/v1/reactive/events/log`.
10. `GET {API_REACTIVE}/api/v1/reactive/streaming/channels`.

Each step prints `PASS/FAIL` with HTTP status and a body excerpt.

## Flutter + Flame client

The Firebase web API key is HTTP-referrer-restricted, and `http://localhost:3000`
is on the allowlist — so the dev server must run on port 3000.

```sh
set -a && source .env && set +a   # from the repo root, to load FIREBASE_API_KEY
cd flutter_client
flutter pub get
flutter run -d chrome --web-port=3000 \
  --dart-define=FIREBASE_API_KEY=$FIREBASE_API_KEY
```

If the key isn't injected, the login screen shows a banner and disables sign-in
instead of failing with an opaque Firebase error.

On the login screen the email is prefilled with a fresh `smoketest+<ts>@...`
address so the auto sign-up path triggers on first run. After login the home
screen runs `profile`, `feature-flags`, `inventory`, `cloud-save`, and
`streaming/channels` in parallel, then mounts the Flame game. Tapping the coin:

- increments the score (Flame state)
- debounce-writes `cloud-save/snapshot` (500ms)
- on every 10th tap, posts `reactive/events/log` with
  `event_type=flame.score.milestone`

## Known gaps in the backend

- No `leaderboard` endpoint yet (roadmap Phase 2); the CLI does not test it.
- Inventory exposes only `GET /items` — no write loop to test.
- `streaming/channels` is REST-only; no WebSocket upgrade yet.

## License

[MIT](LICENSE) © 2026 Brian Chebon
