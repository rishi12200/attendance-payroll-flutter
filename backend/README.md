# Backend development helpers

## Seed a test user

`seed:admin` is a development helper for creating Firebase Auth test accounts
and their minimal `employees/{uid}` profiles. Pass credentials as command-line
arguments; do not hardcode or commit them:

```powershell
npm run seed:admin -- --email admin@example.com --password "<temporary-password>"
npm run seed:admin -- --email employee@example.com --password "<temporary-password>" --role employee
```

The `--role` option accepts `admin` or `employee` and defaults to `admin`.
Employee seeding is only for development/testing; it creates a minimal profile
without an employee code or salary history. Real employee creation and salary
setup are provided by the employee API below.

## Employee API (Step 2 backend)

All endpoints require `Authorization: Bearer <Firebase ID token>`. The admin
endpoints require the `admin` role; employees may only read their own profile.
Successful responses serialize timestamps as ISO 8601 strings.

- `POST /employees` — create an employee with `name`, `email`,
  `tempPassword`, `doj`, and integer `monthlyCtcPaise`; `phone`,
  `designation`, `primaryBranchId`, and `allowedBranchIds` are optional.
  The primary branch is automatically included in the allowed branch IDs.
- `GET /employees?status=active|inactive|all` — list employee profiles without
  salary data. `status` defaults to `active`.
- `GET /employees/:id` — read any employee (admin) or the caller's own profile;
  only admins receive `currentMonthlyCtcPaise`.
- `PATCH /employees/:id` — edit `name`, `phone`, `designation`, `doj`,
  `primaryBranchId`, or `allowedBranchIds`. Email is read-only. Send
  `primaryBranchId: null` and `allowedBranchIds: []` to clear branch assignments.
- `GET /employees/:id/salary` — list salary revisions, newest first.
- `POST /employees/:id/salary` — add `effectiveFrom` and integer
  `monthlyCtcPaise`.
- `POST /employees/:id/deactivate` — disable Auth, revoke refresh tokens, then
  set inactive status and `dol`. An optional JSON body may provide `dol`.
- `POST /employees/:id/reactivate` — enable Auth, set active status, and clear
  `dol`.

All employee profiles include `primaryBranchId` and `allowedBranchIds`; older
profiles without these stored fields are returned as `null` and `[]`.

## Branch API (Step 3 backend)

Every endpoint requires an ID token. Branch write and admin-read endpoints
require the `admin` role. Employees can list only active branches in their
`allowedBranchIds` and read only those same branches. Branch timestamps are
returned as ISO 8601 strings.

- `POST /branches` — create an active branch with `name`, `state`, `lat`,
  `lng`, and integer `radiusMeters`; `address` is optional. Latitude must be
  from -90 to 90, longitude from -180 to 180, and radius from 20 to 1000m.
  Active names must be unique without regard to case.
- `GET /branches?status=active|inactive|all` — admin sees the selected status
  (default `active`); employee always sees only their active assigned branches.
- `GET /branches/:id` — admin can read any branch; employees can read only an
  active branch in their assigned list.
- `PATCH /branches/:id` — admin may edit `name`, `address`, `state`, `lat`,
  `lng`, or `radiusMeters`. The update records `editedBy` and `updatedAt`.
- `POST /branches/:id/deactivate` — admin only. Returns 409 and the active
  employee count while employees are assigned. Deactivation is idempotent.
- `POST /branches/:id/reactivate` — admin only; reactivation is idempotent and
  rejects a duplicate active branch name.

Example create request:

```json
{
  "name": "Chennai Office",
  "address": "12 Example Road",
  "state": "Tamil Nadu",
  "lat": 13.0827,
  "lng": 80.2707,
  "radiusMeters": 150
}
```

Example branch response:

```json
{
  "id": "branch-abc123",
  "name": "Chennai Office",
  "address": "12 Example Road",
  "state": "Tamil Nadu",
  "lat": 13.0827,
  "lng": 80.2707,
  "radiusMeters": 150,
  "status": "active",
  "createdAt": "2026-10-07T06:30:00.000Z",
  "updatedAt": "2026-10-07T06:30:00.000Z"
}
```

Example employee assignment fields in a create or patch body:

```json
{
  "primaryBranchId": "branch-abc123",
  "allowedBranchIds": ["branch-abc123", "branch-other456"]
}
```

## Attendance API (Step 4 backend)

All attendance endpoints require an employee ID token. Admin accounts are
management-only and receive `403 FORBIDDEN`. Attendance dates use IST
(`YYYY-MM-DD`); punch timestamps are assigned by the server and serialized as
ISO 8601 strings. The API accepts no client-supplied timestamp fields.

- `POST /attendance/check-in` — record one check-in for today. The server
  checks employment dates, active assigned branches, GPS accuracy, mock
  location, geofence distance, and payroll-month lock before writing the
  attendance day and raw `checkins` record transactionally.
- `POST /attendance/check-out` — close today's open check-in, or yesterday's
  open check-in if it is less than 24 hours old. Checkout is saved on the day
  of its check-in. Location is recorded; accuracy and distance only block
  checkout when `settings/company.enforceCheckoutLocation` is true.
- `GET /attendance/me?month=YYYY-MM` — return the caller's month attendance,
  the current IST date, and server time. `days` is empty if no monthly
  attendance document exists.

Check-in and check-out accept this body:

```json
{
  "lat": 13.0827,
  "lng": 80.2707,
  "accuracy": 12,
  "deviceId": "android-device-1",
  "isMocked": false
}
```

Example check-in response:

```json
{
  "date": "2026-10-07",
  "status": "P",
  "inTime": "2026-10-07T06:30:00.000Z",
  "branchId": "branch-abc123",
  "branchName": "Chennai Office",
  "distanceMeters": 24.6
}
```

Example check-out response:

```json
{
  "date": "2026-10-07",
  "inTime": "2026-10-07T06:30:00.000Z",
  "outTime": "2026-10-07T15:00:00.000Z",
  "workedMinutes": 510,
  "branchId": "branch-abc123",
  "branchName": "Chennai Office",
  "distanceMeters": 24.6
}
```

Example `GET /attendance/me?month=2026-10` response:

```json
{
  "month": "2026-10",
  "today": "2026-10-07",
  "serverTime": "2026-10-07T06:30:00.000Z",
  "days": {
    "2026-10-07": {
      "status": "P",
      "inTime": "2026-10-07T06:30:00.000Z",
      "inBranchId": "branch-abc123",
      "inDistance": 24.6,
      "source": "app"
    }
  }
}
```

Business-rule error codes include `NOT_YET_JOINED`, `EMPLOYMENT_ENDED`,
`NO_BRANCH_ASSIGNED`, `ACCURACY_TOO_LOW`, `MOCK_LOCATION`,
`OUTSIDE_GEOFENCE`, `MONTH_LOCKED`, `ALREADY_CHECKED_IN`,
`NOT_CHECKED_IN`, and `ALREADY_CHECKED_OUT`. Errors use the standard
`{ "error": { "code": "...", "message": "...", "details": {} } }` shape.
Outside-geofence errors include the nearest branch, distance, radius, and
reported accuracy in `details`. Rejected location attempts are recorded in
`checkins` on a best-effort basis.

## Attendance views, holidays and settings (Step 5 backend)

Attendance calendar days use the stored status when one exists. Otherwise,
dates before `doj` are `NOT_JOINED`, dates after inclusive `dol` are `LEFT`,
holidays beat weekly offs, and working days before today's IST date derive as
`A` (absent). Today and future working days without a record are `PENDING`.
Stored leave and punches are retained even on a future date, holiday, or weekly
off. A record outside the employee's joining window is ignored.

Summary counts partition every date in the month into `weeklyOffs`, `holidays`,
`present`, `halfDays`, `absent`, `paidLeave`, `unpaidLeave`,
`notJoinedOrLeftDays`, or `pending`. `lop` is absent + unpaid leave + half of
half-days; `payableDays` is `daysInMonth - lop`. Days outside the joining
window are neither absent nor LOP. Monthly salary is not prorated for joining
or leaving mid-month; payroll uses the summary and the configured per-day
basis.

- `GET /attendance/me/calendar?month=YYYY-MM` — employee's own calendar;
  admins receive 403.
- `GET /attendance/employee/:id/calendar?month=YYYY-MM` — admin calendar for
  any employee.
- `GET /attendance/summary?month=YYYY-MM` — admin summaries for employees
  whose joining window overlaps the month; an employee receives only their
  own summary.
- `GET /attendance/summary?month=YYYY-MM&empId=<uid>` — one admin summary, or
  an employee's own summary when `empId` is omitted or matches their UID.
- `GET /attendance?date=YYYY-MM-DD` — admin by-date rows for employees whose
  joining window includes the date. Employees without an attendance document
  are included. Future dates are allowed.
- `PATCH /attendance/:empId/:date` — admin edit with `{ "status": "P|H|A|L|UL",
  "inTime": "<ISO 8601, optional>", "outTime": "<ISO 8601, optional>",
  "reason": "<required, max 200 characters>" }`. Times are allowed only for
  `P` and `H`. `A`, `L`, and `UL` edits clear punch and branch/distance fields.
  Every edit sets `source: "admin_edit"`, records `editedBy`/`editedAt`, and
  writes an `attendance.edit` audit log transactionally.
- `GET /checkins/flagged?from=YYYY-MM-DD&to=YYYY-MM-DD` — rejected check-in
  attempts from a range of at most 31 inclusive days; omitted bounds default
  to the last seven IST dates. The response excludes raw latitude/longitude
  and is capped at 500 queried records.
- `GET /holidays?year=YYYY` — sorted holiday list for admins and employees.
- `POST /holidays` — admin create with `{ "date": "YYYY-MM-DD", "name":
  "Holiday name" }`; an existing date returns 409 `HOLIDAY_EXISTS`.
- `DELETE /holidays/:date` — admin delete; a missing date returns 404
  `HOLIDAY_NOT_FOUND`.
- `GET /settings` — admin effective settings, including defaults.
- `PATCH /settings` — admin partial update. Accepted fields are `companyName`,
  `weeklyOffDays` (unique weekday numbers 0–6), `perDayBasis` (`calendar` or
  `working`), `maxAccuracyMeters` (integer 10–500), `rejectMockLocation`, and
  `enforceCheckoutLocation`. Unknown fields are rejected. Updates record
  `editedBy` and `updatedAt`.

Default settings are `companyName: ""`, `weeklyOffDays: [0]`,
`perDayBasis: "calendar"`, `maxAccuracyMeters: 100`,
`rejectMockLocation: true`, and `enforceCheckoutLocation: false`. Changing
`weeklyOffDays` changes the derived statuses of past months that are not
locked; the calendar is built from the current settings and is not a stored
snapshot.

For this example the employee joined on October 6 and October 8 is a holiday.
The following calendar response is abbreviated to show a derived day and a
stored day; actual responses contain an entry for every date in the month.

Example `GET /attendance/me/calendar?month=2026-10` response:

```json
{
  "month": "2026-10",
  "today": "2026-10-10",
  "serverTime": "2026-10-10T10:00:00.000Z",
  "summary": {
    "daysInMonth": 31,
    "weeklyOffs": 3,
    "holidays": 1,
    "present": 1,
    "halfDays": 0,
    "absent": 3,
    "paidLeave": 0,
    "unpaidLeave": 0,
    "notJoinedOrLeftDays": 5,
    "pending": 18,
    "lop": 3,
    "payableDays": 28
  },
  "days": [
    {
      "date": "2026-10-06",
      "weekday": 2,
      "status": "A",
      "derived": true
    },
    {
      "date": "2026-10-10",
      "weekday": 6,
      "status": "P",
      "derived": false,
      "inTime": "2026-10-10T03:30:00.000Z",
      "inBranchId": "branch-abc123",
      "inBranchName": "Chennai Office",
      "source": "app"
    }
  ]
}
```

The following by-date response is abbreviated to one row; actual responses
contain all employees whose employment window includes the date.

Example admin by-date response:

```json
{
  "date": "2026-10-10",
  "today": "2026-10-10",
  "totals": {
    "P": 1,
    "H": 0,
    "A": 0,
    "L": 0,
    "UL": 0,
    "WEEKLY_OFF": 0,
    "HOLIDAY": 0,
    "PENDING": 1
  },
  "rows": [
    {
      "empId": "employee-uid",
      "empCode": "EMP001",
      "name": "Asha",
      "designation": "Associate",
      "date": "2026-10-10",
      "weekday": 6,
      "status": "P",
      "derived": false,
      "inTime": "2026-10-10T03:30:00.000Z",
      "inBranchName": "Chennai Office",
      "noCheckout": false,
      "checkedInNow": true
    }
  ]
}
```

Example effective settings response:

```json
{
  "companyName": "Example Company",
  "weeklyOffDays": [0],
  "perDayBasis": "calendar",
  "maxAccuracyMeters": 100,
  "rejectMockLocation": true,
  "enforceCheckoutLocation": false,
  "editedBy": "admin-uid",
  "updatedAt": "2026-10-10T10:00:00.000Z"
}
```

Example holiday response (`GET /holidays?year=2026`):

```json
[
  {
    "date": "2026-10-08",
    "name": "Company holiday"
  }
]
```

Example flagged-checkin response (coordinates are intentionally omitted):

```json
[
  {
    "id": "checkin-document-id",
    "empId": "employee-uid",
    "empCode": "EMP001",
    "name": "Asha",
    "type": "in",
    "date": "2026-10-09",
    "serverTime": "2026-10-09T03:30:00.000Z",
    "rejectReason": "OUTSIDE_GEOFENCE",
    "nearestBranchName": "Chennai Office",
    "distanceMeters": 1200,
    "accuracy": 15,
    "isMocked": false,
    "deviceId": "install-id"
  }
]
```

Example admin edit response:

```json
{
  "date": "2026-10-09",
  "weekday": 5,
  "status": "P",
  "derived": false,
  "inTime": "2026-10-09T03:30:00.000Z",
  "outTime": "2026-10-09T11:30:00.000Z",
  "workedMinutes": 480,
  "source": "admin_edit",
  "editedBy": "admin-uid",
  "editedAt": "2026-10-10T10:00:00.000Z"
}
```

Business errors include `HOLIDAY_EXISTS`, `HOLIDAY_NOT_FOUND`, `MONTH_LOCKED`,
`EMPLOYEE_NOT_FOUND`, `FUTURE_ATTENDANCE_DATE`,
`OUTSIDE_EMPLOYMENT_WINDOW`, `OUT_TIME_WITHOUT_IN_TIME`,
`INVALID_ATTENDANCE_TIMES`, and `INVALID_DATE_RANGE`. Validation and unknown
fields return 400 `VALIDATION_ERROR`; admin-only endpoints return 403 for
employees. Responses containing Firestore values use the shared serializer for
ISO 8601 timestamps.

## Get a development ID token

Set the Firebase project's Web API key in the current PowerShell process, then
run the helper. The key is not stored by this command, and successful output
contains only the ID token:

```powershell
$env:WEB_API_KEY = "<firebase-web-api-key>"
npm --silent run dev:login -- --email admin@example.com --password "<temporary-password>"
```

## Leave API (Step 6 backend)

Leave request dates are inclusive `YYYY-MM-DD` IST calendar dates. A request
may cover at most 31 days. Employees must be active, and the requested range
must fall within their `doj` and inclusive `dol`. A request is rejected if any
month it touches is locked or if it overlaps another pending or approved
request for that employee. Rejected and cancelled requests do not block a new
request. Lists read at most 200 request documents and filter/sort those results
in memory.

- `POST /leaves` â€” employee only. Body: `{ "fromDate": "2026-10-12",
  "toDate": "2026-10-13", "reason": "Family event" }`. Reason is trimmed,
  required, and limited to 200 characters. Returns `201` with a pending request.
- `GET /leaves/me?status=pending|approved|rejected|cancelled|all` â€” employee
  only; status is optional. Returns the caller's requests newest first.
- `POST /leaves/:id/cancel` â€” employee only; only the request owner may cancel
  a pending request. Returns the updated request.
- `GET /leaves?status=pending|approved|rejected|cancelled|all&empId=<uid>` â€”
  admin only; status defaults to `pending`. Returns up to 200 matching requests
  newest first with `name`, `empCode`, and `designation` from the employee
  profile.
- `GET /leaves/:id` â€” admin or the request owner. A request owned by someone
  else returns 404 to avoid exposing whether its ID exists.
- `POST /leaves/:id/decision` â€” admin only. Approve with
  `{ "decision": "approved", "leaveType": "paid", "note": "Approved" }`,
  or reject with `{ "decision": "rejected", "note": "Please reapply" }`.
  `leaveType` is required for approval and is not accepted for rejection.

Approval runs in one Firestore transaction. It checks the request, employee,
company weekly offs, holidays, attendance months, and payroll locks before any
writes. For each date the classification order is: outside the employee's
joining window, existing `P` or `H` punch/presence, holiday, weekly off, then
write the leave status. Weekly offs and holidays are never written. Existing
`A`, `L`, and `UL` entries may be overwritten. Punch days are returned as
`has_punch` in `skippedDates`; other skip reasons are `outside_employment`,
`holiday`, and `weekly_off`.

For each date written, the corresponding attendance day becomes `L` for paid
leave or `UL` for unpaid leave, with `source: "leave"`, `leaveRequestId`, and
admin edit fields. Existing attendance month documents are updated only at
those day paths; missing month documents are created. The request stores
`writtenDates`, `skippedDates`, `leaveType`, and decision metadata, and an audit
log is written in the same transaction. A request whose dates are all skipped
is still approved and includes `"noDaysWritten": true` in its response.

Example `POST /leaves` response:

```json
{
  "id": "leave-request-id",
  "empId": "employee-uid",
  "fromDate": "2026-10-12",
  "toDate": "2026-10-13",
  "reason": "Family event",
  "status": "pending",
  "createdAt": "2026-10-08T10:00:00.000Z",
  "updatedAt": "2026-10-08T10:00:00.000Z"
}
```

Example approval response with a weekly off skipped:

```json
{
  "id": "leave-request-id",
  "empId": "employee-uid",
  "fromDate": "2026-10-11",
  "toDate": "2026-10-12",
  "reason": "Family event",
  "status": "approved",
  "leaveType": "paid",
  "writtenDates": ["2026-10-12"],
  "skippedDates": [{ "date": "2026-10-11", "reason": "weekly_off" }],
  "decidedBy": "admin-uid",
  "decidedAt": "2026-10-08T10:00:00.000Z",
  "decisionNote": "Approved"
}
```

Leave business errors use the standard error body. Important codes are
`INVALID_DATE_RANGE` (400), `LEAVE_RANGE_TOO_LONG` (422),
`OUTSIDE_EMPLOYMENT_WINDOW` (422), `MONTH_LOCKED` (409),
`LEAVE_OVERLAP` (409, `details.requestId` identifies the conflicting request),
`LEAVE_NOT_FOUND` (404), `NOT_PENDING` (409), and `ALREADY_DECIDED` (409).
Authentication failures are 401; wrong-role or inactive-employee requests are
403. Unknown JSON fields and missing approval leave types return 400
`VALIDATION_ERROR`.

The calendar and summary endpoints read the resulting `L` and `UL` attendance
statuses. `leaveRequestId` is included in the calendar day when stored. A later
check-in on a day marked `L` or `UL` changes that day to `P` with
`source: "app"`, following the existing Step 4 check-in behavior.
