enum ConversationStatus {
  PENDING,
  ACCEPTED,
  REJECTED;

  static ConversationStatus fromJson(String? value) {
    if (value == null) return ConversationStatus.ACCEPTED;
    return ConversationStatus.values.firstWhere(
      (e) => e.name.toUpperCase() == value.toUpperCase(),
      orElse: () => ConversationStatus.ACCEPTED,
    );
  }
}
