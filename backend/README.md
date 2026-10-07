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
Employee seeding is only for development/testing; real employee creation,
including employee codes, salary setup, and the application workflow, is
implemented in Step 2.
