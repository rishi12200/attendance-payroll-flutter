# Attendance & Payroll App: POC Plan

Mobile app (Flutter) with an Express API on Cloud Run and Firebase (Auth, Firestore) as the backend. Two roles: **admin** and **employee**. Multi-branch company with location-based check-in.

The goal of the POC is one thin end-to-end slice that works: login, geofenced check-in, attendance views, leave with types and balances, and payroll with an on-demand payslip. Everything else is deferred.

**Status:** Steps 0 to 5 are done and verified. Step 6 (leave) backend is done and the Flutter screens are built, with live verification still pending. New requirements (leave types, balances, half-day leave, branch-wise holidays) are scheduled as Steps 6.5 and 6.6, **before payroll**, because they change the numbers payroll reads. Regularization, charts and other additive features come after the plan is complete (see section 12, "After the plan").

---

## 1. Scope

### In the POC
- Login with two roles (admin, employee). The admin creates employees and sets a temporary password.
- Admin: manage employees and branches
- Employee: check-in and check-out, only when inside an allowed branch
- Admin: see every employee's in-time, out-time, hours worked and status for a day, and edit it
- Employee: monthly attendance calendar with a day-count summary
- **Holidays by branch:** a holiday applies to all branches or to chosen branches. Employees see their own holiday list.
- **Leave types:** admin-managed types (Casual, Sick, Annual, Floating Holiday, Unpaid, and so on), each with a paid flag, a yearly quota, and whether half days are allowed
- **Leave:** employees apply with a type, optionally for a first or second half of one day. Admin approves or rejects.
- **Leave balances** per type (quota, used, pending, remaining), shown as plain data. Charts come later.
- Payroll: monthly preview, admin adjustments (bonus, other deductions), month lock and unlock
- Payslip generated on demand, never saved

### Assumptions (change if wrong)
- Admins are management-only accounts. They do not check in and do not appear in payroll, so they need no branch or salary.
- Finalized months can be unlocked by an admin (corrections will be needed).
- Leave year runs January to December (a setting).
- Quotas are fixed yearly numbers per leave type. No monthly accrual and no carry-forward in the POC.

### Deferred (after the plan is complete)
- Attendance regularization with admin-managed types (business trip, WFH, training and so on)
- Leave balance charts (donut or bar) in the employee Leave tab
- Leave accrual, carry-forward, manual balance adjustments by the admin
- Per-end sessions for multi-day leave (start in the second half, end in the first half)
- Revoking an approved leave directly (the admin edits individual days instead)
- Refunding balance when a leave day is later overridden by a check-in or an admin edit
- Offline check-in queue
- Push notifications (FCM) and scheduled jobs (reminders, auto-close)
- Server-side PDF export of payslips
- Deductions for late arrival or short hours
- Overtime, shifts
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
- Payroll maths, the location check, leave quotas and balances run on the server only.

### Tech stack
| Layer | Choice |
|---|---|
| Mobile | Flutter, Riverpod, dio, go_router, geolocator, shared_preferences |
| API | Node.js, Express 5, TypeScript, zod 4 (validation), firebase-admin (modular imports) |
| Data | Firestore (region: asia-south1) |
| Auth | Firebase Auth (email and password) with a `role` custom claim |
| Dev environment | The real Firebase project with a service account key. Emulators are optional. |
| Tests | Node test runner for the backend, flutter_test for the app |

Package versions are whatever the lockfiles pin. Do not downgrade them.

---

## 3. Rules that are cheap now and expensive later

1. Money is stored and sent as **integer paise**. Never floats. The app converts to and from rupees for display.
2. Attendance dates are `YYYY-MM-DD` strings in **IST**, not timestamps. The day key is computed from server time at a fixed +05:30 offset (India has no DST).
3. Punch times use **server time**, stored as Firestore timestamps (UTC), displayed in IST.
4. Payslips are **not stored**. Store the inputs (salary history, adjustments, attendance, month lock) so a payslip regenerates identically.
5. Employees are **deactivated, never deleted**.
6. Attendance, leave and payroll maths live in **pure, unit-tested modules** (`backend/src/domain`) with no Firebase imports.
7. Firestore rules deny all from day one.
8. Every admin edit records `editedBy` and `editedAt`.
9. Check-in and check-out run inside a **Firestore transaction** so double taps and retries cannot create duplicates.
10. **Leave balances are calculated, not stored.** They are derived from leave types and approved and pending requests every time.
11. Leave quantities (days used, remaining, summary counts) are **decimals** because half days count as 0.5. Never round them to integers.
12. **Paid or unpaid is decided by the leave type**, never typed in by the admin at approval time.

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

`state` is used for branch-wise holidays and later for Professional Tax.

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
    leaveRequestId, leaveTypeId,  // on full-day L / UL days written by leave approval
    halfLeave: {                  // only on a day with a half-day leave (Step 6.6)
      session: "first_half" | "second_half",
      paid: true | false,
      leaveTypeId, leaveRequestId
    },
    editedBy, editedAt
  }
}
```

Weekly offs and holidays are **not** stored here. They are derived from settings and `holidays`. A half-day leave is stored as a `halfLeave` marker next to the day's punch data, so it never overwrites a punch.

### `checkins/{id}`
The raw trail: `empId`, `type` (`in` | `out`), `serverTime`, `date`, `lat`, `lng`, `accuracy`, `branchId`, `distance`, `deviceId`, `isMocked`, `accepted`, `rejectReason`

Rejected attempts are saved too (best effort, outside the transaction) so the admin can review them later.

### `leave_types/{id}` (Step 6.6)
`name`, `code` (short, e.g. `CL`), `paid` (boolean), `annualQuotaDays` (number, or null for unlimited), `allowHalfDay` (boolean), `status` (`active` | `inactive`), `system` (boolean), `sortOrder`, `createdAt`, `updatedAt`

Seeded by a script (admin edits the values afterwards; the numbers below are sample values only):
- Annual Leave (`AL`, paid, 18 days, half days allowed)
- Casual Leave (`CL`, paid, 8 days, half days allowed)
- Sick Leave (`SL`, paid, 8 days, half days allowed)
- Floating Holiday (`FH`, paid, 2 days, no half days)
- **Unpaid Leave** (`UL`, unpaid, unlimited, half days allowed, `system: true`). It cannot be deactivated and its paid flag cannot change.
- **Paid Leave (legacy)** (`PL`, paid, unlimited, `status: inactive`). Only exists so requests approved before Step 6.6 still display. It never appears in the apply picker.

Rules: types in use are deactivated, never deleted. Changing a type's `paid` flag affects future approvals only. Already approved days keep what was written.

### `leave_requests/{id}`
`empId`, `fromDate`, `toDate`, `reason`, `status` (`pending` | `approved` | `rejected` | `cancelled`), `decidedBy`, `decidedAt`, `decisionNote`, `writtenDates[]`, `skippedDates[]` (`{ date, reason }`), `createdAt`, `updatedAt`

Added in Step 6.6: `leaveTypeId`, `leaveTypeName` and `paid` (snapshots taken at apply time), `session` (`full` | `first_half` | `second_half`, default `full`), `requestedDays` (decimal, working days the request covers), `writtenDays` (decimal, set on approval).

Requests approved before Step 6.6 have `leaveType: "paid" | "unpaid"` and no `leaveTypeId`. They are read as the legacy Paid Leave type or the Unpaid Leave type.

### `holidays/{id}` (changed in Step 6.5)
`date` (date string), `name`, `scope` (`all` | `branches`), `branchIds[]` (when scope is `branches`), `createdBy`, `createdAt`

Several holidays may exist on the same date with different scopes. **Existing holiday documents** are keyed by date (`holidays/2026-10-02`, with `name` only). They stay as they are and are read as `scope: all` with `date` taken from the document id. New holidays use generated ids. The delete endpoint takes the document id, so old and new documents are removed the same way.

An employee's holidays are those with scope `all`, plus those whose `branchIds` contain the employee's **primary branch**. An employee with no primary branch gets only `all` holidays.

### `payroll_adjustments/{yyyy-mm}_{empId}`
`bonusPaise`, `otherDeductionPaise`, `remarks`

### `payroll_months/{yyyy-mm}`
`locked`, `lockedBy`, `lockedAt`, `unlockedBy`, `unlockedAt`

### `settings/company`
`companyName`, `weeklyOffDays` (default `[0]`, Sunday), `perDayBasis` (`calendar` | `working`, default `calendar`), `maxAccuracyMeters` (default 100), `rejectMockLocation` (default true), `enforceCheckoutLocation` (default false), `leaveYearStartMonth` (1 to 12, default 1)

### Migration notes
- Decide or cancel every **pending** leave request before Step 6.6 goes live. Pending requests have no type.
- Run the leave type seed script once.
- Old holidays and old approved leave need no data migration (see above).

---

## 5. Day statuses and the monthly summary

| Status | Meaning | Counts as |
|---|---|---|
| P | Present (checked in or admin-marked) | 1 present |
| H | Half day (admin-marked) | 0.5 present, 0.5 LOP |
| A | Absent (admin-marked or derived) | 1 LOP |
| L | Paid leave | Paid, no LOP |
| UL | Unpaid leave | 1 LOP |
| HL | Half-day leave (a `halfLeave` marker, Step 6.6) | 0.5 leave + 0.5 "other half" |
| Weekly off / Holiday | Derived | Paid, no LOP |

**LOP = absent + unpaidLeave + 0.5 × halfDays**
**payableDays = daysInMonth − LOP**

Rules:
- **Derived absent:** any past working day with no attendance record, no leave and no holiday counts as Absent when the summary is calculated. No nightly job is needed.
- **Joiners and leavers:** days before `doj` and after `dol` are ignored (neither absent nor LOP).
- **Future days** in the current month are not counted.
- **Precedence:** an explicit attendance record wins over derived weekly off or holiday (someone who punches in on a holiday is Present).
- **Holidays depend on the employee's primary branch** (see section 4). The calendar, the summary, the admin by-date list, leave classification and payroll all use the same per-employee holiday lookup.
- The summary is calculated on every request, never stored.

### Half-day leave (HL, Step 6.6)
A day with a `halfLeave` marker contributes 0.5 to `paidLeave` (paid type) or `unpaidLeave` (unpaid type), and the **other half** is decided like this:

| Other half | When |
|---|---|
| Present (0.5 `present`) | The day has a check-in, or its stored status is P |
| Absent (0.5 `absent`) | The date is before today and there is no check-in |
| Pending (0.5 `pending`) | Today or a future date with no check-in |

So half paid leave plus a punch is 0.5 leave + 0.5 present with no LOP. Half paid leave on a past day with no punch is 0.5 LOP. Half unpaid leave plus a punch is 0.5 LOP, and half unpaid leave with no punch is 1 LOP.

All summary counts may be decimals. **Every date must still be counted exactly once**: present + halfDays + absent + paidLeave + unpaidLeave + weeklyOffs + holidays + notJoinedOrLeftDays + pending equals `daysInMonth`.

```
GET /attendance/summary?month=2026-10&empId=...
{ daysInMonth, weeklyOffs, holidays, present, halfDays, absent,
  paidLeave, unpaidLeave, notJoinedOrLeftDays, pending, lop, payableDays }
```

### Admin by-date list
`GET /attendance?date=` returns **every employee whose joining window includes the date**, not only those with a record. Each row has the stored fields when present, plus a derived `status` and `derivedReason` for employees with no record. It also carries `noCheckout` and `checkedInNow` flags.

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
8. A check-in on a **full-day** leave day turns that day into Present. A check-in on a day with a **half-day** leave keeps the `halfLeave` marker, and the other half counts as present.

---

## 7. API conventions

- JSON in and out. Validate every request body and query with zod.
- Errors use one shape: `{ "error": { "code": "VALIDATION_ERROR", "message": "...", "details": {} } }`.
- Status codes: 400 validation, 401 missing or invalid token, 403 wrong role or inactive user, 404 not found, 409 conflict (duplicate check-in, locked month, overlapping leave, already decided), 422 business-rule rejection (outside geofence, poor accuracy, mock location, quota exceeded).
- Money is integer paise. Dates are `YYYY-MM-DD` (IST). Months are `YYYY-MM`. Timestamps are ISO strings. Leave quantities are decimals.
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
- `GET /employees/:id/salary`, `POST /employees/:id/salary` [admin]
- `POST /employees/:id/deactivate` [admin]. Sets `status: inactive` and `dol`, **disables the Auth user and revokes refresh tokens**.
- `POST /employees/:id/reactivate` [admin]

**Branches**
- `POST /branches` [admin], `GET /branches`, `GET /branches/:id`, `PATCH /branches/:id` [admin]
- `POST /branches/:id/deactivate`, `POST /branches/:id/reactivate` [admin]

**Attendance**
- `POST /attendance/check-in`, `POST /attendance/check-out`
- `GET /attendance/me?month=` (own days, used by the punch screen)
- `GET /attendance/me/calendar?month=` [employee], `GET /attendance/employee/:id/calendar?month=` [admin]
- `GET /attendance?date=` [admin] (all employees in their joining window, see section 5)
- `PATCH /attendance/:empId/:date` [admin] (edit status or times; rejected for locked months and future dates)
- `GET /attendance/summary?month=&empId=` (admin: any or all; employee: own)
- `GET /checkins/flagged` [admin] (rejected attempts, no coordinates)

**Settings**
- `GET /settings`, `PATCH /settings` [admin]

**Holidays (Step 6.5)**
- `GET /holidays?year=&branchId=` [admin]. Optional branch filter returns the holidays that apply to that branch.
- `GET /holidays/me?year=` [employee]. The employee's holidays from their primary branch.
- `POST /holidays` [admin] with `{ date, name, scope, branchIds? }`. A helper field `state` may be accepted to select every active branch in that state. 409 if an identical holiday (same date, same name, overlapping scope) exists, and 409 `MONTH_LOCKED` for locked months.
- `DELETE /holidays/:id` [admin]

**Leave types (Step 6.6)**
- `GET /leave-types` (employees see active types only, admins see all)
- `POST /leave-types`, `PATCH /leave-types/:id` [admin]
- `POST /leave-types/:id/deactivate`, `POST /leave-types/:id/reactivate` [admin]. System types cannot be deactivated.

**Leave**
- `POST /leaves` [employee] with `{ leaveTypeId, fromDate, toDate, reason, session? }` (type and session added in Step 6.6)
- `GET /leaves/me`, `POST /leaves/:id/cancel` [employee]
- `GET /leaves/balance?year=` [employee: own; admin may pass `empId`]. Per type: `quota`, `used`, `pending`, `remaining` (decimals; `remaining` is null for unlimited types).
- `GET /leaves`, `GET /leaves/:id`, `POST /leaves/:id/decision` [admin] with `{ decision, note? }` (Step 6.6 removes `leaveType` from the body; the type on the request decides)

**Payroll**
- `GET /payroll/preview?month=` [admin]
- `PUT /payroll/adjustments/:month/:empId` [admin] (rejected when the month is locked)
- `POST /payroll/finalize?month=` [admin]. Only allowed once the month is fully over (today in IST is after its last day). Locks the month.
- `POST /payroll/unlock?month=` [admin]. Unlocks and records `unlockedBy` and `unlockedAt`.
- `GET /payslip?month=&empId=` (admin: any month for any employee; employee: own, and only for finalized months)

### Leave rules (Step 6.6 target)
- **Applying:** the type must be active. `session` other than `full` needs a single date, a type with `allowHalfDay`, and that date to be a working day. `requestedDays` counts the working days in the range (weekly offs, holidays for the employee's branch and days outside employment are not counted), halved for a half-day request. The request is blocked with 422 `QUOTA_EXCEEDED` when `used + pending + requestedDays` would exceed the type's quota. Unlimited types skip the check. Overlap, month lock and joining-window rules from Step 6 still apply (a half-day on the first half and another request on the second half of the same date may be allowed later; for now any overlap is blocked).
- **Approving:** inside one transaction, re-check the quota against what has been approved since, then write the days.
  - Full-day request: write `L` (paid type) or `UL` (unpaid type) with `leaveRequestId` and `leaveTypeId`. Weekly offs and holidays are not written. Days with a punch (`P` or `H`) are skipped as `has_punch`.
  - Half-day request: write the `halfLeave` marker next to the day. A punch does **not** cause a skip. The day is skipped for `weekly_off`, `holiday`, `outside_employment`, or when it already holds a full-day leave or an admin-marked half day.
  - `writtenDays` is stored on the request, and `used` in balances counts approved requests' `writtenDays` by date within the leave year.
  - Any touched month that is locked blocks the approval and nothing is written.
- **Balances:** `used` comes from approved requests, `pending` from pending requests, both counted by date within the leave year (a request that spans two leave years is split by date). A day that is later overridden by a check-in or an admin edit is **not** refunded in the POC.
- **Audit:** each decision writes an `audit_logs` entry in the same transaction.

---

## 9. Payroll calculation

Port the logic from the HTML prototype (`docs/prototype.html`) into one pure function:

```
input:  monthlyCtcPaise, summary (payableDays, lop, daysInMonth), adjustments
output: earnings, deductions, gross, net
```

- Per-day rate = monthly salary ÷ `daysInMonth` (calendar basis, configurable).
- LOP deduction = `lop × perDayRate`. `lop` can be a decimal (for example 0.5), so round only after multiplying.
- Earnings, PF, ESI and PT rules follow the prototype.
- Round once per line item with a single rounding rule. Sum the rounded items.
- Leave types need no special handling in payroll: paid leave never increases `lop`, unpaid leave always does, and both are already inside the summary. Branch-wise holidays are also already inside the summary.
- Employees who joined or left mid-month are handled by the summary (days outside `doj` to `dol` are ignored), and the salary is not otherwise prorated in the POC.

**To verify with a CA before real use:** the PF wage ceiling and employer share, the ESI eligibility wage definition, and whether Professional Tax for Tamil Nadu is half-yearly rather than monthly.

---

## 10. Flutter screens

**Both roles:** login, profile

**Employee**
- Home: today's status, distance to branch, check-in and check-out button
- Attendance calendar with a summary header (present, half days, absent, LOP). Half-day leave days show their session and type.
- **Leave tab with three sections** (Step 6.5 and 6.6):
  - Requests: my requests with status filter, cancel, and an Apply button
  - Balance: one card per leave type showing quota, used, pending and remaining (data only, charts later)
  - Holidays: the employee's holiday list for a chosen year, from their primary branch
- Apply screen: leave type picker (with the remaining balance shown), date range, a Full day / First half / Second half choice that only appears for single days and types that allow half days, and a reason
- Payslip (month picker, rendered from the API response)

**Admin**
- Dashboard: menu tiles (Holidays, Settings, Leave requests, Flagged check-ins) with a pending leave badge
- Employees: list, add and edit (with temporary password), deactivate, assign branches, salary
- Branches: list, add and edit (use current location, radius)
- Attendance by date, month summary, employee calendars, edit sheet
- Leave requests: approve or reject. After Step 6.6 the sheet shows the leave type, session and the employee's remaining balance, and no longer asks for paid or unpaid.
- **Holidays:** year picker, a branch filter, and an add form with the scope choice (all branches, chosen branches, or every branch in a state)
- **Settings:** company, weekly offs, accuracy, and a **Leave types** screen (add, edit quota, toggle paid and half-day, deactivate)
- Payroll: month picker, preview table, adjustments, finalize and unlock
- Payslip view for any employee

### Running the app against a local API
- The API base URL must be configurable (use `--dart-define=API_BASE_URL=...`).
- Android emulator reaches your computer at `http://10.0.2.2:8080`. A physical phone needs your computer's LAN IP, an https tunnel (e.g. ngrok), or a Cloud Run deployment.
- Android 9+ and iOS block plain `http` by default. Add a development-only cleartext exception, or use an https tunnel.
- For geofence testing, set the emulator location (Extended controls, Location) to the branch's coordinates.

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
│   │   ├── domain/           (pure maths: geo, dates, calendar, leave, payroll)
│   │   └── scripts/          (check-firebase, seed-admin, seed-leave-types, seed-demo)
│   ├── test/
│   └── secrets/              (git-ignored; service account key lives here)
└── app/                      (Flutter)
    └── lib/
        ├── core/             (api client, auth, theme, router)
        └── features/         (auth, employees, branches, attendance, leave, payroll)
```

---

## 12. Build order

Each step ends with something you can demo and test. Do one step at a time, backend first and then Flutter, and commit after each piece.

### Step 0: Setup (done)
- [x] Backend skeleton, deny-all rules, Firebase verified
- [x] Flutter project connected to Firebase

### Step 1: Auth and roles (done)
- [x] Auth and role middleware, error shape, `seed-admin`, `GET /me`
- [x] Flutter login, API client, routing by role

### Step 2: Employees (done)
- [x] Employee endpoints, ID counter transaction, salary revisions, deactivate and reactivate
- [x] Flutter list, add and edit forms

### Step 3: Branches (done)
- [x] Branch endpoints, branch assignment on employees
- [x] Flutter branch screens and employee branch picker

### Step 4: Check-in and check-out (done)
- [x] Geofence, IST helpers, transactional punch endpoints
- [x] Flutter punch screen

### Step 5: Attendance views (done)
- [x] Calendar and summary domain, holidays and settings endpoints, admin by-date list, admin edit, flagged check-ins
- [x] Flutter calendars, admin day list, edit sheet, holidays, settings, flagged list

### Step 6: Leave (basic)
- [x] Apply, list, cancel, approve and reject endpoints with the edge-case rules
- [x] Flutter apply screen, request list, admin decision screen
- [ ] **Done when:** live verification of the Flutter screens (apply, overlap, cancel, approve paid, approve unpaid, reject, double decision, two-month range, calendar and summary after approval)

### Step 6.5: Branch-wise holidays and employee holiday list
Backend:
- [ ] Holiday documents gain `scope` and `branchIds`. Old date-keyed documents are read as `scope: all`.
- [ ] One shared "holidays for an employee" lookup (primary branch) used by the calendar, summary, admin by-date list and leave classification
- [ ] `GET /holidays?branchId=`, `GET /holidays/me`, `POST /holidays` with scope and state shortcut, `DELETE /holidays/:id`
- [ ] Domain tests: same date with different scopes, employee with no primary branch, old documents, summary sum check still equals days in the month

Flutter:
- [ ] Admin holidays screen: branch filter, add form with scope choice and state shortcut
- [ ] Employee Leave tab gets a Holidays section (year picker, own branch)
- [ ] **Done when:** a holiday scoped to branch X shows as a holiday for X's employees only, other branches see a normal working day, and every summary still counts each date exactly once

### Step 6.6: Leave types, balances and half-day leave
Backend:
- [ ] `leave_types` collection, `seed-leave-types` script, CRUD endpoints, system type rules
- [ ] Leave requests carry type, session and `requestedDays`. Apply validates type, half-day rules and quota.
- [ ] Decision no longer takes `leaveType`. Approval re-checks quota in the transaction, writes `L` or `UL` from the type, or the `halfLeave` marker for half-day requests. `writtenDays` stored.
- [ ] `GET /leaves/balance` (decimals, by leave year, `leaveYearStartMonth` setting)
- [ ] Calendar, by-date list and summary understand `halfLeave` (status `HL`, decimals, other-half rule). Sum check still equals days in the month.
- [ ] Legacy approved requests (`leaveType: paid | unpaid`) still display and count correctly
- [ ] Domain tests for every row of the half-day table, quota edges, leave-year boundaries, a request spanning two leave years

Flutter:
- [ ] Apply screen: type picker with remaining balance, session choice, quota error message
- [ ] Leave tab: Balance section (data cards per type)
- [ ] Admin Settings: Leave types screen. Decision sheet shows the type, session and balance, without a paid or unpaid choice.
- [ ] Calendars show half-day leave with session and type
- [ ] **Done when:** an employee applies for Sick Leave and sees the balance drop, a half-day request shows 0.5 on the balance and in the calendar, an over-quota request is blocked, paid types add no LOP and unpaid types do, and an admin can add a new leave type that employees immediately see

### Step 7: Payroll
- [ ] Pure payroll function with unit tests, ported from `docs/prototype.html`. It must accept decimal `lop`.
- [ ] Preview, adjustments, finalize and unlock
- [ ] On-demand payslip endpoint
- [ ] Flutter admin payroll screens and employee payslip screen
- [ ] **Done when:** a payslip generated twice for the same month is identical, a locked month rejects attendance, leave and holiday changes, and unlocking allows corrections

### Step 8: Demo pass
- [ ] `seed-demo` script: 2 branches, 5 employees, leave types, a month of sample attendance
- [ ] Run the full happy path, fix rough edges
- [ ] Deploy the API to Cloud Run (optional for the POC)

### After the plan (backlog)
- [ ] Attendance regularization: employee requests a correction for a past day with an admin-managed type (business trip, WFH, training and so on). Approval sets the day to Present and stores the type. Admin manages the type list in Settings. Needs no payroll change.
- [ ] Leave balance charts (donut or bar) in the employee Leave tab, on top of `GET /leaves/balance`
- [ ] Monthly accrual, carry-forward and manual balance adjustments by the admin
- [ ] Per-end sessions for multi-day leave
- [ ] Revoke an approved leave, and refund balance when a leave day is overridden
- [ ] Push notifications (leave decisions, payslip ready) and scheduled jobs
- [ ] Payslip PDF export, reports and CSV or Excel exports
- [ ] Password reset and forced password change on first login
- [ ] Offline check-in queue, map picker for branches
- [ ] Late-arrival and short-hours deductions, overtime, shifts (these would change payroll inputs, so plan them before any real payroll use)

---

## 13. Decisions and defaults

| # | Question | Default for the POC |
|---|---|---|
| 1 | Which branches can an employee check in at? | Any branch in `allowedBranchIds` |
| 2 | Holidays and weekly offs in the POC? | Yes: Sunday plus branch-aware holidays |
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
| 13 | Who decides paid or unpaid leave? | The leave type, not the admin at approval time |
| 14 | Leave year | January to December (`leaveYearStartMonth` setting, default 1) |
| 15 | Quotas | Fixed yearly number per type, no accrual, no carry-forward |
| 16 | Over-quota requests | Blocked at apply and re-checked at approval. Not auto-converted to unpaid |
| 17 | Half-day leave | Single-day requests only, first or second half, and only for types that allow it |
| 18 | Other half of a half-leave day | Present if the day has a punch, absent if the date has passed without one, otherwise pending |
| 19 | Holiday scope | All branches or chosen branches, with a state shortcut when adding |
| 20 | Which branch decides an employee's holidays? | Primary branch. With none, only all-branch holidays |
| 21 | Overridden leave days | A leave day later overridden by a check-in or admin edit is not refunded (POC limitation) |
| 22 | Attendance regularization | After the plan is complete (does not affect payroll) |
| 23 | Leave balance charts | After the plan is complete. Balances are data only until then |

---

## 14. Risks to keep in mind

- GPS indoors can be inaccurate. Use the accuracy cutoff and a "try again" message.
- Mock-location detection is reliable on Android and weak on iOS. Treat it as risk reduction, and keep the `checkins` trail for review.
- A new custom claim only appears after the client refreshes its ID token (`getIdToken(true)`).
- Firestore batches max out at 500 writes. Keep this in mind for bulk operations.
- Reading a whole month of attendance docs for the admin by-date list is fine for a POC but should be revisited with many employees.
- Changing weekly offs, holidays or a leave type's paid flag changes the derived numbers of any month that is not locked. Lock months once payroll is run.
- Half-day leave touches the summary maths. Test the sum check (every date counted exactly once) for every combination.
- Per-branch holidays mean two employees can have different statuses for the same date. The by-date list and payroll must look up holidays per employee, never once for the whole company.
- Statutory rules need a CA's review before real payroll use.

---

## 15. What changed in this revision

- Added requirements: leave types with paid flag and quotas, leave balances, half-day leave (first or second session), branch-wise holidays, and an employee holiday list.
- These are scheduled as Steps 6.5 and 6.6 **before payroll**, because they change what the summary and payroll read. Regularization, balance charts, accrual and carry-forward were moved to the backlog.
- New data: `leave_types`, holiday `scope` and `branchIds`, leave request `leaveTypeId`, `session`, `requestedDays` and `writtenDays`, attendance `halfLeave` marker, setting `leaveYearStartMonth`.
- The summary now allows decimal counts and a new HL status, with the "every date counted once" rule kept.
- Paid or unpaid is decided by the leave type. The admin no longer picks it when approving.
- Added migration notes (legacy holidays, legacy approved leave, decide pending requests first) and new decisions 13 to 23.
- Step statuses updated: Steps 0 to 5 done, Step 6 built and awaiting live verification.