import 'package:flutter/material.dart';
import 'package:outings_app/services/socket_service.dart'; // adjust path

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            final socketService = SocketService();
            socketService.initSocket();
            socketService.sendMessage(
             text: "Hello from Flutter!",
             senderId: "YOUR_USER_ID",
           );

          },
          child: const Text('Send Socket Test Message'),
        ),
      ),
    );
  }
}
