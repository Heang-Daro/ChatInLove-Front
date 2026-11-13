import 'package:flutter/material.dart';

class ChatRequestScreen extends StatefulWidget {
  const ChatRequestScreen({super.key});

  @override
  State<ChatRequestScreen> createState() => _ChatRequestScreenState();
}

class _ChatRequestScreenState extends State<ChatRequestScreen> {
  // Sample list of incoming requests
  final List<Map<String, String>> requests = [
    {"name": "Sophia", "message": "Hey! Would love to chat with you.", "time": "10m ago"},
    {"name": "Liam", "message": "Hi there! Your profile caught my eye.", "time": "1h ago"},
    {"name": "Olivia", "message": "Hello! How's your day going?", "time": "3h ago"},
  ];

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return const Center(
        child: Text(
          "No new chat requests",
          style: TextStyle(color: Colors.pinkAccent, fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      itemCount: requests.length,
      padding: const EdgeInsets.all(8.0),
      itemBuilder: (context, index) {
        final request = requests[index];
        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.pinkAccent,
              child: Icon(Icons.person, color: Colors.white),
            ),
            title: Text(
              request["name"]!,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(request["message"]!),
                const SizedBox(height: 2),
                Text(
                  request["time"]!,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            isThreeLine: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.check_circle, color: Colors.green),
                  onPressed: () {
                    setState(() {
                      requests.removeAt(index);
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Chat request accepted!")),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.cancel, color: Colors.redAccent),
                  onPressed: () {
                    setState(() {
                      requests.removeAt(index);
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Chat request declined")),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}