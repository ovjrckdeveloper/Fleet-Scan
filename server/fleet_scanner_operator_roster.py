# ERPNext API Server Script: fleet_scanner_operator_roster
# Leave Allow Guest unchecked. Use a dedicated device account.
def operator_roster():
    if frappe.session.user == "Guest":
        frappe.throw("Roster access requires authentication.", frappe.PermissionError)
    roles = frappe.call("frappe.core.doctype.user.user.get_roles", uid=frappe.session.user)
    if "Fleet Scanner Roster Reader" not in roles:
        frappe.throw("Roster access is not assigned to this account.", frappe.PermissionError)

    assignments = frappe.get_all(
        "Has Role",
        filters={"parenttype": "User", "parentfield": "roles", "role": "Fleet Scanner Operator"},
        pluck="parent",
    )
    if not assignments:
        return []
    users = frappe.get_all(
        "User",
        filters={"name": ["in", list(set(assignments))], "enabled": 1},
        fields=["name", "full_name"],
        order_by="full_name asc, name asc",
    )
    # User.name is the ERPNext login email. Return only what the picker needs.
    return [{"name": user.full_name or user.name, "email": user.name} for user in users]

frappe.response["message"] = operator_roster()
