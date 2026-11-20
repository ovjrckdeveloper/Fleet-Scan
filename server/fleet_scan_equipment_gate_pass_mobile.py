# ERPNext API Server Script: fleet_scan_equipment_gate_pass_mobile
# Allow Guest: unchecked. Supports preview, driver search, and confirmed movement.
DOCTYPE = "Industrial Equipment Gate Pass"
CONTRACT = "fleet_equipment_v1"
OUT_FIELDS = ("time_equipment_out", "motorpool_on_duty_out")
IN_FIELDS = ("time_equipment_in", "motorpool_on_duty_in", "returned_by")


def employee_name(employee):
    if not employee:
        return None
    try:
        result = frappe.call("frappe.client.get_value", doctype="Employee",
                             filters={"name": employee}, fieldname="employee_name")
        return (result or {}).get("employee_name") or employee
    except frappe.PermissionError:
        return employee


def driver_users():
    users = frappe.get_all("Has Role",
        filters={"role": "Fleet Driver", "parenttype": "User", "parentfield": "roles"},
        pluck="parent")
    if not users:
        return []
    return frappe.get_all("User", filters={"name": ["in", list(set(users))], "enabled": 1},
                          pluck="name")


def scan_gate_pass():
    user = frappe.session.user
    if not user or user == "Guest":
        frappe.throw("Please sign in to ERPNext again.", frappe.PermissionError)
    roles = frappe.call("frappe.core.doctype.user.user.get_roles", uid=user)
    if "Fleet Scanner Operator" not in roles:
        return {"contract": CONTRACT, "success": False, "code": "permission_denied",
                "error": "You are not assigned the Fleet Scanner Operator role."}

    ticket = frappe.form_dict.get("gate_pass_id")
    operation = frappe.form_dict.get("operation")
    if not isinstance(ticket, str) or not ticket.strip() or len(ticket.strip()) > 140:
        frappe.throw("Scan a valid Industrial Equipment Gate Pass ID.")
    ticket = ticket.strip()
    if "\n" in ticket or "\r" in ticket or ticket.lower().startswith(("http:", "https:", "{")):
        frappe.throw("The QR must contain only the Gate Pass ID.")
    if operation not in ("preview", "search", "record"):
        frappe.throw("Invalid Gate Pass operation.")
    if operation == "record":
        # Require a Desk session token even on sites with relaxed CSRF settings.
        if not frappe.session.csrf_token or frappe.form_dict.get("csrf_token") != frappe.session.csrf_token:
            frappe.throw("Invalid scanner session token. Sign in again.", frappe.PermissionError)

    if not frappe.db.exists(DOCTYPE, ticket):
        frappe.throw("Industrial Equipment Gate Pass not found.", frappe.DoesNotExistError)
    doc = frappe.get_doc(DOCTYPE, ticket, for_update=operation == "record")
    doc.check_permission("read")
    if doc.docstatus != 1:
        frappe.throw("Only submitted Industrial Equipment Gate Passes can be scanned.")

    meta = frappe.get_meta(DOCTYPE)
    for field in OUT_FIELDS + IN_FIELDS + ("requested_by",):
        df = meta.get_field(field)
        if field in ("time_equipment_out", "time_equipment_in"):
            valid = df and df.fieldtype == "Datetime"
        else:
            valid = df and df.fieldtype == "Link" and df.options == "Employee"
        if not valid or (field != "requested_by" and not df.allow_on_submit):
            frappe.throw("Check the Gate Pass field type and Allow on Submit settings for " + field + ".")

    if operation == "preview":
        doc.apply_fieldlevel_read_permissions()
        return {"contract": CONTRACT, "success": True, "gate_pass": ticket,
                "requested_by": employee_name(doc.get("requested_by")),
                "departure_at": str(doc.get(OUT_FIELDS[0]) or ""),
                "departure_by": employee_name(doc.get(OUT_FIELDS[1])),
                "arrival_at": str(doc.get(IN_FIELDS[0]) or ""),
                "arrival_by": employee_name(doc.get(IN_FIELDS[1])),
                "returned_by": employee_name(doc.get("returned_by"))}

    doc.check_permission("write")
    has_departure = all(doc.get(field) for field in OUT_FIELDS)
    has_any_arrival = any(doc.get(field) for field in IN_FIELDS)
    if operation == "search":
        if not has_departure or has_any_arrival:
            frappe.throw("Driver search is only available for a pass awaiting arrival.")
        query = frappe.form_dict.get("query")
        if not isinstance(query, str):
            return {"contract": CONTRACT, "success": True, "employees": []}
        query = query.strip()
        if len(query) < 2 or len(query) > 80 or any(char in query for char in ("%", "_", "\\")):
            return {"contract": CONTRACT, "success": True, "employees": []}
        users = driver_users()
        employees = []
        if users:
            # Scoped directory for operators authorized to receive this pass.
            # Return only the ID and display name of eligible Fleet Drivers.
            employees = frappe.get_all("Employee",
                filters={"status": "Active", "user_id": ["in", users],
                         "employee_name": ["like", "%" + query + "%"]},
                fields=["name", "employee_name"], order_by="employee_name asc, name asc",
                limit_page_length=15)
        return {"contract": CONTRACT, "success": True, "employees": employees}

    mode = frappe.form_dict.get("scan_mode")
    if mode not in ("OUT", "IN"):
        frappe.throw("Invalid Gate Pass scan action.")
    if mode == "OUT" and any(doc.get(field) for field in OUT_FIELDS + IN_FIELDS):
        frappe.throw("This pass already has movement data. Existing records will not be overwritten.")
    if mode == "IN" and (not has_departure or has_any_arrival):
        frappe.throw("Arrival requires a recorded departure and no existing arrival data.")

    operators = frappe.get_all("Employee", filters={"user_id": user, "status": "Active"},
                              fields=["name", "employee_name"], limit_page_length=2)
    if len(operators) != 1:
        frappe.throw("Your ERPNext user must be linked to exactly one active Employee.")
    employee = operators[0].name
    timestamp = frappe.utils.now()
    fields = OUT_FIELDS if mode == "OUT" else IN_FIELDS
    updates = {fields[0]: timestamp, fields[1]: employee}
    returned_name = None
    if mode == "IN":
        if frappe.utils.get_datetime(timestamp) < frappe.utils.get_datetime(doc.get(OUT_FIELDS[0])):
            frappe.throw("Arrival cannot be earlier than departure.")
        selected = frappe.form_dict.get("returned_by") or ""
        if not isinstance(selected, str) or len(selected) > 140:
            frappe.throw("Select a valid Employee for Returned by.")
        selected = selected.strip()
        if selected:
            users = driver_users()
            matches = frappe.get_all("Employee",
                filters={"name": selected, "status": "Active", "user_id": ["in", users]},
                fields=["name", "employee_name"], limit_page_length=1) if users else []
            if not matches:
                frappe.throw("Returned by must be an active Employee with the Fleet Driver role.")
            returned_name = matches[0].employee_name or selected
        else:
            selected = doc.get("requested_by")
            if not selected or not frappe.db.exists("Employee", selected):
                frappe.throw("Set a valid Requested by Employee or select who returned the equipment.")
            returned_name = employee_name(selected)
        updates["returned_by"] = selected

    doc.update(updates)
    frappe.call("frappe.client.save", doc=doc.as_dict())
    saved = frappe.db.get_value(DOCTYPE, ticket, list(fields), as_dict=True)
    if (not saved or not saved.get(fields[0])
            or frappe.utils.get_datetime(saved.get(fields[0])) != frappe.utils.get_datetime(timestamp)
            or saved.get(fields[1]) != employee
            or (mode == "IN" and saved.get("returned_by") != updates["returned_by"])):
        frappe.throw("Saved Gate Pass fields did not match. The transaction must be rolled back.")
    return {"contract": CONTRACT, "success": True, "gate_pass": ticket, "scan_mode": mode,
            "scanned_by": user, "employee": employee, "employee_name": operators[0].employee_name,
            "fields": updates, "returned_by_name": returned_name}


frappe.response["message"] = scan_gate_pass()
