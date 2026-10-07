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

## Get a development ID token

Set the Firebase project's Web API key in the current PowerShell process, then
run the helper. The key is not stored by this command, and successful output
contains only the ID token:

```powershell
$env:WEB_API_KEY = "<firebase-web-api-key>"
npm --silent run dev:login -- --email admin@example.com --password "<temporary-password>"
```
