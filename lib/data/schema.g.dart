// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'schema.dart';

// ignore_for_file: type=lint
class $FoldersTable extends Folders with TableInfo<$FoldersTable, FolderRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FoldersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
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
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortKeyMeta = const VerificationMeta(
    'sortKey',
  );
  @override
  late final GeneratedColumn<int> sortKey = GeneratedColumn<int>(
    'sort_key',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
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
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    serverId,
    parentId,
    kind,
    name,
    sortKey,
    revision,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'folders';
  @override
  VerificationContext validateIntegrity(
    Insertable<FolderRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort_key')) {
      context.handle(
        _sortKeyMeta,
        sortKey.isAcceptableOrUnknown(data['sort_key']!, _sortKeyMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FolderRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FolderRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_id'],
      ),
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sortKey: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_key'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $FoldersTable createAlias(String alias) {
    return $FoldersTable(attachedDatabase, alias);
  }
}

class FolderRow extends DataClass implements Insertable<FolderRow> {
  final String id;
  final String? serverId;
  final String? parentId;
  final String kind;
  final String name;
  final int sortKey;
  final int? revision;
  final DateTime updatedAt;
  const FolderRow({
    required this.id,
    this.serverId,
    this.parentId,
    required this.kind,
    required this.name,
    required this.sortKey,
    this.revision,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<String>(serverId);
    }
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    map['kind'] = Variable<String>(kind);
    map['name'] = Variable<String>(name);
    map['sort_key'] = Variable<int>(sortKey);
    if (!nullToAbsent || revision != null) {
      map['revision'] = Variable<int>(revision);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  FoldersCompanion toCompanion(bool nullToAbsent) {
    return FoldersCompanion(
      id: Value(id),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      kind: Value(kind),
      name: Value(name),
      sortKey: Value(sortKey),
      revision: revision == null && nullToAbsent
          ? const Value.absent()
          : Value(revision),
      updatedAt: Value(updatedAt),
    );
  }

  factory FolderRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FolderRow(
      id: serializer.fromJson<String>(json['id']),
      serverId: serializer.fromJson<String?>(json['serverId']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      kind: serializer.fromJson<String>(json['kind']),
      name: serializer.fromJson<String>(json['name']),
      sortKey: serializer.fromJson<int>(json['sortKey']),
      revision: serializer.fromJson<int?>(json['revision']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'serverId': serializer.toJson<String?>(serverId),
      'parentId': serializer.toJson<String?>(parentId),
      'kind': serializer.toJson<String>(kind),
      'name': serializer.toJson<String>(name),
      'sortKey': serializer.toJson<int>(sortKey),
      'revision': serializer.toJson<int?>(revision),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  FolderRow copyWith({
    String? id,
    Value<String?> serverId = const Value.absent(),
    Value<String?> parentId = const Value.absent(),
    String? kind,
    String? name,
    int? sortKey,
    Value<int?> revision = const Value.absent(),
    DateTime? updatedAt,
  }) => FolderRow(
    id: id ?? this.id,
    serverId: serverId.present ? serverId.value : this.serverId,
    parentId: parentId.present ? parentId.value : this.parentId,
    kind: kind ?? this.kind,
    name: name ?? this.name,
    sortKey: sortKey ?? this.sortKey,
    revision: revision.present ? revision.value : this.revision,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  FolderRow copyWithCompanion(FoldersCompanion data) {
    return FolderRow(
      id: data.id.present ? data.id.value : this.id,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      kind: data.kind.present ? data.kind.value : this.kind,
      name: data.name.present ? data.name.value : this.name,
      sortKey: data.sortKey.present ? data.sortKey.value : this.sortKey,
      revision: data.revision.present ? data.revision.value : this.revision,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FolderRow(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('parentId: $parentId, ')
          ..write('kind: $kind, ')
          ..write('name: $name, ')
          ..write('sortKey: $sortKey, ')
          ..write('revision: $revision, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    serverId,
    parentId,
    kind,
    name,
    sortKey,
    revision,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FolderRow &&
          other.id == this.id &&
          other.serverId == this.serverId &&
          other.parentId == this.parentId &&
          other.kind == this.kind &&
          other.name == this.name &&
          other.sortKey == this.sortKey &&
          other.revision == this.revision &&
          other.updatedAt == this.updatedAt);
}

class FoldersCompanion extends UpdateCompanion<FolderRow> {
  final Value<String> id;
  final Value<String?> serverId;
  final Value<String?> parentId;
  final Value<String> kind;
  final Value<String> name;
  final Value<int> sortKey;
  final Value<int?> revision;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const FoldersCompanion({
    this.id = const Value.absent(),
    this.serverId = const Value.absent(),
    this.parentId = const Value.absent(),
    this.kind = const Value.absent(),
    this.name = const Value.absent(),
    this.sortKey = const Value.absent(),
    this.revision = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FoldersCompanion.insert({
    required String id,
    this.serverId = const Value.absent(),
    this.parentId = const Value.absent(),
    required String kind,
    required String name,
    this.sortKey = const Value.absent(),
    this.revision = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       kind = Value(kind),
       name = Value(name),
       updatedAt = Value(updatedAt);
  static Insertable<FolderRow> custom({
    Expression<String>? id,
    Expression<String>? serverId,
    Expression<String>? parentId,
    Expression<String>? kind,
    Expression<String>? name,
    Expression<int>? sortKey,
    Expression<int>? revision,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (serverId != null) 'server_id': serverId,
      if (parentId != null) 'parent_id': parentId,
      if (kind != null) 'kind': kind,
      if (name != null) 'name': name,
      if (sortKey != null) 'sort_key': sortKey,
      if (revision != null) 'revision': revision,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FoldersCompanion copyWith({
    Value<String>? id,
    Value<String?>? serverId,
    Value<String?>? parentId,
    Value<String>? kind,
    Value<String>? name,
    Value<int>? sortKey,
    Value<int?>? revision,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return FoldersCompanion(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      parentId: parentId ?? this.parentId,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      sortKey: sortKey ?? this.sortKey,
      revision: revision ?? this.revision,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortKey.present) {
      map['sort_key'] = Variable<int>(sortKey.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FoldersCompanion(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('parentId: $parentId, ')
          ..write('kind: $kind, ')
          ..write('name: $name, ')
          ..write('sortKey: $sortKey, ')
          ..write('revision: $revision, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SourcesTable extends Sources with TableInfo<$SourcesTable, SourceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SourcesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _collectionIdMeta = const VerificationMeta(
    'collectionId',
  );
  @override
  late final GeneratedColumn<String> collectionId = GeneratedColumn<String>(
    'collection_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hostMeta = const VerificationMeta('host');
  @override
  late final GeneratedColumn<String> host = GeneratedColumn<String>(
    'host',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathKeyMeta = const VerificationMeta(
    'pathKey',
  );
  @override
  late final GeneratedColumn<String> pathKey = GeneratedColumn<String>(
    'path_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _languageMeta = const VerificationMeta(
    'language',
  );
  @override
  late final GeneratedColumn<String> language = GeneratedColumn<String>(
    'language',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _lifecycleMeta = const VerificationMeta(
    'lifecycle',
  );
  @override
  late final GeneratedColumn<String> lifecycle = GeneratedColumn<String>(
    'lifecycle',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('active'),
  );
  static const VerificationMeta _resolvedIntoSourceIdMeta =
      const VerificationMeta('resolvedIntoSourceId');
  @override
  late final GeneratedColumn<String> resolvedIntoSourceId =
      GeneratedColumn<String>(
        'resolved_into_source_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _firstSeenAtMeta = const VerificationMeta(
    'firstSeenAt',
  );
  @override
  late final GeneratedColumn<DateTime> firstSeenAt = GeneratedColumn<DateTime>(
    'first_seen_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSeenAtMeta = const VerificationMeta(
    'lastSeenAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSeenAt = GeneratedColumn<DateTime>(
    'last_seen_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
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
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    serverId,
    collectionId,
    host,
    pathKey,
    language,
    lifecycle,
    resolvedIntoSourceId,
    firstSeenAt,
    lastSeenAt,
    revision,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sources';
  @override
  VerificationContext validateIntegrity(
    Insertable<SourceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    }
    if (data.containsKey('collection_id')) {
      context.handle(
        _collectionIdMeta,
        collectionId.isAcceptableOrUnknown(
          data['collection_id']!,
          _collectionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_collectionIdMeta);
    }
    if (data.containsKey('host')) {
      context.handle(
        _hostMeta,
        host.isAcceptableOrUnknown(data['host']!, _hostMeta),
      );
    } else if (isInserting) {
      context.missing(_hostMeta);
    }
    if (data.containsKey('path_key')) {
      context.handle(
        _pathKeyMeta,
        pathKey.isAcceptableOrUnknown(data['path_key']!, _pathKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_pathKeyMeta);
    }
    if (data.containsKey('language')) {
      context.handle(
        _languageMeta,
        language.isAcceptableOrUnknown(data['language']!, _languageMeta),
      );
    }
    if (data.containsKey('lifecycle')) {
      context.handle(
        _lifecycleMeta,
        lifecycle.isAcceptableOrUnknown(data['lifecycle']!, _lifecycleMeta),
      );
    }
    if (data.containsKey('resolved_into_source_id')) {
      context.handle(
        _resolvedIntoSourceIdMeta,
        resolvedIntoSourceId.isAcceptableOrUnknown(
          data['resolved_into_source_id']!,
          _resolvedIntoSourceIdMeta,
        ),
      );
    }
    if (data.containsKey('first_seen_at')) {
      context.handle(
        _firstSeenAtMeta,
        firstSeenAt.isAcceptableOrUnknown(
          data['first_seen_at']!,
          _firstSeenAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_firstSeenAtMeta);
    }
    if (data.containsKey('last_seen_at')) {
      context.handle(
        _lastSeenAtMeta,
        lastSeenAt.isAcceptableOrUnknown(
          data['last_seen_at']!,
          _lastSeenAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastSeenAtMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {collectionId, host, pathKey},
  ];
  @override
  SourceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SourceRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_id'],
      ),
      collectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}collection_id'],
      )!,
      host: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host'],
      )!,
      pathKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path_key'],
      )!,
      language: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}language'],
      )!,
      lifecycle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lifecycle'],
      )!,
      resolvedIntoSourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resolved_into_source_id'],
      ),
      firstSeenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}first_seen_at'],
      )!,
      lastSeenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_seen_at'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SourcesTable createAlias(String alias) {
    return $SourcesTable(attachedDatabase, alias);
  }
}

class SourceRow extends DataClass implements Insertable<SourceRow> {
  final String id;
  final String? serverId;
  final String collectionId;
  final String host;
  final String pathKey;
  final String language;
  final String lifecycle;
  final String? resolvedIntoSourceId;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final int? revision;
  final DateTime updatedAt;
  const SourceRow({
    required this.id,
    this.serverId,
    required this.collectionId,
    required this.host,
    required this.pathKey,
    required this.language,
    required this.lifecycle,
    this.resolvedIntoSourceId,
    required this.firstSeenAt,
    required this.lastSeenAt,
    this.revision,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<String>(serverId);
    }
    map['collection_id'] = Variable<String>(collectionId);
    map['host'] = Variable<String>(host);
    map['path_key'] = Variable<String>(pathKey);
    map['language'] = Variable<String>(language);
    map['lifecycle'] = Variable<String>(lifecycle);
    if (!nullToAbsent || resolvedIntoSourceId != null) {
      map['resolved_into_source_id'] = Variable<String>(resolvedIntoSourceId);
    }
    map['first_seen_at'] = Variable<DateTime>(firstSeenAt);
    map['last_seen_at'] = Variable<DateTime>(lastSeenAt);
    if (!nullToAbsent || revision != null) {
      map['revision'] = Variable<int>(revision);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SourcesCompanion toCompanion(bool nullToAbsent) {
    return SourcesCompanion(
      id: Value(id),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      collectionId: Value(collectionId),
      host: Value(host),
      pathKey: Value(pathKey),
      language: Value(language),
      lifecycle: Value(lifecycle),
      resolvedIntoSourceId: resolvedIntoSourceId == null && nullToAbsent
          ? const Value.absent()
          : Value(resolvedIntoSourceId),
      firstSeenAt: Value(firstSeenAt),
      lastSeenAt: Value(lastSeenAt),
      revision: revision == null && nullToAbsent
          ? const Value.absent()
          : Value(revision),
      updatedAt: Value(updatedAt),
    );
  }

  factory SourceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SourceRow(
      id: serializer.fromJson<String>(json['id']),
      serverId: serializer.fromJson<String?>(json['serverId']),
      collectionId: serializer.fromJson<String>(json['collectionId']),
      host: serializer.fromJson<String>(json['host']),
      pathKey: serializer.fromJson<String>(json['pathKey']),
      language: serializer.fromJson<String>(json['language']),
      lifecycle: serializer.fromJson<String>(json['lifecycle']),
      resolvedIntoSourceId: serializer.fromJson<String?>(
        json['resolvedIntoSourceId'],
      ),
      firstSeenAt: serializer.fromJson<DateTime>(json['firstSeenAt']),
      lastSeenAt: serializer.fromJson<DateTime>(json['lastSeenAt']),
      revision: serializer.fromJson<int?>(json['revision']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'serverId': serializer.toJson<String?>(serverId),
      'collectionId': serializer.toJson<String>(collectionId),
      'host': serializer.toJson<String>(host),
      'pathKey': serializer.toJson<String>(pathKey),
      'language': serializer.toJson<String>(language),
      'lifecycle': serializer.toJson<String>(lifecycle),
      'resolvedIntoSourceId': serializer.toJson<String?>(resolvedIntoSourceId),
      'firstSeenAt': serializer.toJson<DateTime>(firstSeenAt),
      'lastSeenAt': serializer.toJson<DateTime>(lastSeenAt),
      'revision': serializer.toJson<int?>(revision),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SourceRow copyWith({
    String? id,
    Value<String?> serverId = const Value.absent(),
    String? collectionId,
    String? host,
    String? pathKey,
    String? language,
    String? lifecycle,
    Value<String?> resolvedIntoSourceId = const Value.absent(),
    DateTime? firstSeenAt,
    DateTime? lastSeenAt,
    Value<int?> revision = const Value.absent(),
    DateTime? updatedAt,
  }) => SourceRow(
    id: id ?? this.id,
    serverId: serverId.present ? serverId.value : this.serverId,
    collectionId: collectionId ?? this.collectionId,
    host: host ?? this.host,
    pathKey: pathKey ?? this.pathKey,
    language: language ?? this.language,
    lifecycle: lifecycle ?? this.lifecycle,
    resolvedIntoSourceId: resolvedIntoSourceId.present
        ? resolvedIntoSourceId.value
        : this.resolvedIntoSourceId,
    firstSeenAt: firstSeenAt ?? this.firstSeenAt,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    revision: revision.present ? revision.value : this.revision,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SourceRow copyWithCompanion(SourcesCompanion data) {
    return SourceRow(
      id: data.id.present ? data.id.value : this.id,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      collectionId: data.collectionId.present
          ? data.collectionId.value
          : this.collectionId,
      host: data.host.present ? data.host.value : this.host,
      pathKey: data.pathKey.present ? data.pathKey.value : this.pathKey,
      language: data.language.present ? data.language.value : this.language,
      lifecycle: data.lifecycle.present ? data.lifecycle.value : this.lifecycle,
      resolvedIntoSourceId: data.resolvedIntoSourceId.present
          ? data.resolvedIntoSourceId.value
          : this.resolvedIntoSourceId,
      firstSeenAt: data.firstSeenAt.present
          ? data.firstSeenAt.value
          : this.firstSeenAt,
      lastSeenAt: data.lastSeenAt.present
          ? data.lastSeenAt.value
          : this.lastSeenAt,
      revision: data.revision.present ? data.revision.value : this.revision,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SourceRow(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('collectionId: $collectionId, ')
          ..write('host: $host, ')
          ..write('pathKey: $pathKey, ')
          ..write('language: $language, ')
          ..write('lifecycle: $lifecycle, ')
          ..write('resolvedIntoSourceId: $resolvedIntoSourceId, ')
          ..write('firstSeenAt: $firstSeenAt, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('revision: $revision, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    serverId,
    collectionId,
    host,
    pathKey,
    language,
    lifecycle,
    resolvedIntoSourceId,
    firstSeenAt,
    lastSeenAt,
    revision,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SourceRow &&
          other.id == this.id &&
          other.serverId == this.serverId &&
          other.collectionId == this.collectionId &&
          other.host == this.host &&
          other.pathKey == this.pathKey &&
          other.language == this.language &&
          other.lifecycle == this.lifecycle &&
          other.resolvedIntoSourceId == this.resolvedIntoSourceId &&
          other.firstSeenAt == this.firstSeenAt &&
          other.lastSeenAt == this.lastSeenAt &&
          other.revision == this.revision &&
          other.updatedAt == this.updatedAt);
}

class SourcesCompanion extends UpdateCompanion<SourceRow> {
  final Value<String> id;
  final Value<String?> serverId;
  final Value<String> collectionId;
  final Value<String> host;
  final Value<String> pathKey;
  final Value<String> language;
  final Value<String> lifecycle;
  final Value<String?> resolvedIntoSourceId;
  final Value<DateTime> firstSeenAt;
  final Value<DateTime> lastSeenAt;
  final Value<int?> revision;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SourcesCompanion({
    this.id = const Value.absent(),
    this.serverId = const Value.absent(),
    this.collectionId = const Value.absent(),
    this.host = const Value.absent(),
    this.pathKey = const Value.absent(),
    this.language = const Value.absent(),
    this.lifecycle = const Value.absent(),
    this.resolvedIntoSourceId = const Value.absent(),
    this.firstSeenAt = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.revision = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SourcesCompanion.insert({
    required String id,
    this.serverId = const Value.absent(),
    required String collectionId,
    required String host,
    required String pathKey,
    this.language = const Value.absent(),
    this.lifecycle = const Value.absent(),
    this.resolvedIntoSourceId = const Value.absent(),
    required DateTime firstSeenAt,
    required DateTime lastSeenAt,
    this.revision = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       collectionId = Value(collectionId),
       host = Value(host),
       pathKey = Value(pathKey),
       firstSeenAt = Value(firstSeenAt),
       lastSeenAt = Value(lastSeenAt),
       updatedAt = Value(updatedAt);
  static Insertable<SourceRow> custom({
    Expression<String>? id,
    Expression<String>? serverId,
    Expression<String>? collectionId,
    Expression<String>? host,
    Expression<String>? pathKey,
    Expression<String>? language,
    Expression<String>? lifecycle,
    Expression<String>? resolvedIntoSourceId,
    Expression<DateTime>? firstSeenAt,
    Expression<DateTime>? lastSeenAt,
    Expression<int>? revision,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (serverId != null) 'server_id': serverId,
      if (collectionId != null) 'collection_id': collectionId,
      if (host != null) 'host': host,
      if (pathKey != null) 'path_key': pathKey,
      if (language != null) 'language': language,
      if (lifecycle != null) 'lifecycle': lifecycle,
      if (resolvedIntoSourceId != null)
        'resolved_into_source_id': resolvedIntoSourceId,
      if (firstSeenAt != null) 'first_seen_at': firstSeenAt,
      if (lastSeenAt != null) 'last_seen_at': lastSeenAt,
      if (revision != null) 'revision': revision,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SourcesCompanion copyWith({
    Value<String>? id,
    Value<String?>? serverId,
    Value<String>? collectionId,
    Value<String>? host,
    Value<String>? pathKey,
    Value<String>? language,
    Value<String>? lifecycle,
    Value<String?>? resolvedIntoSourceId,
    Value<DateTime>? firstSeenAt,
    Value<DateTime>? lastSeenAt,
    Value<int?>? revision,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SourcesCompanion(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      collectionId: collectionId ?? this.collectionId,
      host: host ?? this.host,
      pathKey: pathKey ?? this.pathKey,
      language: language ?? this.language,
      lifecycle: lifecycle ?? this.lifecycle,
      resolvedIntoSourceId: resolvedIntoSourceId ?? this.resolvedIntoSourceId,
      firstSeenAt: firstSeenAt ?? this.firstSeenAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      revision: revision ?? this.revision,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (collectionId.present) {
      map['collection_id'] = Variable<String>(collectionId.value);
    }
    if (host.present) {
      map['host'] = Variable<String>(host.value);
    }
    if (pathKey.present) {
      map['path_key'] = Variable<String>(pathKey.value);
    }
    if (language.present) {
      map['language'] = Variable<String>(language.value);
    }
    if (lifecycle.present) {
      map['lifecycle'] = Variable<String>(lifecycle.value);
    }
    if (resolvedIntoSourceId.present) {
      map['resolved_into_source_id'] = Variable<String>(
        resolvedIntoSourceId.value,
      );
    }
    if (firstSeenAt.present) {
      map['first_seen_at'] = Variable<DateTime>(firstSeenAt.value);
    }
    if (lastSeenAt.present) {
      map['last_seen_at'] = Variable<DateTime>(lastSeenAt.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SourcesCompanion(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('collectionId: $collectionId, ')
          ..write('host: $host, ')
          ..write('pathKey: $pathKey, ')
          ..write('language: $language, ')
          ..write('lifecycle: $lifecycle, ')
          ..write('resolvedIntoSourceId: $resolvedIntoSourceId, ')
          ..write('firstSeenAt: $firstSeenAt, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('revision: $revision, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CollectionsTable extends Collections
    with TableInfo<$CollectionsTable, CollectionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CollectionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _folderIdMeta = const VerificationMeta(
    'folderId',
  );
  @override
  late final GeneratedColumn<String> folderId = GeneratedColumn<String>(
    'folder_id',
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
    requiredDuringInsert: true,
  );
  static const VerificationMeta _detectedTitleMeta = const VerificationMeta(
    'detectedTitle',
  );
  @override
  late final GeneratedColumn<String> detectedTitle = GeneratedColumn<String>(
    'detected_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _orderingBasisMeta = const VerificationMeta(
    'orderingBasis',
  );
  @override
  late final GeneratedColumn<String> orderingBasis = GeneratedColumn<String>(
    'ordering_basis',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lifecycleMeta = const VerificationMeta(
    'lifecycle',
  );
  @override
  late final GeneratedColumn<String> lifecycle = GeneratedColumn<String>(
    'lifecycle',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('active'),
  );
  static const VerificationMeta _preferredSourceIdMeta = const VerificationMeta(
    'preferredSourceId',
  );
  @override
  late final GeneratedColumn<String> preferredSourceId =
      GeneratedColumn<String>(
        'preferred_source_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _sortKeyMeta = const VerificationMeta(
    'sortKey',
  );
  @override
  late final GeneratedColumn<int> sortKey = GeneratedColumn<int>(
    'sort_key',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
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
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    serverId,
    folderId,
    name,
    detectedTitle,
    orderingBasis,
    lifecycle,
    preferredSourceId,
    sortKey,
    revision,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'collections';
  @override
  VerificationContext validateIntegrity(
    Insertable<CollectionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    }
    if (data.containsKey('folder_id')) {
      context.handle(
        _folderIdMeta,
        folderId.isAcceptableOrUnknown(data['folder_id']!, _folderIdMeta),
      );
    } else if (isInserting) {
      context.missing(_folderIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('detected_title')) {
      context.handle(
        _detectedTitleMeta,
        detectedTitle.isAcceptableOrUnknown(
          data['detected_title']!,
          _detectedTitleMeta,
        ),
      );
    }
    if (data.containsKey('ordering_basis')) {
      context.handle(
        _orderingBasisMeta,
        orderingBasis.isAcceptableOrUnknown(
          data['ordering_basis']!,
          _orderingBasisMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_orderingBasisMeta);
    }
    if (data.containsKey('lifecycle')) {
      context.handle(
        _lifecycleMeta,
        lifecycle.isAcceptableOrUnknown(data['lifecycle']!, _lifecycleMeta),
      );
    }
    if (data.containsKey('preferred_source_id')) {
      context.handle(
        _preferredSourceIdMeta,
        preferredSourceId.isAcceptableOrUnknown(
          data['preferred_source_id']!,
          _preferredSourceIdMeta,
        ),
      );
    }
    if (data.containsKey('sort_key')) {
      context.handle(
        _sortKeyMeta,
        sortKey.isAcceptableOrUnknown(data['sort_key']!, _sortKeyMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CollectionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CollectionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_id'],
      ),
      folderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}folder_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      detectedTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}detected_title'],
      )!,
      orderingBasis: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ordering_basis'],
      )!,
      lifecycle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lifecycle'],
      )!,
      preferredSourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}preferred_source_id'],
      ),
      sortKey: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_key'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CollectionsTable createAlias(String alias) {
    return $CollectionsTable(attachedDatabase, alias);
  }
}

class CollectionRow extends DataClass implements Insertable<CollectionRow> {
  final String id;
  final String? serverId;
  final String folderId;
  final String name;
  final String detectedTitle;
  final String orderingBasis;
  final String lifecycle;
  final String? preferredSourceId;
  final int sortKey;
  final int? revision;
  final DateTime updatedAt;
  const CollectionRow({
    required this.id,
    this.serverId,
    required this.folderId,
    required this.name,
    required this.detectedTitle,
    required this.orderingBasis,
    required this.lifecycle,
    this.preferredSourceId,
    required this.sortKey,
    this.revision,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<String>(serverId);
    }
    map['folder_id'] = Variable<String>(folderId);
    map['name'] = Variable<String>(name);
    map['detected_title'] = Variable<String>(detectedTitle);
    map['ordering_basis'] = Variable<String>(orderingBasis);
    map['lifecycle'] = Variable<String>(lifecycle);
    if (!nullToAbsent || preferredSourceId != null) {
      map['preferred_source_id'] = Variable<String>(preferredSourceId);
    }
    map['sort_key'] = Variable<int>(sortKey);
    if (!nullToAbsent || revision != null) {
      map['revision'] = Variable<int>(revision);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CollectionsCompanion toCompanion(bool nullToAbsent) {
    return CollectionsCompanion(
      id: Value(id),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      folderId: Value(folderId),
      name: Value(name),
      detectedTitle: Value(detectedTitle),
      orderingBasis: Value(orderingBasis),
      lifecycle: Value(lifecycle),
      preferredSourceId: preferredSourceId == null && nullToAbsent
          ? const Value.absent()
          : Value(preferredSourceId),
      sortKey: Value(sortKey),
      revision: revision == null && nullToAbsent
          ? const Value.absent()
          : Value(revision),
      updatedAt: Value(updatedAt),
    );
  }

  factory CollectionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CollectionRow(
      id: serializer.fromJson<String>(json['id']),
      serverId: serializer.fromJson<String?>(json['serverId']),
      folderId: serializer.fromJson<String>(json['folderId']),
      name: serializer.fromJson<String>(json['name']),
      detectedTitle: serializer.fromJson<String>(json['detectedTitle']),
      orderingBasis: serializer.fromJson<String>(json['orderingBasis']),
      lifecycle: serializer.fromJson<String>(json['lifecycle']),
      preferredSourceId: serializer.fromJson<String?>(
        json['preferredSourceId'],
      ),
      sortKey: serializer.fromJson<int>(json['sortKey']),
      revision: serializer.fromJson<int?>(json['revision']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'serverId': serializer.toJson<String?>(serverId),
      'folderId': serializer.toJson<String>(folderId),
      'name': serializer.toJson<String>(name),
      'detectedTitle': serializer.toJson<String>(detectedTitle),
      'orderingBasis': serializer.toJson<String>(orderingBasis),
      'lifecycle': serializer.toJson<String>(lifecycle),
      'preferredSourceId': serializer.toJson<String?>(preferredSourceId),
      'sortKey': serializer.toJson<int>(sortKey),
      'revision': serializer.toJson<int?>(revision),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CollectionRow copyWith({
    String? id,
    Value<String?> serverId = const Value.absent(),
    String? folderId,
    String? name,
    String? detectedTitle,
    String? orderingBasis,
    String? lifecycle,
    Value<String?> preferredSourceId = const Value.absent(),
    int? sortKey,
    Value<int?> revision = const Value.absent(),
    DateTime? updatedAt,
  }) => CollectionRow(
    id: id ?? this.id,
    serverId: serverId.present ? serverId.value : this.serverId,
    folderId: folderId ?? this.folderId,
    name: name ?? this.name,
    detectedTitle: detectedTitle ?? this.detectedTitle,
    orderingBasis: orderingBasis ?? this.orderingBasis,
    lifecycle: lifecycle ?? this.lifecycle,
    preferredSourceId: preferredSourceId.present
        ? preferredSourceId.value
        : this.preferredSourceId,
    sortKey: sortKey ?? this.sortKey,
    revision: revision.present ? revision.value : this.revision,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CollectionRow copyWithCompanion(CollectionsCompanion data) {
    return CollectionRow(
      id: data.id.present ? data.id.value : this.id,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      folderId: data.folderId.present ? data.folderId.value : this.folderId,
      name: data.name.present ? data.name.value : this.name,
      detectedTitle: data.detectedTitle.present
          ? data.detectedTitle.value
          : this.detectedTitle,
      orderingBasis: data.orderingBasis.present
          ? data.orderingBasis.value
          : this.orderingBasis,
      lifecycle: data.lifecycle.present ? data.lifecycle.value : this.lifecycle,
      preferredSourceId: data.preferredSourceId.present
          ? data.preferredSourceId.value
          : this.preferredSourceId,
      sortKey: data.sortKey.present ? data.sortKey.value : this.sortKey,
      revision: data.revision.present ? data.revision.value : this.revision,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CollectionRow(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('folderId: $folderId, ')
          ..write('name: $name, ')
          ..write('detectedTitle: $detectedTitle, ')
          ..write('orderingBasis: $orderingBasis, ')
          ..write('lifecycle: $lifecycle, ')
          ..write('preferredSourceId: $preferredSourceId, ')
          ..write('sortKey: $sortKey, ')
          ..write('revision: $revision, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    serverId,
    folderId,
    name,
    detectedTitle,
    orderingBasis,
    lifecycle,
    preferredSourceId,
    sortKey,
    revision,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CollectionRow &&
          other.id == this.id &&
          other.serverId == this.serverId &&
          other.folderId == this.folderId &&
          other.name == this.name &&
          other.detectedTitle == this.detectedTitle &&
          other.orderingBasis == this.orderingBasis &&
          other.lifecycle == this.lifecycle &&
          other.preferredSourceId == this.preferredSourceId &&
          other.sortKey == this.sortKey &&
          other.revision == this.revision &&
          other.updatedAt == this.updatedAt);
}

class CollectionsCompanion extends UpdateCompanion<CollectionRow> {
  final Value<String> id;
  final Value<String?> serverId;
  final Value<String> folderId;
  final Value<String> name;
  final Value<String> detectedTitle;
  final Value<String> orderingBasis;
  final Value<String> lifecycle;
  final Value<String?> preferredSourceId;
  final Value<int> sortKey;
  final Value<int?> revision;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CollectionsCompanion({
    this.id = const Value.absent(),
    this.serverId = const Value.absent(),
    this.folderId = const Value.absent(),
    this.name = const Value.absent(),
    this.detectedTitle = const Value.absent(),
    this.orderingBasis = const Value.absent(),
    this.lifecycle = const Value.absent(),
    this.preferredSourceId = const Value.absent(),
    this.sortKey = const Value.absent(),
    this.revision = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CollectionsCompanion.insert({
    required String id,
    this.serverId = const Value.absent(),
    required String folderId,
    required String name,
    this.detectedTitle = const Value.absent(),
    required String orderingBasis,
    this.lifecycle = const Value.absent(),
    this.preferredSourceId = const Value.absent(),
    this.sortKey = const Value.absent(),
    this.revision = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       folderId = Value(folderId),
       name = Value(name),
       orderingBasis = Value(orderingBasis),
       updatedAt = Value(updatedAt);
  static Insertable<CollectionRow> custom({
    Expression<String>? id,
    Expression<String>? serverId,
    Expression<String>? folderId,
    Expression<String>? name,
    Expression<String>? detectedTitle,
    Expression<String>? orderingBasis,
    Expression<String>? lifecycle,
    Expression<String>? preferredSourceId,
    Expression<int>? sortKey,
    Expression<int>? revision,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (serverId != null) 'server_id': serverId,
      if (folderId != null) 'folder_id': folderId,
      if (name != null) 'name': name,
      if (detectedTitle != null) 'detected_title': detectedTitle,
      if (orderingBasis != null) 'ordering_basis': orderingBasis,
      if (lifecycle != null) 'lifecycle': lifecycle,
      if (preferredSourceId != null) 'preferred_source_id': preferredSourceId,
      if (sortKey != null) 'sort_key': sortKey,
      if (revision != null) 'revision': revision,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CollectionsCompanion copyWith({
    Value<String>? id,
    Value<String?>? serverId,
    Value<String>? folderId,
    Value<String>? name,
    Value<String>? detectedTitle,
    Value<String>? orderingBasis,
    Value<String>? lifecycle,
    Value<String?>? preferredSourceId,
    Value<int>? sortKey,
    Value<int?>? revision,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CollectionsCompanion(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      folderId: folderId ?? this.folderId,
      name: name ?? this.name,
      detectedTitle: detectedTitle ?? this.detectedTitle,
      orderingBasis: orderingBasis ?? this.orderingBasis,
      lifecycle: lifecycle ?? this.lifecycle,
      preferredSourceId: preferredSourceId ?? this.preferredSourceId,
      sortKey: sortKey ?? this.sortKey,
      revision: revision ?? this.revision,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (folderId.present) {
      map['folder_id'] = Variable<String>(folderId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (detectedTitle.present) {
      map['detected_title'] = Variable<String>(detectedTitle.value);
    }
    if (orderingBasis.present) {
      map['ordering_basis'] = Variable<String>(orderingBasis.value);
    }
    if (lifecycle.present) {
      map['lifecycle'] = Variable<String>(lifecycle.value);
    }
    if (preferredSourceId.present) {
      map['preferred_source_id'] = Variable<String>(preferredSourceId.value);
    }
    if (sortKey.present) {
      map['sort_key'] = Variable<int>(sortKey.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CollectionsCompanion(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('folderId: $folderId, ')
          ..write('name: $name, ')
          ..write('detectedTitle: $detectedTitle, ')
          ..write('orderingBasis: $orderingBasis, ')
          ..write('lifecycle: $lifecycle, ')
          ..write('preferredSourceId: $preferredSourceId, ')
          ..write('sortKey: $sortKey, ')
          ..write('revision: $revision, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EntriesTable extends Entries with TableInfo<$EntriesTable, EntryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _collectionIdMeta = const VerificationMeta(
    'collectionId',
  );
  @override
  late final GeneratedColumn<String> collectionId = GeneratedColumn<String>(
    'collection_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _folderIdMeta = const VerificationMeta(
    'folderId',
  );
  @override
  late final GeneratedColumn<String> folderId = GeneratedColumn<String>(
    'folder_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ordinalMeta = const VerificationMeta(
    'ordinal',
  );
  @override
  late final GeneratedColumn<double> ordinal = GeneratedColumn<double>(
    'ordinal',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _placementMeta = const VerificationMeta(
    'placement',
  );
  @override
  late final GeneratedColumn<String> placement = GeneratedColumn<String>(
    'placement',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sortKeyMeta = const VerificationMeta(
    'sortKey',
  );
  @override
  late final GeneratedColumn<int> sortKey = GeneratedColumn<int>(
    'sort_key',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
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
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    serverId,
    collectionId,
    folderId,
    ordinal,
    placement,
    title,
    sortKey,
    revision,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<EntryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    }
    if (data.containsKey('collection_id')) {
      context.handle(
        _collectionIdMeta,
        collectionId.isAcceptableOrUnknown(
          data['collection_id']!,
          _collectionIdMeta,
        ),
      );
    }
    if (data.containsKey('folder_id')) {
      context.handle(
        _folderIdMeta,
        folderId.isAcceptableOrUnknown(data['folder_id']!, _folderIdMeta),
      );
    }
    if (data.containsKey('ordinal')) {
      context.handle(
        _ordinalMeta,
        ordinal.isAcceptableOrUnknown(data['ordinal']!, _ordinalMeta),
      );
    }
    if (data.containsKey('placement')) {
      context.handle(
        _placementMeta,
        placement.isAcceptableOrUnknown(data['placement']!, _placementMeta),
      );
    } else if (isInserting) {
      context.missing(_placementMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('sort_key')) {
      context.handle(
        _sortKeyMeta,
        sortKey.isAcceptableOrUnknown(data['sort_key']!, _sortKeyMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EntryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EntryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_id'],
      ),
      collectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}collection_id'],
      ),
      folderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}folder_id'],
      ),
      ordinal: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}ordinal'],
      ),
      placement: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}placement'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      sortKey: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_key'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $EntriesTable createAlias(String alias) {
    return $EntriesTable(attachedDatabase, alias);
  }
}

class EntryRow extends DataClass implements Insertable<EntryRow> {
  final String id;
  final String? serverId;
  final String? collectionId;
  final String? folderId;
  final double? ordinal;
  final String placement;
  final String title;
  final int sortKey;
  final int? revision;
  final DateTime updatedAt;
  const EntryRow({
    required this.id,
    this.serverId,
    this.collectionId,
    this.folderId,
    this.ordinal,
    required this.placement,
    required this.title,
    required this.sortKey,
    this.revision,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<String>(serverId);
    }
    if (!nullToAbsent || collectionId != null) {
      map['collection_id'] = Variable<String>(collectionId);
    }
    if (!nullToAbsent || folderId != null) {
      map['folder_id'] = Variable<String>(folderId);
    }
    if (!nullToAbsent || ordinal != null) {
      map['ordinal'] = Variable<double>(ordinal);
    }
    map['placement'] = Variable<String>(placement);
    map['title'] = Variable<String>(title);
    map['sort_key'] = Variable<int>(sortKey);
    if (!nullToAbsent || revision != null) {
      map['revision'] = Variable<int>(revision);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  EntriesCompanion toCompanion(bool nullToAbsent) {
    return EntriesCompanion(
      id: Value(id),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      collectionId: collectionId == null && nullToAbsent
          ? const Value.absent()
          : Value(collectionId),
      folderId: folderId == null && nullToAbsent
          ? const Value.absent()
          : Value(folderId),
      ordinal: ordinal == null && nullToAbsent
          ? const Value.absent()
          : Value(ordinal),
      placement: Value(placement),
      title: Value(title),
      sortKey: Value(sortKey),
      revision: revision == null && nullToAbsent
          ? const Value.absent()
          : Value(revision),
      updatedAt: Value(updatedAt),
    );
  }

  factory EntryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EntryRow(
      id: serializer.fromJson<String>(json['id']),
      serverId: serializer.fromJson<String?>(json['serverId']),
      collectionId: serializer.fromJson<String?>(json['collectionId']),
      folderId: serializer.fromJson<String?>(json['folderId']),
      ordinal: serializer.fromJson<double?>(json['ordinal']),
      placement: serializer.fromJson<String>(json['placement']),
      title: serializer.fromJson<String>(json['title']),
      sortKey: serializer.fromJson<int>(json['sortKey']),
      revision: serializer.fromJson<int?>(json['revision']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'serverId': serializer.toJson<String?>(serverId),
      'collectionId': serializer.toJson<String?>(collectionId),
      'folderId': serializer.toJson<String?>(folderId),
      'ordinal': serializer.toJson<double?>(ordinal),
      'placement': serializer.toJson<String>(placement),
      'title': serializer.toJson<String>(title),
      'sortKey': serializer.toJson<int>(sortKey),
      'revision': serializer.toJson<int?>(revision),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  EntryRow copyWith({
    String? id,
    Value<String?> serverId = const Value.absent(),
    Value<String?> collectionId = const Value.absent(),
    Value<String?> folderId = const Value.absent(),
    Value<double?> ordinal = const Value.absent(),
    String? placement,
    String? title,
    int? sortKey,
    Value<int?> revision = const Value.absent(),
    DateTime? updatedAt,
  }) => EntryRow(
    id: id ?? this.id,
    serverId: serverId.present ? serverId.value : this.serverId,
    collectionId: collectionId.present ? collectionId.value : this.collectionId,
    folderId: folderId.present ? folderId.value : this.folderId,
    ordinal: ordinal.present ? ordinal.value : this.ordinal,
    placement: placement ?? this.placement,
    title: title ?? this.title,
    sortKey: sortKey ?? this.sortKey,
    revision: revision.present ? revision.value : this.revision,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  EntryRow copyWithCompanion(EntriesCompanion data) {
    return EntryRow(
      id: data.id.present ? data.id.value : this.id,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      collectionId: data.collectionId.present
          ? data.collectionId.value
          : this.collectionId,
      folderId: data.folderId.present ? data.folderId.value : this.folderId,
      ordinal: data.ordinal.present ? data.ordinal.value : this.ordinal,
      placement: data.placement.present ? data.placement.value : this.placement,
      title: data.title.present ? data.title.value : this.title,
      sortKey: data.sortKey.present ? data.sortKey.value : this.sortKey,
      revision: data.revision.present ? data.revision.value : this.revision,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EntryRow(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('collectionId: $collectionId, ')
          ..write('folderId: $folderId, ')
          ..write('ordinal: $ordinal, ')
          ..write('placement: $placement, ')
          ..write('title: $title, ')
          ..write('sortKey: $sortKey, ')
          ..write('revision: $revision, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    serverId,
    collectionId,
    folderId,
    ordinal,
    placement,
    title,
    sortKey,
    revision,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EntryRow &&
          other.id == this.id &&
          other.serverId == this.serverId &&
          other.collectionId == this.collectionId &&
          other.folderId == this.folderId &&
          other.ordinal == this.ordinal &&
          other.placement == this.placement &&
          other.title == this.title &&
          other.sortKey == this.sortKey &&
          other.revision == this.revision &&
          other.updatedAt == this.updatedAt);
}

class EntriesCompanion extends UpdateCompanion<EntryRow> {
  final Value<String> id;
  final Value<String?> serverId;
  final Value<String?> collectionId;
  final Value<String?> folderId;
  final Value<double?> ordinal;
  final Value<String> placement;
  final Value<String> title;
  final Value<int> sortKey;
  final Value<int?> revision;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const EntriesCompanion({
    this.id = const Value.absent(),
    this.serverId = const Value.absent(),
    this.collectionId = const Value.absent(),
    this.folderId = const Value.absent(),
    this.ordinal = const Value.absent(),
    this.placement = const Value.absent(),
    this.title = const Value.absent(),
    this.sortKey = const Value.absent(),
    this.revision = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EntriesCompanion.insert({
    required String id,
    this.serverId = const Value.absent(),
    this.collectionId = const Value.absent(),
    this.folderId = const Value.absent(),
    this.ordinal = const Value.absent(),
    required String placement,
    this.title = const Value.absent(),
    this.sortKey = const Value.absent(),
    this.revision = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       placement = Value(placement),
       updatedAt = Value(updatedAt);
  static Insertable<EntryRow> custom({
    Expression<String>? id,
    Expression<String>? serverId,
    Expression<String>? collectionId,
    Expression<String>? folderId,
    Expression<double>? ordinal,
    Expression<String>? placement,
    Expression<String>? title,
    Expression<int>? sortKey,
    Expression<int>? revision,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (serverId != null) 'server_id': serverId,
      if (collectionId != null) 'collection_id': collectionId,
      if (folderId != null) 'folder_id': folderId,
      if (ordinal != null) 'ordinal': ordinal,
      if (placement != null) 'placement': placement,
      if (title != null) 'title': title,
      if (sortKey != null) 'sort_key': sortKey,
      if (revision != null) 'revision': revision,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EntriesCompanion copyWith({
    Value<String>? id,
    Value<String?>? serverId,
    Value<String?>? collectionId,
    Value<String?>? folderId,
    Value<double?>? ordinal,
    Value<String>? placement,
    Value<String>? title,
    Value<int>? sortKey,
    Value<int?>? revision,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return EntriesCompanion(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      collectionId: collectionId ?? this.collectionId,
      folderId: folderId ?? this.folderId,
      ordinal: ordinal ?? this.ordinal,
      placement: placement ?? this.placement,
      title: title ?? this.title,
      sortKey: sortKey ?? this.sortKey,
      revision: revision ?? this.revision,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (collectionId.present) {
      map['collection_id'] = Variable<String>(collectionId.value);
    }
    if (folderId.present) {
      map['folder_id'] = Variable<String>(folderId.value);
    }
    if (ordinal.present) {
      map['ordinal'] = Variable<double>(ordinal.value);
    }
    if (placement.present) {
      map['placement'] = Variable<String>(placement.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (sortKey.present) {
      map['sort_key'] = Variable<int>(sortKey.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EntriesCompanion(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('collectionId: $collectionId, ')
          ..write('folderId: $folderId, ')
          ..write('ordinal: $ordinal, ')
          ..write('placement: $placement, ')
          ..write('title: $title, ')
          ..write('sortKey: $sortKey, ')
          ..write('revision: $revision, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocationsTable extends Locations
    with TableInfo<$LocationsTable, LocationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _entryIdMeta = const VerificationMeta(
    'entryId',
  );
  @override
  late final GeneratedColumn<String> entryId = GeneratedColumn<String>(
    'entry_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _urlKeyMeta = const VerificationMeta('urlKey');
  @override
  late final GeneratedColumn<String> urlKey = GeneratedColumn<String>(
    'url_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _sourceLabelMeta = const VerificationMeta(
    'sourceLabel',
  );
  @override
  late final GeneratedColumn<String> sourceLabel = GeneratedColumn<String>(
    'source_label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sourceNumberMeta = const VerificationMeta(
    'sourceNumber',
  );
  @override
  late final GeneratedColumn<double> sourceNumber = GeneratedColumn<double>(
    'source_number',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _publishedAtMeta = const VerificationMeta(
    'publishedAt',
  );
  @override
  late final GeneratedColumn<DateTime> publishedAt = GeneratedColumn<DateTime>(
    'published_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _discoveredAtMeta = const VerificationMeta(
    'discoveredAt',
  );
  @override
  late final GeneratedColumn<DateTime> discoveredAt = GeneratedColumn<DateTime>(
    'discovered_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _discoveryBasisMeta = const VerificationMeta(
    'discoveryBasis',
  );
  @override
  late final GeneratedColumn<String> discoveryBasis = GeneratedColumn<String>(
    'discovery_basis',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _lifecycleMeta = const VerificationMeta(
    'lifecycle',
  );
  @override
  late final GeneratedColumn<String> lifecycle = GeneratedColumn<String>(
    'lifecycle',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('active'),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
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
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    serverId,
    entryId,
    sourceId,
    url,
    urlKey,
    sourceLabel,
    sourceNumber,
    publishedAt,
    discoveredAt,
    discoveryBasis,
    lifecycle,
    revision,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'locations';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    }
    if (data.containsKey('entry_id')) {
      context.handle(
        _entryIdMeta,
        entryId.isAcceptableOrUnknown(data['entry_id']!, _entryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entryIdMeta);
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('url_key')) {
      context.handle(
        _urlKeyMeta,
        urlKey.isAcceptableOrUnknown(data['url_key']!, _urlKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_urlKeyMeta);
    }
    if (data.containsKey('source_label')) {
      context.handle(
        _sourceLabelMeta,
        sourceLabel.isAcceptableOrUnknown(
          data['source_label']!,
          _sourceLabelMeta,
        ),
      );
    }
    if (data.containsKey('source_number')) {
      context.handle(
        _sourceNumberMeta,
        sourceNumber.isAcceptableOrUnknown(
          data['source_number']!,
          _sourceNumberMeta,
        ),
      );
    }
    if (data.containsKey('published_at')) {
      context.handle(
        _publishedAtMeta,
        publishedAt.isAcceptableOrUnknown(
          data['published_at']!,
          _publishedAtMeta,
        ),
      );
    }
    if (data.containsKey('discovered_at')) {
      context.handle(
        _discoveredAtMeta,
        discoveredAt.isAcceptableOrUnknown(
          data['discovered_at']!,
          _discoveredAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_discoveredAtMeta);
    }
    if (data.containsKey('discovery_basis')) {
      context.handle(
        _discoveryBasisMeta,
        discoveryBasis.isAcceptableOrUnknown(
          data['discovery_basis']!,
          _discoveryBasisMeta,
        ),
      );
    }
    if (data.containsKey('lifecycle')) {
      context.handle(
        _lifecycleMeta,
        lifecycle.isAcceptableOrUnknown(data['lifecycle']!, _lifecycleMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocationRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_id'],
      ),
      entryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entry_id'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      ),
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      urlKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url_key'],
      )!,
      sourceLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_label'],
      )!,
      sourceNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}source_number'],
      ),
      publishedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}published_at'],
      ),
      discoveredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}discovered_at'],
      )!,
      discoveryBasis: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}discovery_basis'],
      )!,
      lifecycle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lifecycle'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $LocationsTable createAlias(String alias) {
    return $LocationsTable(attachedDatabase, alias);
  }
}

class LocationRow extends DataClass implements Insertable<LocationRow> {
  final String id;
  final String? serverId;
  final String entryId;
  final String? sourceId;
  final String url;
  final String urlKey;
  final String sourceLabel;
  final double? sourceNumber;

  /// The date the source said this page was published, when it said one.
  ///
  /// Evidence about a page, exactly like [sourceLabel] and [sourceNumber]
  /// beside it, so it lives on the Location rather than the Entry: two Sources
  /// of one Collection can publish the same Entry on different days, and the
  /// Entry has no one answer.
  ///
  /// **Local-only, deliberately.** It is absent from `contracts/evidence.yaml`
  /// and from the change feed, so nothing writes it to the outbox and nothing
  /// reads it from a pull. The contract is frozen at Gate B and changes only
  /// through `contracts/README.md`'s protocol; until it does, this is a fact
  /// this device read for itself. Null is ordinary and permanent for a page
  /// nobody has downloaded, and for every page whose site prints no date.
  final DateTime? publishedAt;
  final DateTime discoveredAt;
  final String discoveryBasis;
  final String lifecycle;
  final int? revision;
  final DateTime updatedAt;
  const LocationRow({
    required this.id,
    this.serverId,
    required this.entryId,
    this.sourceId,
    required this.url,
    required this.urlKey,
    required this.sourceLabel,
    this.sourceNumber,
    this.publishedAt,
    required this.discoveredAt,
    required this.discoveryBasis,
    required this.lifecycle,
    this.revision,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<String>(serverId);
    }
    map['entry_id'] = Variable<String>(entryId);
    if (!nullToAbsent || sourceId != null) {
      map['source_id'] = Variable<String>(sourceId);
    }
    map['url'] = Variable<String>(url);
    map['url_key'] = Variable<String>(urlKey);
    map['source_label'] = Variable<String>(sourceLabel);
    if (!nullToAbsent || sourceNumber != null) {
      map['source_number'] = Variable<double>(sourceNumber);
    }
    if (!nullToAbsent || publishedAt != null) {
      map['published_at'] = Variable<DateTime>(publishedAt);
    }
    map['discovered_at'] = Variable<DateTime>(discoveredAt);
    map['discovery_basis'] = Variable<String>(discoveryBasis);
    map['lifecycle'] = Variable<String>(lifecycle);
    if (!nullToAbsent || revision != null) {
      map['revision'] = Variable<int>(revision);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  LocationsCompanion toCompanion(bool nullToAbsent) {
    return LocationsCompanion(
      id: Value(id),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      entryId: Value(entryId),
      sourceId: sourceId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceId),
      url: Value(url),
      urlKey: Value(urlKey),
      sourceLabel: Value(sourceLabel),
      sourceNumber: sourceNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceNumber),
      publishedAt: publishedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(publishedAt),
      discoveredAt: Value(discoveredAt),
      discoveryBasis: Value(discoveryBasis),
      lifecycle: Value(lifecycle),
      revision: revision == null && nullToAbsent
          ? const Value.absent()
          : Value(revision),
      updatedAt: Value(updatedAt),
    );
  }

  factory LocationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocationRow(
      id: serializer.fromJson<String>(json['id']),
      serverId: serializer.fromJson<String?>(json['serverId']),
      entryId: serializer.fromJson<String>(json['entryId']),
      sourceId: serializer.fromJson<String?>(json['sourceId']),
      url: serializer.fromJson<String>(json['url']),
      urlKey: serializer.fromJson<String>(json['urlKey']),
      sourceLabel: serializer.fromJson<String>(json['sourceLabel']),
      sourceNumber: serializer.fromJson<double?>(json['sourceNumber']),
      publishedAt: serializer.fromJson<DateTime?>(json['publishedAt']),
      discoveredAt: serializer.fromJson<DateTime>(json['discoveredAt']),
      discoveryBasis: serializer.fromJson<String>(json['discoveryBasis']),
      lifecycle: serializer.fromJson<String>(json['lifecycle']),
      revision: serializer.fromJson<int?>(json['revision']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'serverId': serializer.toJson<String?>(serverId),
      'entryId': serializer.toJson<String>(entryId),
      'sourceId': serializer.toJson<String?>(sourceId),
      'url': serializer.toJson<String>(url),
      'urlKey': serializer.toJson<String>(urlKey),
      'sourceLabel': serializer.toJson<String>(sourceLabel),
      'sourceNumber': serializer.toJson<double?>(sourceNumber),
      'publishedAt': serializer.toJson<DateTime?>(publishedAt),
      'discoveredAt': serializer.toJson<DateTime>(discoveredAt),
      'discoveryBasis': serializer.toJson<String>(discoveryBasis),
      'lifecycle': serializer.toJson<String>(lifecycle),
      'revision': serializer.toJson<int?>(revision),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  LocationRow copyWith({
    String? id,
    Value<String?> serverId = const Value.absent(),
    String? entryId,
    Value<String?> sourceId = const Value.absent(),
    String? url,
    String? urlKey,
    String? sourceLabel,
    Value<double?> sourceNumber = const Value.absent(),
    Value<DateTime?> publishedAt = const Value.absent(),
    DateTime? discoveredAt,
    String? discoveryBasis,
    String? lifecycle,
    Value<int?> revision = const Value.absent(),
    DateTime? updatedAt,
  }) => LocationRow(
    id: id ?? this.id,
    serverId: serverId.present ? serverId.value : this.serverId,
    entryId: entryId ?? this.entryId,
    sourceId: sourceId.present ? sourceId.value : this.sourceId,
    url: url ?? this.url,
    urlKey: urlKey ?? this.urlKey,
    sourceLabel: sourceLabel ?? this.sourceLabel,
    sourceNumber: sourceNumber.present ? sourceNumber.value : this.sourceNumber,
    publishedAt: publishedAt.present ? publishedAt.value : this.publishedAt,
    discoveredAt: discoveredAt ?? this.discoveredAt,
    discoveryBasis: discoveryBasis ?? this.discoveryBasis,
    lifecycle: lifecycle ?? this.lifecycle,
    revision: revision.present ? revision.value : this.revision,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  LocationRow copyWithCompanion(LocationsCompanion data) {
    return LocationRow(
      id: data.id.present ? data.id.value : this.id,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      entryId: data.entryId.present ? data.entryId.value : this.entryId,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      url: data.url.present ? data.url.value : this.url,
      urlKey: data.urlKey.present ? data.urlKey.value : this.urlKey,
      sourceLabel: data.sourceLabel.present
          ? data.sourceLabel.value
          : this.sourceLabel,
      sourceNumber: data.sourceNumber.present
          ? data.sourceNumber.value
          : this.sourceNumber,
      publishedAt: data.publishedAt.present
          ? data.publishedAt.value
          : this.publishedAt,
      discoveredAt: data.discoveredAt.present
          ? data.discoveredAt.value
          : this.discoveredAt,
      discoveryBasis: data.discoveryBasis.present
          ? data.discoveryBasis.value
          : this.discoveryBasis,
      lifecycle: data.lifecycle.present ? data.lifecycle.value : this.lifecycle,
      revision: data.revision.present ? data.revision.value : this.revision,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocationRow(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('entryId: $entryId, ')
          ..write('sourceId: $sourceId, ')
          ..write('url: $url, ')
          ..write('urlKey: $urlKey, ')
          ..write('sourceLabel: $sourceLabel, ')
          ..write('sourceNumber: $sourceNumber, ')
          ..write('publishedAt: $publishedAt, ')
          ..write('discoveredAt: $discoveredAt, ')
          ..write('discoveryBasis: $discoveryBasis, ')
          ..write('lifecycle: $lifecycle, ')
          ..write('revision: $revision, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    serverId,
    entryId,
    sourceId,
    url,
    urlKey,
    sourceLabel,
    sourceNumber,
    publishedAt,
    discoveredAt,
    discoveryBasis,
    lifecycle,
    revision,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocationRow &&
          other.id == this.id &&
          other.serverId == this.serverId &&
          other.entryId == this.entryId &&
          other.sourceId == this.sourceId &&
          other.url == this.url &&
          other.urlKey == this.urlKey &&
          other.sourceLabel == this.sourceLabel &&
          other.sourceNumber == this.sourceNumber &&
          other.publishedAt == this.publishedAt &&
          other.discoveredAt == this.discoveredAt &&
          other.discoveryBasis == this.discoveryBasis &&
          other.lifecycle == this.lifecycle &&
          other.revision == this.revision &&
          other.updatedAt == this.updatedAt);
}

class LocationsCompanion extends UpdateCompanion<LocationRow> {
  final Value<String> id;
  final Value<String?> serverId;
  final Value<String> entryId;
  final Value<String?> sourceId;
  final Value<String> url;
  final Value<String> urlKey;
  final Value<String> sourceLabel;
  final Value<double?> sourceNumber;
  final Value<DateTime?> publishedAt;
  final Value<DateTime> discoveredAt;
  final Value<String> discoveryBasis;
  final Value<String> lifecycle;
  final Value<int?> revision;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const LocationsCompanion({
    this.id = const Value.absent(),
    this.serverId = const Value.absent(),
    this.entryId = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.url = const Value.absent(),
    this.urlKey = const Value.absent(),
    this.sourceLabel = const Value.absent(),
    this.sourceNumber = const Value.absent(),
    this.publishedAt = const Value.absent(),
    this.discoveredAt = const Value.absent(),
    this.discoveryBasis = const Value.absent(),
    this.lifecycle = const Value.absent(),
    this.revision = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocationsCompanion.insert({
    required String id,
    this.serverId = const Value.absent(),
    required String entryId,
    this.sourceId = const Value.absent(),
    required String url,
    required String urlKey,
    this.sourceLabel = const Value.absent(),
    this.sourceNumber = const Value.absent(),
    this.publishedAt = const Value.absent(),
    required DateTime discoveredAt,
    this.discoveryBasis = const Value.absent(),
    this.lifecycle = const Value.absent(),
    this.revision = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       entryId = Value(entryId),
       url = Value(url),
       urlKey = Value(urlKey),
       discoveredAt = Value(discoveredAt),
       updatedAt = Value(updatedAt);
  static Insertable<LocationRow> custom({
    Expression<String>? id,
    Expression<String>? serverId,
    Expression<String>? entryId,
    Expression<String>? sourceId,
    Expression<String>? url,
    Expression<String>? urlKey,
    Expression<String>? sourceLabel,
    Expression<double>? sourceNumber,
    Expression<DateTime>? publishedAt,
    Expression<DateTime>? discoveredAt,
    Expression<String>? discoveryBasis,
    Expression<String>? lifecycle,
    Expression<int>? revision,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (serverId != null) 'server_id': serverId,
      if (entryId != null) 'entry_id': entryId,
      if (sourceId != null) 'source_id': sourceId,
      if (url != null) 'url': url,
      if (urlKey != null) 'url_key': urlKey,
      if (sourceLabel != null) 'source_label': sourceLabel,
      if (sourceNumber != null) 'source_number': sourceNumber,
      if (publishedAt != null) 'published_at': publishedAt,
      if (discoveredAt != null) 'discovered_at': discoveredAt,
      if (discoveryBasis != null) 'discovery_basis': discoveryBasis,
      if (lifecycle != null) 'lifecycle': lifecycle,
      if (revision != null) 'revision': revision,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocationsCompanion copyWith({
    Value<String>? id,
    Value<String?>? serverId,
    Value<String>? entryId,
    Value<String?>? sourceId,
    Value<String>? url,
    Value<String>? urlKey,
    Value<String>? sourceLabel,
    Value<double?>? sourceNumber,
    Value<DateTime?>? publishedAt,
    Value<DateTime>? discoveredAt,
    Value<String>? discoveryBasis,
    Value<String>? lifecycle,
    Value<int?>? revision,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return LocationsCompanion(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      entryId: entryId ?? this.entryId,
      sourceId: sourceId ?? this.sourceId,
      url: url ?? this.url,
      urlKey: urlKey ?? this.urlKey,
      sourceLabel: sourceLabel ?? this.sourceLabel,
      sourceNumber: sourceNumber ?? this.sourceNumber,
      publishedAt: publishedAt ?? this.publishedAt,
      discoveredAt: discoveredAt ?? this.discoveredAt,
      discoveryBasis: discoveryBasis ?? this.discoveryBasis,
      lifecycle: lifecycle ?? this.lifecycle,
      revision: revision ?? this.revision,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (entryId.present) {
      map['entry_id'] = Variable<String>(entryId.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (urlKey.present) {
      map['url_key'] = Variable<String>(urlKey.value);
    }
    if (sourceLabel.present) {
      map['source_label'] = Variable<String>(sourceLabel.value);
    }
    if (sourceNumber.present) {
      map['source_number'] = Variable<double>(sourceNumber.value);
    }
    if (publishedAt.present) {
      map['published_at'] = Variable<DateTime>(publishedAt.value);
    }
    if (discoveredAt.present) {
      map['discovered_at'] = Variable<DateTime>(discoveredAt.value);
    }
    if (discoveryBasis.present) {
      map['discovery_basis'] = Variable<String>(discoveryBasis.value);
    }
    if (lifecycle.present) {
      map['lifecycle'] = Variable<String>(lifecycle.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocationsCompanion(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('entryId: $entryId, ')
          ..write('sourceId: $sourceId, ')
          ..write('url: $url, ')
          ..write('urlKey: $urlKey, ')
          ..write('sourceLabel: $sourceLabel, ')
          ..write('sourceNumber: $sourceNumber, ')
          ..write('publishedAt: $publishedAt, ')
          ..write('discoveredAt: $discoveredAt, ')
          ..write('discoveryBasis: $discoveryBasis, ')
          ..write('lifecycle: $lifecycle, ')
          ..write('revision: $revision, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReadingStatesTable extends ReadingStates
    with TableInfo<$ReadingStatesTable, ReadingStateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReadingStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _entryIdMeta = const VerificationMeta(
    'entryId',
  );
  @override
  late final GeneratedColumn<String> entryId = GeneratedColumn<String>(
    'entry_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('unread'),
  );
  static const VerificationMeta _firstOpenedAtMeta = const VerificationMeta(
    'firstOpenedAt',
  );
  @override
  late final GeneratedColumn<DateTime> firstOpenedAt =
      GeneratedColumn<DateTime>(
        'first_opened_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastReadAtMeta = const VerificationMeta(
    'lastReadAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastReadAt = GeneratedColumn<DateTime>(
    'last_read_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
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
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    entryId,
    status,
    firstOpenedAt,
    lastReadAt,
    completedAt,
    revision,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reading_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReadingStateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('entry_id')) {
      context.handle(
        _entryIdMeta,
        entryId.isAcceptableOrUnknown(data['entry_id']!, _entryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entryIdMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('first_opened_at')) {
      context.handle(
        _firstOpenedAtMeta,
        firstOpenedAt.isAcceptableOrUnknown(
          data['first_opened_at']!,
          _firstOpenedAtMeta,
        ),
      );
    }
    if (data.containsKey('last_read_at')) {
      context.handle(
        _lastReadAtMeta,
        lastReadAt.isAcceptableOrUnknown(
          data['last_read_at']!,
          _lastReadAtMeta,
        ),
      );
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {entryId};
  @override
  ReadingStateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReadingStateRow(
      entryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entry_id'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      firstOpenedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}first_opened_at'],
      ),
      lastReadAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_read_at'],
      ),
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      ),
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ReadingStatesTable createAlias(String alias) {
    return $ReadingStatesTable(attachedDatabase, alias);
  }
}

class ReadingStateRow extends DataClass implements Insertable<ReadingStateRow> {
  final String entryId;
  final String status;
  final DateTime? firstOpenedAt;
  final DateTime? lastReadAt;
  final DateTime? completedAt;
  final int? revision;
  final DateTime updatedAt;
  const ReadingStateRow({
    required this.entryId,
    required this.status,
    this.firstOpenedAt,
    this.lastReadAt,
    this.completedAt,
    this.revision,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['entry_id'] = Variable<String>(entryId);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || firstOpenedAt != null) {
      map['first_opened_at'] = Variable<DateTime>(firstOpenedAt);
    }
    if (!nullToAbsent || lastReadAt != null) {
      map['last_read_at'] = Variable<DateTime>(lastReadAt);
    }
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    if (!nullToAbsent || revision != null) {
      map['revision'] = Variable<int>(revision);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ReadingStatesCompanion toCompanion(bool nullToAbsent) {
    return ReadingStatesCompanion(
      entryId: Value(entryId),
      status: Value(status),
      firstOpenedAt: firstOpenedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(firstOpenedAt),
      lastReadAt: lastReadAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReadAt),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      revision: revision == null && nullToAbsent
          ? const Value.absent()
          : Value(revision),
      updatedAt: Value(updatedAt),
    );
  }

  factory ReadingStateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReadingStateRow(
      entryId: serializer.fromJson<String>(json['entryId']),
      status: serializer.fromJson<String>(json['status']),
      firstOpenedAt: serializer.fromJson<DateTime?>(json['firstOpenedAt']),
      lastReadAt: serializer.fromJson<DateTime?>(json['lastReadAt']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
      revision: serializer.fromJson<int?>(json['revision']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'entryId': serializer.toJson<String>(entryId),
      'status': serializer.toJson<String>(status),
      'firstOpenedAt': serializer.toJson<DateTime?>(firstOpenedAt),
      'lastReadAt': serializer.toJson<DateTime?>(lastReadAt),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
      'revision': serializer.toJson<int?>(revision),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ReadingStateRow copyWith({
    String? entryId,
    String? status,
    Value<DateTime?> firstOpenedAt = const Value.absent(),
    Value<DateTime?> lastReadAt = const Value.absent(),
    Value<DateTime?> completedAt = const Value.absent(),
    Value<int?> revision = const Value.absent(),
    DateTime? updatedAt,
  }) => ReadingStateRow(
    entryId: entryId ?? this.entryId,
    status: status ?? this.status,
    firstOpenedAt: firstOpenedAt.present
        ? firstOpenedAt.value
        : this.firstOpenedAt,
    lastReadAt: lastReadAt.present ? lastReadAt.value : this.lastReadAt,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
    revision: revision.present ? revision.value : this.revision,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ReadingStateRow copyWithCompanion(ReadingStatesCompanion data) {
    return ReadingStateRow(
      entryId: data.entryId.present ? data.entryId.value : this.entryId,
      status: data.status.present ? data.status.value : this.status,
      firstOpenedAt: data.firstOpenedAt.present
          ? data.firstOpenedAt.value
          : this.firstOpenedAt,
      lastReadAt: data.lastReadAt.present
          ? data.lastReadAt.value
          : this.lastReadAt,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      revision: data.revision.present ? data.revision.value : this.revision,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReadingStateRow(')
          ..write('entryId: $entryId, ')
          ..write('status: $status, ')
          ..write('firstOpenedAt: $firstOpenedAt, ')
          ..write('lastReadAt: $lastReadAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('revision: $revision, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    entryId,
    status,
    firstOpenedAt,
    lastReadAt,
    completedAt,
    revision,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReadingStateRow &&
          other.entryId == this.entryId &&
          other.status == this.status &&
          other.firstOpenedAt == this.firstOpenedAt &&
          other.lastReadAt == this.lastReadAt &&
          other.completedAt == this.completedAt &&
          other.revision == this.revision &&
          other.updatedAt == this.updatedAt);
}

class ReadingStatesCompanion extends UpdateCompanion<ReadingStateRow> {
  final Value<String> entryId;
  final Value<String> status;
  final Value<DateTime?> firstOpenedAt;
  final Value<DateTime?> lastReadAt;
  final Value<DateTime?> completedAt;
  final Value<int?> revision;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ReadingStatesCompanion({
    this.entryId = const Value.absent(),
    this.status = const Value.absent(),
    this.firstOpenedAt = const Value.absent(),
    this.lastReadAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.revision = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReadingStatesCompanion.insert({
    required String entryId,
    this.status = const Value.absent(),
    this.firstOpenedAt = const Value.absent(),
    this.lastReadAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.revision = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : entryId = Value(entryId),
       updatedAt = Value(updatedAt);
  static Insertable<ReadingStateRow> custom({
    Expression<String>? entryId,
    Expression<String>? status,
    Expression<DateTime>? firstOpenedAt,
    Expression<DateTime>? lastReadAt,
    Expression<DateTime>? completedAt,
    Expression<int>? revision,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (entryId != null) 'entry_id': entryId,
      if (status != null) 'status': status,
      if (firstOpenedAt != null) 'first_opened_at': firstOpenedAt,
      if (lastReadAt != null) 'last_read_at': lastReadAt,
      if (completedAt != null) 'completed_at': completedAt,
      if (revision != null) 'revision': revision,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReadingStatesCompanion copyWith({
    Value<String>? entryId,
    Value<String>? status,
    Value<DateTime?>? firstOpenedAt,
    Value<DateTime?>? lastReadAt,
    Value<DateTime?>? completedAt,
    Value<int?>? revision,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ReadingStatesCompanion(
      entryId: entryId ?? this.entryId,
      status: status ?? this.status,
      firstOpenedAt: firstOpenedAt ?? this.firstOpenedAt,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      completedAt: completedAt ?? this.completedAt,
      revision: revision ?? this.revision,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (entryId.present) {
      map['entry_id'] = Variable<String>(entryId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (firstOpenedAt.present) {
      map['first_opened_at'] = Variable<DateTime>(firstOpenedAt.value);
    }
    if (lastReadAt.present) {
      map['last_read_at'] = Variable<DateTime>(lastReadAt.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReadingStatesCompanion(')
          ..write('entryId: $entryId, ')
          ..write('status: $status, ')
          ..write('firstOpenedAt: $firstOpenedAt, ')
          ..write('lastReadAt: $lastReadAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('revision: $revision, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MeasurementsTable extends Measurements
    with TableInfo<$MeasurementsTable, MeasurementRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MeasurementsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _entryIdMeta = const VerificationMeta(
    'entryId',
  );
  @override
  late final GeneratedColumn<String> entryId = GeneratedColumn<String>(
    'entry_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fractionMeta = const VerificationMeta(
    'fraction',
  );
  @override
  late final GeneratedColumn<double> fraction = GeneratedColumn<double>(
    'fraction',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _observedAtMeta = const VerificationMeta(
    'observedAt',
  );
  @override
  late final GeneratedColumn<DateTime> observedAt = GeneratedColumn<DateTime>(
    'observed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    entryId,
    sourceId,
    fraction,
    observedAt,
    revision,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'measurements';
  @override
  VerificationContext validateIntegrity(
    Insertable<MeasurementRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('entry_id')) {
      context.handle(
        _entryIdMeta,
        entryId.isAcceptableOrUnknown(data['entry_id']!, _entryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entryIdMeta);
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('fraction')) {
      context.handle(
        _fractionMeta,
        fraction.isAcceptableOrUnknown(data['fraction']!, _fractionMeta),
      );
    } else if (isInserting) {
      context.missing(_fractionMeta);
    }
    if (data.containsKey('observed_at')) {
      context.handle(
        _observedAtMeta,
        observedAt.isAcceptableOrUnknown(data['observed_at']!, _observedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_observedAtMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {entryId, sourceId};
  @override
  MeasurementRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MeasurementRow(
      entryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entry_id'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      fraction: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}fraction'],
      )!,
      observedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}observed_at'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      ),
    );
  }

  @override
  $MeasurementsTable createAlias(String alias) {
    return $MeasurementsTable(attachedDatabase, alias);
  }
}

class MeasurementRow extends DataClass implements Insertable<MeasurementRow> {
  final String entryId;
  final String sourceId;
  final double fraction;
  final DateTime observedAt;
  final int? revision;
  const MeasurementRow({
    required this.entryId,
    required this.sourceId,
    required this.fraction,
    required this.observedAt,
    this.revision,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['entry_id'] = Variable<String>(entryId);
    map['source_id'] = Variable<String>(sourceId);
    map['fraction'] = Variable<double>(fraction);
    map['observed_at'] = Variable<DateTime>(observedAt);
    if (!nullToAbsent || revision != null) {
      map['revision'] = Variable<int>(revision);
    }
    return map;
  }

  MeasurementsCompanion toCompanion(bool nullToAbsent) {
    return MeasurementsCompanion(
      entryId: Value(entryId),
      sourceId: Value(sourceId),
      fraction: Value(fraction),
      observedAt: Value(observedAt),
      revision: revision == null && nullToAbsent
          ? const Value.absent()
          : Value(revision),
    );
  }

  factory MeasurementRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MeasurementRow(
      entryId: serializer.fromJson<String>(json['entryId']),
      sourceId: serializer.fromJson<String>(json['sourceId']),
      fraction: serializer.fromJson<double>(json['fraction']),
      observedAt: serializer.fromJson<DateTime>(json['observedAt']),
      revision: serializer.fromJson<int?>(json['revision']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'entryId': serializer.toJson<String>(entryId),
      'sourceId': serializer.toJson<String>(sourceId),
      'fraction': serializer.toJson<double>(fraction),
      'observedAt': serializer.toJson<DateTime>(observedAt),
      'revision': serializer.toJson<int?>(revision),
    };
  }

  MeasurementRow copyWith({
    String? entryId,
    String? sourceId,
    double? fraction,
    DateTime? observedAt,
    Value<int?> revision = const Value.absent(),
  }) => MeasurementRow(
    entryId: entryId ?? this.entryId,
    sourceId: sourceId ?? this.sourceId,
    fraction: fraction ?? this.fraction,
    observedAt: observedAt ?? this.observedAt,
    revision: revision.present ? revision.value : this.revision,
  );
  MeasurementRow copyWithCompanion(MeasurementsCompanion data) {
    return MeasurementRow(
      entryId: data.entryId.present ? data.entryId.value : this.entryId,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      fraction: data.fraction.present ? data.fraction.value : this.fraction,
      observedAt: data.observedAt.present
          ? data.observedAt.value
          : this.observedAt,
      revision: data.revision.present ? data.revision.value : this.revision,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MeasurementRow(')
          ..write('entryId: $entryId, ')
          ..write('sourceId: $sourceId, ')
          ..write('fraction: $fraction, ')
          ..write('observedAt: $observedAt, ')
          ..write('revision: $revision')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(entryId, sourceId, fraction, observedAt, revision);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MeasurementRow &&
          other.entryId == this.entryId &&
          other.sourceId == this.sourceId &&
          other.fraction == this.fraction &&
          other.observedAt == this.observedAt &&
          other.revision == this.revision);
}

class MeasurementsCompanion extends UpdateCompanion<MeasurementRow> {
  final Value<String> entryId;
  final Value<String> sourceId;
  final Value<double> fraction;
  final Value<DateTime> observedAt;
  final Value<int?> revision;
  final Value<int> rowid;
  const MeasurementsCompanion({
    this.entryId = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.fraction = const Value.absent(),
    this.observedAt = const Value.absent(),
    this.revision = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MeasurementsCompanion.insert({
    required String entryId,
    required String sourceId,
    required double fraction,
    required DateTime observedAt,
    this.revision = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : entryId = Value(entryId),
       sourceId = Value(sourceId),
       fraction = Value(fraction),
       observedAt = Value(observedAt);
  static Insertable<MeasurementRow> custom({
    Expression<String>? entryId,
    Expression<String>? sourceId,
    Expression<double>? fraction,
    Expression<DateTime>? observedAt,
    Expression<int>? revision,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (entryId != null) 'entry_id': entryId,
      if (sourceId != null) 'source_id': sourceId,
      if (fraction != null) 'fraction': fraction,
      if (observedAt != null) 'observed_at': observedAt,
      if (revision != null) 'revision': revision,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MeasurementsCompanion copyWith({
    Value<String>? entryId,
    Value<String>? sourceId,
    Value<double>? fraction,
    Value<DateTime>? observedAt,
    Value<int?>? revision,
    Value<int>? rowid,
  }) {
    return MeasurementsCompanion(
      entryId: entryId ?? this.entryId,
      sourceId: sourceId ?? this.sourceId,
      fraction: fraction ?? this.fraction,
      observedAt: observedAt ?? this.observedAt,
      revision: revision ?? this.revision,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (entryId.present) {
      map['entry_id'] = Variable<String>(entryId.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (fraction.present) {
      map['fraction'] = Variable<double>(fraction.value);
    }
    if (observedAt.present) {
      map['observed_at'] = Variable<DateTime>(observedAt.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MeasurementsCompanion(')
          ..write('entryId: $entryId, ')
          ..write('sourceId: $sourceId, ')
          ..write('fraction: $fraction, ')
          ..write('observedAt: $observedAt, ')
          ..write('revision: $revision, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DownloadRequestsTable extends DownloadRequests
    with TableInfo<$DownloadRequestsTable, DownloadRequestRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DownloadRequestsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _entryIdMeta = const VerificationMeta(
    'entryId',
  );
  @override
  late final GeneratedColumn<String> entryId = GeneratedColumn<String>(
    'entry_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _locationIdMeta = const VerificationMeta(
    'locationId',
  );
  @override
  late final GeneratedColumn<String> locationId = GeneratedColumn<String>(
    'location_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idempotencyKeyMeta = const VerificationMeta(
    'idempotencyKey',
  );
  @override
  late final GeneratedColumn<String> idempotencyKey = GeneratedColumn<String>(
    'idempotency_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _createdByMeta = const VerificationMeta(
    'createdBy',
  );
  @override
  late final GeneratedColumn<String> createdBy = GeneratedColumn<String>(
    'created_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _claimedByDeviceMeta = const VerificationMeta(
    'claimedByDevice',
  );
  @override
  late final GeneratedColumn<String> claimedByDevice = GeneratedColumn<String>(
    'claimed_by_device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _claimedAtMeta = const VerificationMeta(
    'claimedAt',
  );
  @override
  late final GeneratedColumn<DateTime> claimedAt = GeneratedColumn<DateTime>(
    'claimed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _resolvedAtMeta = const VerificationMeta(
    'resolvedAt',
  );
  @override
  late final GeneratedColumn<DateTime> resolvedAt = GeneratedColumn<DateTime>(
    'resolved_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _failureReasonMeta = const VerificationMeta(
    'failureReason',
  );
  @override
  late final GeneratedColumn<String> failureReason = GeneratedColumn<String>(
    'failure_reason',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _localSaveTaskIdMeta = const VerificationMeta(
    'localSaveTaskId',
  );
  @override
  late final GeneratedColumn<String> localSaveTaskId = GeneratedColumn<String>(
    'local_save_task_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    serverId,
    entryId,
    locationId,
    state,
    idempotencyKey,
    createdBy,
    createdAt,
    claimedByDevice,
    claimedAt,
    resolvedAt,
    failureReason,
    revision,
    localSaveTaskId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'download_requests';
  @override
  VerificationContext validateIntegrity(
    Insertable<DownloadRequestRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    }
    if (data.containsKey('entry_id')) {
      context.handle(
        _entryIdMeta,
        entryId.isAcceptableOrUnknown(data['entry_id']!, _entryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entryIdMeta);
    }
    if (data.containsKey('location_id')) {
      context.handle(
        _locationIdMeta,
        locationId.isAcceptableOrUnknown(data['location_id']!, _locationIdMeta),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('idempotency_key')) {
      context.handle(
        _idempotencyKeyMeta,
        idempotencyKey.isAcceptableOrUnknown(
          data['idempotency_key']!,
          _idempotencyKeyMeta,
        ),
      );
    }
    if (data.containsKey('created_by')) {
      context.handle(
        _createdByMeta,
        createdBy.isAcceptableOrUnknown(data['created_by']!, _createdByMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('claimed_by_device')) {
      context.handle(
        _claimedByDeviceMeta,
        claimedByDevice.isAcceptableOrUnknown(
          data['claimed_by_device']!,
          _claimedByDeviceMeta,
        ),
      );
    }
    if (data.containsKey('claimed_at')) {
      context.handle(
        _claimedAtMeta,
        claimedAt.isAcceptableOrUnknown(data['claimed_at']!, _claimedAtMeta),
      );
    }
    if (data.containsKey('resolved_at')) {
      context.handle(
        _resolvedAtMeta,
        resolvedAt.isAcceptableOrUnknown(data['resolved_at']!, _resolvedAtMeta),
      );
    }
    if (data.containsKey('failure_reason')) {
      context.handle(
        _failureReasonMeta,
        failureReason.isAcceptableOrUnknown(
          data['failure_reason']!,
          _failureReasonMeta,
        ),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('local_save_task_id')) {
      context.handle(
        _localSaveTaskIdMeta,
        localSaveTaskId.isAcceptableOrUnknown(
          data['local_save_task_id']!,
          _localSaveTaskIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DownloadRequestRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DownloadRequestRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_id'],
      ),
      entryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entry_id'],
      )!,
      locationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location_id'],
      ),
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      idempotencyKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}idempotency_key'],
      )!,
      createdBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      claimedByDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}claimed_by_device'],
      )!,
      claimedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}claimed_at'],
      ),
      resolvedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}resolved_at'],
      ),
      failureReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_reason'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      ),
      localSaveTaskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_save_task_id'],
      ),
    );
  }

  @override
  $DownloadRequestsTable createAlias(String alias) {
    return $DownloadRequestsTable(attachedDatabase, alias);
  }
}

class DownloadRequestRow extends DataClass
    implements Insertable<DownloadRequestRow> {
  final String id;
  final String? serverId;
  final String entryId;
  final String? locationId;
  final String state;
  final String idempotencyKey;
  final String createdBy;
  final DateTime createdAt;
  final String claimedByDevice;
  final DateTime? claimedAt;
  final DateTime? resolvedAt;
  final String failureReason;
  final int? revision;

  /// The local save task this device created when it claimed the request.
  /// Device state, never synced.
  final String? localSaveTaskId;
  const DownloadRequestRow({
    required this.id,
    this.serverId,
    required this.entryId,
    this.locationId,
    required this.state,
    required this.idempotencyKey,
    required this.createdBy,
    required this.createdAt,
    required this.claimedByDevice,
    this.claimedAt,
    this.resolvedAt,
    required this.failureReason,
    this.revision,
    this.localSaveTaskId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<String>(serverId);
    }
    map['entry_id'] = Variable<String>(entryId);
    if (!nullToAbsent || locationId != null) {
      map['location_id'] = Variable<String>(locationId);
    }
    map['state'] = Variable<String>(state);
    map['idempotency_key'] = Variable<String>(idempotencyKey);
    map['created_by'] = Variable<String>(createdBy);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['claimed_by_device'] = Variable<String>(claimedByDevice);
    if (!nullToAbsent || claimedAt != null) {
      map['claimed_at'] = Variable<DateTime>(claimedAt);
    }
    if (!nullToAbsent || resolvedAt != null) {
      map['resolved_at'] = Variable<DateTime>(resolvedAt);
    }
    map['failure_reason'] = Variable<String>(failureReason);
    if (!nullToAbsent || revision != null) {
      map['revision'] = Variable<int>(revision);
    }
    if (!nullToAbsent || localSaveTaskId != null) {
      map['local_save_task_id'] = Variable<String>(localSaveTaskId);
    }
    return map;
  }

  DownloadRequestsCompanion toCompanion(bool nullToAbsent) {
    return DownloadRequestsCompanion(
      id: Value(id),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      entryId: Value(entryId),
      locationId: locationId == null && nullToAbsent
          ? const Value.absent()
          : Value(locationId),
      state: Value(state),
      idempotencyKey: Value(idempotencyKey),
      createdBy: Value(createdBy),
      createdAt: Value(createdAt),
      claimedByDevice: Value(claimedByDevice),
      claimedAt: claimedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(claimedAt),
      resolvedAt: resolvedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(resolvedAt),
      failureReason: Value(failureReason),
      revision: revision == null && nullToAbsent
          ? const Value.absent()
          : Value(revision),
      localSaveTaskId: localSaveTaskId == null && nullToAbsent
          ? const Value.absent()
          : Value(localSaveTaskId),
    );
  }

  factory DownloadRequestRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DownloadRequestRow(
      id: serializer.fromJson<String>(json['id']),
      serverId: serializer.fromJson<String?>(json['serverId']),
      entryId: serializer.fromJson<String>(json['entryId']),
      locationId: serializer.fromJson<String?>(json['locationId']),
      state: serializer.fromJson<String>(json['state']),
      idempotencyKey: serializer.fromJson<String>(json['idempotencyKey']),
      createdBy: serializer.fromJson<String>(json['createdBy']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      claimedByDevice: serializer.fromJson<String>(json['claimedByDevice']),
      claimedAt: serializer.fromJson<DateTime?>(json['claimedAt']),
      resolvedAt: serializer.fromJson<DateTime?>(json['resolvedAt']),
      failureReason: serializer.fromJson<String>(json['failureReason']),
      revision: serializer.fromJson<int?>(json['revision']),
      localSaveTaskId: serializer.fromJson<String?>(json['localSaveTaskId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'serverId': serializer.toJson<String?>(serverId),
      'entryId': serializer.toJson<String>(entryId),
      'locationId': serializer.toJson<String?>(locationId),
      'state': serializer.toJson<String>(state),
      'idempotencyKey': serializer.toJson<String>(idempotencyKey),
      'createdBy': serializer.toJson<String>(createdBy),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'claimedByDevice': serializer.toJson<String>(claimedByDevice),
      'claimedAt': serializer.toJson<DateTime?>(claimedAt),
      'resolvedAt': serializer.toJson<DateTime?>(resolvedAt),
      'failureReason': serializer.toJson<String>(failureReason),
      'revision': serializer.toJson<int?>(revision),
      'localSaveTaskId': serializer.toJson<String?>(localSaveTaskId),
    };
  }

  DownloadRequestRow copyWith({
    String? id,
    Value<String?> serverId = const Value.absent(),
    String? entryId,
    Value<String?> locationId = const Value.absent(),
    String? state,
    String? idempotencyKey,
    String? createdBy,
    DateTime? createdAt,
    String? claimedByDevice,
    Value<DateTime?> claimedAt = const Value.absent(),
    Value<DateTime?> resolvedAt = const Value.absent(),
    String? failureReason,
    Value<int?> revision = const Value.absent(),
    Value<String?> localSaveTaskId = const Value.absent(),
  }) => DownloadRequestRow(
    id: id ?? this.id,
    serverId: serverId.present ? serverId.value : this.serverId,
    entryId: entryId ?? this.entryId,
    locationId: locationId.present ? locationId.value : this.locationId,
    state: state ?? this.state,
    idempotencyKey: idempotencyKey ?? this.idempotencyKey,
    createdBy: createdBy ?? this.createdBy,
    createdAt: createdAt ?? this.createdAt,
    claimedByDevice: claimedByDevice ?? this.claimedByDevice,
    claimedAt: claimedAt.present ? claimedAt.value : this.claimedAt,
    resolvedAt: resolvedAt.present ? resolvedAt.value : this.resolvedAt,
    failureReason: failureReason ?? this.failureReason,
    revision: revision.present ? revision.value : this.revision,
    localSaveTaskId: localSaveTaskId.present
        ? localSaveTaskId.value
        : this.localSaveTaskId,
  );
  DownloadRequestRow copyWithCompanion(DownloadRequestsCompanion data) {
    return DownloadRequestRow(
      id: data.id.present ? data.id.value : this.id,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      entryId: data.entryId.present ? data.entryId.value : this.entryId,
      locationId: data.locationId.present
          ? data.locationId.value
          : this.locationId,
      state: data.state.present ? data.state.value : this.state,
      idempotencyKey: data.idempotencyKey.present
          ? data.idempotencyKey.value
          : this.idempotencyKey,
      createdBy: data.createdBy.present ? data.createdBy.value : this.createdBy,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      claimedByDevice: data.claimedByDevice.present
          ? data.claimedByDevice.value
          : this.claimedByDevice,
      claimedAt: data.claimedAt.present ? data.claimedAt.value : this.claimedAt,
      resolvedAt: data.resolvedAt.present
          ? data.resolvedAt.value
          : this.resolvedAt,
      failureReason: data.failureReason.present
          ? data.failureReason.value
          : this.failureReason,
      revision: data.revision.present ? data.revision.value : this.revision,
      localSaveTaskId: data.localSaveTaskId.present
          ? data.localSaveTaskId.value
          : this.localSaveTaskId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DownloadRequestRow(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('entryId: $entryId, ')
          ..write('locationId: $locationId, ')
          ..write('state: $state, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('createdBy: $createdBy, ')
          ..write('createdAt: $createdAt, ')
          ..write('claimedByDevice: $claimedByDevice, ')
          ..write('claimedAt: $claimedAt, ')
          ..write('resolvedAt: $resolvedAt, ')
          ..write('failureReason: $failureReason, ')
          ..write('revision: $revision, ')
          ..write('localSaveTaskId: $localSaveTaskId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    serverId,
    entryId,
    locationId,
    state,
    idempotencyKey,
    createdBy,
    createdAt,
    claimedByDevice,
    claimedAt,
    resolvedAt,
    failureReason,
    revision,
    localSaveTaskId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DownloadRequestRow &&
          other.id == this.id &&
          other.serverId == this.serverId &&
          other.entryId == this.entryId &&
          other.locationId == this.locationId &&
          other.state == this.state &&
          other.idempotencyKey == this.idempotencyKey &&
          other.createdBy == this.createdBy &&
          other.createdAt == this.createdAt &&
          other.claimedByDevice == this.claimedByDevice &&
          other.claimedAt == this.claimedAt &&
          other.resolvedAt == this.resolvedAt &&
          other.failureReason == this.failureReason &&
          other.revision == this.revision &&
          other.localSaveTaskId == this.localSaveTaskId);
}

class DownloadRequestsCompanion extends UpdateCompanion<DownloadRequestRow> {
  final Value<String> id;
  final Value<String?> serverId;
  final Value<String> entryId;
  final Value<String?> locationId;
  final Value<String> state;
  final Value<String> idempotencyKey;
  final Value<String> createdBy;
  final Value<DateTime> createdAt;
  final Value<String> claimedByDevice;
  final Value<DateTime?> claimedAt;
  final Value<DateTime?> resolvedAt;
  final Value<String> failureReason;
  final Value<int?> revision;
  final Value<String?> localSaveTaskId;
  final Value<int> rowid;
  const DownloadRequestsCompanion({
    this.id = const Value.absent(),
    this.serverId = const Value.absent(),
    this.entryId = const Value.absent(),
    this.locationId = const Value.absent(),
    this.state = const Value.absent(),
    this.idempotencyKey = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.claimedByDevice = const Value.absent(),
    this.claimedAt = const Value.absent(),
    this.resolvedAt = const Value.absent(),
    this.failureReason = const Value.absent(),
    this.revision = const Value.absent(),
    this.localSaveTaskId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DownloadRequestsCompanion.insert({
    required String id,
    this.serverId = const Value.absent(),
    required String entryId,
    this.locationId = const Value.absent(),
    required String state,
    this.idempotencyKey = const Value.absent(),
    this.createdBy = const Value.absent(),
    required DateTime createdAt,
    this.claimedByDevice = const Value.absent(),
    this.claimedAt = const Value.absent(),
    this.resolvedAt = const Value.absent(),
    this.failureReason = const Value.absent(),
    this.revision = const Value.absent(),
    this.localSaveTaskId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       entryId = Value(entryId),
       state = Value(state),
       createdAt = Value(createdAt);
  static Insertable<DownloadRequestRow> custom({
    Expression<String>? id,
    Expression<String>? serverId,
    Expression<String>? entryId,
    Expression<String>? locationId,
    Expression<String>? state,
    Expression<String>? idempotencyKey,
    Expression<String>? createdBy,
    Expression<DateTime>? createdAt,
    Expression<String>? claimedByDevice,
    Expression<DateTime>? claimedAt,
    Expression<DateTime>? resolvedAt,
    Expression<String>? failureReason,
    Expression<int>? revision,
    Expression<String>? localSaveTaskId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (serverId != null) 'server_id': serverId,
      if (entryId != null) 'entry_id': entryId,
      if (locationId != null) 'location_id': locationId,
      if (state != null) 'state': state,
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      if (createdBy != null) 'created_by': createdBy,
      if (createdAt != null) 'created_at': createdAt,
      if (claimedByDevice != null) 'claimed_by_device': claimedByDevice,
      if (claimedAt != null) 'claimed_at': claimedAt,
      if (resolvedAt != null) 'resolved_at': resolvedAt,
      if (failureReason != null) 'failure_reason': failureReason,
      if (revision != null) 'revision': revision,
      if (localSaveTaskId != null) 'local_save_task_id': localSaveTaskId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DownloadRequestsCompanion copyWith({
    Value<String>? id,
    Value<String?>? serverId,
    Value<String>? entryId,
    Value<String?>? locationId,
    Value<String>? state,
    Value<String>? idempotencyKey,
    Value<String>? createdBy,
    Value<DateTime>? createdAt,
    Value<String>? claimedByDevice,
    Value<DateTime?>? claimedAt,
    Value<DateTime?>? resolvedAt,
    Value<String>? failureReason,
    Value<int?>? revision,
    Value<String?>? localSaveTaskId,
    Value<int>? rowid,
  }) {
    return DownloadRequestsCompanion(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      entryId: entryId ?? this.entryId,
      locationId: locationId ?? this.locationId,
      state: state ?? this.state,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      claimedByDevice: claimedByDevice ?? this.claimedByDevice,
      claimedAt: claimedAt ?? this.claimedAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      failureReason: failureReason ?? this.failureReason,
      revision: revision ?? this.revision,
      localSaveTaskId: localSaveTaskId ?? this.localSaveTaskId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (entryId.present) {
      map['entry_id'] = Variable<String>(entryId.value);
    }
    if (locationId.present) {
      map['location_id'] = Variable<String>(locationId.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (idempotencyKey.present) {
      map['idempotency_key'] = Variable<String>(idempotencyKey.value);
    }
    if (createdBy.present) {
      map['created_by'] = Variable<String>(createdBy.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (claimedByDevice.present) {
      map['claimed_by_device'] = Variable<String>(claimedByDevice.value);
    }
    if (claimedAt.present) {
      map['claimed_at'] = Variable<DateTime>(claimedAt.value);
    }
    if (resolvedAt.present) {
      map['resolved_at'] = Variable<DateTime>(resolvedAt.value);
    }
    if (failureReason.present) {
      map['failure_reason'] = Variable<String>(failureReason.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (localSaveTaskId.present) {
      map['local_save_task_id'] = Variable<String>(localSaveTaskId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DownloadRequestsCompanion(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('entryId: $entryId, ')
          ..write('locationId: $locationId, ')
          ..write('state: $state, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('createdBy: $createdBy, ')
          ..write('createdAt: $createdAt, ')
          ..write('claimedByDevice: $claimedByDevice, ')
          ..write('claimedAt: $claimedAt, ')
          ..write('resolvedAt: $resolvedAt, ')
          ..write('failureReason: $failureReason, ')
          ..write('revision: $revision, ')
          ..write('localSaveTaskId: $localSaveTaskId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OfflineCopiesTable extends OfflineCopies
    with TableInfo<$OfflineCopiesTable, OfflineCopyRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OfflineCopiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entryIdMeta = const VerificationMeta(
    'entryId',
  );
  @override
  late final GeneratedColumn<String> entryId = GeneratedColumn<String>(
    'entry_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _locationUrlMeta = const VerificationMeta(
    'locationUrl',
  );
  @override
  late final GeneratedColumn<String> locationUrl = GeneratedColumn<String>(
    'location_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceNameMeta = const VerificationMeta(
    'sourceName',
  );
  @override
  late final GeneratedColumn<String> sourceName = GeneratedColumn<String>(
    'source_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sourceHostMeta = const VerificationMeta(
    'sourceHost',
  );
  @override
  late final GeneratedColumn<String> sourceHost = GeneratedColumn<String>(
    'source_host',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sourceLanguageMeta = const VerificationMeta(
    'sourceLanguage',
  );
  @override
  late final GeneratedColumn<String> sourceLanguage = GeneratedColumn<String>(
    'source_language',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _capturedAtMeta = const VerificationMeta(
    'capturedAt',
  );
  @override
  late final GeneratedColumn<DateTime> capturedAt = GeneratedColumn<DateTime>(
    'captured_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _artifactFormatMeta = const VerificationMeta(
    'artifactFormat',
  );
  @override
  late final GeneratedColumn<String> artifactFormat = GeneratedColumn<String>(
    'artifact_format',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentPathMeta = const VerificationMeta(
    'contentPath',
  );
  @override
  late final GeneratedColumn<String> contentPath = GeneratedColumn<String>(
    'content_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _byteSizeMeta = const VerificationMeta(
    'byteSize',
  );
  @override
  late final GeneratedColumn<int> byteSize = GeneratedColumn<int>(
    'byte_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _anchorIndexMeta = const VerificationMeta(
    'anchorIndex',
  );
  @override
  late final GeneratedColumn<int> anchorIndex = GeneratedColumn<int>(
    'anchor_index',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _anchorOffsetMeta = const VerificationMeta(
    'anchorOffset',
  );
  @override
  late final GeneratedColumn<double> anchorOffset = GeneratedColumn<double>(
    'anchor_offset',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _activeMeta = const VerificationMeta('active');
  @override
  late final GeneratedColumn<bool> active = GeneratedColumn<bool>(
    'active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    entryId,
    locationUrl,
    sourceName,
    sourceHost,
    sourceLanguage,
    capturedAt,
    artifactFormat,
    contentPath,
    byteSize,
    anchorIndex,
    anchorOffset,
    active,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'offline_copies';
  @override
  VerificationContext validateIntegrity(
    Insertable<OfflineCopyRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('entry_id')) {
      context.handle(
        _entryIdMeta,
        entryId.isAcceptableOrUnknown(data['entry_id']!, _entryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entryIdMeta);
    }
    if (data.containsKey('location_url')) {
      context.handle(
        _locationUrlMeta,
        locationUrl.isAcceptableOrUnknown(
          data['location_url']!,
          _locationUrlMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_locationUrlMeta);
    }
    if (data.containsKey('source_name')) {
      context.handle(
        _sourceNameMeta,
        sourceName.isAcceptableOrUnknown(data['source_name']!, _sourceNameMeta),
      );
    }
    if (data.containsKey('source_host')) {
      context.handle(
        _sourceHostMeta,
        sourceHost.isAcceptableOrUnknown(data['source_host']!, _sourceHostMeta),
      );
    }
    if (data.containsKey('source_language')) {
      context.handle(
        _sourceLanguageMeta,
        sourceLanguage.isAcceptableOrUnknown(
          data['source_language']!,
          _sourceLanguageMeta,
        ),
      );
    }
    if (data.containsKey('captured_at')) {
      context.handle(
        _capturedAtMeta,
        capturedAt.isAcceptableOrUnknown(data['captured_at']!, _capturedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_capturedAtMeta);
    }
    if (data.containsKey('artifact_format')) {
      context.handle(
        _artifactFormatMeta,
        artifactFormat.isAcceptableOrUnknown(
          data['artifact_format']!,
          _artifactFormatMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_artifactFormatMeta);
    }
    if (data.containsKey('content_path')) {
      context.handle(
        _contentPathMeta,
        contentPath.isAcceptableOrUnknown(
          data['content_path']!,
          _contentPathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentPathMeta);
    }
    if (data.containsKey('byte_size')) {
      context.handle(
        _byteSizeMeta,
        byteSize.isAcceptableOrUnknown(data['byte_size']!, _byteSizeMeta),
      );
    }
    if (data.containsKey('anchor_index')) {
      context.handle(
        _anchorIndexMeta,
        anchorIndex.isAcceptableOrUnknown(
          data['anchor_index']!,
          _anchorIndexMeta,
        ),
      );
    }
    if (data.containsKey('anchor_offset')) {
      context.handle(
        _anchorOffsetMeta,
        anchorOffset.isAcceptableOrUnknown(
          data['anchor_offset']!,
          _anchorOffsetMeta,
        ),
      );
    }
    if (data.containsKey('active')) {
      context.handle(
        _activeMeta,
        active.isAcceptableOrUnknown(data['active']!, _activeMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OfflineCopyRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OfflineCopyRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      entryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entry_id'],
      )!,
      locationUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location_url'],
      )!,
      sourceName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_name'],
      )!,
      sourceHost: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_host'],
      )!,
      sourceLanguage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_language'],
      )!,
      capturedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}captured_at'],
      )!,
      artifactFormat: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artifact_format'],
      )!,
      contentPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_path'],
      )!,
      byteSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}byte_size'],
      )!,
      anchorIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}anchor_index'],
      ),
      anchorOffset: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}anchor_offset'],
      ),
      active: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}active'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $OfflineCopiesTable createAlias(String alias) {
    return $OfflineCopiesTable(attachedDatabase, alias);
  }
}

class OfflineCopyRow extends DataClass implements Insertable<OfflineCopyRow> {
  final String id;
  final String entryId;
  final String locationUrl;
  final String sourceName;
  final String sourceHost;
  final String sourceLanguage;
  final DateTime capturedAt;
  final String artifactFormat;
  final String contentPath;
  final int byteSize;

  /// The reading anchor: position inside this artifact, meaningless without
  /// the bytes it indexes. Never leaves the device.
  final int? anchorIndex;
  final double? anchorOffset;
  final bool active;
  final DateTime createdAt;
  const OfflineCopyRow({
    required this.id,
    required this.entryId,
    required this.locationUrl,
    required this.sourceName,
    required this.sourceHost,
    required this.sourceLanguage,
    required this.capturedAt,
    required this.artifactFormat,
    required this.contentPath,
    required this.byteSize,
    this.anchorIndex,
    this.anchorOffset,
    required this.active,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['entry_id'] = Variable<String>(entryId);
    map['location_url'] = Variable<String>(locationUrl);
    map['source_name'] = Variable<String>(sourceName);
    map['source_host'] = Variable<String>(sourceHost);
    map['source_language'] = Variable<String>(sourceLanguage);
    map['captured_at'] = Variable<DateTime>(capturedAt);
    map['artifact_format'] = Variable<String>(artifactFormat);
    map['content_path'] = Variable<String>(contentPath);
    map['byte_size'] = Variable<int>(byteSize);
    if (!nullToAbsent || anchorIndex != null) {
      map['anchor_index'] = Variable<int>(anchorIndex);
    }
    if (!nullToAbsent || anchorOffset != null) {
      map['anchor_offset'] = Variable<double>(anchorOffset);
    }
    map['active'] = Variable<bool>(active);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  OfflineCopiesCompanion toCompanion(bool nullToAbsent) {
    return OfflineCopiesCompanion(
      id: Value(id),
      entryId: Value(entryId),
      locationUrl: Value(locationUrl),
      sourceName: Value(sourceName),
      sourceHost: Value(sourceHost),
      sourceLanguage: Value(sourceLanguage),
      capturedAt: Value(capturedAt),
      artifactFormat: Value(artifactFormat),
      contentPath: Value(contentPath),
      byteSize: Value(byteSize),
      anchorIndex: anchorIndex == null && nullToAbsent
          ? const Value.absent()
          : Value(anchorIndex),
      anchorOffset: anchorOffset == null && nullToAbsent
          ? const Value.absent()
          : Value(anchorOffset),
      active: Value(active),
      createdAt: Value(createdAt),
    );
  }

  factory OfflineCopyRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OfflineCopyRow(
      id: serializer.fromJson<String>(json['id']),
      entryId: serializer.fromJson<String>(json['entryId']),
      locationUrl: serializer.fromJson<String>(json['locationUrl']),
      sourceName: serializer.fromJson<String>(json['sourceName']),
      sourceHost: serializer.fromJson<String>(json['sourceHost']),
      sourceLanguage: serializer.fromJson<String>(json['sourceLanguage']),
      capturedAt: serializer.fromJson<DateTime>(json['capturedAt']),
      artifactFormat: serializer.fromJson<String>(json['artifactFormat']),
      contentPath: serializer.fromJson<String>(json['contentPath']),
      byteSize: serializer.fromJson<int>(json['byteSize']),
      anchorIndex: serializer.fromJson<int?>(json['anchorIndex']),
      anchorOffset: serializer.fromJson<double?>(json['anchorOffset']),
      active: serializer.fromJson<bool>(json['active']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'entryId': serializer.toJson<String>(entryId),
      'locationUrl': serializer.toJson<String>(locationUrl),
      'sourceName': serializer.toJson<String>(sourceName),
      'sourceHost': serializer.toJson<String>(sourceHost),
      'sourceLanguage': serializer.toJson<String>(sourceLanguage),
      'capturedAt': serializer.toJson<DateTime>(capturedAt),
      'artifactFormat': serializer.toJson<String>(artifactFormat),
      'contentPath': serializer.toJson<String>(contentPath),
      'byteSize': serializer.toJson<int>(byteSize),
      'anchorIndex': serializer.toJson<int?>(anchorIndex),
      'anchorOffset': serializer.toJson<double?>(anchorOffset),
      'active': serializer.toJson<bool>(active),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  OfflineCopyRow copyWith({
    String? id,
    String? entryId,
    String? locationUrl,
    String? sourceName,
    String? sourceHost,
    String? sourceLanguage,
    DateTime? capturedAt,
    String? artifactFormat,
    String? contentPath,
    int? byteSize,
    Value<int?> anchorIndex = const Value.absent(),
    Value<double?> anchorOffset = const Value.absent(),
    bool? active,
    DateTime? createdAt,
  }) => OfflineCopyRow(
    id: id ?? this.id,
    entryId: entryId ?? this.entryId,
    locationUrl: locationUrl ?? this.locationUrl,
    sourceName: sourceName ?? this.sourceName,
    sourceHost: sourceHost ?? this.sourceHost,
    sourceLanguage: sourceLanguage ?? this.sourceLanguage,
    capturedAt: capturedAt ?? this.capturedAt,
    artifactFormat: artifactFormat ?? this.artifactFormat,
    contentPath: contentPath ?? this.contentPath,
    byteSize: byteSize ?? this.byteSize,
    anchorIndex: anchorIndex.present ? anchorIndex.value : this.anchorIndex,
    anchorOffset: anchorOffset.present ? anchorOffset.value : this.anchorOffset,
    active: active ?? this.active,
    createdAt: createdAt ?? this.createdAt,
  );
  OfflineCopyRow copyWithCompanion(OfflineCopiesCompanion data) {
    return OfflineCopyRow(
      id: data.id.present ? data.id.value : this.id,
      entryId: data.entryId.present ? data.entryId.value : this.entryId,
      locationUrl: data.locationUrl.present
          ? data.locationUrl.value
          : this.locationUrl,
      sourceName: data.sourceName.present
          ? data.sourceName.value
          : this.sourceName,
      sourceHost: data.sourceHost.present
          ? data.sourceHost.value
          : this.sourceHost,
      sourceLanguage: data.sourceLanguage.present
          ? data.sourceLanguage.value
          : this.sourceLanguage,
      capturedAt: data.capturedAt.present
          ? data.capturedAt.value
          : this.capturedAt,
      artifactFormat: data.artifactFormat.present
          ? data.artifactFormat.value
          : this.artifactFormat,
      contentPath: data.contentPath.present
          ? data.contentPath.value
          : this.contentPath,
      byteSize: data.byteSize.present ? data.byteSize.value : this.byteSize,
      anchorIndex: data.anchorIndex.present
          ? data.anchorIndex.value
          : this.anchorIndex,
      anchorOffset: data.anchorOffset.present
          ? data.anchorOffset.value
          : this.anchorOffset,
      active: data.active.present ? data.active.value : this.active,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OfflineCopyRow(')
          ..write('id: $id, ')
          ..write('entryId: $entryId, ')
          ..write('locationUrl: $locationUrl, ')
          ..write('sourceName: $sourceName, ')
          ..write('sourceHost: $sourceHost, ')
          ..write('sourceLanguage: $sourceLanguage, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('artifactFormat: $artifactFormat, ')
          ..write('contentPath: $contentPath, ')
          ..write('byteSize: $byteSize, ')
          ..write('anchorIndex: $anchorIndex, ')
          ..write('anchorOffset: $anchorOffset, ')
          ..write('active: $active, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    entryId,
    locationUrl,
    sourceName,
    sourceHost,
    sourceLanguage,
    capturedAt,
    artifactFormat,
    contentPath,
    byteSize,
    anchorIndex,
    anchorOffset,
    active,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OfflineCopyRow &&
          other.id == this.id &&
          other.entryId == this.entryId &&
          other.locationUrl == this.locationUrl &&
          other.sourceName == this.sourceName &&
          other.sourceHost == this.sourceHost &&
          other.sourceLanguage == this.sourceLanguage &&
          other.capturedAt == this.capturedAt &&
          other.artifactFormat == this.artifactFormat &&
          other.contentPath == this.contentPath &&
          other.byteSize == this.byteSize &&
          other.anchorIndex == this.anchorIndex &&
          other.anchorOffset == this.anchorOffset &&
          other.active == this.active &&
          other.createdAt == this.createdAt);
}

class OfflineCopiesCompanion extends UpdateCompanion<OfflineCopyRow> {
  final Value<String> id;
  final Value<String> entryId;
  final Value<String> locationUrl;
  final Value<String> sourceName;
  final Value<String> sourceHost;
  final Value<String> sourceLanguage;
  final Value<DateTime> capturedAt;
  final Value<String> artifactFormat;
  final Value<String> contentPath;
  final Value<int> byteSize;
  final Value<int?> anchorIndex;
  final Value<double?> anchorOffset;
  final Value<bool> active;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const OfflineCopiesCompanion({
    this.id = const Value.absent(),
    this.entryId = const Value.absent(),
    this.locationUrl = const Value.absent(),
    this.sourceName = const Value.absent(),
    this.sourceHost = const Value.absent(),
    this.sourceLanguage = const Value.absent(),
    this.capturedAt = const Value.absent(),
    this.artifactFormat = const Value.absent(),
    this.contentPath = const Value.absent(),
    this.byteSize = const Value.absent(),
    this.anchorIndex = const Value.absent(),
    this.anchorOffset = const Value.absent(),
    this.active = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OfflineCopiesCompanion.insert({
    required String id,
    required String entryId,
    required String locationUrl,
    this.sourceName = const Value.absent(),
    this.sourceHost = const Value.absent(),
    this.sourceLanguage = const Value.absent(),
    required DateTime capturedAt,
    required String artifactFormat,
    required String contentPath,
    this.byteSize = const Value.absent(),
    this.anchorIndex = const Value.absent(),
    this.anchorOffset = const Value.absent(),
    this.active = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       entryId = Value(entryId),
       locationUrl = Value(locationUrl),
       capturedAt = Value(capturedAt),
       artifactFormat = Value(artifactFormat),
       contentPath = Value(contentPath),
       createdAt = Value(createdAt);
  static Insertable<OfflineCopyRow> custom({
    Expression<String>? id,
    Expression<String>? entryId,
    Expression<String>? locationUrl,
    Expression<String>? sourceName,
    Expression<String>? sourceHost,
    Expression<String>? sourceLanguage,
    Expression<DateTime>? capturedAt,
    Expression<String>? artifactFormat,
    Expression<String>? contentPath,
    Expression<int>? byteSize,
    Expression<int>? anchorIndex,
    Expression<double>? anchorOffset,
    Expression<bool>? active,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entryId != null) 'entry_id': entryId,
      if (locationUrl != null) 'location_url': locationUrl,
      if (sourceName != null) 'source_name': sourceName,
      if (sourceHost != null) 'source_host': sourceHost,
      if (sourceLanguage != null) 'source_language': sourceLanguage,
      if (capturedAt != null) 'captured_at': capturedAt,
      if (artifactFormat != null) 'artifact_format': artifactFormat,
      if (contentPath != null) 'content_path': contentPath,
      if (byteSize != null) 'byte_size': byteSize,
      if (anchorIndex != null) 'anchor_index': anchorIndex,
      if (anchorOffset != null) 'anchor_offset': anchorOffset,
      if (active != null) 'active': active,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OfflineCopiesCompanion copyWith({
    Value<String>? id,
    Value<String>? entryId,
    Value<String>? locationUrl,
    Value<String>? sourceName,
    Value<String>? sourceHost,
    Value<String>? sourceLanguage,
    Value<DateTime>? capturedAt,
    Value<String>? artifactFormat,
    Value<String>? contentPath,
    Value<int>? byteSize,
    Value<int?>? anchorIndex,
    Value<double?>? anchorOffset,
    Value<bool>? active,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return OfflineCopiesCompanion(
      id: id ?? this.id,
      entryId: entryId ?? this.entryId,
      locationUrl: locationUrl ?? this.locationUrl,
      sourceName: sourceName ?? this.sourceName,
      sourceHost: sourceHost ?? this.sourceHost,
      sourceLanguage: sourceLanguage ?? this.sourceLanguage,
      capturedAt: capturedAt ?? this.capturedAt,
      artifactFormat: artifactFormat ?? this.artifactFormat,
      contentPath: contentPath ?? this.contentPath,
      byteSize: byteSize ?? this.byteSize,
      anchorIndex: anchorIndex ?? this.anchorIndex,
      anchorOffset: anchorOffset ?? this.anchorOffset,
      active: active ?? this.active,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (entryId.present) {
      map['entry_id'] = Variable<String>(entryId.value);
    }
    if (locationUrl.present) {
      map['location_url'] = Variable<String>(locationUrl.value);
    }
    if (sourceName.present) {
      map['source_name'] = Variable<String>(sourceName.value);
    }
    if (sourceHost.present) {
      map['source_host'] = Variable<String>(sourceHost.value);
    }
    if (sourceLanguage.present) {
      map['source_language'] = Variable<String>(sourceLanguage.value);
    }
    if (capturedAt.present) {
      map['captured_at'] = Variable<DateTime>(capturedAt.value);
    }
    if (artifactFormat.present) {
      map['artifact_format'] = Variable<String>(artifactFormat.value);
    }
    if (contentPath.present) {
      map['content_path'] = Variable<String>(contentPath.value);
    }
    if (byteSize.present) {
      map['byte_size'] = Variable<int>(byteSize.value);
    }
    if (anchorIndex.present) {
      map['anchor_index'] = Variable<int>(anchorIndex.value);
    }
    if (anchorOffset.present) {
      map['anchor_offset'] = Variable<double>(anchorOffset.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OfflineCopiesCompanion(')
          ..write('id: $id, ')
          ..write('entryId: $entryId, ')
          ..write('locationUrl: $locationUrl, ')
          ..write('sourceName: $sourceName, ')
          ..write('sourceHost: $sourceHost, ')
          ..write('sourceLanguage: $sourceLanguage, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('artifactFormat: $artifactFormat, ')
          ..write('contentPath: $contentPath, ')
          ..write('byteSize: $byteSize, ')
          ..write('anchorIndex: $anchorIndex, ')
          ..write('anchorOffset: $anchorOffset, ')
          ..write('active: $active, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SaveQueueTable extends SaveQueue
    with TableInfo<$SaveQueueTable, SaveTaskRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SaveQueueTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entryIdMeta = const VerificationMeta(
    'entryId',
  );
  @override
  late final GeneratedColumn<String> entryId = GeneratedColumn<String>(
    'entry_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _locationIdMeta = const VerificationMeta(
    'locationId',
  );
  @override
  late final GeneratedColumn<String> locationId = GeneratedColumn<String>(
    'location_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _locationUrlMeta = const VerificationMeta(
    'locationUrl',
  );
  @override
  late final GeneratedColumn<String> locationUrl = GeneratedColumn<String>(
    'location_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _captureModeMeta = const VerificationMeta(
    'captureMode',
  );
  @override
  late final GeneratedColumn<String> captureMode = GeneratedColumn<String>(
    'capture_mode',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _captureModeIsUserSetMeta =
      const VerificationMeta('captureModeIsUserSet');
  @override
  late final GeneratedColumn<bool> captureModeIsUserSet = GeneratedColumn<bool>(
    'capture_mode_is_user_set',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("capture_mode_is_user_set" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('queued'),
  );
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
    'origin',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('queue'),
  );
  static const VerificationMeta _outcomeMeta = const VerificationMeta(
    'outcome',
  );
  @override
  late final GeneratedColumn<String> outcome = GeneratedColumn<String>(
    'outcome',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stopReasonMeta = const VerificationMeta(
    'stopReason',
  );
  @override
  late final GeneratedColumn<String> stopReason = GeneratedColumn<String>(
    'stop_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _orderIndexMeta = const VerificationMeta(
    'orderIndex',
  );
  @override
  late final GeneratedColumn<int> orderIndex = GeneratedColumn<int>(
    'order_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _queuedAtMeta = const VerificationMeta(
    'queuedAt',
  );
  @override
  late final GeneratedColumn<DateTime> queuedAt = GeneratedColumn<DateTime>(
    'queued_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _finishedAtMeta = const VerificationMeta(
    'finishedAt',
  );
  @override
  late final GeneratedColumn<DateTime> finishedAt = GeneratedColumn<DateTime>(
    'finished_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    entryId,
    locationId,
    locationUrl,
    captureMode,
    captureModeIsUserSet,
    state,
    origin,
    outcome,
    lastError,
    stopReason,
    orderIndex,
    queuedAt,
    startedAt,
    finishedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'save_queue';
  @override
  VerificationContext validateIntegrity(
    Insertable<SaveTaskRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('entry_id')) {
      context.handle(
        _entryIdMeta,
        entryId.isAcceptableOrUnknown(data['entry_id']!, _entryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entryIdMeta);
    }
    if (data.containsKey('location_id')) {
      context.handle(
        _locationIdMeta,
        locationId.isAcceptableOrUnknown(data['location_id']!, _locationIdMeta),
      );
    }
    if (data.containsKey('location_url')) {
      context.handle(
        _locationUrlMeta,
        locationUrl.isAcceptableOrUnknown(
          data['location_url']!,
          _locationUrlMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_locationUrlMeta);
    }
    if (data.containsKey('capture_mode')) {
      context.handle(
        _captureModeMeta,
        captureMode.isAcceptableOrUnknown(
          data['capture_mode']!,
          _captureModeMeta,
        ),
      );
    }
    if (data.containsKey('capture_mode_is_user_set')) {
      context.handle(
        _captureModeIsUserSetMeta,
        captureModeIsUserSet.isAcceptableOrUnknown(
          data['capture_mode_is_user_set']!,
          _captureModeIsUserSetMeta,
        ),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('origin')) {
      context.handle(
        _originMeta,
        origin.isAcceptableOrUnknown(data['origin']!, _originMeta),
      );
    }
    if (data.containsKey('outcome')) {
      context.handle(
        _outcomeMeta,
        outcome.isAcceptableOrUnknown(data['outcome']!, _outcomeMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('stop_reason')) {
      context.handle(
        _stopReasonMeta,
        stopReason.isAcceptableOrUnknown(data['stop_reason']!, _stopReasonMeta),
      );
    }
    if (data.containsKey('order_index')) {
      context.handle(
        _orderIndexMeta,
        orderIndex.isAcceptableOrUnknown(data['order_index']!, _orderIndexMeta),
      );
    }
    if (data.containsKey('queued_at')) {
      context.handle(
        _queuedAtMeta,
        queuedAt.isAcceptableOrUnknown(data['queued_at']!, _queuedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_queuedAtMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    }
    if (data.containsKey('finished_at')) {
      context.handle(
        _finishedAtMeta,
        finishedAt.isAcceptableOrUnknown(data['finished_at']!, _finishedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SaveTaskRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SaveTaskRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      entryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entry_id'],
      )!,
      locationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location_id'],
      ),
      locationUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location_url'],
      )!,
      captureMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}capture_mode'],
      ),
      captureModeIsUserSet: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}capture_mode_is_user_set'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      origin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin'],
      )!,
      outcome: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}outcome'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      stopReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stop_reason'],
      ),
      orderIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}order_index'],
      )!,
      queuedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}queued_at'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      ),
      finishedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}finished_at'],
      ),
    );
  }

  @override
  $SaveQueueTable createAlias(String alias) {
    return $SaveQueueTable(attachedDatabase, alias);
  }
}

class SaveTaskRow extends DataClass implements Insertable<SaveTaskRow> {
  final String id;
  final String entryId;
  final String? locationId;
  final String locationUrl;

  /// `CaptureMode.name`, or null for a task queued before a mode was chosen —
  /// which means "decide from the settled page", not "assume one".
  final String? captureMode;
  final bool captureModeIsUserSet;

  /// queued | running | completed | failed | cancelled
  final String state;

  /// `queue` | `direct` — queued work, or the record of a save started
  /// straight from the Browser. A `direct` row is only ever terminal.
  final String origin;
  final String? outcome;
  final String? lastError;

  /// `StopReason.name`, when a named condition ended it.
  final String? stopReason;
  final int orderIndex;
  final DateTime queuedAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  const SaveTaskRow({
    required this.id,
    required this.entryId,
    this.locationId,
    required this.locationUrl,
    this.captureMode,
    required this.captureModeIsUserSet,
    required this.state,
    required this.origin,
    this.outcome,
    this.lastError,
    this.stopReason,
    required this.orderIndex,
    required this.queuedAt,
    this.startedAt,
    this.finishedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['entry_id'] = Variable<String>(entryId);
    if (!nullToAbsent || locationId != null) {
      map['location_id'] = Variable<String>(locationId);
    }
    map['location_url'] = Variable<String>(locationUrl);
    if (!nullToAbsent || captureMode != null) {
      map['capture_mode'] = Variable<String>(captureMode);
    }
    map['capture_mode_is_user_set'] = Variable<bool>(captureModeIsUserSet);
    map['state'] = Variable<String>(state);
    map['origin'] = Variable<String>(origin);
    if (!nullToAbsent || outcome != null) {
      map['outcome'] = Variable<String>(outcome);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    if (!nullToAbsent || stopReason != null) {
      map['stop_reason'] = Variable<String>(stopReason);
    }
    map['order_index'] = Variable<int>(orderIndex);
    map['queued_at'] = Variable<DateTime>(queuedAt);
    if (!nullToAbsent || startedAt != null) {
      map['started_at'] = Variable<DateTime>(startedAt);
    }
    if (!nullToAbsent || finishedAt != null) {
      map['finished_at'] = Variable<DateTime>(finishedAt);
    }
    return map;
  }

  SaveQueueCompanion toCompanion(bool nullToAbsent) {
    return SaveQueueCompanion(
      id: Value(id),
      entryId: Value(entryId),
      locationId: locationId == null && nullToAbsent
          ? const Value.absent()
          : Value(locationId),
      locationUrl: Value(locationUrl),
      captureMode: captureMode == null && nullToAbsent
          ? const Value.absent()
          : Value(captureMode),
      captureModeIsUserSet: Value(captureModeIsUserSet),
      state: Value(state),
      origin: Value(origin),
      outcome: outcome == null && nullToAbsent
          ? const Value.absent()
          : Value(outcome),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      stopReason: stopReason == null && nullToAbsent
          ? const Value.absent()
          : Value(stopReason),
      orderIndex: Value(orderIndex),
      queuedAt: Value(queuedAt),
      startedAt: startedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(startedAt),
      finishedAt: finishedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(finishedAt),
    );
  }

  factory SaveTaskRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SaveTaskRow(
      id: serializer.fromJson<String>(json['id']),
      entryId: serializer.fromJson<String>(json['entryId']),
      locationId: serializer.fromJson<String?>(json['locationId']),
      locationUrl: serializer.fromJson<String>(json['locationUrl']),
      captureMode: serializer.fromJson<String?>(json['captureMode']),
      captureModeIsUserSet: serializer.fromJson<bool>(
        json['captureModeIsUserSet'],
      ),
      state: serializer.fromJson<String>(json['state']),
      origin: serializer.fromJson<String>(json['origin']),
      outcome: serializer.fromJson<String?>(json['outcome']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      stopReason: serializer.fromJson<String?>(json['stopReason']),
      orderIndex: serializer.fromJson<int>(json['orderIndex']),
      queuedAt: serializer.fromJson<DateTime>(json['queuedAt']),
      startedAt: serializer.fromJson<DateTime?>(json['startedAt']),
      finishedAt: serializer.fromJson<DateTime?>(json['finishedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'entryId': serializer.toJson<String>(entryId),
      'locationId': serializer.toJson<String?>(locationId),
      'locationUrl': serializer.toJson<String>(locationUrl),
      'captureMode': serializer.toJson<String?>(captureMode),
      'captureModeIsUserSet': serializer.toJson<bool>(captureModeIsUserSet),
      'state': serializer.toJson<String>(state),
      'origin': serializer.toJson<String>(origin),
      'outcome': serializer.toJson<String?>(outcome),
      'lastError': serializer.toJson<String?>(lastError),
      'stopReason': serializer.toJson<String?>(stopReason),
      'orderIndex': serializer.toJson<int>(orderIndex),
      'queuedAt': serializer.toJson<DateTime>(queuedAt),
      'startedAt': serializer.toJson<DateTime?>(startedAt),
      'finishedAt': serializer.toJson<DateTime?>(finishedAt),
    };
  }

  SaveTaskRow copyWith({
    String? id,
    String? entryId,
    Value<String?> locationId = const Value.absent(),
    String? locationUrl,
    Value<String?> captureMode = const Value.absent(),
    bool? captureModeIsUserSet,
    String? state,
    String? origin,
    Value<String?> outcome = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
    Value<String?> stopReason = const Value.absent(),
    int? orderIndex,
    DateTime? queuedAt,
    Value<DateTime?> startedAt = const Value.absent(),
    Value<DateTime?> finishedAt = const Value.absent(),
  }) => SaveTaskRow(
    id: id ?? this.id,
    entryId: entryId ?? this.entryId,
    locationId: locationId.present ? locationId.value : this.locationId,
    locationUrl: locationUrl ?? this.locationUrl,
    captureMode: captureMode.present ? captureMode.value : this.captureMode,
    captureModeIsUserSet: captureModeIsUserSet ?? this.captureModeIsUserSet,
    state: state ?? this.state,
    origin: origin ?? this.origin,
    outcome: outcome.present ? outcome.value : this.outcome,
    lastError: lastError.present ? lastError.value : this.lastError,
    stopReason: stopReason.present ? stopReason.value : this.stopReason,
    orderIndex: orderIndex ?? this.orderIndex,
    queuedAt: queuedAt ?? this.queuedAt,
    startedAt: startedAt.present ? startedAt.value : this.startedAt,
    finishedAt: finishedAt.present ? finishedAt.value : this.finishedAt,
  );
  SaveTaskRow copyWithCompanion(SaveQueueCompanion data) {
    return SaveTaskRow(
      id: data.id.present ? data.id.value : this.id,
      entryId: data.entryId.present ? data.entryId.value : this.entryId,
      locationId: data.locationId.present
          ? data.locationId.value
          : this.locationId,
      locationUrl: data.locationUrl.present
          ? data.locationUrl.value
          : this.locationUrl,
      captureMode: data.captureMode.present
          ? data.captureMode.value
          : this.captureMode,
      captureModeIsUserSet: data.captureModeIsUserSet.present
          ? data.captureModeIsUserSet.value
          : this.captureModeIsUserSet,
      state: data.state.present ? data.state.value : this.state,
      origin: data.origin.present ? data.origin.value : this.origin,
      outcome: data.outcome.present ? data.outcome.value : this.outcome,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      stopReason: data.stopReason.present
          ? data.stopReason.value
          : this.stopReason,
      orderIndex: data.orderIndex.present
          ? data.orderIndex.value
          : this.orderIndex,
      queuedAt: data.queuedAt.present ? data.queuedAt.value : this.queuedAt,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      finishedAt: data.finishedAt.present
          ? data.finishedAt.value
          : this.finishedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SaveTaskRow(')
          ..write('id: $id, ')
          ..write('entryId: $entryId, ')
          ..write('locationId: $locationId, ')
          ..write('locationUrl: $locationUrl, ')
          ..write('captureMode: $captureMode, ')
          ..write('captureModeIsUserSet: $captureModeIsUserSet, ')
          ..write('state: $state, ')
          ..write('origin: $origin, ')
          ..write('outcome: $outcome, ')
          ..write('lastError: $lastError, ')
          ..write('stopReason: $stopReason, ')
          ..write('orderIndex: $orderIndex, ')
          ..write('queuedAt: $queuedAt, ')
          ..write('startedAt: $startedAt, ')
          ..write('finishedAt: $finishedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    entryId,
    locationId,
    locationUrl,
    captureMode,
    captureModeIsUserSet,
    state,
    origin,
    outcome,
    lastError,
    stopReason,
    orderIndex,
    queuedAt,
    startedAt,
    finishedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SaveTaskRow &&
          other.id == this.id &&
          other.entryId == this.entryId &&
          other.locationId == this.locationId &&
          other.locationUrl == this.locationUrl &&
          other.captureMode == this.captureMode &&
          other.captureModeIsUserSet == this.captureModeIsUserSet &&
          other.state == this.state &&
          other.origin == this.origin &&
          other.outcome == this.outcome &&
          other.lastError == this.lastError &&
          other.stopReason == this.stopReason &&
          other.orderIndex == this.orderIndex &&
          other.queuedAt == this.queuedAt &&
          other.startedAt == this.startedAt &&
          other.finishedAt == this.finishedAt);
}

class SaveQueueCompanion extends UpdateCompanion<SaveTaskRow> {
  final Value<String> id;
  final Value<String> entryId;
  final Value<String?> locationId;
  final Value<String> locationUrl;
  final Value<String?> captureMode;
  final Value<bool> captureModeIsUserSet;
  final Value<String> state;
  final Value<String> origin;
  final Value<String?> outcome;
  final Value<String?> lastError;
  final Value<String?> stopReason;
  final Value<int> orderIndex;
  final Value<DateTime> queuedAt;
  final Value<DateTime?> startedAt;
  final Value<DateTime?> finishedAt;
  final Value<int> rowid;
  const SaveQueueCompanion({
    this.id = const Value.absent(),
    this.entryId = const Value.absent(),
    this.locationId = const Value.absent(),
    this.locationUrl = const Value.absent(),
    this.captureMode = const Value.absent(),
    this.captureModeIsUserSet = const Value.absent(),
    this.state = const Value.absent(),
    this.origin = const Value.absent(),
    this.outcome = const Value.absent(),
    this.lastError = const Value.absent(),
    this.stopReason = const Value.absent(),
    this.orderIndex = const Value.absent(),
    this.queuedAt = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.finishedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SaveQueueCompanion.insert({
    required String id,
    required String entryId,
    this.locationId = const Value.absent(),
    required String locationUrl,
    this.captureMode = const Value.absent(),
    this.captureModeIsUserSet = const Value.absent(),
    this.state = const Value.absent(),
    this.origin = const Value.absent(),
    this.outcome = const Value.absent(),
    this.lastError = const Value.absent(),
    this.stopReason = const Value.absent(),
    this.orderIndex = const Value.absent(),
    required DateTime queuedAt,
    this.startedAt = const Value.absent(),
    this.finishedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       entryId = Value(entryId),
       locationUrl = Value(locationUrl),
       queuedAt = Value(queuedAt);
  static Insertable<SaveTaskRow> custom({
    Expression<String>? id,
    Expression<String>? entryId,
    Expression<String>? locationId,
    Expression<String>? locationUrl,
    Expression<String>? captureMode,
    Expression<bool>? captureModeIsUserSet,
    Expression<String>? state,
    Expression<String>? origin,
    Expression<String>? outcome,
    Expression<String>? lastError,
    Expression<String>? stopReason,
    Expression<int>? orderIndex,
    Expression<DateTime>? queuedAt,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? finishedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entryId != null) 'entry_id': entryId,
      if (locationId != null) 'location_id': locationId,
      if (locationUrl != null) 'location_url': locationUrl,
      if (captureMode != null) 'capture_mode': captureMode,
      if (captureModeIsUserSet != null)
        'capture_mode_is_user_set': captureModeIsUserSet,
      if (state != null) 'state': state,
      if (origin != null) 'origin': origin,
      if (outcome != null) 'outcome': outcome,
      if (lastError != null) 'last_error': lastError,
      if (stopReason != null) 'stop_reason': stopReason,
      if (orderIndex != null) 'order_index': orderIndex,
      if (queuedAt != null) 'queued_at': queuedAt,
      if (startedAt != null) 'started_at': startedAt,
      if (finishedAt != null) 'finished_at': finishedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SaveQueueCompanion copyWith({
    Value<String>? id,
    Value<String>? entryId,
    Value<String?>? locationId,
    Value<String>? locationUrl,
    Value<String?>? captureMode,
    Value<bool>? captureModeIsUserSet,
    Value<String>? state,
    Value<String>? origin,
    Value<String?>? outcome,
    Value<String?>? lastError,
    Value<String?>? stopReason,
    Value<int>? orderIndex,
    Value<DateTime>? queuedAt,
    Value<DateTime?>? startedAt,
    Value<DateTime?>? finishedAt,
    Value<int>? rowid,
  }) {
    return SaveQueueCompanion(
      id: id ?? this.id,
      entryId: entryId ?? this.entryId,
      locationId: locationId ?? this.locationId,
      locationUrl: locationUrl ?? this.locationUrl,
      captureMode: captureMode ?? this.captureMode,
      captureModeIsUserSet: captureModeIsUserSet ?? this.captureModeIsUserSet,
      state: state ?? this.state,
      origin: origin ?? this.origin,
      outcome: outcome ?? this.outcome,
      lastError: lastError ?? this.lastError,
      stopReason: stopReason ?? this.stopReason,
      orderIndex: orderIndex ?? this.orderIndex,
      queuedAt: queuedAt ?? this.queuedAt,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (entryId.present) {
      map['entry_id'] = Variable<String>(entryId.value);
    }
    if (locationId.present) {
      map['location_id'] = Variable<String>(locationId.value);
    }
    if (locationUrl.present) {
      map['location_url'] = Variable<String>(locationUrl.value);
    }
    if (captureMode.present) {
      map['capture_mode'] = Variable<String>(captureMode.value);
    }
    if (captureModeIsUserSet.present) {
      map['capture_mode_is_user_set'] = Variable<bool>(
        captureModeIsUserSet.value,
      );
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    if (outcome.present) {
      map['outcome'] = Variable<String>(outcome.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (stopReason.present) {
      map['stop_reason'] = Variable<String>(stopReason.value);
    }
    if (orderIndex.present) {
      map['order_index'] = Variable<int>(orderIndex.value);
    }
    if (queuedAt.present) {
      map['queued_at'] = Variable<DateTime>(queuedAt.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (finishedAt.present) {
      map['finished_at'] = Variable<DateTime>(finishedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SaveQueueCompanion(')
          ..write('id: $id, ')
          ..write('entryId: $entryId, ')
          ..write('locationId: $locationId, ')
          ..write('locationUrl: $locationUrl, ')
          ..write('captureMode: $captureMode, ')
          ..write('captureModeIsUserSet: $captureModeIsUserSet, ')
          ..write('state: $state, ')
          ..write('origin: $origin, ')
          ..write('outcome: $outcome, ')
          ..write('lastError: $lastError, ')
          ..write('stopReason: $stopReason, ')
          ..write('orderIndex: $orderIndex, ')
          ..write('queuedAt: $queuedAt, ')
          ..write('startedAt: $startedAt, ')
          ..write('finishedAt: $finishedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HistoryTable extends History with TableInfo<$HistoryTable, HistoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _urlKeyMeta = const VerificationMeta('urlKey');
  @override
  late final GeneratedColumn<String> urlKey = GeneratedColumn<String>(
    'url_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hostMeta = const VerificationMeta('host');
  @override
  late final GeneratedColumn<String> host = GeneratedColumn<String>(
    'host',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('manual'),
  );
  static const VerificationMeta _finalUrlMeta = const VerificationMeta(
    'finalUrl',
  );
  @override
  late final GeneratedColumn<String> finalUrl = GeneratedColumn<String>(
    'final_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completedMeta = const VerificationMeta(
    'completed',
  );
  @override
  late final GeneratedColumn<bool> completed = GeneratedColumn<bool>(
    'completed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("completed" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _visitedAtMeta = const VerificationMeta(
    'visitedAt',
  );
  @override
  late final GeneratedColumn<DateTime> visitedAt = GeneratedColumn<DateTime>(
    'visited_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    url,
    urlKey,
    host,
    title,
    source,
    finalUrl,
    completed,
    visitedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'history';
  @override
  VerificationContext validateIntegrity(
    Insertable<HistoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('url_key')) {
      context.handle(
        _urlKeyMeta,
        urlKey.isAcceptableOrUnknown(data['url_key']!, _urlKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_urlKeyMeta);
    }
    if (data.containsKey('host')) {
      context.handle(
        _hostMeta,
        host.isAcceptableOrUnknown(data['host']!, _hostMeta),
      );
    } else if (isInserting) {
      context.missing(_hostMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('final_url')) {
      context.handle(
        _finalUrlMeta,
        finalUrl.isAcceptableOrUnknown(data['final_url']!, _finalUrlMeta),
      );
    }
    if (data.containsKey('completed')) {
      context.handle(
        _completedMeta,
        completed.isAcceptableOrUnknown(data['completed']!, _completedMeta),
      );
    }
    if (data.containsKey('visited_at')) {
      context.handle(
        _visitedAtMeta,
        visitedAt.isAcceptableOrUnknown(data['visited_at']!, _visitedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_visitedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  HistoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HistoryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      urlKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url_key'],
      )!,
      host: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      finalUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}final_url'],
      ),
      completed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}completed'],
      )!,
      visitedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}visited_at'],
      )!,
    );
  }

  @override
  $HistoryTable createAlias(String alias) {
    return $HistoryTable(attachedDatabase, alias);
  }
}

class HistoryRow extends DataClass implements Insertable<HistoryRow> {
  final String id;
  final String url;
  final String urlKey;
  final String host;
  final String title;
  final String source;
  final String? finalUrl;
  final bool completed;
  final DateTime visitedAt;
  const HistoryRow({
    required this.id,
    required this.url,
    required this.urlKey,
    required this.host,
    required this.title,
    required this.source,
    this.finalUrl,
    required this.completed,
    required this.visitedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['url'] = Variable<String>(url);
    map['url_key'] = Variable<String>(urlKey);
    map['host'] = Variable<String>(host);
    map['title'] = Variable<String>(title);
    map['source'] = Variable<String>(source);
    if (!nullToAbsent || finalUrl != null) {
      map['final_url'] = Variable<String>(finalUrl);
    }
    map['completed'] = Variable<bool>(completed);
    map['visited_at'] = Variable<DateTime>(visitedAt);
    return map;
  }

  HistoryCompanion toCompanion(bool nullToAbsent) {
    return HistoryCompanion(
      id: Value(id),
      url: Value(url),
      urlKey: Value(urlKey),
      host: Value(host),
      title: Value(title),
      source: Value(source),
      finalUrl: finalUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(finalUrl),
      completed: Value(completed),
      visitedAt: Value(visitedAt),
    );
  }

  factory HistoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HistoryRow(
      id: serializer.fromJson<String>(json['id']),
      url: serializer.fromJson<String>(json['url']),
      urlKey: serializer.fromJson<String>(json['urlKey']),
      host: serializer.fromJson<String>(json['host']),
      title: serializer.fromJson<String>(json['title']),
      source: serializer.fromJson<String>(json['source']),
      finalUrl: serializer.fromJson<String?>(json['finalUrl']),
      completed: serializer.fromJson<bool>(json['completed']),
      visitedAt: serializer.fromJson<DateTime>(json['visitedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'url': serializer.toJson<String>(url),
      'urlKey': serializer.toJson<String>(urlKey),
      'host': serializer.toJson<String>(host),
      'title': serializer.toJson<String>(title),
      'source': serializer.toJson<String>(source),
      'finalUrl': serializer.toJson<String?>(finalUrl),
      'completed': serializer.toJson<bool>(completed),
      'visitedAt': serializer.toJson<DateTime>(visitedAt),
    };
  }

  HistoryRow copyWith({
    String? id,
    String? url,
    String? urlKey,
    String? host,
    String? title,
    String? source,
    Value<String?> finalUrl = const Value.absent(),
    bool? completed,
    DateTime? visitedAt,
  }) => HistoryRow(
    id: id ?? this.id,
    url: url ?? this.url,
    urlKey: urlKey ?? this.urlKey,
    host: host ?? this.host,
    title: title ?? this.title,
    source: source ?? this.source,
    finalUrl: finalUrl.present ? finalUrl.value : this.finalUrl,
    completed: completed ?? this.completed,
    visitedAt: visitedAt ?? this.visitedAt,
  );
  HistoryRow copyWithCompanion(HistoryCompanion data) {
    return HistoryRow(
      id: data.id.present ? data.id.value : this.id,
      url: data.url.present ? data.url.value : this.url,
      urlKey: data.urlKey.present ? data.urlKey.value : this.urlKey,
      host: data.host.present ? data.host.value : this.host,
      title: data.title.present ? data.title.value : this.title,
      source: data.source.present ? data.source.value : this.source,
      finalUrl: data.finalUrl.present ? data.finalUrl.value : this.finalUrl,
      completed: data.completed.present ? data.completed.value : this.completed,
      visitedAt: data.visitedAt.present ? data.visitedAt.value : this.visitedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HistoryRow(')
          ..write('id: $id, ')
          ..write('url: $url, ')
          ..write('urlKey: $urlKey, ')
          ..write('host: $host, ')
          ..write('title: $title, ')
          ..write('source: $source, ')
          ..write('finalUrl: $finalUrl, ')
          ..write('completed: $completed, ')
          ..write('visitedAt: $visitedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    url,
    urlKey,
    host,
    title,
    source,
    finalUrl,
    completed,
    visitedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HistoryRow &&
          other.id == this.id &&
          other.url == this.url &&
          other.urlKey == this.urlKey &&
          other.host == this.host &&
          other.title == this.title &&
          other.source == this.source &&
          other.finalUrl == this.finalUrl &&
          other.completed == this.completed &&
          other.visitedAt == this.visitedAt);
}

class HistoryCompanion extends UpdateCompanion<HistoryRow> {
  final Value<String> id;
  final Value<String> url;
  final Value<String> urlKey;
  final Value<String> host;
  final Value<String> title;
  final Value<String> source;
  final Value<String?> finalUrl;
  final Value<bool> completed;
  final Value<DateTime> visitedAt;
  final Value<int> rowid;
  const HistoryCompanion({
    this.id = const Value.absent(),
    this.url = const Value.absent(),
    this.urlKey = const Value.absent(),
    this.host = const Value.absent(),
    this.title = const Value.absent(),
    this.source = const Value.absent(),
    this.finalUrl = const Value.absent(),
    this.completed = const Value.absent(),
    this.visitedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HistoryCompanion.insert({
    required String id,
    required String url,
    required String urlKey,
    required String host,
    required String title,
    this.source = const Value.absent(),
    this.finalUrl = const Value.absent(),
    this.completed = const Value.absent(),
    required DateTime visitedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       url = Value(url),
       urlKey = Value(urlKey),
       host = Value(host),
       title = Value(title),
       visitedAt = Value(visitedAt);
  static Insertable<HistoryRow> custom({
    Expression<String>? id,
    Expression<String>? url,
    Expression<String>? urlKey,
    Expression<String>? host,
    Expression<String>? title,
    Expression<String>? source,
    Expression<String>? finalUrl,
    Expression<bool>? completed,
    Expression<DateTime>? visitedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (url != null) 'url': url,
      if (urlKey != null) 'url_key': urlKey,
      if (host != null) 'host': host,
      if (title != null) 'title': title,
      if (source != null) 'source': source,
      if (finalUrl != null) 'final_url': finalUrl,
      if (completed != null) 'completed': completed,
      if (visitedAt != null) 'visited_at': visitedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HistoryCompanion copyWith({
    Value<String>? id,
    Value<String>? url,
    Value<String>? urlKey,
    Value<String>? host,
    Value<String>? title,
    Value<String>? source,
    Value<String?>? finalUrl,
    Value<bool>? completed,
    Value<DateTime>? visitedAt,
    Value<int>? rowid,
  }) {
    return HistoryCompanion(
      id: id ?? this.id,
      url: url ?? this.url,
      urlKey: urlKey ?? this.urlKey,
      host: host ?? this.host,
      title: title ?? this.title,
      source: source ?? this.source,
      finalUrl: finalUrl ?? this.finalUrl,
      completed: completed ?? this.completed,
      visitedAt: visitedAt ?? this.visitedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (urlKey.present) {
      map['url_key'] = Variable<String>(urlKey.value);
    }
    if (host.present) {
      map['host'] = Variable<String>(host.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (finalUrl.present) {
      map['final_url'] = Variable<String>(finalUrl.value);
    }
    if (completed.present) {
      map['completed'] = Variable<bool>(completed.value);
    }
    if (visitedAt.present) {
      map['visited_at'] = Variable<DateTime>(visitedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HistoryCompanion(')
          ..write('id: $id, ')
          ..write('url: $url, ')
          ..write('urlKey: $urlKey, ')
          ..write('host: $host, ')
          ..write('title: $title, ')
          ..write('source: $source, ')
          ..write('finalUrl: $finalUrl, ')
          ..write('completed: $completed, ')
          ..write('visitedAt: $visitedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxTable extends Outbox with TableInfo<$OutboxTable, OutboxRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _opIdMeta = const VerificationMeta('opId');
  @override
  late final GeneratedColumn<int> opId = GeneratedColumn<int>(
    'op_id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _mutationIdMeta = const VerificationMeta(
    'mutationId',
  );
  @override
  late final GeneratedColumn<String> mutationId = GeneratedColumn<String>(
    'mutation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _entityKindMeta = const VerificationMeta(
    'entityKind',
  );
  @override
  late final GeneratedColumn<String> entityKind = GeneratedColumn<String>(
    'entity_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _opMeta = const VerificationMeta('op');
  @override
  late final GeneratedColumn<String> op = GeneratedColumn<String>(
    'op',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    opId,
    mutationId,
    entityKind,
    entityId,
    op,
    payload,
    createdAt,
    attempts,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('op_id')) {
      context.handle(
        _opIdMeta,
        opId.isAcceptableOrUnknown(data['op_id']!, _opIdMeta),
      );
    }
    if (data.containsKey('mutation_id')) {
      context.handle(
        _mutationIdMeta,
        mutationId.isAcceptableOrUnknown(data['mutation_id']!, _mutationIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mutationIdMeta);
    }
    if (data.containsKey('entity_kind')) {
      context.handle(
        _entityKindMeta,
        entityKind.isAcceptableOrUnknown(data['entity_kind']!, _entityKindMeta),
      );
    } else if (isInserting) {
      context.missing(_entityKindMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('op')) {
      context.handle(_opMeta, op.isAcceptableOrUnknown(data['op']!, _opMeta));
    } else if (isInserting) {
      context.missing(_opMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {opId};
  @override
  OutboxRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxRow(
      opId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}op_id'],
      )!,
      mutationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mutation_id'],
      )!,
      entityKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_kind'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      op: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}op'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
    );
  }

  @override
  $OutboxTable createAlias(String alias) {
    return $OutboxTable(attachedDatabase, alias);
  }
}

class OutboxRow extends DataClass implements Insertable<OutboxRow> {
  final int opId;
  final String mutationId;
  final String entityKind;
  final String entityId;
  final String op;
  final String payload;
  final DateTime createdAt;
  final int attempts;
  final String? lastError;
  const OutboxRow({
    required this.opId,
    required this.mutationId,
    required this.entityKind,
    required this.entityId,
    required this.op,
    required this.payload,
    required this.createdAt,
    required this.attempts,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['op_id'] = Variable<int>(opId);
    map['mutation_id'] = Variable<String>(mutationId);
    map['entity_kind'] = Variable<String>(entityKind);
    map['entity_id'] = Variable<String>(entityId);
    map['op'] = Variable<String>(op);
    map['payload'] = Variable<String>(payload);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  OutboxCompanion toCompanion(bool nullToAbsent) {
    return OutboxCompanion(
      opId: Value(opId),
      mutationId: Value(mutationId),
      entityKind: Value(entityKind),
      entityId: Value(entityId),
      op: Value(op),
      payload: Value(payload),
      createdAt: Value(createdAt),
      attempts: Value(attempts),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory OutboxRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxRow(
      opId: serializer.fromJson<int>(json['opId']),
      mutationId: serializer.fromJson<String>(json['mutationId']),
      entityKind: serializer.fromJson<String>(json['entityKind']),
      entityId: serializer.fromJson<String>(json['entityId']),
      op: serializer.fromJson<String>(json['op']),
      payload: serializer.fromJson<String>(json['payload']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      attempts: serializer.fromJson<int>(json['attempts']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'opId': serializer.toJson<int>(opId),
      'mutationId': serializer.toJson<String>(mutationId),
      'entityKind': serializer.toJson<String>(entityKind),
      'entityId': serializer.toJson<String>(entityId),
      'op': serializer.toJson<String>(op),
      'payload': serializer.toJson<String>(payload),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'attempts': serializer.toJson<int>(attempts),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  OutboxRow copyWith({
    int? opId,
    String? mutationId,
    String? entityKind,
    String? entityId,
    String? op,
    String? payload,
    DateTime? createdAt,
    int? attempts,
    Value<String?> lastError = const Value.absent(),
  }) => OutboxRow(
    opId: opId ?? this.opId,
    mutationId: mutationId ?? this.mutationId,
    entityKind: entityKind ?? this.entityKind,
    entityId: entityId ?? this.entityId,
    op: op ?? this.op,
    payload: payload ?? this.payload,
    createdAt: createdAt ?? this.createdAt,
    attempts: attempts ?? this.attempts,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  OutboxRow copyWithCompanion(OutboxCompanion data) {
    return OutboxRow(
      opId: data.opId.present ? data.opId.value : this.opId,
      mutationId: data.mutationId.present
          ? data.mutationId.value
          : this.mutationId,
      entityKind: data.entityKind.present
          ? data.entityKind.value
          : this.entityKind,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      op: data.op.present ? data.op.value : this.op,
      payload: data.payload.present ? data.payload.value : this.payload,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxRow(')
          ..write('opId: $opId, ')
          ..write('mutationId: $mutationId, ')
          ..write('entityKind: $entityKind, ')
          ..write('entityId: $entityId, ')
          ..write('op: $op, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    opId,
    mutationId,
    entityKind,
    entityId,
    op,
    payload,
    createdAt,
    attempts,
    lastError,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxRow &&
          other.opId == this.opId &&
          other.mutationId == this.mutationId &&
          other.entityKind == this.entityKind &&
          other.entityId == this.entityId &&
          other.op == this.op &&
          other.payload == this.payload &&
          other.createdAt == this.createdAt &&
          other.attempts == this.attempts &&
          other.lastError == this.lastError);
}

class OutboxCompanion extends UpdateCompanion<OutboxRow> {
  final Value<int> opId;
  final Value<String> mutationId;
  final Value<String> entityKind;
  final Value<String> entityId;
  final Value<String> op;
  final Value<String> payload;
  final Value<DateTime> createdAt;
  final Value<int> attempts;
  final Value<String?> lastError;
  const OutboxCompanion({
    this.opId = const Value.absent(),
    this.mutationId = const Value.absent(),
    this.entityKind = const Value.absent(),
    this.entityId = const Value.absent(),
    this.op = const Value.absent(),
    this.payload = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
  });
  OutboxCompanion.insert({
    this.opId = const Value.absent(),
    required String mutationId,
    required String entityKind,
    required String entityId,
    required String op,
    required String payload,
    required DateTime createdAt,
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
  }) : mutationId = Value(mutationId),
       entityKind = Value(entityKind),
       entityId = Value(entityId),
       op = Value(op),
       payload = Value(payload),
       createdAt = Value(createdAt);
  static Insertable<OutboxRow> custom({
    Expression<int>? opId,
    Expression<String>? mutationId,
    Expression<String>? entityKind,
    Expression<String>? entityId,
    Expression<String>? op,
    Expression<String>? payload,
    Expression<DateTime>? createdAt,
    Expression<int>? attempts,
    Expression<String>? lastError,
  }) {
    return RawValuesInsertable({
      if (opId != null) 'op_id': opId,
      if (mutationId != null) 'mutation_id': mutationId,
      if (entityKind != null) 'entity_kind': entityKind,
      if (entityId != null) 'entity_id': entityId,
      if (op != null) 'op': op,
      if (payload != null) 'payload': payload,
      if (createdAt != null) 'created_at': createdAt,
      if (attempts != null) 'attempts': attempts,
      if (lastError != null) 'last_error': lastError,
    });
  }

  OutboxCompanion copyWith({
    Value<int>? opId,
    Value<String>? mutationId,
    Value<String>? entityKind,
    Value<String>? entityId,
    Value<String>? op,
    Value<String>? payload,
    Value<DateTime>? createdAt,
    Value<int>? attempts,
    Value<String?>? lastError,
  }) {
    return OutboxCompanion(
      opId: opId ?? this.opId,
      mutationId: mutationId ?? this.mutationId,
      entityKind: entityKind ?? this.entityKind,
      entityId: entityId ?? this.entityId,
      op: op ?? this.op,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (opId.present) {
      map['op_id'] = Variable<int>(opId.value);
    }
    if (mutationId.present) {
      map['mutation_id'] = Variable<String>(mutationId.value);
    }
    if (entityKind.present) {
      map['entity_kind'] = Variable<String>(entityKind.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (op.present) {
      map['op'] = Variable<String>(op.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxCompanion(')
          ..write('opId: $opId, ')
          ..write('mutationId: $mutationId, ')
          ..write('entityKind: $entityKind, ')
          ..write('entityId: $entityId, ')
          ..write('op: $op, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }
}

class $SyncStateTable extends SyncState
    with TableInfo<$SyncStateTable, SyncStateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cursorMeta = const VerificationMeta('cursor');
  @override
  late final GeneratedColumn<int> cursor = GeneratedColumn<int>(
    'cursor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastSuccessAtMeta = const VerificationMeta(
    'lastSuccessAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSuccessAt =
      GeneratedColumn<DateTime>(
        'last_success_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastAttemptAtMeta = const VerificationMeta(
    'lastAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastAttemptAt =
      GeneratedColumn<DateTime>(
        'last_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    cursor,
    lastSuccessAt,
    lastAttemptAt,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncStateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('cursor')) {
      context.handle(
        _cursorMeta,
        cursor.isAcceptableOrUnknown(data['cursor']!, _cursorMeta),
      );
    }
    if (data.containsKey('last_success_at')) {
      context.handle(
        _lastSuccessAtMeta,
        lastSuccessAt.isAcceptableOrUnknown(
          data['last_success_at']!,
          _lastSuccessAtMeta,
        ),
      );
    }
    if (data.containsKey('last_attempt_at')) {
      context.handle(
        _lastAttemptAtMeta,
        lastAttemptAt.isAcceptableOrUnknown(
          data['last_attempt_at']!,
          _lastAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncStateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncStateRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      cursor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cursor'],
      )!,
      lastSuccessAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_success_at'],
      ),
      lastAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_attempt_at'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
    );
  }

  @override
  $SyncStateTable createAlias(String alias) {
    return $SyncStateTable(attachedDatabase, alias);
  }
}

class SyncStateRow extends DataClass implements Insertable<SyncStateRow> {
  final int id;
  final int cursor;
  final DateTime? lastSuccessAt;
  final DateTime? lastAttemptAt;
  final String? lastError;
  const SyncStateRow({
    required this.id,
    required this.cursor,
    this.lastSuccessAt,
    this.lastAttemptAt,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['cursor'] = Variable<int>(cursor);
    if (!nullToAbsent || lastSuccessAt != null) {
      map['last_success_at'] = Variable<DateTime>(lastSuccessAt);
    }
    if (!nullToAbsent || lastAttemptAt != null) {
      map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  SyncStateCompanion toCompanion(bool nullToAbsent) {
    return SyncStateCompanion(
      id: Value(id),
      cursor: Value(cursor),
      lastSuccessAt: lastSuccessAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSuccessAt),
      lastAttemptAt: lastAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAttemptAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory SyncStateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncStateRow(
      id: serializer.fromJson<int>(json['id']),
      cursor: serializer.fromJson<int>(json['cursor']),
      lastSuccessAt: serializer.fromJson<DateTime?>(json['lastSuccessAt']),
      lastAttemptAt: serializer.fromJson<DateTime?>(json['lastAttemptAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'cursor': serializer.toJson<int>(cursor),
      'lastSuccessAt': serializer.toJson<DateTime?>(lastSuccessAt),
      'lastAttemptAt': serializer.toJson<DateTime?>(lastAttemptAt),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  SyncStateRow copyWith({
    int? id,
    int? cursor,
    Value<DateTime?> lastSuccessAt = const Value.absent(),
    Value<DateTime?> lastAttemptAt = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
  }) => SyncStateRow(
    id: id ?? this.id,
    cursor: cursor ?? this.cursor,
    lastSuccessAt: lastSuccessAt.present
        ? lastSuccessAt.value
        : this.lastSuccessAt,
    lastAttemptAt: lastAttemptAt.present
        ? lastAttemptAt.value
        : this.lastAttemptAt,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  SyncStateRow copyWithCompanion(SyncStateCompanion data) {
    return SyncStateRow(
      id: data.id.present ? data.id.value : this.id,
      cursor: data.cursor.present ? data.cursor.value : this.cursor,
      lastSuccessAt: data.lastSuccessAt.present
          ? data.lastSuccessAt.value
          : this.lastSuccessAt,
      lastAttemptAt: data.lastAttemptAt.present
          ? data.lastAttemptAt.value
          : this.lastAttemptAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateRow(')
          ..write('id: $id, ')
          ..write('cursor: $cursor, ')
          ..write('lastSuccessAt: $lastSuccessAt, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, cursor, lastSuccessAt, lastAttemptAt, lastError);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncStateRow &&
          other.id == this.id &&
          other.cursor == this.cursor &&
          other.lastSuccessAt == this.lastSuccessAt &&
          other.lastAttemptAt == this.lastAttemptAt &&
          other.lastError == this.lastError);
}

class SyncStateCompanion extends UpdateCompanion<SyncStateRow> {
  final Value<int> id;
  final Value<int> cursor;
  final Value<DateTime?> lastSuccessAt;
  final Value<DateTime?> lastAttemptAt;
  final Value<String?> lastError;
  const SyncStateCompanion({
    this.id = const Value.absent(),
    this.cursor = const Value.absent(),
    this.lastSuccessAt = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
  });
  SyncStateCompanion.insert({
    this.id = const Value.absent(),
    this.cursor = const Value.absent(),
    this.lastSuccessAt = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
  });
  static Insertable<SyncStateRow> custom({
    Expression<int>? id,
    Expression<int>? cursor,
    Expression<DateTime>? lastSuccessAt,
    Expression<DateTime>? lastAttemptAt,
    Expression<String>? lastError,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (cursor != null) 'cursor': cursor,
      if (lastSuccessAt != null) 'last_success_at': lastSuccessAt,
      if (lastAttemptAt != null) 'last_attempt_at': lastAttemptAt,
      if (lastError != null) 'last_error': lastError,
    });
  }

  SyncStateCompanion copyWith({
    Value<int>? id,
    Value<int>? cursor,
    Value<DateTime?>? lastSuccessAt,
    Value<DateTime?>? lastAttemptAt,
    Value<String?>? lastError,
  }) {
    return SyncStateCompanion(
      id: id ?? this.id,
      cursor: cursor ?? this.cursor,
      lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      lastError: lastError ?? this.lastError,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (cursor.present) {
      map['cursor'] = Variable<int>(cursor.value);
    }
    if (lastSuccessAt.present) {
      map['last_success_at'] = Variable<DateTime>(lastSuccessAt.value);
    }
    if (lastAttemptAt.present) {
      map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateCompanion(')
          ..write('id: $id, ')
          ..write('cursor: $cursor, ')
          ..write('lastSuccessAt: $lastSuccessAt, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }
}

class $PageHintsTable extends PageHints
    with TableInfo<$PageHintsTable, PageHintRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PageHintsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hostMeta = const VerificationMeta('host');
  @override
  late final GeneratedColumn<String> host = GeneratedColumn<String>(
    'host',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hintPathMeta = const VerificationMeta(
    'hintPath',
  );
  @override
  late final GeneratedColumn<String> hintPath = GeneratedColumn<String>(
    'hint_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _locatorJsonMeta = const VerificationMeta(
    'locatorJson',
  );
  @override
  late final GeneratedColumn<String> locatorJson = GeneratedColumn<String>(
    'locator_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _exampleSourceUrlMeta = const VerificationMeta(
    'exampleSourceUrl',
  );
  @override
  late final GeneratedColumn<String> exampleSourceUrl = GeneratedColumn<String>(
    'example_source_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _exampleTargetUrlMeta = const VerificationMeta(
    'exampleTargetUrl',
  );
  @override
  late final GeneratedColumn<String> exampleTargetUrl = GeneratedColumn<String>(
    'example_target_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sameHostOnlyMeta = const VerificationMeta(
    'sameHostOnly',
  );
  @override
  late final GeneratedColumn<bool> sameHostOnly = GeneratedColumn<bool>(
    'same_host_only',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("same_host_only" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastUsedAtMeta = const VerificationMeta(
    'lastUsedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastUsedAt = GeneratedColumn<DateTime>(
    'last_used_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _successCountMeta = const VerificationMeta(
    'successCount',
  );
  @override
  late final GeneratedColumn<int> successCount = GeneratedColumn<int>(
    'success_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _failureCountMeta = const VerificationMeta(
    'failureCount',
  );
  @override
  late final GeneratedColumn<int> failureCount = GeneratedColumn<int>(
    'failure_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    host,
    hintPath,
    scope,
    kind,
    locatorJson,
    exampleSourceUrl,
    exampleTargetUrl,
    sameHostOnly,
    createdAt,
    lastUsedAt,
    successCount,
    failureCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'page_hints';
  @override
  VerificationContext validateIntegrity(
    Insertable<PageHintRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('host')) {
      context.handle(
        _hostMeta,
        host.isAcceptableOrUnknown(data['host']!, _hostMeta),
      );
    } else if (isInserting) {
      context.missing(_hostMeta);
    }
    if (data.containsKey('hint_path')) {
      context.handle(
        _hintPathMeta,
        hintPath.isAcceptableOrUnknown(data['hint_path']!, _hintPathMeta),
      );
    }
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('locator_json')) {
      context.handle(
        _locatorJsonMeta,
        locatorJson.isAcceptableOrUnknown(
          data['locator_json']!,
          _locatorJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_locatorJsonMeta);
    }
    if (data.containsKey('example_source_url')) {
      context.handle(
        _exampleSourceUrlMeta,
        exampleSourceUrl.isAcceptableOrUnknown(
          data['example_source_url']!,
          _exampleSourceUrlMeta,
        ),
      );
    }
    if (data.containsKey('example_target_url')) {
      context.handle(
        _exampleTargetUrlMeta,
        exampleTargetUrl.isAcceptableOrUnknown(
          data['example_target_url']!,
          _exampleTargetUrlMeta,
        ),
      );
    }
    if (data.containsKey('same_host_only')) {
      context.handle(
        _sameHostOnlyMeta,
        sameHostOnly.isAcceptableOrUnknown(
          data['same_host_only']!,
          _sameHostOnlyMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('last_used_at')) {
      context.handle(
        _lastUsedAtMeta,
        lastUsedAt.isAcceptableOrUnknown(
          data['last_used_at']!,
          _lastUsedAtMeta,
        ),
      );
    }
    if (data.containsKey('success_count')) {
      context.handle(
        _successCountMeta,
        successCount.isAcceptableOrUnknown(
          data['success_count']!,
          _successCountMeta,
        ),
      );
    }
    if (data.containsKey('failure_count')) {
      context.handle(
        _failureCountMeta,
        failureCount.isAcceptableOrUnknown(
          data['failure_count']!,
          _failureCountMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PageHintRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PageHintRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      host: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host'],
      )!,
      hintPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hint_path'],
      ),
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      locatorJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}locator_json'],
      )!,
      exampleSourceUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}example_source_url'],
      ),
      exampleTargetUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}example_target_url'],
      ),
      sameHostOnly: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}same_host_only'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      lastUsedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_used_at'],
      ),
      successCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}success_count'],
      )!,
      failureCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}failure_count'],
      )!,
    );
  }

  @override
  $PageHintsTable createAlias(String alias) {
    return $PageHintsTable(attachedDatabase, alias);
  }
}

class PageHintRow extends DataClass implements Insertable<PageHintRow> {
  final String id;
  final String host;
  final String? hintPath;
  final String scope;
  final String kind;
  final String locatorJson;
  final String? exampleSourceUrl;
  final String? exampleTargetUrl;
  final bool sameHostOnly;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final int successCount;
  final int failureCount;
  const PageHintRow({
    required this.id,
    required this.host,
    this.hintPath,
    required this.scope,
    required this.kind,
    required this.locatorJson,
    this.exampleSourceUrl,
    this.exampleTargetUrl,
    required this.sameHostOnly,
    required this.createdAt,
    this.lastUsedAt,
    required this.successCount,
    required this.failureCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['host'] = Variable<String>(host);
    if (!nullToAbsent || hintPath != null) {
      map['hint_path'] = Variable<String>(hintPath);
    }
    map['scope'] = Variable<String>(scope);
    map['kind'] = Variable<String>(kind);
    map['locator_json'] = Variable<String>(locatorJson);
    if (!nullToAbsent || exampleSourceUrl != null) {
      map['example_source_url'] = Variable<String>(exampleSourceUrl);
    }
    if (!nullToAbsent || exampleTargetUrl != null) {
      map['example_target_url'] = Variable<String>(exampleTargetUrl);
    }
    map['same_host_only'] = Variable<bool>(sameHostOnly);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || lastUsedAt != null) {
      map['last_used_at'] = Variable<DateTime>(lastUsedAt);
    }
    map['success_count'] = Variable<int>(successCount);
    map['failure_count'] = Variable<int>(failureCount);
    return map;
  }

  PageHintsCompanion toCompanion(bool nullToAbsent) {
    return PageHintsCompanion(
      id: Value(id),
      host: Value(host),
      hintPath: hintPath == null && nullToAbsent
          ? const Value.absent()
          : Value(hintPath),
      scope: Value(scope),
      kind: Value(kind),
      locatorJson: Value(locatorJson),
      exampleSourceUrl: exampleSourceUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(exampleSourceUrl),
      exampleTargetUrl: exampleTargetUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(exampleTargetUrl),
      sameHostOnly: Value(sameHostOnly),
      createdAt: Value(createdAt),
      lastUsedAt: lastUsedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastUsedAt),
      successCount: Value(successCount),
      failureCount: Value(failureCount),
    );
  }

  factory PageHintRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PageHintRow(
      id: serializer.fromJson<String>(json['id']),
      host: serializer.fromJson<String>(json['host']),
      hintPath: serializer.fromJson<String?>(json['hintPath']),
      scope: serializer.fromJson<String>(json['scope']),
      kind: serializer.fromJson<String>(json['kind']),
      locatorJson: serializer.fromJson<String>(json['locatorJson']),
      exampleSourceUrl: serializer.fromJson<String?>(json['exampleSourceUrl']),
      exampleTargetUrl: serializer.fromJson<String?>(json['exampleTargetUrl']),
      sameHostOnly: serializer.fromJson<bool>(json['sameHostOnly']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      lastUsedAt: serializer.fromJson<DateTime?>(json['lastUsedAt']),
      successCount: serializer.fromJson<int>(json['successCount']),
      failureCount: serializer.fromJson<int>(json['failureCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'host': serializer.toJson<String>(host),
      'hintPath': serializer.toJson<String?>(hintPath),
      'scope': serializer.toJson<String>(scope),
      'kind': serializer.toJson<String>(kind),
      'locatorJson': serializer.toJson<String>(locatorJson),
      'exampleSourceUrl': serializer.toJson<String?>(exampleSourceUrl),
      'exampleTargetUrl': serializer.toJson<String?>(exampleTargetUrl),
      'sameHostOnly': serializer.toJson<bool>(sameHostOnly),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'lastUsedAt': serializer.toJson<DateTime?>(lastUsedAt),
      'successCount': serializer.toJson<int>(successCount),
      'failureCount': serializer.toJson<int>(failureCount),
    };
  }

  PageHintRow copyWith({
    String? id,
    String? host,
    Value<String?> hintPath = const Value.absent(),
    String? scope,
    String? kind,
    String? locatorJson,
    Value<String?> exampleSourceUrl = const Value.absent(),
    Value<String?> exampleTargetUrl = const Value.absent(),
    bool? sameHostOnly,
    DateTime? createdAt,
    Value<DateTime?> lastUsedAt = const Value.absent(),
    int? successCount,
    int? failureCount,
  }) => PageHintRow(
    id: id ?? this.id,
    host: host ?? this.host,
    hintPath: hintPath.present ? hintPath.value : this.hintPath,
    scope: scope ?? this.scope,
    kind: kind ?? this.kind,
    locatorJson: locatorJson ?? this.locatorJson,
    exampleSourceUrl: exampleSourceUrl.present
        ? exampleSourceUrl.value
        : this.exampleSourceUrl,
    exampleTargetUrl: exampleTargetUrl.present
        ? exampleTargetUrl.value
        : this.exampleTargetUrl,
    sameHostOnly: sameHostOnly ?? this.sameHostOnly,
    createdAt: createdAt ?? this.createdAt,
    lastUsedAt: lastUsedAt.present ? lastUsedAt.value : this.lastUsedAt,
    successCount: successCount ?? this.successCount,
    failureCount: failureCount ?? this.failureCount,
  );
  PageHintRow copyWithCompanion(PageHintsCompanion data) {
    return PageHintRow(
      id: data.id.present ? data.id.value : this.id,
      host: data.host.present ? data.host.value : this.host,
      hintPath: data.hintPath.present ? data.hintPath.value : this.hintPath,
      scope: data.scope.present ? data.scope.value : this.scope,
      kind: data.kind.present ? data.kind.value : this.kind,
      locatorJson: data.locatorJson.present
          ? data.locatorJson.value
          : this.locatorJson,
      exampleSourceUrl: data.exampleSourceUrl.present
          ? data.exampleSourceUrl.value
          : this.exampleSourceUrl,
      exampleTargetUrl: data.exampleTargetUrl.present
          ? data.exampleTargetUrl.value
          : this.exampleTargetUrl,
      sameHostOnly: data.sameHostOnly.present
          ? data.sameHostOnly.value
          : this.sameHostOnly,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastUsedAt: data.lastUsedAt.present
          ? data.lastUsedAt.value
          : this.lastUsedAt,
      successCount: data.successCount.present
          ? data.successCount.value
          : this.successCount,
      failureCount: data.failureCount.present
          ? data.failureCount.value
          : this.failureCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PageHintRow(')
          ..write('id: $id, ')
          ..write('host: $host, ')
          ..write('hintPath: $hintPath, ')
          ..write('scope: $scope, ')
          ..write('kind: $kind, ')
          ..write('locatorJson: $locatorJson, ')
          ..write('exampleSourceUrl: $exampleSourceUrl, ')
          ..write('exampleTargetUrl: $exampleTargetUrl, ')
          ..write('sameHostOnly: $sameHostOnly, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastUsedAt: $lastUsedAt, ')
          ..write('successCount: $successCount, ')
          ..write('failureCount: $failureCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    host,
    hintPath,
    scope,
    kind,
    locatorJson,
    exampleSourceUrl,
    exampleTargetUrl,
    sameHostOnly,
    createdAt,
    lastUsedAt,
    successCount,
    failureCount,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PageHintRow &&
          other.id == this.id &&
          other.host == this.host &&
          other.hintPath == this.hintPath &&
          other.scope == this.scope &&
          other.kind == this.kind &&
          other.locatorJson == this.locatorJson &&
          other.exampleSourceUrl == this.exampleSourceUrl &&
          other.exampleTargetUrl == this.exampleTargetUrl &&
          other.sameHostOnly == this.sameHostOnly &&
          other.createdAt == this.createdAt &&
          other.lastUsedAt == this.lastUsedAt &&
          other.successCount == this.successCount &&
          other.failureCount == this.failureCount);
}

class PageHintsCompanion extends UpdateCompanion<PageHintRow> {
  final Value<String> id;
  final Value<String> host;
  final Value<String?> hintPath;
  final Value<String> scope;
  final Value<String> kind;
  final Value<String> locatorJson;
  final Value<String?> exampleSourceUrl;
  final Value<String?> exampleTargetUrl;
  final Value<bool> sameHostOnly;
  final Value<DateTime> createdAt;
  final Value<DateTime?> lastUsedAt;
  final Value<int> successCount;
  final Value<int> failureCount;
  final Value<int> rowid;
  const PageHintsCompanion({
    this.id = const Value.absent(),
    this.host = const Value.absent(),
    this.hintPath = const Value.absent(),
    this.scope = const Value.absent(),
    this.kind = const Value.absent(),
    this.locatorJson = const Value.absent(),
    this.exampleSourceUrl = const Value.absent(),
    this.exampleTargetUrl = const Value.absent(),
    this.sameHostOnly = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastUsedAt = const Value.absent(),
    this.successCount = const Value.absent(),
    this.failureCount = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PageHintsCompanion.insert({
    required String id,
    required String host,
    this.hintPath = const Value.absent(),
    required String scope,
    required String kind,
    required String locatorJson,
    this.exampleSourceUrl = const Value.absent(),
    this.exampleTargetUrl = const Value.absent(),
    this.sameHostOnly = const Value.absent(),
    required DateTime createdAt,
    this.lastUsedAt = const Value.absent(),
    this.successCount = const Value.absent(),
    this.failureCount = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       host = Value(host),
       scope = Value(scope),
       kind = Value(kind),
       locatorJson = Value(locatorJson),
       createdAt = Value(createdAt);
  static Insertable<PageHintRow> custom({
    Expression<String>? id,
    Expression<String>? host,
    Expression<String>? hintPath,
    Expression<String>? scope,
    Expression<String>? kind,
    Expression<String>? locatorJson,
    Expression<String>? exampleSourceUrl,
    Expression<String>? exampleTargetUrl,
    Expression<bool>? sameHostOnly,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? lastUsedAt,
    Expression<int>? successCount,
    Expression<int>? failureCount,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (host != null) 'host': host,
      if (hintPath != null) 'hint_path': hintPath,
      if (scope != null) 'scope': scope,
      if (kind != null) 'kind': kind,
      if (locatorJson != null) 'locator_json': locatorJson,
      if (exampleSourceUrl != null) 'example_source_url': exampleSourceUrl,
      if (exampleTargetUrl != null) 'example_target_url': exampleTargetUrl,
      if (sameHostOnly != null) 'same_host_only': sameHostOnly,
      if (createdAt != null) 'created_at': createdAt,
      if (lastUsedAt != null) 'last_used_at': lastUsedAt,
      if (successCount != null) 'success_count': successCount,
      if (failureCount != null) 'failure_count': failureCount,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PageHintsCompanion copyWith({
    Value<String>? id,
    Value<String>? host,
    Value<String?>? hintPath,
    Value<String>? scope,
    Value<String>? kind,
    Value<String>? locatorJson,
    Value<String?>? exampleSourceUrl,
    Value<String?>? exampleTargetUrl,
    Value<bool>? sameHostOnly,
    Value<DateTime>? createdAt,
    Value<DateTime?>? lastUsedAt,
    Value<int>? successCount,
    Value<int>? failureCount,
    Value<int>? rowid,
  }) {
    return PageHintsCompanion(
      id: id ?? this.id,
      host: host ?? this.host,
      hintPath: hintPath ?? this.hintPath,
      scope: scope ?? this.scope,
      kind: kind ?? this.kind,
      locatorJson: locatorJson ?? this.locatorJson,
      exampleSourceUrl: exampleSourceUrl ?? this.exampleSourceUrl,
      exampleTargetUrl: exampleTargetUrl ?? this.exampleTargetUrl,
      sameHostOnly: sameHostOnly ?? this.sameHostOnly,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      successCount: successCount ?? this.successCount,
      failureCount: failureCount ?? this.failureCount,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (host.present) {
      map['host'] = Variable<String>(host.value);
    }
    if (hintPath.present) {
      map['hint_path'] = Variable<String>(hintPath.value);
    }
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (locatorJson.present) {
      map['locator_json'] = Variable<String>(locatorJson.value);
    }
    if (exampleSourceUrl.present) {
      map['example_source_url'] = Variable<String>(exampleSourceUrl.value);
    }
    if (exampleTargetUrl.present) {
      map['example_target_url'] = Variable<String>(exampleTargetUrl.value);
    }
    if (sameHostOnly.present) {
      map['same_host_only'] = Variable<bool>(sameHostOnly.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (lastUsedAt.present) {
      map['last_used_at'] = Variable<DateTime>(lastUsedAt.value);
    }
    if (successCount.present) {
      map['success_count'] = Variable<int>(successCount.value);
    }
    if (failureCount.present) {
      map['failure_count'] = Variable<int>(failureCount.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PageHintsCompanion(')
          ..write('id: $id, ')
          ..write('host: $host, ')
          ..write('hintPath: $hintPath, ')
          ..write('scope: $scope, ')
          ..write('kind: $kind, ')
          ..write('locatorJson: $locatorJson, ')
          ..write('exampleSourceUrl: $exampleSourceUrl, ')
          ..write('exampleTargetUrl: $exampleTargetUrl, ')
          ..write('sameHostOnly: $sameHostOnly, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastUsedAt: $lastUsedAt, ')
          ..write('successCount: $successCount, ')
          ..write('failureCount: $failureCount, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SavedSitesTable extends SavedSites
    with TableInfo<$SavedSitesTable, SavedSiteRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SavedSitesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _urlKeyMeta = const VerificationMeta('urlKey');
  @override
  late final GeneratedColumn<String> urlKey = GeneratedColumn<String>(
    'url_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hostMeta = const VerificationMeta('host');
  @override
  late final GeneratedColumn<String> host = GeneratedColumn<String>(
    'host',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userTitleMeta = const VerificationMeta(
    'userTitle',
  );
  @override
  late final GeneratedColumn<String> userTitle = GeneratedColumn<String>(
    'user_title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
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
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastOpenedAtMeta = const VerificationMeta(
    'lastOpenedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastOpenedAt = GeneratedColumn<DateTime>(
    'last_opened_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _orderIndexMeta = const VerificationMeta(
    'orderIndex',
  );
  @override
  late final GeneratedColumn<int> orderIndex = GeneratedColumn<int>(
    'order_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    url,
    urlKey,
    host,
    title,
    userTitle,
    createdAt,
    updatedAt,
    lastOpenedAt,
    orderIndex,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'saved_sites';
  @override
  VerificationContext validateIntegrity(
    Insertable<SavedSiteRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('url_key')) {
      context.handle(
        _urlKeyMeta,
        urlKey.isAcceptableOrUnknown(data['url_key']!, _urlKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_urlKeyMeta);
    }
    if (data.containsKey('host')) {
      context.handle(
        _hostMeta,
        host.isAcceptableOrUnknown(data['host']!, _hostMeta),
      );
    } else if (isInserting) {
      context.missing(_hostMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('user_title')) {
      context.handle(
        _userTitleMeta,
        userTitle.isAcceptableOrUnknown(data['user_title']!, _userTitleMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('last_opened_at')) {
      context.handle(
        _lastOpenedAtMeta,
        lastOpenedAt.isAcceptableOrUnknown(
          data['last_opened_at']!,
          _lastOpenedAtMeta,
        ),
      );
    }
    if (data.containsKey('order_index')) {
      context.handle(
        _orderIndexMeta,
        orderIndex.isAcceptableOrUnknown(data['order_index']!, _orderIndexMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SavedSiteRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SavedSiteRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      urlKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url_key'],
      )!,
      host: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      userTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_title'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      lastOpenedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_opened_at'],
      ),
      orderIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}order_index'],
      )!,
    );
  }

  @override
  $SavedSitesTable createAlias(String alias) {
    return $SavedSitesTable(attachedDatabase, alias);
  }
}

class SavedSiteRow extends DataClass implements Insertable<SavedSiteRow> {
  final String id;
  final String url;
  final String urlKey;
  final String host;
  final String title;
  final String? userTitle;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastOpenedAt;
  final int orderIndex;
  const SavedSiteRow({
    required this.id,
    required this.url,
    required this.urlKey,
    required this.host,
    required this.title,
    this.userTitle,
    required this.createdAt,
    required this.updatedAt,
    this.lastOpenedAt,
    required this.orderIndex,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['url'] = Variable<String>(url);
    map['url_key'] = Variable<String>(urlKey);
    map['host'] = Variable<String>(host);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || userTitle != null) {
      map['user_title'] = Variable<String>(userTitle);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || lastOpenedAt != null) {
      map['last_opened_at'] = Variable<DateTime>(lastOpenedAt);
    }
    map['order_index'] = Variable<int>(orderIndex);
    return map;
  }

  SavedSitesCompanion toCompanion(bool nullToAbsent) {
    return SavedSitesCompanion(
      id: Value(id),
      url: Value(url),
      urlKey: Value(urlKey),
      host: Value(host),
      title: Value(title),
      userTitle: userTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(userTitle),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      lastOpenedAt: lastOpenedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastOpenedAt),
      orderIndex: Value(orderIndex),
    );
  }

  factory SavedSiteRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SavedSiteRow(
      id: serializer.fromJson<String>(json['id']),
      url: serializer.fromJson<String>(json['url']),
      urlKey: serializer.fromJson<String>(json['urlKey']),
      host: serializer.fromJson<String>(json['host']),
      title: serializer.fromJson<String>(json['title']),
      userTitle: serializer.fromJson<String?>(json['userTitle']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      lastOpenedAt: serializer.fromJson<DateTime?>(json['lastOpenedAt']),
      orderIndex: serializer.fromJson<int>(json['orderIndex']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'url': serializer.toJson<String>(url),
      'urlKey': serializer.toJson<String>(urlKey),
      'host': serializer.toJson<String>(host),
      'title': serializer.toJson<String>(title),
      'userTitle': serializer.toJson<String?>(userTitle),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'lastOpenedAt': serializer.toJson<DateTime?>(lastOpenedAt),
      'orderIndex': serializer.toJson<int>(orderIndex),
    };
  }

  SavedSiteRow copyWith({
    String? id,
    String? url,
    String? urlKey,
    String? host,
    String? title,
    Value<String?> userTitle = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> lastOpenedAt = const Value.absent(),
    int? orderIndex,
  }) => SavedSiteRow(
    id: id ?? this.id,
    url: url ?? this.url,
    urlKey: urlKey ?? this.urlKey,
    host: host ?? this.host,
    title: title ?? this.title,
    userTitle: userTitle.present ? userTitle.value : this.userTitle,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    lastOpenedAt: lastOpenedAt.present ? lastOpenedAt.value : this.lastOpenedAt,
    orderIndex: orderIndex ?? this.orderIndex,
  );
  SavedSiteRow copyWithCompanion(SavedSitesCompanion data) {
    return SavedSiteRow(
      id: data.id.present ? data.id.value : this.id,
      url: data.url.present ? data.url.value : this.url,
      urlKey: data.urlKey.present ? data.urlKey.value : this.urlKey,
      host: data.host.present ? data.host.value : this.host,
      title: data.title.present ? data.title.value : this.title,
      userTitle: data.userTitle.present ? data.userTitle.value : this.userTitle,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      lastOpenedAt: data.lastOpenedAt.present
          ? data.lastOpenedAt.value
          : this.lastOpenedAt,
      orderIndex: data.orderIndex.present
          ? data.orderIndex.value
          : this.orderIndex,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SavedSiteRow(')
          ..write('id: $id, ')
          ..write('url: $url, ')
          ..write('urlKey: $urlKey, ')
          ..write('host: $host, ')
          ..write('title: $title, ')
          ..write('userTitle: $userTitle, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastOpenedAt: $lastOpenedAt, ')
          ..write('orderIndex: $orderIndex')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    url,
    urlKey,
    host,
    title,
    userTitle,
    createdAt,
    updatedAt,
    lastOpenedAt,
    orderIndex,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SavedSiteRow &&
          other.id == this.id &&
          other.url == this.url &&
          other.urlKey == this.urlKey &&
          other.host == this.host &&
          other.title == this.title &&
          other.userTitle == this.userTitle &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.lastOpenedAt == this.lastOpenedAt &&
          other.orderIndex == this.orderIndex);
}

class SavedSitesCompanion extends UpdateCompanion<SavedSiteRow> {
  final Value<String> id;
  final Value<String> url;
  final Value<String> urlKey;
  final Value<String> host;
  final Value<String> title;
  final Value<String?> userTitle;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> lastOpenedAt;
  final Value<int> orderIndex;
  final Value<int> rowid;
  const SavedSitesCompanion({
    this.id = const Value.absent(),
    this.url = const Value.absent(),
    this.urlKey = const Value.absent(),
    this.host = const Value.absent(),
    this.title = const Value.absent(),
    this.userTitle = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.lastOpenedAt = const Value.absent(),
    this.orderIndex = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SavedSitesCompanion.insert({
    required String id,
    required String url,
    required String urlKey,
    required String host,
    required String title,
    this.userTitle = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.lastOpenedAt = const Value.absent(),
    this.orderIndex = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       url = Value(url),
       urlKey = Value(urlKey),
       host = Value(host),
       title = Value(title),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<SavedSiteRow> custom({
    Expression<String>? id,
    Expression<String>? url,
    Expression<String>? urlKey,
    Expression<String>? host,
    Expression<String>? title,
    Expression<String>? userTitle,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? lastOpenedAt,
    Expression<int>? orderIndex,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (url != null) 'url': url,
      if (urlKey != null) 'url_key': urlKey,
      if (host != null) 'host': host,
      if (title != null) 'title': title,
      if (userTitle != null) 'user_title': userTitle,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (lastOpenedAt != null) 'last_opened_at': lastOpenedAt,
      if (orderIndex != null) 'order_index': orderIndex,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SavedSitesCompanion copyWith({
    Value<String>? id,
    Value<String>? url,
    Value<String>? urlKey,
    Value<String>? host,
    Value<String>? title,
    Value<String?>? userTitle,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? lastOpenedAt,
    Value<int>? orderIndex,
    Value<int>? rowid,
  }) {
    return SavedSitesCompanion(
      id: id ?? this.id,
      url: url ?? this.url,
      urlKey: urlKey ?? this.urlKey,
      host: host ?? this.host,
      title: title ?? this.title,
      userTitle: userTitle ?? this.userTitle,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      orderIndex: orderIndex ?? this.orderIndex,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (urlKey.present) {
      map['url_key'] = Variable<String>(urlKey.value);
    }
    if (host.present) {
      map['host'] = Variable<String>(host.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (userTitle.present) {
      map['user_title'] = Variable<String>(userTitle.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (lastOpenedAt.present) {
      map['last_opened_at'] = Variable<DateTime>(lastOpenedAt.value);
    }
    if (orderIndex.present) {
      map['order_index'] = Variable<int>(orderIndex.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SavedSitesCompanion(')
          ..write('id: $id, ')
          ..write('url: $url, ')
          ..write('urlKey: $urlKey, ')
          ..write('host: $host, ')
          ..write('title: $title, ')
          ..write('userTitle: $userTitle, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastOpenedAt: $lastOpenedAt, ')
          ..write('orderIndex: $orderIndex, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FaviconsTable extends Favicons
    with TableInfo<$FaviconsTable, FaviconRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FaviconsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _hostMeta = const VerificationMeta('host');
  @override
  late final GeneratedColumn<String> host = GeneratedColumn<String>(
    'host',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bytesMeta = const VerificationMeta('bytes');
  @override
  late final GeneratedColumn<Uint8List> bytes = GeneratedColumn<Uint8List>(
    'bytes',
    aliasedName,
    true,
    type: DriftSqlType.blob,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceUrlMeta = const VerificationMeta(
    'sourceUrl',
  );
  @override
  late final GeneratedColumn<String> sourceUrl = GeneratedColumn<String>(
    'source_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [host, bytes, sourceUrl, fetchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'favicons';
  @override
  VerificationContext validateIntegrity(
    Insertable<FaviconRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('host')) {
      context.handle(
        _hostMeta,
        host.isAcceptableOrUnknown(data['host']!, _hostMeta),
      );
    } else if (isInserting) {
      context.missing(_hostMeta);
    }
    if (data.containsKey('bytes')) {
      context.handle(
        _bytesMeta,
        bytes.isAcceptableOrUnknown(data['bytes']!, _bytesMeta),
      );
    }
    if (data.containsKey('source_url')) {
      context.handle(
        _sourceUrlMeta,
        sourceUrl.isAcceptableOrUnknown(data['source_url']!, _sourceUrlMeta),
      );
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {host};
  @override
  FaviconRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FaviconRow(
      host: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host'],
      )!,
      bytes: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}bytes'],
      ),
      sourceUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_url'],
      ),
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $FaviconsTable createAlias(String alias) {
    return $FaviconsTable(attachedDatabase, alias);
  }
}

class FaviconRow extends DataClass implements Insertable<FaviconRow> {
  final String host;
  final Uint8List? bytes;
  final String? sourceUrl;
  final DateTime fetchedAt;
  const FaviconRow({
    required this.host,
    this.bytes,
    this.sourceUrl,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['host'] = Variable<String>(host);
    if (!nullToAbsent || bytes != null) {
      map['bytes'] = Variable<Uint8List>(bytes);
    }
    if (!nullToAbsent || sourceUrl != null) {
      map['source_url'] = Variable<String>(sourceUrl);
    }
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  FaviconsCompanion toCompanion(bool nullToAbsent) {
    return FaviconsCompanion(
      host: Value(host),
      bytes: bytes == null && nullToAbsent
          ? const Value.absent()
          : Value(bytes),
      sourceUrl: sourceUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceUrl),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory FaviconRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FaviconRow(
      host: serializer.fromJson<String>(json['host']),
      bytes: serializer.fromJson<Uint8List?>(json['bytes']),
      sourceUrl: serializer.fromJson<String?>(json['sourceUrl']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'host': serializer.toJson<String>(host),
      'bytes': serializer.toJson<Uint8List?>(bytes),
      'sourceUrl': serializer.toJson<String?>(sourceUrl),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  FaviconRow copyWith({
    String? host,
    Value<Uint8List?> bytes = const Value.absent(),
    Value<String?> sourceUrl = const Value.absent(),
    DateTime? fetchedAt,
  }) => FaviconRow(
    host: host ?? this.host,
    bytes: bytes.present ? bytes.value : this.bytes,
    sourceUrl: sourceUrl.present ? sourceUrl.value : this.sourceUrl,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  FaviconRow copyWithCompanion(FaviconsCompanion data) {
    return FaviconRow(
      host: data.host.present ? data.host.value : this.host,
      bytes: data.bytes.present ? data.bytes.value : this.bytes,
      sourceUrl: data.sourceUrl.present ? data.sourceUrl.value : this.sourceUrl,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FaviconRow(')
          ..write('host: $host, ')
          ..write('bytes: $bytes, ')
          ..write('sourceUrl: $sourceUrl, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(host, $driftBlobEquality.hash(bytes), sourceUrl, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FaviconRow &&
          other.host == this.host &&
          $driftBlobEquality.equals(other.bytes, this.bytes) &&
          other.sourceUrl == this.sourceUrl &&
          other.fetchedAt == this.fetchedAt);
}

class FaviconsCompanion extends UpdateCompanion<FaviconRow> {
  final Value<String> host;
  final Value<Uint8List?> bytes;
  final Value<String?> sourceUrl;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const FaviconsCompanion({
    this.host = const Value.absent(),
    this.bytes = const Value.absent(),
    this.sourceUrl = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FaviconsCompanion.insert({
    required String host,
    this.bytes = const Value.absent(),
    this.sourceUrl = const Value.absent(),
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  }) : host = Value(host),
       fetchedAt = Value(fetchedAt);
  static Insertable<FaviconRow> custom({
    Expression<String>? host,
    Expression<Uint8List>? bytes,
    Expression<String>? sourceUrl,
    Expression<DateTime>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (host != null) 'host': host,
      if (bytes != null) 'bytes': bytes,
      if (sourceUrl != null) 'source_url': sourceUrl,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FaviconsCompanion copyWith({
    Value<String>? host,
    Value<Uint8List?>? bytes,
    Value<String?>? sourceUrl,
    Value<DateTime>? fetchedAt,
    Value<int>? rowid,
  }) {
    return FaviconsCompanion(
      host: host ?? this.host,
      bytes: bytes ?? this.bytes,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (host.present) {
      map['host'] = Variable<String>(host.value);
    }
    if (bytes.present) {
      map['bytes'] = Variable<Uint8List>(bytes.value);
    }
    if (sourceUrl.present) {
      map['source_url'] = Variable<String>(sourceUrl.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FaviconsCompanion(')
          ..write('host: $host, ')
          ..write('bytes: $bytes, ')
          ..write('sourceUrl: $sourceUrl, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AssetOriginsTable extends AssetOrigins
    with TableInfo<$AssetOriginsTable, AssetOriginRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AssetOriginsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
    'origin',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _verdictMeta = const VerificationMeta(
    'verdict',
  );
  @override
  late final GeneratedColumn<String> verdict = GeneratedColumn<String>(
    'verdict',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('unknown'),
  );
  static const VerificationMeta _refusedCapturesMeta = const VerificationMeta(
    'refusedCaptures',
  );
  @override
  late final GeneratedColumn<int> refusedCaptures = GeneratedColumn<int>(
    'refused_captures',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastRefusedLocationKeyMeta =
      const VerificationMeta('lastRefusedLocationKey');
  @override
  late final GeneratedColumn<String> lastRefusedLocationKey =
      GeneratedColumn<String>(
        'last_refused_location_key',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastServedAtMeta = const VerificationMeta(
    'lastServedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastServedAt = GeneratedColumn<DateTime>(
    'last_served_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _firstRefusedAtMeta = const VerificationMeta(
    'firstRefusedAt',
  );
  @override
  late final GeneratedColumn<DateTime> firstRefusedAt =
      GeneratedColumn<DateTime>(
        'first_refused_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _establishedAtMeta = const VerificationMeta(
    'establishedAt',
  );
  @override
  late final GeneratedColumn<DateTime> establishedAt =
      GeneratedColumn<DateTime>(
        'established_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
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
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    origin,
    verdict,
    refusedCaptures,
    lastRefusedLocationKey,
    lastServedAt,
    firstRefusedAt,
    establishedAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'asset_origins';
  @override
  VerificationContext validateIntegrity(
    Insertable<AssetOriginRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('origin')) {
      context.handle(
        _originMeta,
        origin.isAcceptableOrUnknown(data['origin']!, _originMeta),
      );
    } else if (isInserting) {
      context.missing(_originMeta);
    }
    if (data.containsKey('verdict')) {
      context.handle(
        _verdictMeta,
        verdict.isAcceptableOrUnknown(data['verdict']!, _verdictMeta),
      );
    }
    if (data.containsKey('refused_captures')) {
      context.handle(
        _refusedCapturesMeta,
        refusedCaptures.isAcceptableOrUnknown(
          data['refused_captures']!,
          _refusedCapturesMeta,
        ),
      );
    }
    if (data.containsKey('last_refused_location_key')) {
      context.handle(
        _lastRefusedLocationKeyMeta,
        lastRefusedLocationKey.isAcceptableOrUnknown(
          data['last_refused_location_key']!,
          _lastRefusedLocationKeyMeta,
        ),
      );
    }
    if (data.containsKey('last_served_at')) {
      context.handle(
        _lastServedAtMeta,
        lastServedAt.isAcceptableOrUnknown(
          data['last_served_at']!,
          _lastServedAtMeta,
        ),
      );
    }
    if (data.containsKey('first_refused_at')) {
      context.handle(
        _firstRefusedAtMeta,
        firstRefusedAt.isAcceptableOrUnknown(
          data['first_refused_at']!,
          _firstRefusedAtMeta,
        ),
      );
    }
    if (data.containsKey('established_at')) {
      context.handle(
        _establishedAtMeta,
        establishedAt.isAcceptableOrUnknown(
          data['established_at']!,
          _establishedAtMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {origin};
  @override
  AssetOriginRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AssetOriginRow(
      origin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin'],
      )!,
      verdict: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}verdict'],
      )!,
      refusedCaptures: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}refused_captures'],
      )!,
      lastRefusedLocationKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_refused_location_key'],
      ),
      lastServedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_served_at'],
      ),
      firstRefusedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}first_refused_at'],
      ),
      establishedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}established_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $AssetOriginsTable createAlias(String alias) {
    return $AssetOriginsTable(attachedDatabase, alias);
  }
}

class AssetOriginRow extends DataClass implements Insertable<AssetOriginRow> {
  /// `scheme://host[:port]`, lowercased. The unit the answer belongs to.
  final String origin;

  /// `unknown` · `suspected` · `refusing`. See `AssetOriginVerdict`.
  final String verdict;

  /// Captures — not assets — that this origin refused, counted once per
  /// Location so re-saving the same page cannot promote a verdict on its own.
  final int refusedCaptures;

  /// The last Location that was refused, so the count above stays honest.
  final String? lastRefusedLocationKey;

  /// When this origin last handed over a file. Any success at all clears a
  /// verdict: the host changed its mind, or it never meant it.
  final DateTime? lastServedAt;
  final DateTime? firstRefusedAt;

  /// When the verdict reached `refusing`. What staleness is measured from.
  final DateTime? establishedAt;
  final DateTime updatedAt;
  const AssetOriginRow({
    required this.origin,
    required this.verdict,
    required this.refusedCaptures,
    this.lastRefusedLocationKey,
    this.lastServedAt,
    this.firstRefusedAt,
    this.establishedAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['origin'] = Variable<String>(origin);
    map['verdict'] = Variable<String>(verdict);
    map['refused_captures'] = Variable<int>(refusedCaptures);
    if (!nullToAbsent || lastRefusedLocationKey != null) {
      map['last_refused_location_key'] = Variable<String>(
        lastRefusedLocationKey,
      );
    }
    if (!nullToAbsent || lastServedAt != null) {
      map['last_served_at'] = Variable<DateTime>(lastServedAt);
    }
    if (!nullToAbsent || firstRefusedAt != null) {
      map['first_refused_at'] = Variable<DateTime>(firstRefusedAt);
    }
    if (!nullToAbsent || establishedAt != null) {
      map['established_at'] = Variable<DateTime>(establishedAt);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AssetOriginsCompanion toCompanion(bool nullToAbsent) {
    return AssetOriginsCompanion(
      origin: Value(origin),
      verdict: Value(verdict),
      refusedCaptures: Value(refusedCaptures),
      lastRefusedLocationKey: lastRefusedLocationKey == null && nullToAbsent
          ? const Value.absent()
          : Value(lastRefusedLocationKey),
      lastServedAt: lastServedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastServedAt),
      firstRefusedAt: firstRefusedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(firstRefusedAt),
      establishedAt: establishedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(establishedAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory AssetOriginRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AssetOriginRow(
      origin: serializer.fromJson<String>(json['origin']),
      verdict: serializer.fromJson<String>(json['verdict']),
      refusedCaptures: serializer.fromJson<int>(json['refusedCaptures']),
      lastRefusedLocationKey: serializer.fromJson<String?>(
        json['lastRefusedLocationKey'],
      ),
      lastServedAt: serializer.fromJson<DateTime?>(json['lastServedAt']),
      firstRefusedAt: serializer.fromJson<DateTime?>(json['firstRefusedAt']),
      establishedAt: serializer.fromJson<DateTime?>(json['establishedAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'origin': serializer.toJson<String>(origin),
      'verdict': serializer.toJson<String>(verdict),
      'refusedCaptures': serializer.toJson<int>(refusedCaptures),
      'lastRefusedLocationKey': serializer.toJson<String?>(
        lastRefusedLocationKey,
      ),
      'lastServedAt': serializer.toJson<DateTime?>(lastServedAt),
      'firstRefusedAt': serializer.toJson<DateTime?>(firstRefusedAt),
      'establishedAt': serializer.toJson<DateTime?>(establishedAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  AssetOriginRow copyWith({
    String? origin,
    String? verdict,
    int? refusedCaptures,
    Value<String?> lastRefusedLocationKey = const Value.absent(),
    Value<DateTime?> lastServedAt = const Value.absent(),
    Value<DateTime?> firstRefusedAt = const Value.absent(),
    Value<DateTime?> establishedAt = const Value.absent(),
    DateTime? updatedAt,
  }) => AssetOriginRow(
    origin: origin ?? this.origin,
    verdict: verdict ?? this.verdict,
    refusedCaptures: refusedCaptures ?? this.refusedCaptures,
    lastRefusedLocationKey: lastRefusedLocationKey.present
        ? lastRefusedLocationKey.value
        : this.lastRefusedLocationKey,
    lastServedAt: lastServedAt.present ? lastServedAt.value : this.lastServedAt,
    firstRefusedAt: firstRefusedAt.present
        ? firstRefusedAt.value
        : this.firstRefusedAt,
    establishedAt: establishedAt.present
        ? establishedAt.value
        : this.establishedAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  AssetOriginRow copyWithCompanion(AssetOriginsCompanion data) {
    return AssetOriginRow(
      origin: data.origin.present ? data.origin.value : this.origin,
      verdict: data.verdict.present ? data.verdict.value : this.verdict,
      refusedCaptures: data.refusedCaptures.present
          ? data.refusedCaptures.value
          : this.refusedCaptures,
      lastRefusedLocationKey: data.lastRefusedLocationKey.present
          ? data.lastRefusedLocationKey.value
          : this.lastRefusedLocationKey,
      lastServedAt: data.lastServedAt.present
          ? data.lastServedAt.value
          : this.lastServedAt,
      firstRefusedAt: data.firstRefusedAt.present
          ? data.firstRefusedAt.value
          : this.firstRefusedAt,
      establishedAt: data.establishedAt.present
          ? data.establishedAt.value
          : this.establishedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AssetOriginRow(')
          ..write('origin: $origin, ')
          ..write('verdict: $verdict, ')
          ..write('refusedCaptures: $refusedCaptures, ')
          ..write('lastRefusedLocationKey: $lastRefusedLocationKey, ')
          ..write('lastServedAt: $lastServedAt, ')
          ..write('firstRefusedAt: $firstRefusedAt, ')
          ..write('establishedAt: $establishedAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    origin,
    verdict,
    refusedCaptures,
    lastRefusedLocationKey,
    lastServedAt,
    firstRefusedAt,
    establishedAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AssetOriginRow &&
          other.origin == this.origin &&
          other.verdict == this.verdict &&
          other.refusedCaptures == this.refusedCaptures &&
          other.lastRefusedLocationKey == this.lastRefusedLocationKey &&
          other.lastServedAt == this.lastServedAt &&
          other.firstRefusedAt == this.firstRefusedAt &&
          other.establishedAt == this.establishedAt &&
          other.updatedAt == this.updatedAt);
}

class AssetOriginsCompanion extends UpdateCompanion<AssetOriginRow> {
  final Value<String> origin;
  final Value<String> verdict;
  final Value<int> refusedCaptures;
  final Value<String?> lastRefusedLocationKey;
  final Value<DateTime?> lastServedAt;
  final Value<DateTime?> firstRefusedAt;
  final Value<DateTime?> establishedAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const AssetOriginsCompanion({
    this.origin = const Value.absent(),
    this.verdict = const Value.absent(),
    this.refusedCaptures = const Value.absent(),
    this.lastRefusedLocationKey = const Value.absent(),
    this.lastServedAt = const Value.absent(),
    this.firstRefusedAt = const Value.absent(),
    this.establishedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AssetOriginsCompanion.insert({
    required String origin,
    this.verdict = const Value.absent(),
    this.refusedCaptures = const Value.absent(),
    this.lastRefusedLocationKey = const Value.absent(),
    this.lastServedAt = const Value.absent(),
    this.firstRefusedAt = const Value.absent(),
    this.establishedAt = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : origin = Value(origin),
       updatedAt = Value(updatedAt);
  static Insertable<AssetOriginRow> custom({
    Expression<String>? origin,
    Expression<String>? verdict,
    Expression<int>? refusedCaptures,
    Expression<String>? lastRefusedLocationKey,
    Expression<DateTime>? lastServedAt,
    Expression<DateTime>? firstRefusedAt,
    Expression<DateTime>? establishedAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (origin != null) 'origin': origin,
      if (verdict != null) 'verdict': verdict,
      if (refusedCaptures != null) 'refused_captures': refusedCaptures,
      if (lastRefusedLocationKey != null)
        'last_refused_location_key': lastRefusedLocationKey,
      if (lastServedAt != null) 'last_served_at': lastServedAt,
      if (firstRefusedAt != null) 'first_refused_at': firstRefusedAt,
      if (establishedAt != null) 'established_at': establishedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AssetOriginsCompanion copyWith({
    Value<String>? origin,
    Value<String>? verdict,
    Value<int>? refusedCaptures,
    Value<String?>? lastRefusedLocationKey,
    Value<DateTime?>? lastServedAt,
    Value<DateTime?>? firstRefusedAt,
    Value<DateTime?>? establishedAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return AssetOriginsCompanion(
      origin: origin ?? this.origin,
      verdict: verdict ?? this.verdict,
      refusedCaptures: refusedCaptures ?? this.refusedCaptures,
      lastRefusedLocationKey:
          lastRefusedLocationKey ?? this.lastRefusedLocationKey,
      lastServedAt: lastServedAt ?? this.lastServedAt,
      firstRefusedAt: firstRefusedAt ?? this.firstRefusedAt,
      establishedAt: establishedAt ?? this.establishedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    if (verdict.present) {
      map['verdict'] = Variable<String>(verdict.value);
    }
    if (refusedCaptures.present) {
      map['refused_captures'] = Variable<int>(refusedCaptures.value);
    }
    if (lastRefusedLocationKey.present) {
      map['last_refused_location_key'] = Variable<String>(
        lastRefusedLocationKey.value,
      );
    }
    if (lastServedAt.present) {
      map['last_served_at'] = Variable<DateTime>(lastServedAt.value);
    }
    if (firstRefusedAt.present) {
      map['first_refused_at'] = Variable<DateTime>(firstRefusedAt.value);
    }
    if (establishedAt.present) {
      map['established_at'] = Variable<DateTime>(establishedAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AssetOriginsCompanion(')
          ..write('origin: $origin, ')
          ..write('verdict: $verdict, ')
          ..write('refusedCaptures: $refusedCaptures, ')
          ..write('lastRefusedLocationKey: $lastRefusedLocationKey, ')
          ..write('lastServedAt: $lastServedAt, ')
          ..write('firstRefusedAt: $firstRefusedAt, ')
          ..write('establishedAt: $establishedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalSettingsTable extends LocalSettings
    with TableInfo<$LocalSettingsTable, SettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $LocalSettingsTable createAlias(String alias) {
    return $LocalSettingsTable(attachedDatabase, alias);
  }
}

class SettingRow extends DataClass implements Insertable<SettingRow> {
  final String key;
  final String value;
  const SettingRow({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  LocalSettingsCompanion toCompanion(bool nullToAbsent) {
    return LocalSettingsCompanion(key: Value(key), value: Value(value));
  }

  factory SettingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SettingRow copyWith({String? key, String? value}) =>
      SettingRow(key: key ?? this.key, value: value ?? this.value);
  SettingRow copyWithCompanion(LocalSettingsCompanion data) {
    return SettingRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingRow(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingRow &&
          other.key == this.key &&
          other.value == this.value);
}

class LocalSettingsCompanion extends UpdateCompanion<SettingRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const LocalSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalSettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SettingRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return LocalSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LibraryDatabase extends GeneratedDatabase {
  _$LibraryDatabase(QueryExecutor e) : super(e);
  $LibraryDatabaseManager get managers => $LibraryDatabaseManager(this);
  late final $FoldersTable folders = $FoldersTable(this);
  late final $SourcesTable sources = $SourcesTable(this);
  late final $CollectionsTable collections = $CollectionsTable(this);
  late final $EntriesTable entries = $EntriesTable(this);
  late final $LocationsTable locations = $LocationsTable(this);
  late final $ReadingStatesTable readingStates = $ReadingStatesTable(this);
  late final $MeasurementsTable measurements = $MeasurementsTable(this);
  late final $DownloadRequestsTable downloadRequests = $DownloadRequestsTable(
    this,
  );
  late final $OfflineCopiesTable offlineCopies = $OfflineCopiesTable(this);
  late final $SaveQueueTable saveQueue = $SaveQueueTable(this);
  late final $HistoryTable history = $HistoryTable(this);
  late final $OutboxTable outbox = $OutboxTable(this);
  late final $SyncStateTable syncState = $SyncStateTable(this);
  late final $PageHintsTable pageHints = $PageHintsTable(this);
  late final $SavedSitesTable savedSites = $SavedSitesTable(this);
  late final $FaviconsTable favicons = $FaviconsTable(this);
  late final $AssetOriginsTable assetOrigins = $AssetOriginsTable(this);
  late final $LocalSettingsTable localSettings = $LocalSettingsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    folders,
    sources,
    collections,
    entries,
    locations,
    readingStates,
    measurements,
    downloadRequests,
    offlineCopies,
    saveQueue,
    history,
    outbox,
    syncState,
    pageHints,
    savedSites,
    favicons,
    assetOrigins,
    localSettings,
  ];
}

typedef $$FoldersTableCreateCompanionBuilder =
    FoldersCompanion Function({
      required String id,
      Value<String?> serverId,
      Value<String?> parentId,
      required String kind,
      required String name,
      Value<int> sortKey,
      Value<int?> revision,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$FoldersTableUpdateCompanionBuilder =
    FoldersCompanion Function({
      Value<String> id,
      Value<String?> serverId,
      Value<String?> parentId,
      Value<String> kind,
      Value<String> name,
      Value<int> sortKey,
      Value<int?> revision,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$FoldersTableFilterComposer
    extends Composer<_$LibraryDatabase, $FoldersTable> {
  $$FoldersTableFilterComposer({
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

  ColumnFilters<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortKey => $composableBuilder(
    column: $table.sortKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FoldersTableOrderingComposer
    extends Composer<_$LibraryDatabase, $FoldersTable> {
  $$FoldersTableOrderingComposer({
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

  ColumnOrderings<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortKey => $composableBuilder(
    column: $table.sortKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FoldersTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $FoldersTable> {
  $$FoldersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get sortKey =>
      $composableBuilder(column: $table.sortKey, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$FoldersTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $FoldersTable,
          FolderRow,
          $$FoldersTableFilterComposer,
          $$FoldersTableOrderingComposer,
          $$FoldersTableAnnotationComposer,
          $$FoldersTableCreateCompanionBuilder,
          $$FoldersTableUpdateCompanionBuilder,
          (
            FolderRow,
            BaseReferences<_$LibraryDatabase, $FoldersTable, FolderRow>,
          ),
          FolderRow,
          PrefetchHooks Function()
        > {
  $$FoldersTableTableManager(_$LibraryDatabase db, $FoldersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FoldersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FoldersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FoldersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> serverId = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> sortKey = const Value.absent(),
                Value<int?> revision = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FoldersCompanion(
                id: id,
                serverId: serverId,
                parentId: parentId,
                kind: kind,
                name: name,
                sortKey: sortKey,
                revision: revision,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> serverId = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                required String kind,
                required String name,
                Value<int> sortKey = const Value.absent(),
                Value<int?> revision = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => FoldersCompanion.insert(
                id: id,
                serverId: serverId,
                parentId: parentId,
                kind: kind,
                name: name,
                sortKey: sortKey,
                revision: revision,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FoldersTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $FoldersTable,
      FolderRow,
      $$FoldersTableFilterComposer,
      $$FoldersTableOrderingComposer,
      $$FoldersTableAnnotationComposer,
      $$FoldersTableCreateCompanionBuilder,
      $$FoldersTableUpdateCompanionBuilder,
      (FolderRow, BaseReferences<_$LibraryDatabase, $FoldersTable, FolderRow>),
      FolderRow,
      PrefetchHooks Function()
    >;
typedef $$SourcesTableCreateCompanionBuilder =
    SourcesCompanion Function({
      required String id,
      Value<String?> serverId,
      required String collectionId,
      required String host,
      required String pathKey,
      Value<String> language,
      Value<String> lifecycle,
      Value<String?> resolvedIntoSourceId,
      required DateTime firstSeenAt,
      required DateTime lastSeenAt,
      Value<int?> revision,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$SourcesTableUpdateCompanionBuilder =
    SourcesCompanion Function({
      Value<String> id,
      Value<String?> serverId,
      Value<String> collectionId,
      Value<String> host,
      Value<String> pathKey,
      Value<String> language,
      Value<String> lifecycle,
      Value<String?> resolvedIntoSourceId,
      Value<DateTime> firstSeenAt,
      Value<DateTime> lastSeenAt,
      Value<int?> revision,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$SourcesTableFilterComposer
    extends Composer<_$LibraryDatabase, $SourcesTable> {
  $$SourcesTableFilterComposer({
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

  ColumnFilters<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get collectionId => $composableBuilder(
    column: $table.collectionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pathKey => $composableBuilder(
    column: $table.pathKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lifecycle => $composableBuilder(
    column: $table.lifecycle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resolvedIntoSourceId => $composableBuilder(
    column: $table.resolvedIntoSourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get firstSeenAt => $composableBuilder(
    column: $table.firstSeenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SourcesTableOrderingComposer
    extends Composer<_$LibraryDatabase, $SourcesTable> {
  $$SourcesTableOrderingComposer({
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

  ColumnOrderings<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get collectionId => $composableBuilder(
    column: $table.collectionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pathKey => $composableBuilder(
    column: $table.pathKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lifecycle => $composableBuilder(
    column: $table.lifecycle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resolvedIntoSourceId => $composableBuilder(
    column: $table.resolvedIntoSourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get firstSeenAt => $composableBuilder(
    column: $table.firstSeenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SourcesTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $SourcesTable> {
  $$SourcesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get collectionId => $composableBuilder(
    column: $table.collectionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get host =>
      $composableBuilder(column: $table.host, builder: (column) => column);

  GeneratedColumn<String> get pathKey =>
      $composableBuilder(column: $table.pathKey, builder: (column) => column);

  GeneratedColumn<String> get language =>
      $composableBuilder(column: $table.language, builder: (column) => column);

  GeneratedColumn<String> get lifecycle =>
      $composableBuilder(column: $table.lifecycle, builder: (column) => column);

  GeneratedColumn<String> get resolvedIntoSourceId => $composableBuilder(
    column: $table.resolvedIntoSourceId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get firstSeenAt => $composableBuilder(
    column: $table.firstSeenAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SourcesTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $SourcesTable,
          SourceRow,
          $$SourcesTableFilterComposer,
          $$SourcesTableOrderingComposer,
          $$SourcesTableAnnotationComposer,
          $$SourcesTableCreateCompanionBuilder,
          $$SourcesTableUpdateCompanionBuilder,
          (
            SourceRow,
            BaseReferences<_$LibraryDatabase, $SourcesTable, SourceRow>,
          ),
          SourceRow,
          PrefetchHooks Function()
        > {
  $$SourcesTableTableManager(_$LibraryDatabase db, $SourcesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SourcesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SourcesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SourcesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> serverId = const Value.absent(),
                Value<String> collectionId = const Value.absent(),
                Value<String> host = const Value.absent(),
                Value<String> pathKey = const Value.absent(),
                Value<String> language = const Value.absent(),
                Value<String> lifecycle = const Value.absent(),
                Value<String?> resolvedIntoSourceId = const Value.absent(),
                Value<DateTime> firstSeenAt = const Value.absent(),
                Value<DateTime> lastSeenAt = const Value.absent(),
                Value<int?> revision = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SourcesCompanion(
                id: id,
                serverId: serverId,
                collectionId: collectionId,
                host: host,
                pathKey: pathKey,
                language: language,
                lifecycle: lifecycle,
                resolvedIntoSourceId: resolvedIntoSourceId,
                firstSeenAt: firstSeenAt,
                lastSeenAt: lastSeenAt,
                revision: revision,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> serverId = const Value.absent(),
                required String collectionId,
                required String host,
                required String pathKey,
                Value<String> language = const Value.absent(),
                Value<String> lifecycle = const Value.absent(),
                Value<String?> resolvedIntoSourceId = const Value.absent(),
                required DateTime firstSeenAt,
                required DateTime lastSeenAt,
                Value<int?> revision = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SourcesCompanion.insert(
                id: id,
                serverId: serverId,
                collectionId: collectionId,
                host: host,
                pathKey: pathKey,
                language: language,
                lifecycle: lifecycle,
                resolvedIntoSourceId: resolvedIntoSourceId,
                firstSeenAt: firstSeenAt,
                lastSeenAt: lastSeenAt,
                revision: revision,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SourcesTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $SourcesTable,
      SourceRow,
      $$SourcesTableFilterComposer,
      $$SourcesTableOrderingComposer,
      $$SourcesTableAnnotationComposer,
      $$SourcesTableCreateCompanionBuilder,
      $$SourcesTableUpdateCompanionBuilder,
      (SourceRow, BaseReferences<_$LibraryDatabase, $SourcesTable, SourceRow>),
      SourceRow,
      PrefetchHooks Function()
    >;
typedef $$CollectionsTableCreateCompanionBuilder =
    CollectionsCompanion Function({
      required String id,
      Value<String?> serverId,
      required String folderId,
      required String name,
      Value<String> detectedTitle,
      required String orderingBasis,
      Value<String> lifecycle,
      Value<String?> preferredSourceId,
      Value<int> sortKey,
      Value<int?> revision,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$CollectionsTableUpdateCompanionBuilder =
    CollectionsCompanion Function({
      Value<String> id,
      Value<String?> serverId,
      Value<String> folderId,
      Value<String> name,
      Value<String> detectedTitle,
      Value<String> orderingBasis,
      Value<String> lifecycle,
      Value<String?> preferredSourceId,
      Value<int> sortKey,
      Value<int?> revision,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$CollectionsTableFilterComposer
    extends Composer<_$LibraryDatabase, $CollectionsTable> {
  $$CollectionsTableFilterComposer({
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

  ColumnFilters<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get folderId => $composableBuilder(
    column: $table.folderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get detectedTitle => $composableBuilder(
    column: $table.detectedTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get orderingBasis => $composableBuilder(
    column: $table.orderingBasis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lifecycle => $composableBuilder(
    column: $table.lifecycle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get preferredSourceId => $composableBuilder(
    column: $table.preferredSourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortKey => $composableBuilder(
    column: $table.sortKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CollectionsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $CollectionsTable> {
  $$CollectionsTableOrderingComposer({
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

  ColumnOrderings<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get folderId => $composableBuilder(
    column: $table.folderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get detectedTitle => $composableBuilder(
    column: $table.detectedTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get orderingBasis => $composableBuilder(
    column: $table.orderingBasis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lifecycle => $composableBuilder(
    column: $table.lifecycle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get preferredSourceId => $composableBuilder(
    column: $table.preferredSourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortKey => $composableBuilder(
    column: $table.sortKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CollectionsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $CollectionsTable> {
  $$CollectionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get folderId =>
      $composableBuilder(column: $table.folderId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get detectedTitle => $composableBuilder(
    column: $table.detectedTitle,
    builder: (column) => column,
  );

  GeneratedColumn<String> get orderingBasis => $composableBuilder(
    column: $table.orderingBasis,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lifecycle =>
      $composableBuilder(column: $table.lifecycle, builder: (column) => column);

  GeneratedColumn<String> get preferredSourceId => $composableBuilder(
    column: $table.preferredSourceId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortKey =>
      $composableBuilder(column: $table.sortKey, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CollectionsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $CollectionsTable,
          CollectionRow,
          $$CollectionsTableFilterComposer,
          $$CollectionsTableOrderingComposer,
          $$CollectionsTableAnnotationComposer,
          $$CollectionsTableCreateCompanionBuilder,
          $$CollectionsTableUpdateCompanionBuilder,
          (
            CollectionRow,
            BaseReferences<_$LibraryDatabase, $CollectionsTable, CollectionRow>,
          ),
          CollectionRow,
          PrefetchHooks Function()
        > {
  $$CollectionsTableTableManager(_$LibraryDatabase db, $CollectionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CollectionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CollectionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CollectionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> serverId = const Value.absent(),
                Value<String> folderId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> detectedTitle = const Value.absent(),
                Value<String> orderingBasis = const Value.absent(),
                Value<String> lifecycle = const Value.absent(),
                Value<String?> preferredSourceId = const Value.absent(),
                Value<int> sortKey = const Value.absent(),
                Value<int?> revision = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CollectionsCompanion(
                id: id,
                serverId: serverId,
                folderId: folderId,
                name: name,
                detectedTitle: detectedTitle,
                orderingBasis: orderingBasis,
                lifecycle: lifecycle,
                preferredSourceId: preferredSourceId,
                sortKey: sortKey,
                revision: revision,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> serverId = const Value.absent(),
                required String folderId,
                required String name,
                Value<String> detectedTitle = const Value.absent(),
                required String orderingBasis,
                Value<String> lifecycle = const Value.absent(),
                Value<String?> preferredSourceId = const Value.absent(),
                Value<int> sortKey = const Value.absent(),
                Value<int?> revision = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CollectionsCompanion.insert(
                id: id,
                serverId: serverId,
                folderId: folderId,
                name: name,
                detectedTitle: detectedTitle,
                orderingBasis: orderingBasis,
                lifecycle: lifecycle,
                preferredSourceId: preferredSourceId,
                sortKey: sortKey,
                revision: revision,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CollectionsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $CollectionsTable,
      CollectionRow,
      $$CollectionsTableFilterComposer,
      $$CollectionsTableOrderingComposer,
      $$CollectionsTableAnnotationComposer,
      $$CollectionsTableCreateCompanionBuilder,
      $$CollectionsTableUpdateCompanionBuilder,
      (
        CollectionRow,
        BaseReferences<_$LibraryDatabase, $CollectionsTable, CollectionRow>,
      ),
      CollectionRow,
      PrefetchHooks Function()
    >;
typedef $$EntriesTableCreateCompanionBuilder =
    EntriesCompanion Function({
      required String id,
      Value<String?> serverId,
      Value<String?> collectionId,
      Value<String?> folderId,
      Value<double?> ordinal,
      required String placement,
      Value<String> title,
      Value<int> sortKey,
      Value<int?> revision,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$EntriesTableUpdateCompanionBuilder =
    EntriesCompanion Function({
      Value<String> id,
      Value<String?> serverId,
      Value<String?> collectionId,
      Value<String?> folderId,
      Value<double?> ordinal,
      Value<String> placement,
      Value<String> title,
      Value<int> sortKey,
      Value<int?> revision,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$EntriesTableFilterComposer
    extends Composer<_$LibraryDatabase, $EntriesTable> {
  $$EntriesTableFilterComposer({
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

  ColumnFilters<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get collectionId => $composableBuilder(
    column: $table.collectionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get folderId => $composableBuilder(
    column: $table.folderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get ordinal => $composableBuilder(
    column: $table.ordinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get placement => $composableBuilder(
    column: $table.placement,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortKey => $composableBuilder(
    column: $table.sortKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EntriesTableOrderingComposer
    extends Composer<_$LibraryDatabase, $EntriesTable> {
  $$EntriesTableOrderingComposer({
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

  ColumnOrderings<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get collectionId => $composableBuilder(
    column: $table.collectionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get folderId => $composableBuilder(
    column: $table.folderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get ordinal => $composableBuilder(
    column: $table.ordinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get placement => $composableBuilder(
    column: $table.placement,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortKey => $composableBuilder(
    column: $table.sortKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EntriesTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $EntriesTable> {
  $$EntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get collectionId => $composableBuilder(
    column: $table.collectionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get folderId =>
      $composableBuilder(column: $table.folderId, builder: (column) => column);

  GeneratedColumn<double> get ordinal =>
      $composableBuilder(column: $table.ordinal, builder: (column) => column);

  GeneratedColumn<String> get placement =>
      $composableBuilder(column: $table.placement, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get sortKey =>
      $composableBuilder(column: $table.sortKey, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$EntriesTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $EntriesTable,
          EntryRow,
          $$EntriesTableFilterComposer,
          $$EntriesTableOrderingComposer,
          $$EntriesTableAnnotationComposer,
          $$EntriesTableCreateCompanionBuilder,
          $$EntriesTableUpdateCompanionBuilder,
          (
            EntryRow,
            BaseReferences<_$LibraryDatabase, $EntriesTable, EntryRow>,
          ),
          EntryRow,
          PrefetchHooks Function()
        > {
  $$EntriesTableTableManager(_$LibraryDatabase db, $EntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> serverId = const Value.absent(),
                Value<String?> collectionId = const Value.absent(),
                Value<String?> folderId = const Value.absent(),
                Value<double?> ordinal = const Value.absent(),
                Value<String> placement = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<int> sortKey = const Value.absent(),
                Value<int?> revision = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EntriesCompanion(
                id: id,
                serverId: serverId,
                collectionId: collectionId,
                folderId: folderId,
                ordinal: ordinal,
                placement: placement,
                title: title,
                sortKey: sortKey,
                revision: revision,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> serverId = const Value.absent(),
                Value<String?> collectionId = const Value.absent(),
                Value<String?> folderId = const Value.absent(),
                Value<double?> ordinal = const Value.absent(),
                required String placement,
                Value<String> title = const Value.absent(),
                Value<int> sortKey = const Value.absent(),
                Value<int?> revision = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => EntriesCompanion.insert(
                id: id,
                serverId: serverId,
                collectionId: collectionId,
                folderId: folderId,
                ordinal: ordinal,
                placement: placement,
                title: title,
                sortKey: sortKey,
                revision: revision,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $EntriesTable,
      EntryRow,
      $$EntriesTableFilterComposer,
      $$EntriesTableOrderingComposer,
      $$EntriesTableAnnotationComposer,
      $$EntriesTableCreateCompanionBuilder,
      $$EntriesTableUpdateCompanionBuilder,
      (EntryRow, BaseReferences<_$LibraryDatabase, $EntriesTable, EntryRow>),
      EntryRow,
      PrefetchHooks Function()
    >;
typedef $$LocationsTableCreateCompanionBuilder =
    LocationsCompanion Function({
      required String id,
      Value<String?> serverId,
      required String entryId,
      Value<String?> sourceId,
      required String url,
      required String urlKey,
      Value<String> sourceLabel,
      Value<double?> sourceNumber,
      Value<DateTime?> publishedAt,
      required DateTime discoveredAt,
      Value<String> discoveryBasis,
      Value<String> lifecycle,
      Value<int?> revision,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$LocationsTableUpdateCompanionBuilder =
    LocationsCompanion Function({
      Value<String> id,
      Value<String?> serverId,
      Value<String> entryId,
      Value<String?> sourceId,
      Value<String> url,
      Value<String> urlKey,
      Value<String> sourceLabel,
      Value<double?> sourceNumber,
      Value<DateTime?> publishedAt,
      Value<DateTime> discoveredAt,
      Value<String> discoveryBasis,
      Value<String> lifecycle,
      Value<int?> revision,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$LocationsTableFilterComposer
    extends Composer<_$LibraryDatabase, $LocationsTable> {
  $$LocationsTableFilterComposer({
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

  ColumnFilters<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entryId => $composableBuilder(
    column: $table.entryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get urlKey => $composableBuilder(
    column: $table.urlKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceLabel => $composableBuilder(
    column: $table.sourceLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get sourceNumber => $composableBuilder(
    column: $table.sourceNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get publishedAt => $composableBuilder(
    column: $table.publishedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get discoveredAt => $composableBuilder(
    column: $table.discoveredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get discoveryBasis => $composableBuilder(
    column: $table.discoveryBasis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lifecycle => $composableBuilder(
    column: $table.lifecycle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocationsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $LocationsTable> {
  $$LocationsTableOrderingComposer({
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

  ColumnOrderings<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entryId => $composableBuilder(
    column: $table.entryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get urlKey => $composableBuilder(
    column: $table.urlKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceLabel => $composableBuilder(
    column: $table.sourceLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get sourceNumber => $composableBuilder(
    column: $table.sourceNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get publishedAt => $composableBuilder(
    column: $table.publishedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get discoveredAt => $composableBuilder(
    column: $table.discoveredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get discoveryBasis => $composableBuilder(
    column: $table.discoveryBasis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lifecycle => $composableBuilder(
    column: $table.lifecycle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocationsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $LocationsTable> {
  $$LocationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get entryId =>
      $composableBuilder(column: $table.entryId, builder: (column) => column);

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get urlKey =>
      $composableBuilder(column: $table.urlKey, builder: (column) => column);

  GeneratedColumn<String> get sourceLabel => $composableBuilder(
    column: $table.sourceLabel,
    builder: (column) => column,
  );

  GeneratedColumn<double> get sourceNumber => $composableBuilder(
    column: $table.sourceNumber,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get publishedAt => $composableBuilder(
    column: $table.publishedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get discoveredAt => $composableBuilder(
    column: $table.discoveredAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get discoveryBasis => $composableBuilder(
    column: $table.discoveryBasis,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lifecycle =>
      $composableBuilder(column: $table.lifecycle, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$LocationsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $LocationsTable,
          LocationRow,
          $$LocationsTableFilterComposer,
          $$LocationsTableOrderingComposer,
          $$LocationsTableAnnotationComposer,
          $$LocationsTableCreateCompanionBuilder,
          $$LocationsTableUpdateCompanionBuilder,
          (
            LocationRow,
            BaseReferences<_$LibraryDatabase, $LocationsTable, LocationRow>,
          ),
          LocationRow,
          PrefetchHooks Function()
        > {
  $$LocationsTableTableManager(_$LibraryDatabase db, $LocationsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> serverId = const Value.absent(),
                Value<String> entryId = const Value.absent(),
                Value<String?> sourceId = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<String> urlKey = const Value.absent(),
                Value<String> sourceLabel = const Value.absent(),
                Value<double?> sourceNumber = const Value.absent(),
                Value<DateTime?> publishedAt = const Value.absent(),
                Value<DateTime> discoveredAt = const Value.absent(),
                Value<String> discoveryBasis = const Value.absent(),
                Value<String> lifecycle = const Value.absent(),
                Value<int?> revision = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocationsCompanion(
                id: id,
                serverId: serverId,
                entryId: entryId,
                sourceId: sourceId,
                url: url,
                urlKey: urlKey,
                sourceLabel: sourceLabel,
                sourceNumber: sourceNumber,
                publishedAt: publishedAt,
                discoveredAt: discoveredAt,
                discoveryBasis: discoveryBasis,
                lifecycle: lifecycle,
                revision: revision,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> serverId = const Value.absent(),
                required String entryId,
                Value<String?> sourceId = const Value.absent(),
                required String url,
                required String urlKey,
                Value<String> sourceLabel = const Value.absent(),
                Value<double?> sourceNumber = const Value.absent(),
                Value<DateTime?> publishedAt = const Value.absent(),
                required DateTime discoveredAt,
                Value<String> discoveryBasis = const Value.absent(),
                Value<String> lifecycle = const Value.absent(),
                Value<int?> revision = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => LocationsCompanion.insert(
                id: id,
                serverId: serverId,
                entryId: entryId,
                sourceId: sourceId,
                url: url,
                urlKey: urlKey,
                sourceLabel: sourceLabel,
                sourceNumber: sourceNumber,
                publishedAt: publishedAt,
                discoveredAt: discoveredAt,
                discoveryBasis: discoveryBasis,
                lifecycle: lifecycle,
                revision: revision,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocationsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $LocationsTable,
      LocationRow,
      $$LocationsTableFilterComposer,
      $$LocationsTableOrderingComposer,
      $$LocationsTableAnnotationComposer,
      $$LocationsTableCreateCompanionBuilder,
      $$LocationsTableUpdateCompanionBuilder,
      (
        LocationRow,
        BaseReferences<_$LibraryDatabase, $LocationsTable, LocationRow>,
      ),
      LocationRow,
      PrefetchHooks Function()
    >;
typedef $$ReadingStatesTableCreateCompanionBuilder =
    ReadingStatesCompanion Function({
      required String entryId,
      Value<String> status,
      Value<DateTime?> firstOpenedAt,
      Value<DateTime?> lastReadAt,
      Value<DateTime?> completedAt,
      Value<int?> revision,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ReadingStatesTableUpdateCompanionBuilder =
    ReadingStatesCompanion Function({
      Value<String> entryId,
      Value<String> status,
      Value<DateTime?> firstOpenedAt,
      Value<DateTime?> lastReadAt,
      Value<DateTime?> completedAt,
      Value<int?> revision,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$ReadingStatesTableFilterComposer
    extends Composer<_$LibraryDatabase, $ReadingStatesTable> {
  $$ReadingStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get entryId => $composableBuilder(
    column: $table.entryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get firstOpenedAt => $composableBuilder(
    column: $table.firstOpenedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReadingStatesTableOrderingComposer
    extends Composer<_$LibraryDatabase, $ReadingStatesTable> {
  $$ReadingStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get entryId => $composableBuilder(
    column: $table.entryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get firstOpenedAt => $composableBuilder(
    column: $table.firstOpenedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReadingStatesTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $ReadingStatesTable> {
  $$ReadingStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get entryId =>
      $composableBuilder(column: $table.entryId, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get firstOpenedAt => $composableBuilder(
    column: $table.firstOpenedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ReadingStatesTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $ReadingStatesTable,
          ReadingStateRow,
          $$ReadingStatesTableFilterComposer,
          $$ReadingStatesTableOrderingComposer,
          $$ReadingStatesTableAnnotationComposer,
          $$ReadingStatesTableCreateCompanionBuilder,
          $$ReadingStatesTableUpdateCompanionBuilder,
          (
            ReadingStateRow,
            BaseReferences<
              _$LibraryDatabase,
              $ReadingStatesTable,
              ReadingStateRow
            >,
          ),
          ReadingStateRow,
          PrefetchHooks Function()
        > {
  $$ReadingStatesTableTableManager(
    _$LibraryDatabase db,
    $ReadingStatesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReadingStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReadingStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReadingStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> entryId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime?> firstOpenedAt = const Value.absent(),
                Value<DateTime?> lastReadAt = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<int?> revision = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReadingStatesCompanion(
                entryId: entryId,
                status: status,
                firstOpenedAt: firstOpenedAt,
                lastReadAt: lastReadAt,
                completedAt: completedAt,
                revision: revision,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String entryId,
                Value<String> status = const Value.absent(),
                Value<DateTime?> firstOpenedAt = const Value.absent(),
                Value<DateTime?> lastReadAt = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<int?> revision = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ReadingStatesCompanion.insert(
                entryId: entryId,
                status: status,
                firstOpenedAt: firstOpenedAt,
                lastReadAt: lastReadAt,
                completedAt: completedAt,
                revision: revision,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReadingStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $ReadingStatesTable,
      ReadingStateRow,
      $$ReadingStatesTableFilterComposer,
      $$ReadingStatesTableOrderingComposer,
      $$ReadingStatesTableAnnotationComposer,
      $$ReadingStatesTableCreateCompanionBuilder,
      $$ReadingStatesTableUpdateCompanionBuilder,
      (
        ReadingStateRow,
        BaseReferences<_$LibraryDatabase, $ReadingStatesTable, ReadingStateRow>,
      ),
      ReadingStateRow,
      PrefetchHooks Function()
    >;
typedef $$MeasurementsTableCreateCompanionBuilder =
    MeasurementsCompanion Function({
      required String entryId,
      required String sourceId,
      required double fraction,
      required DateTime observedAt,
      Value<int?> revision,
      Value<int> rowid,
    });
typedef $$MeasurementsTableUpdateCompanionBuilder =
    MeasurementsCompanion Function({
      Value<String> entryId,
      Value<String> sourceId,
      Value<double> fraction,
      Value<DateTime> observedAt,
      Value<int?> revision,
      Value<int> rowid,
    });

class $$MeasurementsTableFilterComposer
    extends Composer<_$LibraryDatabase, $MeasurementsTable> {
  $$MeasurementsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get entryId => $composableBuilder(
    column: $table.entryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get fraction => $composableBuilder(
    column: $table.fraction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get observedAt => $composableBuilder(
    column: $table.observedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MeasurementsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $MeasurementsTable> {
  $$MeasurementsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get entryId => $composableBuilder(
    column: $table.entryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get fraction => $composableBuilder(
    column: $table.fraction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get observedAt => $composableBuilder(
    column: $table.observedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MeasurementsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $MeasurementsTable> {
  $$MeasurementsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get entryId =>
      $composableBuilder(column: $table.entryId, builder: (column) => column);

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<double> get fraction =>
      $composableBuilder(column: $table.fraction, builder: (column) => column);

  GeneratedColumn<DateTime> get observedAt => $composableBuilder(
    column: $table.observedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);
}

class $$MeasurementsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $MeasurementsTable,
          MeasurementRow,
          $$MeasurementsTableFilterComposer,
          $$MeasurementsTableOrderingComposer,
          $$MeasurementsTableAnnotationComposer,
          $$MeasurementsTableCreateCompanionBuilder,
          $$MeasurementsTableUpdateCompanionBuilder,
          (
            MeasurementRow,
            BaseReferences<
              _$LibraryDatabase,
              $MeasurementsTable,
              MeasurementRow
            >,
          ),
          MeasurementRow,
          PrefetchHooks Function()
        > {
  $$MeasurementsTableTableManager(
    _$LibraryDatabase db,
    $MeasurementsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MeasurementsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MeasurementsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MeasurementsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> entryId = const Value.absent(),
                Value<String> sourceId = const Value.absent(),
                Value<double> fraction = const Value.absent(),
                Value<DateTime> observedAt = const Value.absent(),
                Value<int?> revision = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MeasurementsCompanion(
                entryId: entryId,
                sourceId: sourceId,
                fraction: fraction,
                observedAt: observedAt,
                revision: revision,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String entryId,
                required String sourceId,
                required double fraction,
                required DateTime observedAt,
                Value<int?> revision = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MeasurementsCompanion.insert(
                entryId: entryId,
                sourceId: sourceId,
                fraction: fraction,
                observedAt: observedAt,
                revision: revision,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MeasurementsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $MeasurementsTable,
      MeasurementRow,
      $$MeasurementsTableFilterComposer,
      $$MeasurementsTableOrderingComposer,
      $$MeasurementsTableAnnotationComposer,
      $$MeasurementsTableCreateCompanionBuilder,
      $$MeasurementsTableUpdateCompanionBuilder,
      (
        MeasurementRow,
        BaseReferences<_$LibraryDatabase, $MeasurementsTable, MeasurementRow>,
      ),
      MeasurementRow,
      PrefetchHooks Function()
    >;
typedef $$DownloadRequestsTableCreateCompanionBuilder =
    DownloadRequestsCompanion Function({
      required String id,
      Value<String?> serverId,
      required String entryId,
      Value<String?> locationId,
      required String state,
      Value<String> idempotencyKey,
      Value<String> createdBy,
      required DateTime createdAt,
      Value<String> claimedByDevice,
      Value<DateTime?> claimedAt,
      Value<DateTime?> resolvedAt,
      Value<String> failureReason,
      Value<int?> revision,
      Value<String?> localSaveTaskId,
      Value<int> rowid,
    });
typedef $$DownloadRequestsTableUpdateCompanionBuilder =
    DownloadRequestsCompanion Function({
      Value<String> id,
      Value<String?> serverId,
      Value<String> entryId,
      Value<String?> locationId,
      Value<String> state,
      Value<String> idempotencyKey,
      Value<String> createdBy,
      Value<DateTime> createdAt,
      Value<String> claimedByDevice,
      Value<DateTime?> claimedAt,
      Value<DateTime?> resolvedAt,
      Value<String> failureReason,
      Value<int?> revision,
      Value<String?> localSaveTaskId,
      Value<int> rowid,
    });

class $$DownloadRequestsTableFilterComposer
    extends Composer<_$LibraryDatabase, $DownloadRequestsTable> {
  $$DownloadRequestsTableFilterComposer({
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

  ColumnFilters<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entryId => $composableBuilder(
    column: $table.entryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get locationId => $composableBuilder(
    column: $table.locationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get claimedByDevice => $composableBuilder(
    column: $table.claimedByDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get claimedAt => $composableBuilder(
    column: $table.claimedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localSaveTaskId => $composableBuilder(
    column: $table.localSaveTaskId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DownloadRequestsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $DownloadRequestsTable> {
  $$DownloadRequestsTableOrderingComposer({
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

  ColumnOrderings<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entryId => $composableBuilder(
    column: $table.entryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locationId => $composableBuilder(
    column: $table.locationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get claimedByDevice => $composableBuilder(
    column: $table.claimedByDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get claimedAt => $composableBuilder(
    column: $table.claimedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localSaveTaskId => $composableBuilder(
    column: $table.localSaveTaskId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DownloadRequestsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $DownloadRequestsTable> {
  $$DownloadRequestsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get entryId =>
      $composableBuilder(column: $table.entryId, builder: (column) => column);

  GeneratedColumn<String> get locationId => $composableBuilder(
    column: $table.locationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdBy =>
      $composableBuilder(column: $table.createdBy, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get claimedByDevice => $composableBuilder(
    column: $table.claimedByDevice,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get claimedAt =>
      $composableBuilder(column: $table.claimedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<String> get localSaveTaskId => $composableBuilder(
    column: $table.localSaveTaskId,
    builder: (column) => column,
  );
}

class $$DownloadRequestsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $DownloadRequestsTable,
          DownloadRequestRow,
          $$DownloadRequestsTableFilterComposer,
          $$DownloadRequestsTableOrderingComposer,
          $$DownloadRequestsTableAnnotationComposer,
          $$DownloadRequestsTableCreateCompanionBuilder,
          $$DownloadRequestsTableUpdateCompanionBuilder,
          (
            DownloadRequestRow,
            BaseReferences<
              _$LibraryDatabase,
              $DownloadRequestsTable,
              DownloadRequestRow
            >,
          ),
          DownloadRequestRow,
          PrefetchHooks Function()
        > {
  $$DownloadRequestsTableTableManager(
    _$LibraryDatabase db,
    $DownloadRequestsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DownloadRequestsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DownloadRequestsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DownloadRequestsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> serverId = const Value.absent(),
                Value<String> entryId = const Value.absent(),
                Value<String?> locationId = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String> idempotencyKey = const Value.absent(),
                Value<String> createdBy = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String> claimedByDevice = const Value.absent(),
                Value<DateTime?> claimedAt = const Value.absent(),
                Value<DateTime?> resolvedAt = const Value.absent(),
                Value<String> failureReason = const Value.absent(),
                Value<int?> revision = const Value.absent(),
                Value<String?> localSaveTaskId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DownloadRequestsCompanion(
                id: id,
                serverId: serverId,
                entryId: entryId,
                locationId: locationId,
                state: state,
                idempotencyKey: idempotencyKey,
                createdBy: createdBy,
                createdAt: createdAt,
                claimedByDevice: claimedByDevice,
                claimedAt: claimedAt,
                resolvedAt: resolvedAt,
                failureReason: failureReason,
                revision: revision,
                localSaveTaskId: localSaveTaskId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> serverId = const Value.absent(),
                required String entryId,
                Value<String?> locationId = const Value.absent(),
                required String state,
                Value<String> idempotencyKey = const Value.absent(),
                Value<String> createdBy = const Value.absent(),
                required DateTime createdAt,
                Value<String> claimedByDevice = const Value.absent(),
                Value<DateTime?> claimedAt = const Value.absent(),
                Value<DateTime?> resolvedAt = const Value.absent(),
                Value<String> failureReason = const Value.absent(),
                Value<int?> revision = const Value.absent(),
                Value<String?> localSaveTaskId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DownloadRequestsCompanion.insert(
                id: id,
                serverId: serverId,
                entryId: entryId,
                locationId: locationId,
                state: state,
                idempotencyKey: idempotencyKey,
                createdBy: createdBy,
                createdAt: createdAt,
                claimedByDevice: claimedByDevice,
                claimedAt: claimedAt,
                resolvedAt: resolvedAt,
                failureReason: failureReason,
                revision: revision,
                localSaveTaskId: localSaveTaskId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DownloadRequestsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $DownloadRequestsTable,
      DownloadRequestRow,
      $$DownloadRequestsTableFilterComposer,
      $$DownloadRequestsTableOrderingComposer,
      $$DownloadRequestsTableAnnotationComposer,
      $$DownloadRequestsTableCreateCompanionBuilder,
      $$DownloadRequestsTableUpdateCompanionBuilder,
      (
        DownloadRequestRow,
        BaseReferences<
          _$LibraryDatabase,
          $DownloadRequestsTable,
          DownloadRequestRow
        >,
      ),
      DownloadRequestRow,
      PrefetchHooks Function()
    >;
typedef $$OfflineCopiesTableCreateCompanionBuilder =
    OfflineCopiesCompanion Function({
      required String id,
      required String entryId,
      required String locationUrl,
      Value<String> sourceName,
      Value<String> sourceHost,
      Value<String> sourceLanguage,
      required DateTime capturedAt,
      required String artifactFormat,
      required String contentPath,
      Value<int> byteSize,
      Value<int?> anchorIndex,
      Value<double?> anchorOffset,
      Value<bool> active,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$OfflineCopiesTableUpdateCompanionBuilder =
    OfflineCopiesCompanion Function({
      Value<String> id,
      Value<String> entryId,
      Value<String> locationUrl,
      Value<String> sourceName,
      Value<String> sourceHost,
      Value<String> sourceLanguage,
      Value<DateTime> capturedAt,
      Value<String> artifactFormat,
      Value<String> contentPath,
      Value<int> byteSize,
      Value<int?> anchorIndex,
      Value<double?> anchorOffset,
      Value<bool> active,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$OfflineCopiesTableFilterComposer
    extends Composer<_$LibraryDatabase, $OfflineCopiesTable> {
  $$OfflineCopiesTableFilterComposer({
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

  ColumnFilters<String> get entryId => $composableBuilder(
    column: $table.entryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get locationUrl => $composableBuilder(
    column: $table.locationUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceHost => $composableBuilder(
    column: $table.sourceHost,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceLanguage => $composableBuilder(
    column: $table.sourceLanguage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artifactFormat => $composableBuilder(
    column: $table.artifactFormat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentPath => $composableBuilder(
    column: $table.contentPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get anchorIndex => $composableBuilder(
    column: $table.anchorIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get anchorOffset => $composableBuilder(
    column: $table.anchorOffset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OfflineCopiesTableOrderingComposer
    extends Composer<_$LibraryDatabase, $OfflineCopiesTable> {
  $$OfflineCopiesTableOrderingComposer({
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

  ColumnOrderings<String> get entryId => $composableBuilder(
    column: $table.entryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locationUrl => $composableBuilder(
    column: $table.locationUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceHost => $composableBuilder(
    column: $table.sourceHost,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceLanguage => $composableBuilder(
    column: $table.sourceLanguage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artifactFormat => $composableBuilder(
    column: $table.artifactFormat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentPath => $composableBuilder(
    column: $table.contentPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get anchorIndex => $composableBuilder(
    column: $table.anchorIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get anchorOffset => $composableBuilder(
    column: $table.anchorOffset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OfflineCopiesTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $OfflineCopiesTable> {
  $$OfflineCopiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entryId =>
      $composableBuilder(column: $table.entryId, builder: (column) => column);

  GeneratedColumn<String> get locationUrl => $composableBuilder(
    column: $table.locationUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceHost => $composableBuilder(
    column: $table.sourceHost,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceLanguage => $composableBuilder(
    column: $table.sourceLanguage,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get artifactFormat => $composableBuilder(
    column: $table.artifactFormat,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contentPath => $composableBuilder(
    column: $table.contentPath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get byteSize =>
      $composableBuilder(column: $table.byteSize, builder: (column) => column);

  GeneratedColumn<int> get anchorIndex => $composableBuilder(
    column: $table.anchorIndex,
    builder: (column) => column,
  );

  GeneratedColumn<double> get anchorOffset => $composableBuilder(
    column: $table.anchorOffset,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$OfflineCopiesTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $OfflineCopiesTable,
          OfflineCopyRow,
          $$OfflineCopiesTableFilterComposer,
          $$OfflineCopiesTableOrderingComposer,
          $$OfflineCopiesTableAnnotationComposer,
          $$OfflineCopiesTableCreateCompanionBuilder,
          $$OfflineCopiesTableUpdateCompanionBuilder,
          (
            OfflineCopyRow,
            BaseReferences<
              _$LibraryDatabase,
              $OfflineCopiesTable,
              OfflineCopyRow
            >,
          ),
          OfflineCopyRow,
          PrefetchHooks Function()
        > {
  $$OfflineCopiesTableTableManager(
    _$LibraryDatabase db,
    $OfflineCopiesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OfflineCopiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OfflineCopiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OfflineCopiesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> entryId = const Value.absent(),
                Value<String> locationUrl = const Value.absent(),
                Value<String> sourceName = const Value.absent(),
                Value<String> sourceHost = const Value.absent(),
                Value<String> sourceLanguage = const Value.absent(),
                Value<DateTime> capturedAt = const Value.absent(),
                Value<String> artifactFormat = const Value.absent(),
                Value<String> contentPath = const Value.absent(),
                Value<int> byteSize = const Value.absent(),
                Value<int?> anchorIndex = const Value.absent(),
                Value<double?> anchorOffset = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OfflineCopiesCompanion(
                id: id,
                entryId: entryId,
                locationUrl: locationUrl,
                sourceName: sourceName,
                sourceHost: sourceHost,
                sourceLanguage: sourceLanguage,
                capturedAt: capturedAt,
                artifactFormat: artifactFormat,
                contentPath: contentPath,
                byteSize: byteSize,
                anchorIndex: anchorIndex,
                anchorOffset: anchorOffset,
                active: active,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String entryId,
                required String locationUrl,
                Value<String> sourceName = const Value.absent(),
                Value<String> sourceHost = const Value.absent(),
                Value<String> sourceLanguage = const Value.absent(),
                required DateTime capturedAt,
                required String artifactFormat,
                required String contentPath,
                Value<int> byteSize = const Value.absent(),
                Value<int?> anchorIndex = const Value.absent(),
                Value<double?> anchorOffset = const Value.absent(),
                Value<bool> active = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => OfflineCopiesCompanion.insert(
                id: id,
                entryId: entryId,
                locationUrl: locationUrl,
                sourceName: sourceName,
                sourceHost: sourceHost,
                sourceLanguage: sourceLanguage,
                capturedAt: capturedAt,
                artifactFormat: artifactFormat,
                contentPath: contentPath,
                byteSize: byteSize,
                anchorIndex: anchorIndex,
                anchorOffset: anchorOffset,
                active: active,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OfflineCopiesTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $OfflineCopiesTable,
      OfflineCopyRow,
      $$OfflineCopiesTableFilterComposer,
      $$OfflineCopiesTableOrderingComposer,
      $$OfflineCopiesTableAnnotationComposer,
      $$OfflineCopiesTableCreateCompanionBuilder,
      $$OfflineCopiesTableUpdateCompanionBuilder,
      (
        OfflineCopyRow,
        BaseReferences<_$LibraryDatabase, $OfflineCopiesTable, OfflineCopyRow>,
      ),
      OfflineCopyRow,
      PrefetchHooks Function()
    >;
typedef $$SaveQueueTableCreateCompanionBuilder =
    SaveQueueCompanion Function({
      required String id,
      required String entryId,
      Value<String?> locationId,
      required String locationUrl,
      Value<String?> captureMode,
      Value<bool> captureModeIsUserSet,
      Value<String> state,
      Value<String> origin,
      Value<String?> outcome,
      Value<String?> lastError,
      Value<String?> stopReason,
      Value<int> orderIndex,
      required DateTime queuedAt,
      Value<DateTime?> startedAt,
      Value<DateTime?> finishedAt,
      Value<int> rowid,
    });
typedef $$SaveQueueTableUpdateCompanionBuilder =
    SaveQueueCompanion Function({
      Value<String> id,
      Value<String> entryId,
      Value<String?> locationId,
      Value<String> locationUrl,
      Value<String?> captureMode,
      Value<bool> captureModeIsUserSet,
      Value<String> state,
      Value<String> origin,
      Value<String?> outcome,
      Value<String?> lastError,
      Value<String?> stopReason,
      Value<int> orderIndex,
      Value<DateTime> queuedAt,
      Value<DateTime?> startedAt,
      Value<DateTime?> finishedAt,
      Value<int> rowid,
    });

class $$SaveQueueTableFilterComposer
    extends Composer<_$LibraryDatabase, $SaveQueueTable> {
  $$SaveQueueTableFilterComposer({
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

  ColumnFilters<String> get entryId => $composableBuilder(
    column: $table.entryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get locationId => $composableBuilder(
    column: $table.locationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get locationUrl => $composableBuilder(
    column: $table.locationUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get captureMode => $composableBuilder(
    column: $table.captureMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get captureModeIsUserSet => $composableBuilder(
    column: $table.captureModeIsUserSet,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get outcome => $composableBuilder(
    column: $table.outcome,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stopReason => $composableBuilder(
    column: $table.stopReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get queuedAt => $composableBuilder(
    column: $table.queuedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SaveQueueTableOrderingComposer
    extends Composer<_$LibraryDatabase, $SaveQueueTable> {
  $$SaveQueueTableOrderingComposer({
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

  ColumnOrderings<String> get entryId => $composableBuilder(
    column: $table.entryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locationId => $composableBuilder(
    column: $table.locationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locationUrl => $composableBuilder(
    column: $table.locationUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get captureMode => $composableBuilder(
    column: $table.captureMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get captureModeIsUserSet => $composableBuilder(
    column: $table.captureModeIsUserSet,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get outcome => $composableBuilder(
    column: $table.outcome,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stopReason => $composableBuilder(
    column: $table.stopReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get queuedAt => $composableBuilder(
    column: $table.queuedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SaveQueueTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $SaveQueueTable> {
  $$SaveQueueTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entryId =>
      $composableBuilder(column: $table.entryId, builder: (column) => column);

  GeneratedColumn<String> get locationId => $composableBuilder(
    column: $table.locationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get locationUrl => $composableBuilder(
    column: $table.locationUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get captureMode => $composableBuilder(
    column: $table.captureMode,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get captureModeIsUserSet => $composableBuilder(
    column: $table.captureModeIsUserSet,
    builder: (column) => column,
  );

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<String> get outcome =>
      $composableBuilder(column: $table.outcome, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<String> get stopReason => $composableBuilder(
    column: $table.stopReason,
    builder: (column) => column,
  );

  GeneratedColumn<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get queuedAt =>
      $composableBuilder(column: $table.queuedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => column,
  );
}

class $$SaveQueueTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $SaveQueueTable,
          SaveTaskRow,
          $$SaveQueueTableFilterComposer,
          $$SaveQueueTableOrderingComposer,
          $$SaveQueueTableAnnotationComposer,
          $$SaveQueueTableCreateCompanionBuilder,
          $$SaveQueueTableUpdateCompanionBuilder,
          (
            SaveTaskRow,
            BaseReferences<_$LibraryDatabase, $SaveQueueTable, SaveTaskRow>,
          ),
          SaveTaskRow,
          PrefetchHooks Function()
        > {
  $$SaveQueueTableTableManager(_$LibraryDatabase db, $SaveQueueTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SaveQueueTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SaveQueueTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SaveQueueTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> entryId = const Value.absent(),
                Value<String?> locationId = const Value.absent(),
                Value<String> locationUrl = const Value.absent(),
                Value<String?> captureMode = const Value.absent(),
                Value<bool> captureModeIsUserSet = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String> origin = const Value.absent(),
                Value<String?> outcome = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<String?> stopReason = const Value.absent(),
                Value<int> orderIndex = const Value.absent(),
                Value<DateTime> queuedAt = const Value.absent(),
                Value<DateTime?> startedAt = const Value.absent(),
                Value<DateTime?> finishedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SaveQueueCompanion(
                id: id,
                entryId: entryId,
                locationId: locationId,
                locationUrl: locationUrl,
                captureMode: captureMode,
                captureModeIsUserSet: captureModeIsUserSet,
                state: state,
                origin: origin,
                outcome: outcome,
                lastError: lastError,
                stopReason: stopReason,
                orderIndex: orderIndex,
                queuedAt: queuedAt,
                startedAt: startedAt,
                finishedAt: finishedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String entryId,
                Value<String?> locationId = const Value.absent(),
                required String locationUrl,
                Value<String?> captureMode = const Value.absent(),
                Value<bool> captureModeIsUserSet = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String> origin = const Value.absent(),
                Value<String?> outcome = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<String?> stopReason = const Value.absent(),
                Value<int> orderIndex = const Value.absent(),
                required DateTime queuedAt,
                Value<DateTime?> startedAt = const Value.absent(),
                Value<DateTime?> finishedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SaveQueueCompanion.insert(
                id: id,
                entryId: entryId,
                locationId: locationId,
                locationUrl: locationUrl,
                captureMode: captureMode,
                captureModeIsUserSet: captureModeIsUserSet,
                state: state,
                origin: origin,
                outcome: outcome,
                lastError: lastError,
                stopReason: stopReason,
                orderIndex: orderIndex,
                queuedAt: queuedAt,
                startedAt: startedAt,
                finishedAt: finishedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SaveQueueTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $SaveQueueTable,
      SaveTaskRow,
      $$SaveQueueTableFilterComposer,
      $$SaveQueueTableOrderingComposer,
      $$SaveQueueTableAnnotationComposer,
      $$SaveQueueTableCreateCompanionBuilder,
      $$SaveQueueTableUpdateCompanionBuilder,
      (
        SaveTaskRow,
        BaseReferences<_$LibraryDatabase, $SaveQueueTable, SaveTaskRow>,
      ),
      SaveTaskRow,
      PrefetchHooks Function()
    >;
typedef $$HistoryTableCreateCompanionBuilder =
    HistoryCompanion Function({
      required String id,
      required String url,
      required String urlKey,
      required String host,
      required String title,
      Value<String> source,
      Value<String?> finalUrl,
      Value<bool> completed,
      required DateTime visitedAt,
      Value<int> rowid,
    });
typedef $$HistoryTableUpdateCompanionBuilder =
    HistoryCompanion Function({
      Value<String> id,
      Value<String> url,
      Value<String> urlKey,
      Value<String> host,
      Value<String> title,
      Value<String> source,
      Value<String?> finalUrl,
      Value<bool> completed,
      Value<DateTime> visitedAt,
      Value<int> rowid,
    });

class $$HistoryTableFilterComposer
    extends Composer<_$LibraryDatabase, $HistoryTable> {
  $$HistoryTableFilterComposer({
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

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get urlKey => $composableBuilder(
    column: $table.urlKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get finalUrl => $composableBuilder(
    column: $table.finalUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get visitedAt => $composableBuilder(
    column: $table.visitedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HistoryTableOrderingComposer
    extends Composer<_$LibraryDatabase, $HistoryTable> {
  $$HistoryTableOrderingComposer({
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

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get urlKey => $composableBuilder(
    column: $table.urlKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get finalUrl => $composableBuilder(
    column: $table.finalUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get visitedAt => $composableBuilder(
    column: $table.visitedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HistoryTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $HistoryTable> {
  $$HistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get urlKey =>
      $composableBuilder(column: $table.urlKey, builder: (column) => column);

  GeneratedColumn<String> get host =>
      $composableBuilder(column: $table.host, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get finalUrl =>
      $composableBuilder(column: $table.finalUrl, builder: (column) => column);

  GeneratedColumn<bool> get completed =>
      $composableBuilder(column: $table.completed, builder: (column) => column);

  GeneratedColumn<DateTime> get visitedAt =>
      $composableBuilder(column: $table.visitedAt, builder: (column) => column);
}

class $$HistoryTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $HistoryTable,
          HistoryRow,
          $$HistoryTableFilterComposer,
          $$HistoryTableOrderingComposer,
          $$HistoryTableAnnotationComposer,
          $$HistoryTableCreateCompanionBuilder,
          $$HistoryTableUpdateCompanionBuilder,
          (
            HistoryRow,
            BaseReferences<_$LibraryDatabase, $HistoryTable, HistoryRow>,
          ),
          HistoryRow,
          PrefetchHooks Function()
        > {
  $$HistoryTableTableManager(_$LibraryDatabase db, $HistoryTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<String> urlKey = const Value.absent(),
                Value<String> host = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String?> finalUrl = const Value.absent(),
                Value<bool> completed = const Value.absent(),
                Value<DateTime> visitedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HistoryCompanion(
                id: id,
                url: url,
                urlKey: urlKey,
                host: host,
                title: title,
                source: source,
                finalUrl: finalUrl,
                completed: completed,
                visitedAt: visitedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String url,
                required String urlKey,
                required String host,
                required String title,
                Value<String> source = const Value.absent(),
                Value<String?> finalUrl = const Value.absent(),
                Value<bool> completed = const Value.absent(),
                required DateTime visitedAt,
                Value<int> rowid = const Value.absent(),
              }) => HistoryCompanion.insert(
                id: id,
                url: url,
                urlKey: urlKey,
                host: host,
                title: title,
                source: source,
                finalUrl: finalUrl,
                completed: completed,
                visitedAt: visitedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HistoryTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $HistoryTable,
      HistoryRow,
      $$HistoryTableFilterComposer,
      $$HistoryTableOrderingComposer,
      $$HistoryTableAnnotationComposer,
      $$HistoryTableCreateCompanionBuilder,
      $$HistoryTableUpdateCompanionBuilder,
      (
        HistoryRow,
        BaseReferences<_$LibraryDatabase, $HistoryTable, HistoryRow>,
      ),
      HistoryRow,
      PrefetchHooks Function()
    >;
typedef $$OutboxTableCreateCompanionBuilder =
    OutboxCompanion Function({
      Value<int> opId,
      required String mutationId,
      required String entityKind,
      required String entityId,
      required String op,
      required String payload,
      required DateTime createdAt,
      Value<int> attempts,
      Value<String?> lastError,
    });
typedef $$OutboxTableUpdateCompanionBuilder =
    OutboxCompanion Function({
      Value<int> opId,
      Value<String> mutationId,
      Value<String> entityKind,
      Value<String> entityId,
      Value<String> op,
      Value<String> payload,
      Value<DateTime> createdAt,
      Value<int> attempts,
      Value<String?> lastError,
    });

class $$OutboxTableFilterComposer
    extends Composer<_$LibraryDatabase, $OutboxTable> {
  $$OutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get opId => $composableBuilder(
    column: $table.opId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mutationId => $composableBuilder(
    column: $table.mutationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityKind => $composableBuilder(
    column: $table.entityKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get op => $composableBuilder(
    column: $table.op,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutboxTableOrderingComposer
    extends Composer<_$LibraryDatabase, $OutboxTable> {
  $$OutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get opId => $composableBuilder(
    column: $table.opId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mutationId => $composableBuilder(
    column: $table.mutationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityKind => $composableBuilder(
    column: $table.entityKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get op => $composableBuilder(
    column: $table.op,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboxTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $OutboxTable> {
  $$OutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get opId =>
      $composableBuilder(column: $table.opId, builder: (column) => column);

  GeneratedColumn<String> get mutationId => $composableBuilder(
    column: $table.mutationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityKind => $composableBuilder(
    column: $table.entityKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get op =>
      $composableBuilder(column: $table.op, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$OutboxTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $OutboxTable,
          OutboxRow,
          $$OutboxTableFilterComposer,
          $$OutboxTableOrderingComposer,
          $$OutboxTableAnnotationComposer,
          $$OutboxTableCreateCompanionBuilder,
          $$OutboxTableUpdateCompanionBuilder,
          (
            OutboxRow,
            BaseReferences<_$LibraryDatabase, $OutboxTable, OutboxRow>,
          ),
          OutboxRow,
          PrefetchHooks Function()
        > {
  $$OutboxTableTableManager(_$LibraryDatabase db, $OutboxTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> opId = const Value.absent(),
                Value<String> mutationId = const Value.absent(),
                Value<String> entityKind = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> op = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
              }) => OutboxCompanion(
                opId: opId,
                mutationId: mutationId,
                entityKind: entityKind,
                entityId: entityId,
                op: op,
                payload: payload,
                createdAt: createdAt,
                attempts: attempts,
                lastError: lastError,
              ),
          createCompanionCallback:
              ({
                Value<int> opId = const Value.absent(),
                required String mutationId,
                required String entityKind,
                required String entityId,
                required String op,
                required String payload,
                required DateTime createdAt,
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
              }) => OutboxCompanion.insert(
                opId: opId,
                mutationId: mutationId,
                entityKind: entityKind,
                entityId: entityId,
                op: op,
                payload: payload,
                createdAt: createdAt,
                attempts: attempts,
                lastError: lastError,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $OutboxTable,
      OutboxRow,
      $$OutboxTableFilterComposer,
      $$OutboxTableOrderingComposer,
      $$OutboxTableAnnotationComposer,
      $$OutboxTableCreateCompanionBuilder,
      $$OutboxTableUpdateCompanionBuilder,
      (OutboxRow, BaseReferences<_$LibraryDatabase, $OutboxTable, OutboxRow>),
      OutboxRow,
      PrefetchHooks Function()
    >;
typedef $$SyncStateTableCreateCompanionBuilder =
    SyncStateCompanion Function({
      Value<int> id,
      Value<int> cursor,
      Value<DateTime?> lastSuccessAt,
      Value<DateTime?> lastAttemptAt,
      Value<String?> lastError,
    });
typedef $$SyncStateTableUpdateCompanionBuilder =
    SyncStateCompanion Function({
      Value<int> id,
      Value<int> cursor,
      Value<DateTime?> lastSuccessAt,
      Value<DateTime?> lastAttemptAt,
      Value<String?> lastError,
    });

class $$SyncStateTableFilterComposer
    extends Composer<_$LibraryDatabase, $SyncStateTable> {
  $$SyncStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cursor => $composableBuilder(
    column: $table.cursor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSuccessAt => $composableBuilder(
    column: $table.lastSuccessAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncStateTableOrderingComposer
    extends Composer<_$LibraryDatabase, $SyncStateTable> {
  $$SyncStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cursor => $composableBuilder(
    column: $table.cursor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSuccessAt => $composableBuilder(
    column: $table.lastSuccessAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncStateTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $SyncStateTable> {
  $$SyncStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get cursor =>
      $composableBuilder(column: $table.cursor, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSuccessAt => $composableBuilder(
    column: $table.lastSuccessAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$SyncStateTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $SyncStateTable,
          SyncStateRow,
          $$SyncStateTableFilterComposer,
          $$SyncStateTableOrderingComposer,
          $$SyncStateTableAnnotationComposer,
          $$SyncStateTableCreateCompanionBuilder,
          $$SyncStateTableUpdateCompanionBuilder,
          (
            SyncStateRow,
            BaseReferences<_$LibraryDatabase, $SyncStateTable, SyncStateRow>,
          ),
          SyncStateRow,
          PrefetchHooks Function()
        > {
  $$SyncStateTableTableManager(_$LibraryDatabase db, $SyncStateTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> cursor = const Value.absent(),
                Value<DateTime?> lastSuccessAt = const Value.absent(),
                Value<DateTime?> lastAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
              }) => SyncStateCompanion(
                id: id,
                cursor: cursor,
                lastSuccessAt: lastSuccessAt,
                lastAttemptAt: lastAttemptAt,
                lastError: lastError,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> cursor = const Value.absent(),
                Value<DateTime?> lastSuccessAt = const Value.absent(),
                Value<DateTime?> lastAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
              }) => SyncStateCompanion.insert(
                id: id,
                cursor: cursor,
                lastSuccessAt: lastSuccessAt,
                lastAttemptAt: lastAttemptAt,
                lastError: lastError,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncStateTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $SyncStateTable,
      SyncStateRow,
      $$SyncStateTableFilterComposer,
      $$SyncStateTableOrderingComposer,
      $$SyncStateTableAnnotationComposer,
      $$SyncStateTableCreateCompanionBuilder,
      $$SyncStateTableUpdateCompanionBuilder,
      (
        SyncStateRow,
        BaseReferences<_$LibraryDatabase, $SyncStateTable, SyncStateRow>,
      ),
      SyncStateRow,
      PrefetchHooks Function()
    >;
typedef $$PageHintsTableCreateCompanionBuilder =
    PageHintsCompanion Function({
      required String id,
      required String host,
      Value<String?> hintPath,
      required String scope,
      required String kind,
      required String locatorJson,
      Value<String?> exampleSourceUrl,
      Value<String?> exampleTargetUrl,
      Value<bool> sameHostOnly,
      required DateTime createdAt,
      Value<DateTime?> lastUsedAt,
      Value<int> successCount,
      Value<int> failureCount,
      Value<int> rowid,
    });
typedef $$PageHintsTableUpdateCompanionBuilder =
    PageHintsCompanion Function({
      Value<String> id,
      Value<String> host,
      Value<String?> hintPath,
      Value<String> scope,
      Value<String> kind,
      Value<String> locatorJson,
      Value<String?> exampleSourceUrl,
      Value<String?> exampleTargetUrl,
      Value<bool> sameHostOnly,
      Value<DateTime> createdAt,
      Value<DateTime?> lastUsedAt,
      Value<int> successCount,
      Value<int> failureCount,
      Value<int> rowid,
    });

class $$PageHintsTableFilterComposer
    extends Composer<_$LibraryDatabase, $PageHintsTable> {
  $$PageHintsTableFilterComposer({
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

  ColumnFilters<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hintPath => $composableBuilder(
    column: $table.hintPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get locatorJson => $composableBuilder(
    column: $table.locatorJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get exampleSourceUrl => $composableBuilder(
    column: $table.exampleSourceUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get exampleTargetUrl => $composableBuilder(
    column: $table.exampleTargetUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get sameHostOnly => $composableBuilder(
    column: $table.sameHostOnly,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get successCount => $composableBuilder(
    column: $table.successCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get failureCount => $composableBuilder(
    column: $table.failureCount,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PageHintsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $PageHintsTable> {
  $$PageHintsTableOrderingComposer({
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

  ColumnOrderings<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hintPath => $composableBuilder(
    column: $table.hintPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locatorJson => $composableBuilder(
    column: $table.locatorJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get exampleSourceUrl => $composableBuilder(
    column: $table.exampleSourceUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get exampleTargetUrl => $composableBuilder(
    column: $table.exampleTargetUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get sameHostOnly => $composableBuilder(
    column: $table.sameHostOnly,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get successCount => $composableBuilder(
    column: $table.successCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get failureCount => $composableBuilder(
    column: $table.failureCount,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PageHintsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $PageHintsTable> {
  $$PageHintsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get host =>
      $composableBuilder(column: $table.host, builder: (column) => column);

  GeneratedColumn<String> get hintPath =>
      $composableBuilder(column: $table.hintPath, builder: (column) => column);

  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get locatorJson => $composableBuilder(
    column: $table.locatorJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get exampleSourceUrl => $composableBuilder(
    column: $table.exampleSourceUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get exampleTargetUrl => $composableBuilder(
    column: $table.exampleTargetUrl,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get sameHostOnly => $composableBuilder(
    column: $table.sameHostOnly,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get successCount => $composableBuilder(
    column: $table.successCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get failureCount => $composableBuilder(
    column: $table.failureCount,
    builder: (column) => column,
  );
}

class $$PageHintsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $PageHintsTable,
          PageHintRow,
          $$PageHintsTableFilterComposer,
          $$PageHintsTableOrderingComposer,
          $$PageHintsTableAnnotationComposer,
          $$PageHintsTableCreateCompanionBuilder,
          $$PageHintsTableUpdateCompanionBuilder,
          (
            PageHintRow,
            BaseReferences<_$LibraryDatabase, $PageHintsTable, PageHintRow>,
          ),
          PageHintRow,
          PrefetchHooks Function()
        > {
  $$PageHintsTableTableManager(_$LibraryDatabase db, $PageHintsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PageHintsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PageHintsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PageHintsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> host = const Value.absent(),
                Value<String?> hintPath = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> locatorJson = const Value.absent(),
                Value<String?> exampleSourceUrl = const Value.absent(),
                Value<String?> exampleTargetUrl = const Value.absent(),
                Value<bool> sameHostOnly = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> lastUsedAt = const Value.absent(),
                Value<int> successCount = const Value.absent(),
                Value<int> failureCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PageHintsCompanion(
                id: id,
                host: host,
                hintPath: hintPath,
                scope: scope,
                kind: kind,
                locatorJson: locatorJson,
                exampleSourceUrl: exampleSourceUrl,
                exampleTargetUrl: exampleTargetUrl,
                sameHostOnly: sameHostOnly,
                createdAt: createdAt,
                lastUsedAt: lastUsedAt,
                successCount: successCount,
                failureCount: failureCount,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String host,
                Value<String?> hintPath = const Value.absent(),
                required String scope,
                required String kind,
                required String locatorJson,
                Value<String?> exampleSourceUrl = const Value.absent(),
                Value<String?> exampleTargetUrl = const Value.absent(),
                Value<bool> sameHostOnly = const Value.absent(),
                required DateTime createdAt,
                Value<DateTime?> lastUsedAt = const Value.absent(),
                Value<int> successCount = const Value.absent(),
                Value<int> failureCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PageHintsCompanion.insert(
                id: id,
                host: host,
                hintPath: hintPath,
                scope: scope,
                kind: kind,
                locatorJson: locatorJson,
                exampleSourceUrl: exampleSourceUrl,
                exampleTargetUrl: exampleTargetUrl,
                sameHostOnly: sameHostOnly,
                createdAt: createdAt,
                lastUsedAt: lastUsedAt,
                successCount: successCount,
                failureCount: failureCount,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PageHintsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $PageHintsTable,
      PageHintRow,
      $$PageHintsTableFilterComposer,
      $$PageHintsTableOrderingComposer,
      $$PageHintsTableAnnotationComposer,
      $$PageHintsTableCreateCompanionBuilder,
      $$PageHintsTableUpdateCompanionBuilder,
      (
        PageHintRow,
        BaseReferences<_$LibraryDatabase, $PageHintsTable, PageHintRow>,
      ),
      PageHintRow,
      PrefetchHooks Function()
    >;
typedef $$SavedSitesTableCreateCompanionBuilder =
    SavedSitesCompanion Function({
      required String id,
      required String url,
      required String urlKey,
      required String host,
      required String title,
      Value<String?> userTitle,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> lastOpenedAt,
      Value<int> orderIndex,
      Value<int> rowid,
    });
typedef $$SavedSitesTableUpdateCompanionBuilder =
    SavedSitesCompanion Function({
      Value<String> id,
      Value<String> url,
      Value<String> urlKey,
      Value<String> host,
      Value<String> title,
      Value<String?> userTitle,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> lastOpenedAt,
      Value<int> orderIndex,
      Value<int> rowid,
    });

class $$SavedSitesTableFilterComposer
    extends Composer<_$LibraryDatabase, $SavedSitesTable> {
  $$SavedSitesTableFilterComposer({
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

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get urlKey => $composableBuilder(
    column: $table.urlKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userTitle => $composableBuilder(
    column: $table.userTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastOpenedAt => $composableBuilder(
    column: $table.lastOpenedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SavedSitesTableOrderingComposer
    extends Composer<_$LibraryDatabase, $SavedSitesTable> {
  $$SavedSitesTableOrderingComposer({
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

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get urlKey => $composableBuilder(
    column: $table.urlKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userTitle => $composableBuilder(
    column: $table.userTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastOpenedAt => $composableBuilder(
    column: $table.lastOpenedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SavedSitesTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $SavedSitesTable> {
  $$SavedSitesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get urlKey =>
      $composableBuilder(column: $table.urlKey, builder: (column) => column);

  GeneratedColumn<String> get host =>
      $composableBuilder(column: $table.host, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get userTitle =>
      $composableBuilder(column: $table.userTitle, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastOpenedAt => $composableBuilder(
    column: $table.lastOpenedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => column,
  );
}

class $$SavedSitesTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $SavedSitesTable,
          SavedSiteRow,
          $$SavedSitesTableFilterComposer,
          $$SavedSitesTableOrderingComposer,
          $$SavedSitesTableAnnotationComposer,
          $$SavedSitesTableCreateCompanionBuilder,
          $$SavedSitesTableUpdateCompanionBuilder,
          (
            SavedSiteRow,
            BaseReferences<_$LibraryDatabase, $SavedSitesTable, SavedSiteRow>,
          ),
          SavedSiteRow,
          PrefetchHooks Function()
        > {
  $$SavedSitesTableTableManager(_$LibraryDatabase db, $SavedSitesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SavedSitesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SavedSitesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SavedSitesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<String> urlKey = const Value.absent(),
                Value<String> host = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> userTitle = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> lastOpenedAt = const Value.absent(),
                Value<int> orderIndex = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SavedSitesCompanion(
                id: id,
                url: url,
                urlKey: urlKey,
                host: host,
                title: title,
                userTitle: userTitle,
                createdAt: createdAt,
                updatedAt: updatedAt,
                lastOpenedAt: lastOpenedAt,
                orderIndex: orderIndex,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String url,
                required String urlKey,
                required String host,
                required String title,
                Value<String?> userTitle = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> lastOpenedAt = const Value.absent(),
                Value<int> orderIndex = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SavedSitesCompanion.insert(
                id: id,
                url: url,
                urlKey: urlKey,
                host: host,
                title: title,
                userTitle: userTitle,
                createdAt: createdAt,
                updatedAt: updatedAt,
                lastOpenedAt: lastOpenedAt,
                orderIndex: orderIndex,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SavedSitesTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $SavedSitesTable,
      SavedSiteRow,
      $$SavedSitesTableFilterComposer,
      $$SavedSitesTableOrderingComposer,
      $$SavedSitesTableAnnotationComposer,
      $$SavedSitesTableCreateCompanionBuilder,
      $$SavedSitesTableUpdateCompanionBuilder,
      (
        SavedSiteRow,
        BaseReferences<_$LibraryDatabase, $SavedSitesTable, SavedSiteRow>,
      ),
      SavedSiteRow,
      PrefetchHooks Function()
    >;
typedef $$FaviconsTableCreateCompanionBuilder =
    FaviconsCompanion Function({
      required String host,
      Value<Uint8List?> bytes,
      Value<String?> sourceUrl,
      required DateTime fetchedAt,
      Value<int> rowid,
    });
typedef $$FaviconsTableUpdateCompanionBuilder =
    FaviconsCompanion Function({
      Value<String> host,
      Value<Uint8List?> bytes,
      Value<String?> sourceUrl,
      Value<DateTime> fetchedAt,
      Value<int> rowid,
    });

class $$FaviconsTableFilterComposer
    extends Composer<_$LibraryDatabase, $FaviconsTable> {
  $$FaviconsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceUrl => $composableBuilder(
    column: $table.sourceUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FaviconsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $FaviconsTable> {
  $$FaviconsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceUrl => $composableBuilder(
    column: $table.sourceUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FaviconsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $FaviconsTable> {
  $$FaviconsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get host =>
      $composableBuilder(column: $table.host, builder: (column) => column);

  GeneratedColumn<Uint8List> get bytes =>
      $composableBuilder(column: $table.bytes, builder: (column) => column);

  GeneratedColumn<String> get sourceUrl =>
      $composableBuilder(column: $table.sourceUrl, builder: (column) => column);

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$FaviconsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $FaviconsTable,
          FaviconRow,
          $$FaviconsTableFilterComposer,
          $$FaviconsTableOrderingComposer,
          $$FaviconsTableAnnotationComposer,
          $$FaviconsTableCreateCompanionBuilder,
          $$FaviconsTableUpdateCompanionBuilder,
          (
            FaviconRow,
            BaseReferences<_$LibraryDatabase, $FaviconsTable, FaviconRow>,
          ),
          FaviconRow,
          PrefetchHooks Function()
        > {
  $$FaviconsTableTableManager(_$LibraryDatabase db, $FaviconsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FaviconsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FaviconsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FaviconsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> host = const Value.absent(),
                Value<Uint8List?> bytes = const Value.absent(),
                Value<String?> sourceUrl = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FaviconsCompanion(
                host: host,
                bytes: bytes,
                sourceUrl: sourceUrl,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String host,
                Value<Uint8List?> bytes = const Value.absent(),
                Value<String?> sourceUrl = const Value.absent(),
                required DateTime fetchedAt,
                Value<int> rowid = const Value.absent(),
              }) => FaviconsCompanion.insert(
                host: host,
                bytes: bytes,
                sourceUrl: sourceUrl,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FaviconsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $FaviconsTable,
      FaviconRow,
      $$FaviconsTableFilterComposer,
      $$FaviconsTableOrderingComposer,
      $$FaviconsTableAnnotationComposer,
      $$FaviconsTableCreateCompanionBuilder,
      $$FaviconsTableUpdateCompanionBuilder,
      (
        FaviconRow,
        BaseReferences<_$LibraryDatabase, $FaviconsTable, FaviconRow>,
      ),
      FaviconRow,
      PrefetchHooks Function()
    >;
typedef $$AssetOriginsTableCreateCompanionBuilder =
    AssetOriginsCompanion Function({
      required String origin,
      Value<String> verdict,
      Value<int> refusedCaptures,
      Value<String?> lastRefusedLocationKey,
      Value<DateTime?> lastServedAt,
      Value<DateTime?> firstRefusedAt,
      Value<DateTime?> establishedAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$AssetOriginsTableUpdateCompanionBuilder =
    AssetOriginsCompanion Function({
      Value<String> origin,
      Value<String> verdict,
      Value<int> refusedCaptures,
      Value<String?> lastRefusedLocationKey,
      Value<DateTime?> lastServedAt,
      Value<DateTime?> firstRefusedAt,
      Value<DateTime?> establishedAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$AssetOriginsTableFilterComposer
    extends Composer<_$LibraryDatabase, $AssetOriginsTable> {
  $$AssetOriginsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get verdict => $composableBuilder(
    column: $table.verdict,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get refusedCaptures => $composableBuilder(
    column: $table.refusedCaptures,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastRefusedLocationKey => $composableBuilder(
    column: $table.lastRefusedLocationKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastServedAt => $composableBuilder(
    column: $table.lastServedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get firstRefusedAt => $composableBuilder(
    column: $table.firstRefusedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get establishedAt => $composableBuilder(
    column: $table.establishedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AssetOriginsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $AssetOriginsTable> {
  $$AssetOriginsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get verdict => $composableBuilder(
    column: $table.verdict,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get refusedCaptures => $composableBuilder(
    column: $table.refusedCaptures,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastRefusedLocationKey => $composableBuilder(
    column: $table.lastRefusedLocationKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastServedAt => $composableBuilder(
    column: $table.lastServedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get firstRefusedAt => $composableBuilder(
    column: $table.firstRefusedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get establishedAt => $composableBuilder(
    column: $table.establishedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AssetOriginsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $AssetOriginsTable> {
  $$AssetOriginsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<String> get verdict =>
      $composableBuilder(column: $table.verdict, builder: (column) => column);

  GeneratedColumn<int> get refusedCaptures => $composableBuilder(
    column: $table.refusedCaptures,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastRefusedLocationKey => $composableBuilder(
    column: $table.lastRefusedLocationKey,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastServedAt => $composableBuilder(
    column: $table.lastServedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get firstRefusedAt => $composableBuilder(
    column: $table.firstRefusedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get establishedAt => $composableBuilder(
    column: $table.establishedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AssetOriginsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $AssetOriginsTable,
          AssetOriginRow,
          $$AssetOriginsTableFilterComposer,
          $$AssetOriginsTableOrderingComposer,
          $$AssetOriginsTableAnnotationComposer,
          $$AssetOriginsTableCreateCompanionBuilder,
          $$AssetOriginsTableUpdateCompanionBuilder,
          (
            AssetOriginRow,
            BaseReferences<
              _$LibraryDatabase,
              $AssetOriginsTable,
              AssetOriginRow
            >,
          ),
          AssetOriginRow,
          PrefetchHooks Function()
        > {
  $$AssetOriginsTableTableManager(
    _$LibraryDatabase db,
    $AssetOriginsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AssetOriginsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AssetOriginsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AssetOriginsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> origin = const Value.absent(),
                Value<String> verdict = const Value.absent(),
                Value<int> refusedCaptures = const Value.absent(),
                Value<String?> lastRefusedLocationKey = const Value.absent(),
                Value<DateTime?> lastServedAt = const Value.absent(),
                Value<DateTime?> firstRefusedAt = const Value.absent(),
                Value<DateTime?> establishedAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AssetOriginsCompanion(
                origin: origin,
                verdict: verdict,
                refusedCaptures: refusedCaptures,
                lastRefusedLocationKey: lastRefusedLocationKey,
                lastServedAt: lastServedAt,
                firstRefusedAt: firstRefusedAt,
                establishedAt: establishedAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String origin,
                Value<String> verdict = const Value.absent(),
                Value<int> refusedCaptures = const Value.absent(),
                Value<String?> lastRefusedLocationKey = const Value.absent(),
                Value<DateTime?> lastServedAt = const Value.absent(),
                Value<DateTime?> firstRefusedAt = const Value.absent(),
                Value<DateTime?> establishedAt = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => AssetOriginsCompanion.insert(
                origin: origin,
                verdict: verdict,
                refusedCaptures: refusedCaptures,
                lastRefusedLocationKey: lastRefusedLocationKey,
                lastServedAt: lastServedAt,
                firstRefusedAt: firstRefusedAt,
                establishedAt: establishedAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AssetOriginsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $AssetOriginsTable,
      AssetOriginRow,
      $$AssetOriginsTableFilterComposer,
      $$AssetOriginsTableOrderingComposer,
      $$AssetOriginsTableAnnotationComposer,
      $$AssetOriginsTableCreateCompanionBuilder,
      $$AssetOriginsTableUpdateCompanionBuilder,
      (
        AssetOriginRow,
        BaseReferences<_$LibraryDatabase, $AssetOriginsTable, AssetOriginRow>,
      ),
      AssetOriginRow,
      PrefetchHooks Function()
    >;
typedef $$LocalSettingsTableCreateCompanionBuilder =
    LocalSettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$LocalSettingsTableUpdateCompanionBuilder =
    LocalSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$LocalSettingsTableFilterComposer
    extends Composer<_$LibraryDatabase, $LocalSettingsTable> {
  $$LocalSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalSettingsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $LocalSettingsTable> {
  $$LocalSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalSettingsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $LocalSettingsTable> {
  $$LocalSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$LocalSettingsTableTableManager
    extends
        RootTableManager<
          _$LibraryDatabase,
          $LocalSettingsTable,
          SettingRow,
          $$LocalSettingsTableFilterComposer,
          $$LocalSettingsTableOrderingComposer,
          $$LocalSettingsTableAnnotationComposer,
          $$LocalSettingsTableCreateCompanionBuilder,
          $$LocalSettingsTableUpdateCompanionBuilder,
          (
            SettingRow,
            BaseReferences<_$LibraryDatabase, $LocalSettingsTable, SettingRow>,
          ),
          SettingRow,
          PrefetchHooks Function()
        > {
  $$LocalSettingsTableTableManager(
    _$LibraryDatabase db,
    $LocalSettingsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) =>
                  LocalSettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => LocalSettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDatabase,
      $LocalSettingsTable,
      SettingRow,
      $$LocalSettingsTableFilterComposer,
      $$LocalSettingsTableOrderingComposer,
      $$LocalSettingsTableAnnotationComposer,
      $$LocalSettingsTableCreateCompanionBuilder,
      $$LocalSettingsTableUpdateCompanionBuilder,
      (
        SettingRow,
        BaseReferences<_$LibraryDatabase, $LocalSettingsTable, SettingRow>,
      ),
      SettingRow,
      PrefetchHooks Function()
    >;

class $LibraryDatabaseManager {
  final _$LibraryDatabase _db;
  $LibraryDatabaseManager(this._db);
  $$FoldersTableTableManager get folders =>
      $$FoldersTableTableManager(_db, _db.folders);
  $$SourcesTableTableManager get sources =>
      $$SourcesTableTableManager(_db, _db.sources);
  $$CollectionsTableTableManager get collections =>
      $$CollectionsTableTableManager(_db, _db.collections);
  $$EntriesTableTableManager get entries =>
      $$EntriesTableTableManager(_db, _db.entries);
  $$LocationsTableTableManager get locations =>
      $$LocationsTableTableManager(_db, _db.locations);
  $$ReadingStatesTableTableManager get readingStates =>
      $$ReadingStatesTableTableManager(_db, _db.readingStates);
  $$MeasurementsTableTableManager get measurements =>
      $$MeasurementsTableTableManager(_db, _db.measurements);
  $$DownloadRequestsTableTableManager get downloadRequests =>
      $$DownloadRequestsTableTableManager(_db, _db.downloadRequests);
  $$OfflineCopiesTableTableManager get offlineCopies =>
      $$OfflineCopiesTableTableManager(_db, _db.offlineCopies);
  $$SaveQueueTableTableManager get saveQueue =>
      $$SaveQueueTableTableManager(_db, _db.saveQueue);
  $$HistoryTableTableManager get history =>
      $$HistoryTableTableManager(_db, _db.history);
  $$OutboxTableTableManager get outbox =>
      $$OutboxTableTableManager(_db, _db.outbox);
  $$SyncStateTableTableManager get syncState =>
      $$SyncStateTableTableManager(_db, _db.syncState);
  $$PageHintsTableTableManager get pageHints =>
      $$PageHintsTableTableManager(_db, _db.pageHints);
  $$SavedSitesTableTableManager get savedSites =>
      $$SavedSitesTableTableManager(_db, _db.savedSites);
  $$FaviconsTableTableManager get favicons =>
      $$FaviconsTableTableManager(_db, _db.favicons);
  $$AssetOriginsTableTableManager get assetOrigins =>
      $$AssetOriginsTableTableManager(_db, _db.assetOrigins);
  $$LocalSettingsTableTableManager get localSettings =>
      $$LocalSettingsTableTableManager(_db, _db.localSettings);
}
