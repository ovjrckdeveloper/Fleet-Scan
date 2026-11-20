# Fleet Scan

GSCWD Fleet QR scanner for Trip Tickets and Industrial Equipment Gate Passes, built with Flutter for Android.

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

## Industrial Equipment Gate Passes

Scan the QR for a submitted pass directly. The scanner recognizes `IEGP-` as
an Equipment Gate Pass and `TRIP-` as a Trip Ticket. Keep the exact document
ID in the QR from the existing ERPNext Client Script.
The preview shows the requester and any recorded OUT and IN details.

Install [the Gate Pass Server Script](server/fleet_scan_equipment_gate_pass_mobile.py)
as an **API** Server Script with API Method `fleet_scan_equipment_gate_pass_mobile`.
Keep **Allow Guest** unchecked. The Trip Ticket script stays installed separately.

In **Customize Form → Industrial Equipment Gate Pass**, configure these fields:

| Field | Type | Allow on Submit |
|---|---|---|
| `requested_by` | Link → Employee | Existing setting |
| `motorpool_on_duty_out` | Link → Employee | Yes |
| `time_equipment_out` | Datetime | Yes |
| `motorpool_on_duty_in` | Link → Employee | Yes |
| `time_equipment_in` | Datetime | Yes |
| `returned_by` | Link → Employee | Yes |

Give scanner operators Read and Write access to the Gate Passes they handle,
including the fields above. Each scanner login must link to exactly one active
Employee. For an authorized operator receiving a pass, the API returns only
the IDs and names of active Employees linked to an enabled ERPNext User with
the **Fleet Driver** role. The search does not require general Employee list
access. ERPNext rechecks eligibility and applies normal document permissions
when saving IN.
Leaving **Returned by** blank uses the pass's `requested_by` Employee.

To verify on ERPNext, scan separate submitted passes through OUT and IN.
Leave **Returned by** blank on one and select a matching Fleet Driver on another.
Verify the Employee links and site timestamps on the saved passes, rescan to
confirm their status and scan history, and try an already recorded movement to
confirm it cannot be overwritten.

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
