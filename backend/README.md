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
  `tempPassword`, `doj`, and `monthlyCtcPaise`; `phone` and `designation` are
  optional.
- `GET /employees?status=active|inactive|all` — list employee profiles without
  salary data. `status` defaults to `active`.
- `GET /employees/:id` — read any employee (admin) or the caller's own profile;
  only admins receive `currentMonthlyCtcPaise`.
- `PATCH /employees/:id` — edit `name`, `phone`, `designation`, or `doj`.
- `GET /employees/:id/salary` — list salary revisions, newest first.
- `POST /employees/:id/salary` — add `effectiveFrom` and integer
  `monthlyCtcPaise`.
- `POST /employees/:id/deactivate` — disable Auth, revoke refresh tokens, then
  set inactive status and `dol`. An optional JSON body may provide `dol`.
- `POST /employees/:id/reactivate` — enable Auth, set active status, and clear
  `dol`.

Branch assignment is intentionally not accepted yet; it belongs to Step 3.

## Get a development ID token

Set the Firebase project's Web API key in the current PowerShell process, then
run the helper. The key is not stored by this command, and successful output
contains only the ID token:

```powershell
$env:WEB_API_KEY = "<firebase-web-api-key>"
npm --silent run dev:login -- --email admin@example.com --password "<temporary-password>"
```
