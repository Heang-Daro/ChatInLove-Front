import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../model/emun/MessageType.dart';

part 'app_database.g.dart';

/// Lifecycle of a message inside the local database.
///
/// The value is persisted as text, so the enum can be extended without a
/// schema migration.
enum DeliveryStatus {
  /// Written locally, not yet acknowledged by the server.
  pending,

  /// The server accepted the message and returned its id.
  sent,

  /// The server confirmed that the message reached the other device.
  delivered,

  /// The other device has read the message.
  read,

  /// The send failed (offline, timeout, server error) and can be retried.
  failed,
}

/// A chat (conversation) as it is stored on the device.
@TableIndex(name: 'chats_updated_at_idx', columns: {#updatedAt})
class Chats extends Table {
  /// Server id of the conversation.
  TextColumn get id => text()();

  /// Display name of the chat (group name or the partner's username).
  TextColumn get name => text().withDefault(const Constant(''))();

  /// Preview of the last message, used by the chat list.
  TextColumn get lastMessage => text().nullable()();

  /// Number of messages that arrived while the chat was not open.
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();

  /// Timestamp of the last activity, used to sort the chat list.
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  /// Highest server sequence id that was synced for this chat. Used to ask
  /// the backend for everything that was missed while offline.
  IntColumn get lastSequenceId => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A message as it is stored on the device.
///
/// A message exists in the database *before* it is sent to the server
/// (optimistic UI) and is reconciled once the server answers.
@TableIndex(name: 'messages_chat_ts_idx', columns: {#chatId, #timestamp})
@TableIndex(name: 'messages_server_id_idx', columns: {#serverId})
class Messages extends Table {
  /// Client side uuid v4. It is the primary key and never changes.
  TextColumn get localId => text()();

  /// Id assigned by the server. Null while the message is still pending.
  TextColumn get serverId => text().nullable()();

  /// Chat this message belongs to.
  TextColumn get chatId => text()();

  /// Author of the message.
  TextColumn get senderId => text()();

  /// Message body. For media messages this holds the path/URL of the file.
  TextColumn get content => text()();

  /// Path of a file that was downloaded to the device (optional).
  TextColumn get mediaLocalPath => text().nullable()();

  /// Absolute url of a media message.
  TextColumn get mediaUrl => text().nullable()();

  /// Creation time. For pending messages this is the local time.
  DateTimeColumn get timestamp => dateTime()();

  /// Delivery state of the message.
  TextColumn get status => textEnum<DeliveryStatus>()();

  /// Type of the message (text, image, voice, ...).
  TextColumn get messageType => textEnum<MessageType>()();

  /// Monotonic sequence id assigned by the server, used for delta sync.
  IntColumn get sequenceId => integer().nullable()();

  @override
  Set<Column> get primaryKey => {localId};
}

/// The local database of the app.
@DriftDatabase(tables: [Chats, Messages])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Used by tests: `AppDatabase.forTesting(NativeDatabase.memory())`.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) => m.createAll(),
        onUpgrade: (Migrator m, int from, int to) async {
          // Only schema version 1 exists so far. Future migrations go here.
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

QueryExecutor _openConnection() {
  return driftDatabase(
    name: 'love_in_chat',
    native: const DriftNativeOptions(
      // One shared isolate keeps the streams of all screens in sync.
      shareAcrossIsolates: true,
    ),
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.js'),
    ),
  );
}
