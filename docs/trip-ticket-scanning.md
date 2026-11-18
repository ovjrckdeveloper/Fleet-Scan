# Trip Ticket departure and arrival scanning

Sign in to Fleet Scan, open the main camera and scan a QR containing the exact
Trip Ticket document ID (not a URL or JSON). The camera pauses and retrieves the
current records. A ticket without departure data shows **Ready to Depart** and
only the light-blue **Confirm Departure (OUT)** button. A recorded departure
(date and time) with no arrival data shows **On Trip** and only the orange
**Confirm Arrival (IN)** button. Recorded departure and arrival show **Completed**
with no confirm button. Partial/inconsistent records show **Check Records** and
require checking ERPNext. Loading and failed lookups show no confirm button.
A successful save updates the status; scan again to retrieve the next action.
Each existing Departure/Arrival row also shows Employee on Duty, resolved from
that action's saved security Employee link using normal Employee read permissions.
It never substitutes the currently signed-in operator. Missing links or unavailable
names display “Name unavailable” without hiding the recorded time or blocking scanning.
The server still locks and validates the latest record when saving.
Nothing is submitted until the displayed action is confirmed.
Cancel / scan again discards the selection without writing.

The scanned-ticket sheet uses the app's light-blue accent and shows only Vehicle
and Driver from the Trip Ticket's `vehicle` and `driver` fields, with no destination.
A read-only session-authenticated GET to `/api/resource/Trip%20Ticket/{id}`
loads these values under normal document permissions. Only submitted tickets
are accepted. Loading or lookup errors disable confirmation and offer a retry;
missing field values display “Not provided”. No additional Server Script is needed
for this preview. Vehicle remains the stored value. Driver displays the ticket's
`driver_name` when present; otherwise the app reads the linked Driver's `full_name`
using `frappe.client.get_value`, filtered by the exact Driver document ID, requesting
`name` and `full_name`. This uses normal Driver read permissions. The Driver row
now distinguishes permission denial (“Driver read permission required”), missing
records, empty full names and connection failures, without blocking an otherwise
valid ticket. An expired session still requires signing in again.
For denied access, give Fleet Scanner Operator Read access to Driver in ERPNext's
Role Permission Manager, subject to the intended document restrictions.

Selecting an action submits only the ticket ID and OUT/IN action, using the
signed-in session and Frappe CSRF protection. The app never supplies employee
identity, dates or times. A success message includes “Employee on Duty” with the
Employee's `employee_name` and the server date/time. The Link field still stores
the Employee document ID. The updated Server Script returns `employee_name`
alongside `employee`; paste the local script into ERPNext to enable that response.
For older scripts the app attempts a normal read of the confirmed Employee.
If that read is denied or unavailable, it displays “Name unavailable” while
preserving the confirmed save. It never substitutes the User's name for the
Employee's name. Success is shown only after ERPNext confirms all selected fields.

## Required ERPNext installation — Server Scripts only

The new mobile endpoint is separate from any existing `fleet_scan_trip_ticket`
script, so existing browser Fleet workflows are not replaced. The app cannot
install Server Scripts through this workspace connection.

1. In ERPNext, create a **Server Script** named **Fleet Mobile Trip Ticket Scan**.
2. Set **Script Type** to **API** and **API Method** to
   `fleet_scan_trip_ticket_mobile` (exact spelling).
3. Leave **Allow Guest** unchecked, ensure the script is enabled, and paste the
   full contents of [fleet_scan_trip_ticket_mobile.py](../server/fleet_scan_trip_ticket_mobile.py)
   into **Script**, then save. API Server Scripts must already be enabled on the site.
4. In **Customize Form → Trip Ticket**, verify all eight fields below and enable
   **Allow on Submit** on each. Their permission levels must allow the operator
   to write them. Do not bypass submitted-document validation in code.
5. Give the **Fleet Scanner Operator** role Read and Write access to Trip Ticket
   using Role Permission Manager, with the intended company/document restrictions.
6. In the scanner operator's **Employee**, set **User ID** (`user_id`) to their
   ERPNext login account and **Status** to **Active**. Exactly one active Employee
   must match this account. The Employee **name/document ID**, not the email or
   `full_name`, is stored in the security Link fields.
7. The signed-in account must be a System User with Desk access: the app loads
   the authenticated `/app` bootstrap to obtain the standard session CSRF token.
   No API key/secret is required. Do not disable CSRF protection.
   The app follows up to four same-site Desk redirects and requests HTML.
   A redirect to login means the session expired; HTTP 401/403 means Desk access
   was denied. Other HTTP errors indicate a Desk/server problem and include
   the status code. These failures happen before any scan is submitted.
   For denied access, check **User → User Type = System User** and Desk access.
   For HTTP 5xx, have the administrator inspect the ERPNext server logs.

| Action | Field | Type | Saved value |
|---|---|---|---|
| Departure | `custom_out_date` | Date | ERPNext site date |
| Departure | `out` | Time | ERPNext site time |
| Departure | `custom_security_on_duty_departure` | Link → Employee | Employee linked to signed-in User |
| Departure | `custom_departure_scan_date` | Datetime | ERPNext site date and time |
| Arrival | `custom_in_date` | Date | ERPNext site date |
| Arrival | `in` | Time | ERPNext site time |
| Arrival | `custom_security_on_duty_arrival` | Link → Employee | Employee linked to signed-in User |
| Arrival | `custom_arrival_scan_date` | Datetime | ERPNext site date and time |

Both scan-date fields are **Datetime**. The app validates their date and time
against the separate date and time fields for each action. All four values for an action come from one server timestamp.
The other action's scan fields are preserved.

To enable mileage on mobile scans, keep `fleet_get_tracksolid_mileage` enabled
and accessible to the scanner account. The account also needs Read access to
the linked Vehicle and its `custom_imei` field. Enable **Allow on Submit** for
`km_before` and `km_after` and give the scanner role write access to them.
Data fields store mileage as text with three decimal places. Float and Currency
fields store numeric values and should have at least three decimal places of precision.

- **OUT** uses the latest confirmed Tracksolid trip end at or before OUT in a
  72-hour lookback. The end odometer is converted from meters to kilometers.
- **IN** uses the confirmed full-window summary's end mileage. It keeps an
  existing OUT reading and uses the summary start mileage if OUT mileage is missing.
- When Tracksolid has no complete reading, the scan still saves its timestamps
  and leaves missing kilometer fields alone. An IN scan can recover missing OUT
  mileage. An existing browser mileage script can still retry missing readings.

After installing the updated API Server Script, scan OUT and IN on a test ticket
with a known GPS history while its Desk form is closed. Verify the stored fields
in the Trip Ticket list or through the resource API before opening the form.
The scan waits for the Tracksolid lookup. Verify it completes within the app's
30-second request timeout with your live integration.

## Server behavior

The script derives the user from `frappe.session.user`, checks the exact Fleet
Scanner Operator role for every request (no Administrator bypass), and resolves
`Employee.user_id` with Status=Active. It checks Read/Write document permissions
and requires a submitted Trip Ticket (`docstatus=1`). Missing/duplicate Employee
links, incorrect field types and missing Allow on Submit settings are rejected.

The document and children are loaded with `for_update=True` before inspecting
existing departure/arrival fields. This serializes concurrent scans of that ticket.
Existing data is never overwritten; arrival requires a recorded departure.
Both user selection and server scan order are checked; arrival cannot precede
the server's recorded departure timestamp.

The scan fields and any confirmed mileage are applied to the locked document and saved via
`frappe.client.save`, which requires POST/PUT and runs normal permission,
controller and submitted-document validation. No `ignore_permissions`,
`ignore_validate_update_after_submit` or direct database update is used.
Readback mismatch raises an error so Frappe rolls back the request transaction.
There is no manual commit. Actual hooks, permissions and concurrent behavior
must still be verified on your deployed ERPNext site.

## Request and confirmation contract

Endpoint: `POST /api/method/fleet_scan_trip_ticket_mobile`.
The app sends the session cookie, `X-Frappe-CSRF-Token`, and form fields
`trip_ticket_id`, `scan_mode` (OUT/IN), and `csrf_token`.
Never accept identity or timestamp fields from the client.

Example response for Departure:

```json
{
  "message": {
    "contract": "fleet_mobile_v1",
    "success": true,
    "trip_ticket": "TRIP-TEST",
    "scan_mode": "OUT",
    "scanned_by": "guard@example.com",
    "employee": "EMP-001",
    "datetime": "2026-11-12 09:10:11",
    "fields": {
      "custom_out_date": "2026-11-12",
      "out": "09:10:11",
      "custom_security_on_duty_departure": "EMP-001",
      "custom_departure_scan_date": "2026-11-12 09:10:11"
    }
  }
}
```

Validation failures before a write return contract=fleet_mobile_v1,
success=false and a plain error message. Permission failures invalidate local
access. Standard Frappe permission/validation exceptions also remain in force.

No automatic retry is performed. If a connection drops, a 5xx occurs, or the
response does not confirm all required fields, the record may have been saved.
Check ERPNext first; the app requires acknowledgement before starting another
scan after an uncertain outcome. Leaving the scanner is blocked while submitting.

## Login

The app uses ERPNext username/password login, supports Frappe OTP challenges,
and verifies identity and the Fleet Scanner Operator role. The role is rechecked
before opening the camera and again on the server when recording. Cookies remain
in memory; app restarts require login. Passwords/OTPs are not persisted or logged.
Browser cookie login is not implemented; use the Android app.

## Verification

Local Flutter tests cover exact field mapping, session/CSRF transport, no writes
before action selection, both actions, duplicate-tap prevention, incomplete
confirmation, missing endpoint/Employee errors, network failure and cancellation.

After installing the script, test with a disposable submitted ticket and a User
linked to an active Employee. Verify all four Departure fields, then all four
Arrival fields, using ERPNext site time. Also test drafts/cancelled/unknown IDs,
missing role, missing/inactive/duplicate Employee mapping, repeated actions,
IN before OUT, two operators scanning simultaneously, permission restrictions,
and connection loss. These tests change real ERPNext data: do not use a live trip
just to check installation. Live server writes have not been verified here.

The old `TripScan`/API-key screen and FleetApi implementation are retained but
unrouted and are not used by this session-based main scanner.

References: [Frappe REST API](https://docs.frappe.io/framework/user/en/api/rest),
[Employee](https://docs.frappe.io/hr/employee).
