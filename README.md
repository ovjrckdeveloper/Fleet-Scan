# Fleet Scan

GSCWD Fleet Trip Ticket QR scanner built with Flutter for Android.

Sign in with your ERPNext username/email and password. Accounts need the
**Fleet Scanner Operator** role. Every account, including Administrator, must
have this exact role assigned. Verification codes are requested when ERPNext
requires two-factor authentication. No employee API keys are generated or copied.

After sign-in, tap the main scan area to open the camera. Scan a Trip Ticket ID,
then select **Departure (OUT)** or **Arrival (IN)** to save its server date/time
and the signed-in operator's linked Employee. No write occurs until you choose.

**ERPNext setup is required before saving:** install the supplied API Server Script
[`server/fleet_scan_trip_ticket_mobile.py`](server/fleet_scan_trip_ticket_mobile.py)
as `fleet_scan_trip_ticket_mobile`, with Allow Guest unchecked. Configure the
fields, permissions and Employee User ID link described in
[scanner setup](docs/trip-ticket-scanning.md). No API key is needed.

## Development

```sh
flutter pub get
flutter test
flutter run
```

The default ERPNext site is https://tubigconnect.gscwd.app. Override only the site
URL with `--dart-define=FRAPPE_URL=https://your-erp-site.example` if needed.
Android application ID: `com.gscwd.fleet_scan`. Startup needs no .env file.

### Remembered guards on a shared scanner

Each guard signs in normally once. After ERPNext verifies the guard's account
and Fleet Scanner Operator role, the app saves their name and login email on
this phone. On later shifts, tap the email field and select the guard's name
to fill the email and focus the password. Passwords, verification codes and
sessions are never saved. ERPNext checks the guard's current role every time,
even if their name is still on the phone.

No roster Server Script or API credentials are needed. If you installed
`fleet_scanner_operator_roster` for a previous build, you can disable that
script and revoke the dedicated roster reader credentials.

Session cookies are held only in memory, so restarting the app requires sign-in.
Use **Sign out** to invalidate the session and return to login. Browser session
login is not configured; use the Android app.

See [scanner setup](docs/trip-ticket-scanning.md) for the retained Fleet recording
API and [Android build notes](docs/android-build.md) for tool versions.
