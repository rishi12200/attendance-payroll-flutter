# AGENTS.md

Instructions for AI coding agents working in this repo. Read `plan.md` first. It is the source of truth for scope, data model, API and build order.

## Project

Attendance and payroll mobile app for a multi-branch company.

- **App:** Flutter (`/app`), one app, UI switches by role (`admin` | `employee`)
- **API:** Node.js + Express 5 + TypeScript (`/backend`), deployed to Cloud Run
- **Data and auth:** Firebase Auth + Firestore (accessed only through the API)
- **Reference:** `docs/prototype.html` is the original HTML prototype. Payroll formulas are ported from it.

## How to work

1. **One step at a time.** Implement only the step you are asked for from `plan.md` section 12. Do not start the next step or build deferred features.
2. **Stop after each step** and report: what you built, which files changed, and the exact commands and requests I can run to test it.
3. **Read before writing.** Check existing code and `plan.md` before adding files. Reuse existing helpers.
4. **If the plan is unclear or conflicts with the code, ask** instead of guessing. Do not silently change the plan. If something in `plan.md` needs to change, say so and propose the edit.
5. **Keep changes small and focused.** No drive-by refactors, no renaming unrelated files.
6. Update the checkboxes in `plan.md` section 12 when a step is done and verified.
7. Commit your work as you go, following the "Git and commits" section below.

## Security: do not touch secrets

- Never read, print, log, copy or commit anything in `backend/secrets/`, any `.env` file, or any `*-firebase-adminsdk-*.json` key.
- Never ask me to paste a key or token into chat.
- Use `.env.example` for documenting variables. Real values stay local.
- Do not add the key path or contents to any committed file.

## Commands

Run from `backend/`:

```
npm install
npm run dev              # start API with reload
npm run typecheck        # tsc --noEmit
npm run build && npm start
npm run check:firebase   # verifies the key, Auth and Firestore access
npm test                 # unit tests (add the test runner in Step 1 if missing)
```

Run from `app/`:

```
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

Before reporting a step as done, `npm run typecheck`, `npm test`, `flutter analyze` and `flutter test` (for the parts you touched) must pass.

## Dependencies

- Do not downgrade or change major versions of anything pinned in `backend/package-lock.json`. Versions are modern: Express 5, firebase-admin 14 (modular imports), zod 4, TypeScript 7.
- Do not follow older tutorials blindly:
  - `firebase-admin`: import from `firebase-admin/app`, `firebase-admin/auth`, `firebase-admin/firestore`. Not the old `admin.firestore()` namespace.
  - Express 5: async route handlers that throw or reject reach the error middleware. Wildcard route syntax differs from Express 4.
  - zod 4: check the current API before using older zod 3 patterns.
- Ask before adding a new dependency. Prefer what is already installed.

## Hard rules (from plan.md section 3)

1. Money is **integer paise** everywhere (storage, API, maths). Never floats. Convert to rupees only for display in the app.
2. Attendance dates are `YYYY-MM-DD` strings in **IST** (fixed +05:30 offset). Months are `YYYY-MM`.
3. Punch times come from **server time**, never from the client. Store as Firestore timestamps.
4. **Do not store payslips.** Payslips are calculated on demand from stored inputs.
5. **Never delete employees.** Deactivate: set `status: inactive` and `dol`, disable the Auth user, revoke refresh tokens.
6. Attendance and payroll maths go in `backend/src/domain/`. That folder is pure TypeScript with **no Firebase or Express imports** and has unit tests.
7. Firestore rules stay **deny all**. The app never reads or writes Firestore directly.
8. Admin edits record `editedBy` and `editedAt`.
9. Check-in and check-out run inside a **Firestore transaction** (reads before writes).
10. Verify ID tokens with revocation checking: `verifyIdToken(token, true)`.

## Backend conventions

- Layers: `routes/` (HTTP only: parse, validate, call service, respond) → `services/` (Firebase access, transactions) → `domain/` (pure logic).
- Validate every request body, query and param with zod in `middleware/validate`.
- Errors: throw an `AppError(status, code, message, details?)`. The error middleware responds with:
  ```json
  { "error": { "code": "VALIDATION_ERROR", "message": "...", "details": {} } }
  ```
  The Step 0 code returns plain `{ "error": "..." }` strings. Switch it to this shape in Step 1.
- Status codes: 400 validation, 401 missing or invalid token, 403 wrong role or inactive user, 404 not found, 409 conflict (duplicate check-in, locked month, overlapping leave), 422 business-rule rejection (outside geofence, poor accuracy, mock location).
- Authorization is enforced in middleware (`requireRole('admin')`) and again in the service when a user may only access their own data (employees can only read their own attendance, leave, payslips).
- Firestore batches max 500 writes. Chunk bulk operations.
- TypeScript is `strict`. No `any` unless commented why.
- Do not log personal data, tokens, or coordinates beyond what the `checkins` record needs.

## Testing

- Every function in `domain/` gets unit tests: Haversine and geofence, IST date helpers, attendance summary (all statuses, weekly offs, holidays, `doj`, `dol`, derived absent, future days), payroll calculation (rounding, LOP, adjustments).
- Services and routes: test the important rules (role checks, locked month, duplicate check-in, leave overlap) with the Firebase emulators or mocks. Do not hit the real project from automated tests.
- Add a test for each bug you fix.

## Flutter conventions

- State management: Riverpod. Navigation: go_router. HTTP: dio with an interceptor that attaches the ID token and refreshes it on 401.
- Structure: `lib/core/` (api client, auth, theme, router) and `lib/features/<feature>/` (data, domain, presentation).
- The API base URL comes from `--dart-define=API_BASE_URL`. Never hardcode it.
- Do not calculate payroll, summaries or geofence decisions in the app. The server decides. The app may show a distance estimate for UX only.
- Store tokens only through Firebase Auth's own persistence (no custom token storage in plain preferences).
- Show clear messages for permission denied, location services off, poor GPS accuracy, and server rejections.
- Android emulator reaches the host at `10.0.2.2`. Plain `http` is blocked by default on Android 9+ and iOS, so use a development-only exception or an https tunnel.

## Git and commits

### When to commit
- Commit **after each logical piece of a step** once it works, not one giant commit at the end. A typical step is 2 to 5 commits.
- Before every commit: `npm run typecheck` and `npm test` (backend) or `flutter analyze` and `flutter test` (app) must pass for the code you touched.
- Do not commit broken or half-finished work. Do not commit unrelated changes together.
- Each commit should contain one idea: for example the domain function and its tests together, the route and service together, but not a route plus an unrelated refactor.
- Work on a branch per step, named `step-<n>-<short-name>` (for example `step-1-auth-roles`). I will merge it after I have tested it. If the repo has no branches yet, create the branch before the first commit of the step.

### Message format (Conventional Commits)
```
<type>(<scope>): <summary in imperative mood, max 72 chars>

<body: what changed and why, wrapped at ~72 chars. Optional but preferred
for anything non-trivial.>

Refs: plan.md Step <n>
```

Types: `feat`, `fix`, `test`, `refactor`, `docs`, `chore`, `build`.
Scopes: `backend`, `app`, `domain`, `auth`, `employees`, `branches`, `attendance`, `leave`, `payroll`, `rules`, `plan`.

Rules for the summary line:
- Imperative mood: "add auth middleware", not "added" or "adds".
- Lowercase after the colon, no trailing period.
- Say what the commit does, not which files it touches.
- No vague messages like "update", "fix stuff", "wip", or "changes".

### Examples
```
feat(auth): verify ID tokens with revocation check

Add auth middleware that reads the Bearer token, verifies it with
verifyIdToken(token, true) and attaches uid and role to the request.
Disabled or revoked users now get 401 immediately.

Refs: plan.md Step 1
```
```
feat(auth): add role middleware and standard error shape
feat(auth): add seed-admin script and GET /me
test(domain): cover haversine and geofence edge cases
feat(attendance): add transactional check-in endpoint
fix(attendance): count half days as 0.5 LOP in summary
docs(plan): tick off Step 1 checklist
chore(backend): add vitest and test script
```

### What never goes in a commit
- `node_modules`, `dist`, build output, `.env` files, and anything in `backend/secrets/` or any service account key. If you are unsure, run `git status` and `git diff --staged` first.
- Do not rewrite history, amend commits that were already shared, or force push.

### Step finish
At the end of a step, show me `git log --oneline` for the step's commits along with the manual test instructions.

## Out of scope (do not build unless asked)

Offline queue, push notifications and scheduled jobs, PDF export, late or short-hours deductions, leave balances, overtime and shifts, TDS and employer contributions, App Check, Secret Manager, rate limiting, branch map picker, multiple punches per day.

## Definition of done for a step

- The behavior in the step's "Done when" line works.
- Typecheck, lint and tests pass.
- New domain logic has unit tests.
- No secrets, debug leftovers or unrelated changes in the diff.
- `plan.md` checkboxes updated.
- Work is committed on the step branch with proper commit messages (see Git and commits).
- You have written the manual test instructions (commands, sample requests, expected responses).