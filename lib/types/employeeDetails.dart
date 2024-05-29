class EmployeeDetails {
  String? userId;
  String? companyId;
  String? employeeFullName;
  Assignment? assignment;
  String? userRole;
  String? photoUrl;

  EmployeeDetails({required this.userId, required this.companyId, required this.employeeFullName, required this.assignment, required this.userRole, required this.photoUrl});

  factory EmployeeDetails.fromJson(Map<String, dynamic> json) {
    return EmployeeDetails(
      userId: json['userId'],
      companyId: json['companyId'],
      employeeFullName: json['employeeFullName'],
      assignment: json['assignment' 'positionTitle'],
      userRole: json['userRole'],
      photoUrl: json['photoUrl'],
    );
  }
}

class Assignment {
  String? id;
  String? name;
  String? positionId;
  String? positionTitle;

  Assignment({required id, required name, required positionId, required positionTitle});

  factory Assignment.fromJson(Map<String, dynamic> json) {
    return Assignment(
      id: json['id'],
      name: json['name'],
      positionId: json['positionId'],
      positionTitle: json['positionTitle'],
    );
  }
}