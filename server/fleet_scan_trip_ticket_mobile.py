# ERPNext Server Script (API). API Method: fleet_scan_trip_ticket_mobile
# Allow Guest: unchecked. Paste this entire file into the Script field.
# No imports, manual commits, permission bypasses, or device-supplied timestamps.

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
        departure = str(doc.get("custom_out_date")) + " " + str(doc.get("out"))
        if frappe.utils.get_datetime(timestamp) < frappe.utils.get_datetime(departure):
            return {"contract": contract, "success": False, "error": "Arrival cannot be earlier than Departure."}

    updates = {fields[0]: date, fields[1]: time, fields[2]: employee, fields[3]: timestamp}
    # The standard whitelisted helper checks HTTP POST/PUT, document Write
    # permissions, field permissions, controller hooks and submitted-doc rules.
    # All four fields are saved in one transaction. Do not use db.set_value here.
    doc.update(updates)
    frappe.call("frappe.client.save", doc=doc.as_dict())
    saved = frappe.db.get_value("Trip Ticket", ticket, list(fields), as_dict=True)
    if str(saved.get(fields[0])) != date or str(saved.get(fields[2])) != employee or not saved.get(fields[3]) or frappe.utils.get_datetime(saved.get(fields[3])) != frappe.utils.get_datetime(timestamp) or frappe.utils.get_time(str(saved.get(fields[1]))) != frappe.utils.get_time(time):
        # Throw rather than return success/false after a write, so Frappe rolls back.
        frappe.throw("Saved scan fields did not match. The transaction must be rolled back.")
    return {"contract": contract, "success": True, "trip_ticket": ticket,
            "scan_mode": mode, "employee": employee, "scanned_by": user,
            "employee_name": employees[0].employee_name,
            "datetime": timestamp, "fields": updates}

frappe.response["message"] = scan_trip()
