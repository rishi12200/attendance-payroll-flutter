# Attendance & Payroll App: POC Plan

Mobile app (Flutter) with an Express API on Cloud Run and Firebase (Auth, Firestore) as the backend. Two roles: **admin** and **employee**. Multi-branch company with location-based check-in.

The goal of the POC is one thin end-to-end slice that works: login, geofenced check-in, attendance views, basic leave, and payroll with an on-demand payslip. Everything else is deferred.

**Status:** Step 0 backend skeleton is written (Express + TypeScript + Firebase Admin, `/health`, `check:firebase` script). Verification against the real Firebase project is pending.

---

## 1. Scope

### In the POC
- Login with two roles (admin, employee). The admin creates employees and sets a temporary password.
- Admin: manage employees and branches
- Employee: check-in and check-out, only when inside an allowed branch
- Admin: see every employee's in-time, out-time, hours worked and status for a day, and edit it
- Employee: monthly attendance calendar with a day-count summary
- Leave: apply, admin approves or rejects as paid or unpaid
- Payroll: monthly preview, admin adjustments (bonus, other deductions), month lock and unlock
- Payslip generated on demand, never saved

### Assumptions (change if wrong)
- Admins are management-only accounts. They do not check in and do not appear in payroll, so they need no branch or salary.
- Finalized months can be unlocked by an admin (corrections will be needed).

### Deferred (after the POC works)
- Offline check-in queue
- Push notifications (FCM) and scheduled jobs (reminders, auto-close)
- Server-side PDF export of payslips
- Deductions for late arrival or short hours
- Leave balances, accrual, carry-forward
- Overtime, shifts, regularization requests
- TDS, employer-side statutory contributions, challans
- App Check, Secret Manager, rate limiting, full audit logger
- Map picker for branches (POC uses "use my current location")
- Multiple punches per day
- Forced password change on first login, password reset flow

---

## 2. Architecture

```
Flutter app ──(Firebase Auth login, ID token)──► Express API (Cloud Run)
                                                     │  firebase-admin
                                                     ▼
                                                 Firestore
```

- The app signs in with Firebase Auth and sends the ID token in the `Authorization: Bearer <token>` header on every API call.
- Express verifies the token **with revocation checking** (`verifyIdToken(token, true)`), reads the `role` custom claim, and enforces authorization. Revocation checking also blocks disabled users immediately.
- Firestore rules **deny all client access**. The app only reaches data through Express.
- Payroll maths and the location check run on the server only.

### Tech stack
| Layer | Choice |
|---|---|
| Mobile | Flutter, Riverpod, dio, go_router, geolocator, permission_handler |
| API | Node.js, Express 5, TypeScript, zod 4 (validation), firebase-admin (modular imports) |
| Data | Firestore (region: asia-south1) |
| Auth | Firebase Auth (email and password) with a `role` custom claim |
| Dev environment | The real Firebase project with a service account key. Emulators are optional. |
| Tests | Vitest or Jest for the pure domain maths |

Package versions are whatever `backend/package-lock.json` pins. Do not downgrade them.

---

## 3. Rules that are cheap now and expensive later

1. Money is stored and sent as **integer paise**. Never floats. The app converts to and from rupees for display.
2. Attendance dates are `YYYY-MM-DD` strings in **IST**, not timestamps. The day key is computed from server time at a fixed +05:30 offset (India has no DST).
3. Punch times use **server time**, stored as Firestore timestamps (UTC), displayed in IST.
4. Payslips are **not stored**. Store the inputs (salary history, adjustments, attendance, month lock) so a payslip regenerates identically.
5. Employees are **deactivated, never deleted**.
6. Attendance and payroll maths live in one **pure, unit-tested module** (`backend/src/domain`) with no Firebase imports.
7. Firestore rules deny all from day one.
8. Every admin edit records `editedBy` and `editedAt`.
9. Check-in and check-out run inside a **Firestore transaction** so double taps and retries cannot create duplicates.

---

## 4. Data model

### `employees/{empId}`
`empCode`, `name`, `email`, `phone`, `role` (`employee` only; admins are created by script), `designation`, `doj` (date string), `dol` (date string, set on deactivation), `status` (`active` | `inactive`), `primaryBranchId`, `allowedBranchIds[]`, `createdAt`, `updatedAt`

`empId` equals the Firebase Auth `uid`. `empCode` (e.g. `EMP001`) is generated with a Firestore transaction counter. Admin users get a minimal doc (`name`, `email`, `role: "admin"`, `status`) so `GET /me` works the same for both roles.

### `salary_history/{empId}_{effectiveFrom}`
`empId`, `effectiveFrom` (date string), `monthlyCtcPaise`

A month uses the latest revision with `effectiveFrom` on or before the month's last day.

### `branches/{branchId}`
`name`, `address`, `state`, `lat`, `lng`, `radiusMeters`, `status`

`state` is stored now because Professional Tax depends on it later.

### `attendance/{yyyy-mm}_{empId}`
One document per employee per month. It carries `empId` and `month` as real fields so it can be queried (`where month == "2026-10"`).

```
empId, month,
days: {
  "2026-10-06": {
    status: "P" | "H" | "A" | "L" | "UL",
    inTime, outTime,              // Firestore timestamps (UTC)
    inBranchId, outBranchId,
    inDistance, outDistance,      // metres from the branch
    workedMinutes,
    source: "app" | "admin_edit" | "leave",
    editedBy, editedAt
  }
}
```

Weekly offs and holidays are **not** stored here. They are derived from settings and `holidays`.

### `checkins/{id}`
The raw trail: `empId`, `type` (`in` | `out`), `serverTime`, `date`, `lat`, `lng`, `accuracy`, `branchId`, `distance`, `deviceId`, `isMocked`, `accepted`, `rejectReason`

Rejected attempts are saved too (best effort, outside the transaction) so the admin can review them later.

### `leave_requests/{id}`
`empId`, `fromDate`, `toDate`, `reason`, `status` (`pending` | `approved` | `rejected`), `leaveType` (`paid` | `unpaid`, set on approval), `decidedBy`, `decidedAt`, `skippedDates[]`, `createdAt`

### `holidays/{yyyy-mm-dd}`
`name`

### `payroll_adjustments/{yyyy-mm}_{empId}`
`bonusPaise`, `otherDeductionPaise`, `remarks`

### `payroll_months/{yyyy-mm}`
`locked`, `lockedBy`, `lockedAt`, `unlockedBy`, `unlockedAt`

### `settings/company`
`companyName`, `weeklyOffDays` (default `[0]`, Sunday), `perDayBasis` (`calendar` | `working`, default `calendar`), `maxAccuracyMeters` (default 100), `rejectMockLocation` (default true), `enforceCheckoutLocation` (default false)

---

## 5. Day statuses and the monthly summary

| Status | Meaning | Counts as |
|---|---|---|
| P | Present (checked in or admin-marked) | 1 present |
| H | Half day (admin-marked) | 0.5 present, 0.5 LOP |
| A | Absent (admin-marked or derived) | 1 LOP |
| L | Paid leave | Paid, no LOP |
| UL | Unpaid leave | 1 LOP |
| Weekly off / Holiday | Derived | Paid, no LOP |

**LOP = absent + unpaidLeave + 0.5 × halfDays**
**payableDays = daysInMonth − LOP**

Rules:
- **Derived absent:** any past working day with no attendance record, no leave and no holiday counts as Absent when the summary is calculated. No nightly job is needed.
- **Joiners and leavers:** days before `doj` and after `dol` are ignored (neither absent nor LOP).
- **Future days** in the current month are not counted.
- **Precedence:** an explicit attendance record wins over derived weekly off or holiday (someone who punches in on a holiday is Present).
- The summary is calculated on every request, never stored.

```
GET /attendance/summary?month=2026-10&empId=...
{ daysInMonth, weeklyOffs, holidays, present, halfDays, absent,
  paidLeave, unpaidLeave, lop, payableDays }
```

### Admin by-date list
`GET /attendance?date=` returns **every active employee** for that date, not only those with a record. Each row has the stored fields when present, plus a derived `status` and `derivedReason` (`absent`, `weekly_off`, `holiday`, `not_joined`, `left`) for employees with no record. It also carries a `noCheckout` flag when there is an in-time and no out-time.

---

## 6. Check-in flow

1. Employee taps **Check in**. The app makes sure location services and permission are on, then gets a high-accuracy fix and reads `isMocked`.
2. The app shows the distance to the nearest allowed branch (UX only).
3. The app calls `POST /attendance/check-in` with `lat`, `lng`, `accuracy`, `deviceId`, `isMocked`.
4. The **server decides**:
   - Reject if the employee is inactive or has not joined yet.
   - Reject if accuracy is worse than `maxAccuracyMeters`.
   - Reject if mocked and `rejectMockLocation` is on.
   - Compute Haversine distance to each allowed branch and pick the nearest.
   - Accept if `distance − min(accuracy, 50) <= radiusMeters`.
   - Reject if the month is locked.
5. **Inside one Firestore transaction:** read the month's attendance doc, reject if the day already has a check-in, then write the `checkins` record and set the day to `P` with `inTime`, `inBranchId`, `inDistance`.
6. **Check-out** (also transactional) needs an existing check-in and no existing out-time. It records `outTime`, branch, distance and `workedMinutes`. Location is recorded but only blocks when `enforceCheckoutLocation` is on.
7. One in and one out per day. A check-out always belongs to the **day of its check-in**, even if it happens after midnight. If there is no check-out, `workedMinutes` stays empty and the day is flagged "no check-out" for the admin. It does not become absent automatically.

---

## 7. API conventions

- JSON in and out. Validate every request body and query with zod.
- Errors use one shape: `{ "error": { "code": "VALIDATION_ERROR", "message": "...", "details": {} } }`.
- Status codes: 400 validation, 401 missing or invalid token, 403 wrong role or inactive user, 404 not found, 409 conflict (duplicate check-in, locked month, overlapping leave), 422 business-rule rejection (outside geofence, poor accuracy, mock location).
- Money is integer paise. Dates are `YYYY-MM-DD` (IST). Months are `YYYY-MM`.
- Layers: routes (HTTP only) call services (Firebase access, transactions) which call the pure domain module (maths).

## 8. API

All routes require a valid ID token. `[admin]` means admin only.

**Auth / profile**
- `GET /me`

**Employees**
- `POST /employees` [admin]. Creates the Auth user with the admin-supplied temporary password, sets the `role` claim, saves the doc and the first salary revision.
- `GET /employees` [admin]
- `GET /employees/:id` [admin, or self]
- `PATCH /employees/:id` [admin]
- `POST /employees/:id/salary` [admin] (add a salary revision)
- `POST /employees/:id/deactivate` [admin]. Sets `status: inactive` and `dol`, **disables the Auth user and revokes refresh tokens**.
- `POST /employees/:id/reactivate` [admin]. Enables the Auth user again and clears `dol`.

**Branches**
- `POST /branches` [admin]
- `GET /branches`
- `PATCH /branches/:id` [admin]

**Attendance**
- `POST /attendance/check-in`
- `POST /attendance/check-out`
- `GET /attendance/me?month=` (own days)
- `GET /attendance?date=` [admin] (all active employees, see section 5)
- `GET /attendance/employee/:id?month=` [admin]
- `PATCH /attendance/:empId/:date` [admin] (edit status or times; rejected for locked months and future dates)
- `GET /attendance/summary?month=&empId=` (admin: any or all; employee: own)
- `GET /checkins/flagged` [admin] (rejected attempts)

**Leave**
- `POST /leaves` (rejected if dates overlap another pending or approved request, or fall before `doj`)
- `GET /leaves/me`
- `GET /leaves?status=pending` [admin]
- `POST /leaves/:id/decision` [admin] (`approved` or `rejected`, plus `paid` or `unpaid`)

**Holidays and settings**
- `GET /holidays`, `POST /holidays` [admin]
- `GET /settings`, `PATCH /settings` [admin]

**Payroll**
- `GET /payroll/preview?month=` [admin]
- `PUT /payroll/adjustments/:month/:empId` [admin] (rejected when the month is locked)
- `POST /payroll/finalize?month=` [admin]. Only allowed once the month is fully over (today in IST is after its last day). Locks the month.
- `POST /payroll/unlock?month=` [admin]. Unlocks and records `unlockedBy` and `unlockedAt`.
- `GET /payslip?month=&empId=` (admin: any month for any employee; employee: own, and only for finalized months)

### Leave approval rules
- Approval writes `L` or `UL` for each date in the range, in one batch across all affected month docs (a request can span two months).
- Weekly offs and holidays inside the range are **not** written.
- Days that already have a punch (`P` or `H`) are **skipped** and returned in the response as `skippedDates`.
- If any month in the range is locked, the approval is rejected with 409.

### Locking
Once a month is finalized, attendance edits, leave approvals that touch it, check-ins for it, and payroll adjustments for it are all rejected until it is unlocked.

---

## 9. Payroll calculation

Port the logic from the HTML prototype (`docs/prototype.html`) into one pure function:

```
input:  monthlyCtcPaise, summary (payableDays, lop, daysInMonth), adjustments
output: earnings, deductions, gross, net
```

- Per-day rate = monthly salary ÷ `daysInMonth` (calendar basis, configurable).
- LOP deduction = `lop × perDayRate`.
- Earnings, PF, ESI and PT rules follow the prototype.
- Round once per line item with a single rounding rule. Sum the rounded items.
- Employees who joined or left mid-month are handled by the summary (days outside `doj` to `dol` are ignored), and the salary is not otherwise prorated in the POC.

**To verify with a CA before real use:** the PF wage ceiling and employer share, the ESI eligibility wage definition, and whether Professional Tax for Tamil Nadu is half-yearly rather than monthly.

---

## 10. Flutter screens

**Both roles:** login, profile

**Employee**
- Home: today's status, distance to branch, check-in and check-out button
- Attendance calendar with a summary header (present, half days, absent, LOP)
- Apply leave and my requests
- Payslip (month picker, rendered from the API response)

**Admin**
- Dashboard: present and absent counts today, pending leaves
- Employees: list, add and edit (with temporary password), deactivate, assign branches, salary
- Branches: list, add and edit (use current location, radius)
- Attendance by date: in-time, out-time, hours, branch, status chip, "no check-out" flag, tap to edit
- Attendance by employee: month calendar with details
- Leave requests: approve or reject as paid or unpaid
- Payroll: month picker, preview table, adjustments, finalize and unlock
- Payslip view for any employee
- Settings and holidays

### Running the app against a local API
- The API base URL must be configurable (use `--dart-define=API_BASE_URL=...`).
- Android emulator reaches your computer at `http://10.0.2.2:8080`. A physical phone needs your computer's LAN IP, an https tunnel (e.g. ngrok), or a Cloud Run deployment.
- Android 9+ and iOS block plain `http` by default. Add a development-only cleartext exception, or use an https tunnel.
- For geofence testing, set a branch's coordinates to where you currently are.

---

## 11. Setup

### You (Firebase console, ~15 minutes)
1. Create a Firebase project.
2. Enable Authentication, with the Email/Password provider.
3. Create a Firestore database in production mode, region `asia-south1`.
4. Register the Android app (and iOS if needed).
5. Generate a service account key and keep it out of git.
6. Blaze plan is only needed when deploying to Cloud Run.

### Tools to install
Node.js LTS, Flutter SDK (with Android Studio or Xcode), Firebase CLI (`npm i -g firebase-tools`), FlutterFire CLI (`dart pub global activate flutterfire_cli`), Git.

### Repo layout
```
/
├── plan.md
├── AGENTS.md
├── docs/prototype.html       (the original HTML prototype, reference for payroll formulas)
├── firebase.json
├── firestore.rules           (deny all)
├── firestore.indexes.json
├── backend/
│   ├── src/
│   │   ├── app.ts, server.ts
│   │   ├── config/
│   │   ├── middleware/       (auth, role, validate, error)
│   │   ├── routes/
│   │   ├── services/
│   │   ├── domain/           (pure maths: geo, dates, attendance summary, payroll)
│   │   └── scripts/          (check-firebase, seed-admin, seed-demo)
│   ├── test/
│   └── secrets/              (git-ignored; service account key lives here)
└── app/                      (Flutter)
    └── lib/
        ├── core/             (api client, auth, theme, router)
        └── features/         (auth, employees, branches, attendance, leave, payroll)
```

---

## 12. Build order

Each step ends with something you can demo and test. Do one step at a time and commit after each.

### Step 0: Setup
- [x] Backend skeleton (Express + TypeScript + Firebase Admin, `/health`, `check:firebase`)
- [x] `firebase.json`, deny-all rules, `.gitignore`
- [ ] Verified against the real Firebase project (`npm run check:firebase` passes)
- [ ] Deploy deny-all rules (`firebase deploy --only firestore:rules`)
- [ ] Flutter project with dependencies and `flutterfire configure`

### Step 1: Auth and roles
- [ ] Auth middleware (verify token with revocation check) and role middleware
- [ ] Standard error shape and error middleware
- [ ] `seed-admin` script that creates the first admin, sets the claim, and writes the admin doc
- [ ] `GET /me`
- [ ] Flutter login, API client that attaches the token, routing to the admin or employee home
- [ ] **Done when:** two test users log in and see different screens, and a request without a token gets 401

### Step 2: Employees
- [ ] Employee endpoints, ID counter transaction, salary revisions
- [ ] Deactivate and reactivate (disable Auth user, revoke tokens)
- [ ] Flutter list and add or edit forms
- [ ] **Done when:** the admin creates an employee who can log in, and a deactivated employee is blocked immediately

### Step 3: Branches
- [ ] Branch endpoints
- [ ] Flutter branch form with "use my current location" and radius
- [ ] Assign branches to employees

### Step 4: Check-in and check-out (the core)
- [ ] Haversine, geofence and IST date helpers with unit tests
- [ ] Transactional check-in and check-out endpoints, `checkins` records
- [ ] Flutter home screen: permissions, distance readout, clear rejection messages
- [ ] **Done when:** inside the radius succeeds, outside is rejected, mock location is flagged, a double tap creates one check-in

### Step 5: Attendance views
- [ ] Summary function with unit tests (statuses, holidays, weekly offs, `doj`, `dol`, derived absent)
- [ ] Holidays and settings endpoints
- [ ] Admin by-date list with in and out times, hours and derived statuses
- [ ] Admin edit (status and times)
- [ ] Employee calendar with the summary header

### Step 6: Leave
- [ ] Apply, list, and approve or reject endpoints with the edge-case rules above
- [ ] Approval writes `L` or `UL` on the requested dates
- [ ] Flutter apply screen and admin approval screen

### Step 7: Payroll
- [ ] Pure payroll function with unit tests, ported from `docs/prototype.html`
- [ ] Preview, adjustments, finalize and unlock
- [ ] On-demand payslip endpoint
- [ ] Flutter admin payroll screens and employee payslip screen

### Step 8: Demo pass
- [ ] `seed-demo` script: 2 branches, 5 employees, a month of sample attendance
- [ ] Run the full happy path, fix rough edges
- [ ] Deploy the API to Cloud Run (optional for the POC)

---

## 13. Decisions and defaults

| # | Question | Default for the POC |
|---|---|---|
| 1 | Which branches can an employee check in at? | Any branch in `allowedBranchIds` |
| 2 | Holidays and weekly offs in the POC? | Yes: Sunday plus a `holidays` collection |
| 3 | Per-day rate basis | Calendar days of the month (setting) |
| 4 | Enforce location on check-out? | Record only, do not block (setting) |
| 5 | Mock location | Reject (setting) |
| 6 | Statutory items on the payslip | As in the prototype (PF, ESI, PT), to be verified |
| 7 | Late or short-hours deductions | None. Times are shown only |
| 8 | Who can see a payslip? | Employee: own finalized months. Admin: any |
| 9 | Do admins appear in attendance and payroll? | No, management-only (assumption) |
| 10 | Can a finalized month be unlocked? | Yes, by an admin, with a record of who and when (assumption) |
| 11 | How does a new employee get credentials? | Admin sets a temporary password |
| 12 | Check-out after midnight | Belongs to the check-in day |

---

## 14. Risks to keep in mind

- GPS indoors can be inaccurate. Use the accuracy cutoff and a "try again" message.
- Mock-location detection is reliable on Android and weak on iOS. Treat it as risk reduction, and keep the `checkins` trail for review.
- A new custom claim only appears after the client refreshes its ID token (`getIdToken(true)`).
- Firestore batches max out at 500 writes. Keep this in mind for bulk operations.
- Reading a whole month of attendance docs for the admin by-date list is fine for a POC but should be revisited with many employees.
- Statutory rules need a CA's review before real payroll use.

---

## 15. What changed in this revision

- Attendance docs now carry `empId` and `month`; the admin by-date list returns derived statuses for employees with no record.
- Check-in and check-out are transactional.
- Deactivation disables the Auth user, revokes tokens, sets `dol`, and tokens are verified with revocation checking.
- Employee credentials: admin sets a temporary password.
- Leave edge cases defined (multi-month, existing punches, locked months, weekly offs and holidays, overlapping requests).
- Finalize only for completed months; added unlock.
- API units, error shape and status codes defined.
- Check-out after midnight belongs to the check-in day; day keys use a fixed +05:30 offset.
- Emulators are optional; real project is the default.
- Added `docs/prototype.html`, `AGENTS.md`, local device testing notes, and the assumption that admins are management-only.
