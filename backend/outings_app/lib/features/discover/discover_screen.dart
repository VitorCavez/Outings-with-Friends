import 'package:flutter/material.dart';

class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> mockOutings = [
      {
        'title': 'Beach Picnic',
        'date': 'Aug 20, 2025',
        'location': 'Santa Monica Beach',
      },
      {
        'title': 'Hiking Trip',
        'date': 'Aug 22, 2025',
        'location': 'Griffith Park',
      },
      {
        'title': 'Movie Night',
        'date': 'Aug 24, 2025',
        'location': 'Downtown Cinema',
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover Outings'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: ListView.builder(
        itemCount: mockOutings.length,
        itemBuilder: (context, index) {
          final outing = mockOutings[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            elevation: 4,
            child: ListTile(
              leading: const Icon(Icons.event),
              title: Text(outing['title'] ?? ''),
              subtitle: Text('${outing['date']} • ${outing['location']}'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                // TODO: Navigate to outing details
              },
            ),
          );
        },
      ),
    );
  }
}
