// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ChatsTable extends Chats with TableInfo<$ChatsTable, Chat> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _lastMessageMeta = const VerificationMeta(
    'lastMessage',
  );
  @override
  late final GeneratedColumn<String> lastMessage = GeneratedColumn<String>(
    'last_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unreadCountMeta = const VerificationMeta(
    'unreadCount',
  );
  @override
  late final GeneratedColumn<int> unreadCount = GeneratedColumn<int>(
    'unread_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _lastSequenceIdMeta = const VerificationMeta(
    'lastSequenceId',
  );
  @override
  late final GeneratedColumn<int> lastSequenceId = GeneratedColumn<int>(
    'last_sequence_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    lastMessage,
    unreadCount,
    updatedAt,
    lastSequenceId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chats';
  @override
  VerificationContext validateIntegrity(
    Insertable<Chat> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('last_message')) {
      context.handle(
        _lastMessageMeta,
        lastMessage.isAcceptableOrUnknown(
          data['last_message']!,
          _lastMessageMeta,
        ),
      );
    }
    if (data.containsKey('unread_count')) {
      context.handle(
        _unreadCountMeta,
        unreadCount.isAcceptableOrUnknown(
          data['unread_count']!,
          _unreadCountMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('last_sequence_id')) {
      context.handle(
        _lastSequenceIdMeta,
        lastSequenceId.isAcceptableOrUnknown(
          data['last_sequence_id']!,
          _lastSequenceIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Chat map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Chat(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      lastMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_message'],
      ),
      unreadCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unread_count'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      lastSequenceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_sequence_id'],
      )!,
    );
  }

  @override
  $ChatsTable createAlias(String alias) {
    return $ChatsTable(attachedDatabase, alias);
  }
}

class Chat extends DataClass implements Insertable<Chat> {
  /// Server id of the conversation.
  final String id;

  /// Display name of the chat (group name or the partner's username).
  final String name;

  /// Preview of the last message, used by the chat list.
  final String? lastMessage;

  /// Number of messages that arrived while the chat was not open.
  final int unreadCount;

  /// Timestamp of the last activity, used to sort the chat list.
  final DateTime updatedAt;

  /// Highest server sequence id that was synced for this chat. Used to ask
  /// the backend for everything that was missed while offline.
  final int lastSequenceId;
  const Chat({
    required this.id,
    required this.name,
    this.lastMessage,
    required this.unreadCount,
    required this.updatedAt,
    required this.lastSequenceId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || lastMessage != null) {
      map['last_message'] = Variable<String>(lastMessage);
    }
    map['unread_count'] = Variable<int>(unreadCount);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['last_sequence_id'] = Variable<int>(lastSequenceId);
    return map;
  }

  ChatsCompanion toCompanion(bool nullToAbsent) {
    return ChatsCompanion(
      id: Value(id),
      name: Value(name),
      lastMessage: lastMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessage),
      unreadCount: Value(unreadCount),
      updatedAt: Value(updatedAt),
      lastSequenceId: Value(lastSequenceId),
    );
  }

  factory Chat.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Chat(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      lastMessage: serializer.fromJson<String?>(json['lastMessage']),
      unreadCount: serializer.fromJson<int>(json['unreadCount']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      lastSequenceId: serializer.fromJson<int>(json['lastSequenceId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'lastMessage': serializer.toJson<String?>(lastMessage),
      'unreadCount': serializer.toJson<int>(unreadCount),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'lastSequenceId': serializer.toJson<int>(lastSequenceId),
    };
  }

  Chat copyWith({
    String? id,
    String? name,
    Value<String?> lastMessage = const Value.absent(),
    int? unreadCount,
    DateTime? updatedAt,
    int? lastSequenceId,
  }) => Chat(
    id: id ?? this.id,
    name: name ?? this.name,
    lastMessage: lastMessage.present ? lastMessage.value : this.lastMessage,
    unreadCount: unreadCount ?? this.unreadCount,
    updatedAt: updatedAt ?? this.updatedAt,
    lastSequenceId: lastSequenceId ?? this.lastSequenceId,
  );
  Chat copyWithCompanion(ChatsCompanion data) {
    return Chat(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      lastMessage: data.lastMessage.present
          ? data.lastMessage.value
          : this.lastMessage,
      unreadCount: data.unreadCount.present
          ? data.unreadCount.value
          : this.unreadCount,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      lastSequenceId: data.lastSequenceId.present
          ? data.lastSequenceId.value
          : this.lastSequenceId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Chat(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('lastMessage: $lastMessage, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastSequenceId: $lastSequenceId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    lastMessage,
    unreadCount,
    updatedAt,
    lastSequenceId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Chat &&
          other.id == this.id &&
          other.name == this.name &&
          other.lastMessage == this.lastMessage &&
          other.unreadCount == this.unreadCount &&
          other.updatedAt == this.updatedAt &&
          other.lastSequenceId == this.lastSequenceId);
}

class ChatsCompanion extends UpdateCompanion<Chat> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> lastMessage;
  final Value<int> unreadCount;
  final Value<DateTime> updatedAt;
  final Value<int> lastSequenceId;
  final Value<int> rowid;
  const ChatsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.lastMessage = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.lastSequenceId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChatsCompanion.insert({
    required String id,
    this.name = const Value.absent(),
    this.lastMessage = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.lastSequenceId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id);
  static Insertable<Chat> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? lastMessage,
    Expression<int>? unreadCount,
    Expression<DateTime>? updatedAt,
    Expression<int>? lastSequenceId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (lastMessage != null) 'last_message': lastMessage,
      if (unreadCount != null) 'unread_count': unreadCount,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (lastSequenceId != null) 'last_sequence_id': lastSequenceId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChatsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? lastMessage,
    Value<int>? unreadCount,
    Value<DateTime>? updatedAt,
    Value<int>? lastSequenceId,
    Value<int>? rowid,
  }) {
    return ChatsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      updatedAt: updatedAt ?? this.updatedAt,
      lastSequenceId: lastSequenceId ?? this.lastSequenceId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (lastMessage.present) {
      map['last_message'] = Variable<String>(lastMessage.value);
    }
    if (unreadCount.present) {
      map['unread_count'] = Variable<int>(unreadCount.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (lastSequenceId.present) {
      map['last_sequence_id'] = Variable<int>(lastSequenceId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('lastMessage: $lastMessage, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastSequenceId: $lastSequenceId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages with TableInfo<$MessagesTable, Message> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localIdMeta = const VerificationMeta(
    'localId',
  );
  @override
  late final GeneratedColumn<String> localId = GeneratedColumn<String>(
    'local_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<String> serverId = GeneratedColumn<String>(
    'server_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _chatIdMeta = const VerificationMeta('chatId');
  @override
  late final GeneratedColumn<String> chatId = GeneratedColumn<String>(
    'chat_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _senderIdMeta = const VerificationMeta(
    'senderId',
  );
  @override
  late final GeneratedColumn<String> senderId = GeneratedColumn<String>(
    'sender_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mediaLocalPathMeta = const VerificationMeta(
    'mediaLocalPath',
  );
  @override
  late final GeneratedColumn<String> mediaLocalPath = GeneratedColumn<String>(
    'media_local_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mediaUrlMeta = const VerificationMeta(
    'mediaUrl',
  );
  @override
  late final GeneratedColumn<String> mediaUrl = GeneratedColumn<String>(
    'media_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DeliveryStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DeliveryStatus>($MessagesTable.$converterstatus);
  @override
  late final GeneratedColumnWithTypeConverter<MessageType, String> messageType =
      GeneratedColumn<String>(
        'message_type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<MessageType>($MessagesTable.$convertermessageType);
  static const VerificationMeta _sequenceIdMeta = const VerificationMeta(
    'sequenceId',
  );
  @override
  late final GeneratedColumn<int> sequenceId = GeneratedColumn<int>(
    'sequence_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    localId,
    serverId,
    chatId,
    senderId,
    content,
    mediaLocalPath,
    mediaUrl,
    timestamp,
    status,
    messageType,
    sequenceId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<Message> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_id')) {
      context.handle(
        _localIdMeta,
        localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta),
      );
    } else if (isInserting) {
      context.missing(_localIdMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    }
    if (data.containsKey('chat_id')) {
      context.handle(
        _chatIdMeta,
        chatId.isAcceptableOrUnknown(data['chat_id']!, _chatIdMeta),
      );
    } else if (isInserting) {
      context.missing(_chatIdMeta);
    }
    if (data.containsKey('sender_id')) {
      context.handle(
        _senderIdMeta,
        senderId.isAcceptableOrUnknown(data['sender_id']!, _senderIdMeta),
      );
    } else if (isInserting) {
      context.missing(_senderIdMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('media_local_path')) {
      context.handle(
        _mediaLocalPathMeta,
        mediaLocalPath.isAcceptableOrUnknown(
          data['media_local_path']!,
          _mediaLocalPathMeta,
        ),
      );
    }
    if (data.containsKey('media_url')) {
      context.handle(
        _mediaUrlMeta,
        mediaUrl.isAcceptableOrUnknown(data['media_url']!, _mediaUrlMeta),
      );
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('sequence_id')) {
      context.handle(
        _sequenceIdMeta,
        sequenceId.isAcceptableOrUnknown(data['sequence_id']!, _sequenceIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {localId};
  @override
  Message map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Message(
      localId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_id'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_id'],
      ),
      chatId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chat_id'],
      )!,
      senderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_id'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      mediaLocalPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_local_path'],
      ),
      mediaUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_url'],
      ),
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
      status: $MessagesTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      messageType: $MessagesTable.$convertermessageType.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}message_type'],
        )!,
      ),
      sequenceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence_id'],
      ),
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<DeliveryStatus, String, String> $converterstatus =
      const EnumNameConverter<DeliveryStatus>(DeliveryStatus.values);
  static JsonTypeConverter2<MessageType, String, String> $convertermessageType =
      const EnumNameConverter<MessageType>(MessageType.values);
}

class Message extends DataClass implements Insertable<Message> {
  /// Client side uuid v4. It is the primary key and never changes.
  final String localId;

  /// Id assigned by the server. Null while the message is still pending.
  final String? serverId;

  /// Chat this message belongs to.
  final String chatId;

  /// Author of the message.
  final String senderId;

  /// Message body. For media messages this holds the path/URL of the file.
  final String content;

  /// Path of a file that was downloaded to the device (optional).
  final String? mediaLocalPath;

  /// Absolute url of a media message.
  final String? mediaUrl;

  /// Creation time. For pending messages this is the local time.
  final DateTime timestamp;

  /// Delivery state of the message.
  final DeliveryStatus status;

  /// Type of the message (text, image, voice, ...).
  final MessageType messageType;

  /// Monotonic sequence id assigned by the server, used for delta sync.
  final int? sequenceId;
  const Message({
    required this.localId,
    this.serverId,
    required this.chatId,
    required this.senderId,
    required this.content,
    this.mediaLocalPath,
    this.mediaUrl,
    required this.timestamp,
    required this.status,
    required this.messageType,
    this.sequenceId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_id'] = Variable<String>(localId);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<String>(serverId);
    }
    map['chat_id'] = Variable<String>(chatId);
    map['sender_id'] = Variable<String>(senderId);
    map['content'] = Variable<String>(content);
    if (!nullToAbsent || mediaLocalPath != null) {
      map['media_local_path'] = Variable<String>(mediaLocalPath);
    }
    if (!nullToAbsent || mediaUrl != null) {
      map['media_url'] = Variable<String>(mediaUrl);
    }
    map['timestamp'] = Variable<DateTime>(timestamp);
    {
      map['status'] = Variable<String>(
        $MessagesTable.$converterstatus.toSql(status),
      );
    }
    {
      map['message_type'] = Variable<String>(
        $MessagesTable.$convertermessageType.toSql(messageType),
      );
    }
    if (!nullToAbsent || sequenceId != null) {
      map['sequence_id'] = Variable<int>(sequenceId);
    }
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      localId: Value(localId),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      chatId: Value(chatId),
      senderId: Value(senderId),
      content: Value(content),
      mediaLocalPath: mediaLocalPath == null && nullToAbsent
          ? const Value.absent()
          : Value(mediaLocalPath),
      mediaUrl: mediaUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(mediaUrl),
      timestamp: Value(timestamp),
      status: Value(status),
      messageType: Value(messageType),
      sequenceId: sequenceId == null && nullToAbsent
          ? const Value.absent()
          : Value(sequenceId),
    );
  }

  factory Message.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Message(
      localId: serializer.fromJson<String>(json['localId']),
      serverId: serializer.fromJson<String?>(json['serverId']),
      chatId: serializer.fromJson<String>(json['chatId']),
      senderId: serializer.fromJson<String>(json['senderId']),
      content: serializer.fromJson<String>(json['content']),
      mediaLocalPath: serializer.fromJson<String?>(json['mediaLocalPath']),
      mediaUrl: serializer.fromJson<String?>(json['mediaUrl']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      status: $MessagesTable.$converterstatus.fromJson(
        serializer.fromJson<String>(json['status']),
      ),
      messageType: $MessagesTable.$convertermessageType.fromJson(
        serializer.fromJson<String>(json['messageType']),
      ),
      sequenceId: serializer.fromJson<int?>(json['sequenceId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localId': serializer.toJson<String>(localId),
      'serverId': serializer.toJson<String?>(serverId),
      'chatId': serializer.toJson<String>(chatId),
      'senderId': serializer.toJson<String>(senderId),
      'content': serializer.toJson<String>(content),
      'mediaLocalPath': serializer.toJson<String?>(mediaLocalPath),
      'mediaUrl': serializer.toJson<String?>(mediaUrl),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'status': serializer.toJson<String>(
        $MessagesTable.$converterstatus.toJson(status),
      ),
      'messageType': serializer.toJson<String>(
        $MessagesTable.$convertermessageType.toJson(messageType),
      ),
      'sequenceId': serializer.toJson<int?>(sequenceId),
    };
  }

  Message copyWith({
    String? localId,
    Value<String?> serverId = const Value.absent(),
    String? chatId,
    String? senderId,
    String? content,
    Value<String?> mediaLocalPath = const Value.absent(),
    Value<String?> mediaUrl = const Value.absent(),
    DateTime? timestamp,
    DeliveryStatus? status,
    MessageType? messageType,
    Value<int?> sequenceId = const Value.absent(),
  }) => Message(
    localId: localId ?? this.localId,
    serverId: serverId.present ? serverId.value : this.serverId,
    chatId: chatId ?? this.chatId,
    senderId: senderId ?? this.senderId,
    content: content ?? this.content,
    mediaLocalPath: mediaLocalPath.present
        ? mediaLocalPath.value
        : this.mediaLocalPath,
    mediaUrl: mediaUrl.present ? mediaUrl.value : this.mediaUrl,
    timestamp: timestamp ?? this.timestamp,
    status: status ?? this.status,
    messageType: messageType ?? this.messageType,
    sequenceId: sequenceId.present ? sequenceId.value : this.sequenceId,
  );
  Message copyWithCompanion(MessagesCompanion data) {
    return Message(
      localId: data.localId.present ? data.localId.value : this.localId,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      chatId: data.chatId.present ? data.chatId.value : this.chatId,
      senderId: data.senderId.present ? data.senderId.value : this.senderId,
      content: data.content.present ? data.content.value : this.content,
      mediaLocalPath: data.mediaLocalPath.present
          ? data.mediaLocalPath.value
          : this.mediaLocalPath,
      mediaUrl: data.mediaUrl.present ? data.mediaUrl.value : this.mediaUrl,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      status: data.status.present ? data.status.value : this.status,
      messageType: data.messageType.present
          ? data.messageType.value
          : this.messageType,
      sequenceId: data.sequenceId.present
          ? data.sequenceId.value
          : this.sequenceId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Message(')
          ..write('localId: $localId, ')
          ..write('serverId: $serverId, ')
          ..write('chatId: $chatId, ')
          ..write('senderId: $senderId, ')
          ..write('content: $content, ')
          ..write('mediaLocalPath: $mediaLocalPath, ')
          ..write('mediaUrl: $mediaUrl, ')
          ..write('timestamp: $timestamp, ')
          ..write('status: $status, ')
          ..write('messageType: $messageType, ')
          ..write('sequenceId: $sequenceId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    localId,
    serverId,
    chatId,
    senderId,
    content,
    mediaLocalPath,
    mediaUrl,
    timestamp,
    status,
    messageType,
    sequenceId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Message &&
          other.localId == this.localId &&
          other.serverId == this.serverId &&
          other.chatId == this.chatId &&
          other.senderId == this.senderId &&
          other.content == this.content &&
          other.mediaLocalPath == this.mediaLocalPath &&
          other.mediaUrl == this.mediaUrl &&
          other.timestamp == this.timestamp &&
          other.status == this.status &&
          other.messageType == this.messageType &&
          other.sequenceId == this.sequenceId);
}

class MessagesCompanion extends UpdateCompanion<Message> {
  final Value<String> localId;
  final Value<String?> serverId;
  final Value<String> chatId;
  final Value<String> senderId;
  final Value<String> content;
  final Value<String?> mediaLocalPath;
  final Value<String?> mediaUrl;
  final Value<DateTime> timestamp;
  final Value<DeliveryStatus> status;
  final Value<MessageType> messageType;
  final Value<int?> sequenceId;
  final Value<int> rowid;
  const MessagesCompanion({
    this.localId = const Value.absent(),
    this.serverId = const Value.absent(),
    this.chatId = const Value.absent(),
    this.senderId = const Value.absent(),
    this.content = const Value.absent(),
    this.mediaLocalPath = const Value.absent(),
    this.mediaUrl = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.status = const Value.absent(),
    this.messageType = const Value.absent(),
    this.sequenceId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessagesCompanion.insert({
    required String localId,
    this.serverId = const Value.absent(),
    required String chatId,
    required String senderId,
    required String content,
    this.mediaLocalPath = const Value.absent(),
    this.mediaUrl = const Value.absent(),
    required DateTime timestamp,
    required DeliveryStatus status,
    required MessageType messageType,
    this.sequenceId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : localId = Value(localId),
       chatId = Value(chatId),
       senderId = Value(senderId),
       content = Value(content),
       timestamp = Value(timestamp),
       status = Value(status),
       messageType = Value(messageType);
  static Insertable<Message> custom({
    Expression<String>? localId,
    Expression<String>? serverId,
    Expression<String>? chatId,
    Expression<String>? senderId,
    Expression<String>? content,
    Expression<String>? mediaLocalPath,
    Expression<String>? mediaUrl,
    Expression<DateTime>? timestamp,
    Expression<String>? status,
    Expression<String>? messageType,
    Expression<int>? sequenceId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (localId != null) 'local_id': localId,
      if (serverId != null) 'server_id': serverId,
      if (chatId != null) 'chat_id': chatId,
      if (senderId != null) 'sender_id': senderId,
      if (content != null) 'content': content,
      if (mediaLocalPath != null) 'media_local_path': mediaLocalPath,
      if (mediaUrl != null) 'media_url': mediaUrl,
      if (timestamp != null) 'timestamp': timestamp,
      if (status != null) 'status': status,
      if (messageType != null) 'message_type': messageType,
      if (sequenceId != null) 'sequence_id': sequenceId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessagesCompanion copyWith({
    Value<String>? localId,
    Value<String?>? serverId,
    Value<String>? chatId,
    Value<String>? senderId,
    Value<String>? content,
    Value<String?>? mediaLocalPath,
    Value<String?>? mediaUrl,
    Value<DateTime>? timestamp,
    Value<DeliveryStatus>? status,
    Value<MessageType>? messageType,
    Value<int?>? sequenceId,
    Value<int>? rowid,
  }) {
    return MessagesCompanion(
      localId: localId ?? this.localId,
      serverId: serverId ?? this.serverId,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      mediaLocalPath: mediaLocalPath ?? this.mediaLocalPath,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      messageType: messageType ?? this.messageType,
      sequenceId: sequenceId ?? this.sequenceId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localId.present) {
      map['local_id'] = Variable<String>(localId.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (chatId.present) {
      map['chat_id'] = Variable<String>(chatId.value);
    }
    if (senderId.present) {
      map['sender_id'] = Variable<String>(senderId.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (mediaLocalPath.present) {
      map['media_local_path'] = Variable<String>(mediaLocalPath.value);
    }
    if (mediaUrl.present) {
      map['media_url'] = Variable<String>(mediaUrl.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $MessagesTable.$converterstatus.toSql(status.value),
      );
    }
    if (messageType.present) {
      map['message_type'] = Variable<String>(
        $MessagesTable.$convertermessageType.toSql(messageType.value),
      );
    }
    if (sequenceId.present) {
      map['sequence_id'] = Variable<int>(sequenceId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('localId: $localId, ')
          ..write('serverId: $serverId, ')
          ..write('chatId: $chatId, ')
          ..write('senderId: $senderId, ')
          ..write('content: $content, ')
          ..write('mediaLocalPath: $mediaLocalPath, ')
          ..write('mediaUrl: $mediaUrl, ')
          ..write('timestamp: $timestamp, ')
          ..write('status: $status, ')
          ..write('messageType: $messageType, ')
          ..write('sequenceId: $sequenceId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ChatsTable chats = $ChatsTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  late final Index chatsUpdatedAtIdx = Index(
    'chats_updated_at_idx',
    'CREATE INDEX chats_updated_at_idx ON chats (updated_at)',
  );
  late final Index messagesChatTsIdx = Index(
    'messages_chat_ts_idx',
    'CREATE INDEX messages_chat_ts_idx ON messages (chat_id, timestamp)',
  );
  late final Index messagesServerIdIdx = Index(
    'messages_server_id_idx',
    'CREATE INDEX messages_server_id_idx ON messages (server_id)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    chats,
    messages,
    chatsUpdatedAtIdx,
    messagesChatTsIdx,
    messagesServerIdIdx,
  ];
}

typedef $$ChatsTableCreateCompanionBuilder =
    ChatsCompanion Function({
      required String id,
      Value<String> name,
      Value<String?> lastMessage,
      Value<int> unreadCount,
      Value<DateTime> updatedAt,
      Value<int> lastSequenceId,
      Value<int> rowid,
    });
typedef $$ChatsTableUpdateCompanionBuilder =
    ChatsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String?> lastMessage,
      Value<int> unreadCount,
      Value<DateTime> updatedAt,
      Value<int> lastSequenceId,
      Value<int> rowid,
    });

class $$ChatsTableFilterComposer extends Composer<_$AppDatabase, $ChatsTable> {
  $$ChatsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastMessage => $composableBuilder(
    column: $table.lastMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSequenceId => $composableBuilder(
    column: $table.lastSequenceId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChatsTableOrderingComposer
    extends Composer<_$AppDatabase, $ChatsTable> {
  $$ChatsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastMessage => $composableBuilder(
    column: $table.lastMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSequenceId => $composableBuilder(
    column: $table.lastSequenceId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChatsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChatsTable> {
  $$ChatsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get lastMessage => $composableBuilder(
    column: $table.lastMessage,
    builder: (column) => column,
  );

  GeneratedColumn<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get lastSequenceId => $composableBuilder(
    column: $table.lastSequenceId,
    builder: (column) => column,
  );
}

class $$ChatsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChatsTable,
          Chat,
          $$ChatsTableFilterComposer,
          $$ChatsTableOrderingComposer,
          $$ChatsTableAnnotationComposer,
          $$ChatsTableCreateCompanionBuilder,
          $$ChatsTableUpdateCompanionBuilder,
          (Chat, BaseReferences<_$AppDatabase, $ChatsTable, Chat>),
          Chat,
          PrefetchHooks Function()
        > {
  $$ChatsTableTableManager(_$AppDatabase db, $ChatsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> lastMessage = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> lastSequenceId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatsCompanion(
                id: id,
                name: name,
                lastMessage: lastMessage,
                unreadCount: unreadCount,
                updatedAt: updatedAt,
                lastSequenceId: lastSequenceId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> name = const Value.absent(),
                Value<String?> lastMessage = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> lastSequenceId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatsCompanion.insert(
                id: id,
                name: name,
                lastMessage: lastMessage,
                unreadCount: unreadCount,
                updatedAt: updatedAt,
                lastSequenceId: lastSequenceId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ChatsTable, Chat>(table),
                  BaseReferences<_$AppDatabase, $ChatsTable, Chat>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChatsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChatsTable,
      Chat,
      $$ChatsTableFilterComposer,
      $$ChatsTableOrderingComposer,
      $$ChatsTableAnnotationComposer,
      $$ChatsTableCreateCompanionBuilder,
      $$ChatsTableUpdateCompanionBuilder,
      (Chat, BaseReferences<_$AppDatabase, $ChatsTable, Chat>),
      Chat,
      PrefetchHooks Function()
    >;
typedef $$MessagesTableCreateCompanionBuilder =
    MessagesCompanion Function({
      required String localId,
      Value<String?> serverId,
      required String chatId,
      required String senderId,
      required String content,
      Value<String?> mediaLocalPath,
      Value<String?> mediaUrl,
      required DateTime timestamp,
      required DeliveryStatus status,
      required MessageType messageType,
      Value<int?> sequenceId,
      Value<int> rowid,
    });
typedef $$MessagesTableUpdateCompanionBuilder =
    MessagesCompanion Function({
      Value<String> localId,
      Value<String?> serverId,
      Value<String> chatId,
      Value<String> senderId,
      Value<String> content,
      Value<String?> mediaLocalPath,
      Value<String?> mediaUrl,
      Value<DateTime> timestamp,
      Value<DeliveryStatus> status,
      Value<MessageType> messageType,
      Value<int?> sequenceId,
      Value<int> rowid,
    });

class $$MessagesTableFilterComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chatId => $composableBuilder(
    column: $table.chatId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get senderId => $composableBuilder(
    column: $table.senderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaLocalPath => $composableBuilder(
    column: $table.mediaLocalPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaUrl => $composableBuilder(
    column: $table.mediaUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DeliveryStatus, DeliveryStatus, String>
  get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<MessageType, MessageType, String>
  get messageType => $composableBuilder(
    column: $table.messageType,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get sequenceId => $composableBuilder(
    column: $table.sequenceId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chatId => $composableBuilder(
    column: $table.chatId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderId => $composableBuilder(
    column: $table.senderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaLocalPath => $composableBuilder(
    column: $table.mediaLocalPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaUrl => $composableBuilder(
    column: $table.mediaUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageType => $composableBuilder(
    column: $table.messageType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sequenceId => $composableBuilder(
    column: $table.sequenceId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get localId =>
      $composableBuilder(column: $table.localId, builder: (column) => column);

  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get chatId =>
      $composableBuilder(column: $table.chatId, builder: (column) => column);

  GeneratedColumn<String> get senderId =>
      $composableBuilder(column: $table.senderId, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get mediaLocalPath => $composableBuilder(
    column: $table.mediaLocalPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mediaUrl =>
      $composableBuilder(column: $table.mediaUrl, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DeliveryStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumnWithTypeConverter<MessageType, String> get messageType =>
      $composableBuilder(
        column: $table.messageType,
        builder: (column) => column,
      );

  GeneratedColumn<int> get sequenceId => $composableBuilder(
    column: $table.sequenceId,
    builder: (column) => column,
  );
}

class $$MessagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MessagesTable,
          Message,
          $$MessagesTableFilterComposer,
          $$MessagesTableOrderingComposer,
          $$MessagesTableAnnotationComposer,
          $$MessagesTableCreateCompanionBuilder,
          $$MessagesTableUpdateCompanionBuilder,
          (Message, BaseReferences<_$AppDatabase, $MessagesTable, Message>),
          Message,
          PrefetchHooks Function()
        > {
  $$MessagesTableTableManager(_$AppDatabase db, $MessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> localId = const Value.absent(),
                Value<String?> serverId = const Value.absent(),
                Value<String> chatId = const Value.absent(),
                Value<String> senderId = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String?> mediaLocalPath = const Value.absent(),
                Value<String?> mediaUrl = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                Value<DeliveryStatus> status = const Value.absent(),
                Value<MessageType> messageType = const Value.absent(),
                Value<int?> sequenceId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessagesCompanion(
                localId: localId,
                serverId: serverId,
                chatId: chatId,
                senderId: senderId,
                content: content,
                mediaLocalPath: mediaLocalPath,
                mediaUrl: mediaUrl,
                timestamp: timestamp,
                status: status,
                messageType: messageType,
                sequenceId: sequenceId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String localId,
                Value<String?> serverId = const Value.absent(),
                required String chatId,
                required String senderId,
                required String content,
                Value<String?> mediaLocalPath = const Value.absent(),
                Value<String?> mediaUrl = const Value.absent(),
                required DateTime timestamp,
                required DeliveryStatus status,
                required MessageType messageType,
                Value<int?> sequenceId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessagesCompanion.insert(
                localId: localId,
                serverId: serverId,
                chatId: chatId,
                senderId: senderId,
                content: content,
                mediaLocalPath: mediaLocalPath,
                mediaUrl: mediaUrl,
                timestamp: timestamp,
                status: status,
                messageType: messageType,
                sequenceId: sequenceId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MessagesTable, Message>(table),
                  BaseReferences<_$AppDatabase, $MessagesTable, Message>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MessagesTable,
      Message,
      $$MessagesTableFilterComposer,
      $$MessagesTableOrderingComposer,
      $$MessagesTableAnnotationComposer,
      $$MessagesTableCreateCompanionBuilder,
      $$MessagesTableUpdateCompanionBuilder,
      (Message, BaseReferences<_$AppDatabase, $MessagesTable, Message>),
      Message,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ChatsTableTableManager get chats =>
      $$ChatsTableTableManager(_db, _db.chats);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
}
