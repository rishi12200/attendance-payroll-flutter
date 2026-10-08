# Attendance & Payroll app

Flutter client for the attendance and payroll API.

## Run the employee app

From this directory:

```powershell
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

The Android emulator reaches a development API on the host at
`10.0.2.2:8080`. The employee home requests foreground location permission,
shows a one-time nearest-branch distance estimate, and sends check-in/check-out
requests to the server. The server-provided IST date, times, and attendance
records determine the displayed punch state; the phone clock is not used to
calculate attendance.

To test location in the Android emulator, open **Extended controls → Location**,
set a point inside an assigned branch radius, and press **Set location**.
Choose a point outside the radius to verify that the app displays its distance
estimate while the server makes the final acceptance decision.

The app stores a random install identifier in `shared_preferences` for the API's
`deviceId`; it does not store authentication tokens or location history there.
