class Contact {
  final String id; // stable UI id (e.g., userId or local key)
  final String name;
  final String? email;
  final String? phone;

  Contact({required this.id, required this.name, this.email, this.phone});
}
