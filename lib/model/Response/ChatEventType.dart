import 'MessageResponse.dart';

enum ChatEventType { created, edited, deleted }

class ChatEvent {
  final ChatEventType type;
  final MessageResponse message;

  ChatEvent(this.type, this.message);

  factory ChatEvent.fromJson(Map<String, dynamic> json) {
    final raw = (json['type'] as String?)?.toUpperCase();
    return ChatEvent(
      ChatEventType.values.firstWhere(
            (t) => t.name.toUpperCase() == raw,
        orElse: () => ChatEventType.created,
      ),
      MessageResponse.fromJson(json['message'] as Map<String, dynamic>),
    );
  }
}