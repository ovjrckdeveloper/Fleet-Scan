# ERPNext Server Script (API). API Method: fleet_scan_trip_ticket_mobile
# Allow Guest: unchecked. Paste this entire file into the Script field.
# No imports, manual commits, permission bypasses, or device-supplied timestamps.

def mileage_number(value):
    if value in (None, "") or isinstance(value, bool):
        return None
    try:
        number = float(value)
        if 0 <= number < float("inf"):
            return number
    except (TypeError, ValueError, OverflowError):
        pass
    return None


def tracksolid_mileage(imei, begin, end):
    # Frappe API scripts can either return flags or set frappe.response.message.
    # Keep their response fields out of the mobile scan response.
    response = frappe.response
    original = dict(response)
    try:
        response["message"] = None
        result = frappe.call(
            "fleet_get_tracksolid_mileage", imeis=imei,
            beginTime=begin, endTime=end,
        )
        if not result:
            result = response.get("message")
        if response.get("http_status_code", 200) >= 400:
            return None
        if isinstance(result, dict) and result.get("success") is True and result.get("complete") is True:
            if str(result.get("imei")) == imei and isinstance(result.get("data"), list):
                return result
    finally:
        response.clear()
        response.update(original)
    return None


def scan_mileage(doc, mode, boundary):
    vehicle = doc.get("vehicle")
    if not vehicle:
        return {}
    # Use the same permission-checked Vehicle lookup as the browser form.
    vehicle_data = frappe.call("frappe.client.get_value", doctype="Vehicle",
                               filters={"name": vehicle}, fieldname="custom_imei")
    imei = str((vehicle_data or {}).get("custom_imei") or "").strip()
    if not imei:
        return {}

    if mode == "OUT":
        if mileage_number(doc.get("km_before")) is not None:
            return {}
        begin = frappe.utils.add_to_date(boundary, hours=-72, as_string=True, as_datetime=True).split(".")[0]
        begin_at = frappe.utils.get_datetime(begin)
        boundary_at = frappe.utils.get_datetime(boundary)
        result = tracksolid_mileage(imei, begin, boundary)
        latest_end = None
        latest_reading = None
        for trip in (result or {}).get("data", []):
            if not isinstance(trip, dict):
                continue
            reading = mileage_number(trip.get("endMileage"))
            end = str(trip.get("endTime") or "").replace("T", " ")
            if reading is None or not end:
                continue
            try:
                end_at = frappe.utils.get_datetime(end)
                if (begin_at <= end_at <= boundary_at
                        and (latest_end is None or end_at > latest_end)):
                    latest_end = end_at
                    latest_reading = reading
            except (TypeError, ValueError):
                continue
        if latest_reading is not None:
            return {"km_before": round(latest_reading / 1000, 3)}
        return {}

    if mileage_number(doc.get("km_after")) is not None and mileage_number(doc.get("km_before")) is not None:
        return {}
    departure = str(doc.get("custom_out_date")) + " " + str(frappe.utils.get_time(str(doc.get("out"))))
    if frappe.utils.get_datetime(boundary) <= frappe.utils.get_datetime(departure):
        return {}
    result = tracksolid_mileage(imei, departure, boundary)
    if not result or not result.get("data"):
        return {}
    summary = result.get("summary")
    if not isinstance(summary, dict):
        return {}
    start = mileage_number(summary.get("gps_start_mileage"))
    end = mileage_number(summary.get("gps_end_mileage"))
    if start is None or end is None or end < start:
        return {}
    updates = {}
    if mileage_number(doc.get("km_after")) is None:
        updates["km_after"] = round(end, 3)
    if mileage_number(doc.get("km_before")) is None:
        updates["km_before"] = round(start, 3)
    return updates


def scan_trip():
    contract = "fleet_mobile_v1"
    user = frappe.session.user
    if not user or user == "Guest":
        return {"contract": contract, "success": False, "code": "permission_denied", "error": "Please sign in to ERPNext again."}
    roles = frappe.call("frappe.core.doctype.user.user.get_roles")
    if "Fleet Scanner Operator" not in roles:
        return {"contract": contract, "success": False, "code": "permission_denied", "error": "You are not assigned the Fleet Scanner Operator role."}

    ticket = frappe.form_dict.get("trip_ticket_id")
    mode = frappe.form_dict.get("scan_mode")
    if not isinstance(ticket, str) or not ticket.strip() or len(ticket.strip()) > 140:
        return {"contract": contract, "success": False, "error": "Scan a valid Trip Ticket document ID."}
    ticket = ticket.strip()
    if "\n" in ticket or "\r" in ticket or ticket.lower().startswith(("http:", "https:", "{")) or mode not in ("OUT", "IN"):
        return {"contract": contract, "success": False, "error": "Invalid Trip Ticket ID or scan action."}

    # Require a CSRF token even if site-level CSRF protection was disabled.
    if not frappe.session.csrf_token or frappe.form_dict.get("csrf_token") != frappe.session.csrf_token:
        frappe.throw("Invalid scanner session token. Sign in again.", frappe.PermissionError)

    employees = frappe.get_all("Employee", filters={"user_id": user, "status": "Active"}, fields=["name", "employee_name"], limit_page_length=2)
    if len(employees) != 1:
        return {"contract": contract, "success": False, "error": "Your ERPNext User must be linked to exactly one active Employee through Employee.user_id. Ask your administrator to check the link."}
    employee = employees[0].name
    if not frappe.db.exists("Trip Ticket", ticket):
        return {"contract": contract, "success": False, "error": "Trip Ticket not found."}

    # Load the latest document and children under a row lock, not a stale
    # pre-lock snapshot. Frappe holds this lock until the request transaction ends.
    doc = frappe.get_doc("Trip Ticket", ticket, for_update=True)
    doc.check_permission("read")
    doc.check_permission("write")
    if doc.docstatus != 1:
        return {"contract": contract, "success": False, "error": "Only submitted Trip Tickets can be scanned."}

    schema = {
        "custom_out_date": "Date", "out": "Time",
        "custom_in_date": "Date", "in": "Time",
        "custom_security_on_duty_departure": "Link", "custom_departure_scan_date": "Datetime",
        "custom_security_on_duty_arrival": "Link", "custom_arrival_scan_date": "Datetime",
    }
    meta = frappe.get_meta("Trip Ticket")
    for fieldname in schema:
        df = meta.get_field(fieldname)
        if not df or df.fieldtype != schema[fieldname] or not df.allow_on_submit:
            return {"contract": contract, "success": False, "error": "Trip Ticket field " + fieldname + " must have the expected type and Allow on Submit enabled."}
        if schema[fieldname] == "Link" and df.options != "Employee":
            return {"contract": contract, "success": False, "error": "Security on duty fields must link to Employee."}

    departure_fields = ("custom_out_date", "out", "custom_security_on_duty_departure", "custom_departure_scan_date")
    arrival_fields = ("custom_in_date", "in", "custom_security_on_duty_arrival", "custom_arrival_scan_date")
    if mode == "OUT":
        if any(doc.get(fieldname) not in (None, "") for fieldname in departure_fields + arrival_fields):
            return {"contract": contract, "success": False, "error": "This ticket already has departure or arrival data. Existing records will not be overwritten."}
        fields = departure_fields
    else:
        if not doc.get("custom_out_date") or doc.get("out") in (None, ""):
            return {"contract": contract, "success": False, "error": "Record Departure (OUT) before Arrival (IN)."}
        if any(doc.get(fieldname) not in (None, "") for fieldname in arrival_fields):
            return {"contract": contract, "success": False, "error": "Arrival is already recorded. Existing records will not be overwritten."}
        fields = arrival_fields

    # frappe.utils.now() uses the ERPNext site's timezone, not the phone clock.
    timestamp = frappe.utils.now()
    date = timestamp.split(" ")[0]
    time = timestamp.split(" ")[1].split(".")[0]
    if mode == "IN":
        departure = str(doc.get("custom_out_date")) + " " + str(frappe.utils.get_time(str(doc.get("out"))))
        if frappe.utils.get_datetime(timestamp) < frappe.utils.get_datetime(departure):
            return {"contract": contract, "success": False, "error": "Arrival cannot be earlier than Departure."}

    updates = {fields[0]: date, fields[1]: time, fields[2]: employee, fields[3]: timestamp}
    mileage_status = "already_recorded"
    mileage_updates = {}
    needed = mileage_number(doc.get("km_before")) is None or (
        mode == "IN" and mileage_number(doc.get("km_after")) is None
    )
    if needed:
        mileage_status = "unavailable"
        try:
            mileage_updates = scan_mileage(doc, mode, date + " " + time)
        except Exception:
            # GPS availability must not prevent a guard from recording OUT/IN.
            frappe.log_error(title="Fleet mobile mileage lookup failed", message="Trip Ticket: " + ticket + ", scan: " + mode)
        if mileage_updates:
            for fieldname in mileage_updates:
                df = meta.get_field(fieldname)
                if not df or df.fieldtype not in ("Data", "Float", "Currency") or not df.allow_on_submit:
                    frappe.throw("Trip Ticket field " + fieldname + " must be Data, Float, or Currency with Allow on Submit enabled.")
                reading = mileage_updates[fieldname]
                updates[fieldname] = "%.3f" % reading if df.fieldtype == "Data" else reading
            mileage_status = "saved"

    # Save the scan and any confirmed GPS readings in the same transaction.
    # Use the normal permissions, field validation and submitted-document rules.
    doc.update(updates)
    frappe.call("frappe.client.save", doc=doc.as_dict())
    saved = frappe.db.get_value("Trip Ticket", ticket, list(fields), as_dict=True)
    if str(saved.get(fields[0])) != date or str(saved.get(fields[2])) != employee or not saved.get(fields[3]) or frappe.utils.get_datetime(saved.get(fields[3])) != frappe.utils.get_datetime(timestamp) or frappe.utils.get_time(str(saved.get(fields[1]))) != frappe.utils.get_time(time):
        # Throw rather than return success/false after a write, so Frappe rolls back.
        frappe.throw("Saved scan fields did not match. The transaction must be rolled back.")
    if mileage_updates:
        saved_mileage = frappe.db.get_value("Trip Ticket", ticket, list(mileage_updates), as_dict=True)
        for fieldname in mileage_updates:
            reading = mileage_number(saved_mileage.get(fieldname))
            if reading is None or round(reading, 3) != mileage_updates[fieldname]:
                frappe.throw("Saved " + fieldname + " did not match the Tracksolid reading.")

    return {"contract": contract, "success": True, "trip_ticket": ticket,
            "scan_mode": mode, "employee": employee, "scanned_by": user,
            "employee_name": employees[0].employee_name,
            "datetime": timestamp, "fields": updates, "mileage_status": mileage_status}

frappe.response["message"] = scan_trip()
