// lib/features/contacts/ui_contact.dart
class UiContact {
  final String? userId; // present if this contact is a registered user
  final String displayName; // fullName/label fallback
  final String? email;
  final String? phone;

  UiContact({required this.displayName, this.userId, this.email, this.phone});

  factory UiContact.fromJson(Map<String, dynamic> j) {
    final display =
        (j['displayName'] ?? j['fullName'] ?? j['label'] ?? j['username'] ?? '')
            .toString();
    return UiContact(
      userId: (j['userId'] ?? j['contactUserId']) as String?,
      displayName: display.isEmpty
          ? (j['email'] ?? j['phone'] ?? 'Contact')
          : display,
      email: j['email'] as String?,
      phone: (j['phone'] as String?) ?? (j['phoneE164'] as String?),
    );
  }
}
