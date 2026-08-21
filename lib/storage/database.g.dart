// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $CollectionsTable extends Collections
    with TableInfo<$CollectionsTable, Collection> {
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
  static const VerificationMeta _sourceUrlMeta = const VerificationMeta(
    'sourceUrl',
  );
  @override
  late final GeneratedColumn<String> sourceUrl = GeneratedColumn<String>(
    'source_url',
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
  static const VerificationMeta _collectionKeyMeta = const VerificationMeta(
    'collectionKey',
  );
  @override
  late final GeneratedColumn<String> collectionKey = GeneratedColumn<String>(
    'collection_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _collectionIndexUrlMeta =
      const VerificationMeta('collectionIndexUrl');
  @override
  late final GeneratedColumn<String> collectionIndexUrl =
      GeneratedColumn<String>(
        'collection_index_url',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _identityBasisMeta = const VerificationMeta(
    'identityBasis',
  );
  @override
  late final GeneratedColumn<String> identityBasis = GeneratedColumn<String>(
    'identity_basis',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _identityConfidenceMeta =
      const VerificationMeta('identityConfidence');
  @override
  late final GeneratedColumn<String> identityConfidence =
      GeneratedColumn<String>(
        'identity_confidence',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _contentKindMeta = const VerificationMeta(
    'contentKind',
  );
  @override
  late final GeneratedColumn<String> contentKind = GeneratedColumn<String>(
    'content_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('unknownWebContent'),
  );
  static const VerificationMeta _sequenceKindMeta = const VerificationMeta(
    'sequenceKind',
  );
  @override
  late final GeneratedColumn<String> sequenceKind = GeneratedColumn<String>(
    'sequence_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('none'),
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
    requiredDuringInsert: false,
    defaultValue: const Constant('discoveryOrder'),
  );
  static const VerificationMeta _shapeConfidenceMeta = const VerificationMeta(
    'shapeConfidence',
  );
  @override
  late final GeneratedColumn<String> shapeConfidence = GeneratedColumn<String>(
    'shape_confidence',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('low'),
  );
  static const VerificationMeta _knownEntryTotalMeta = const VerificationMeta(
    'knownEntryTotal',
  );
  @override
  late final GeneratedColumn<int> knownEntryTotal = GeneratedColumn<int>(
    'known_entry_total',
    aliasedName,
    true,
    type: DriftSqlType.int,
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
  static const VerificationMeta _lastSavedAtMeta = const VerificationMeta(
    'lastSavedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSavedAt = GeneratedColumn<DateTime>(
    'last_saved_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastOpenedEntryIdMeta = const VerificationMeta(
    'lastOpenedEntryId',
  );
  @override
  late final GeneratedColumn<String> lastOpenedEntryId =
      GeneratedColumn<String>(
        'last_opened_entry_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastCompletedEntryIdMeta =
      const VerificationMeta('lastCompletedEntryId');
  @override
  late final GeneratedColumn<String> lastCompletedEntryId =
      GeneratedColumn<String>(
        'last_completed_entry_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
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
  static const VerificationMeta _lastCheckAtMeta = const VerificationMeta(
    'lastCheckAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastCheckAt = GeneratedColumn<DateTime>(
    'last_check_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastCheckSuccessAtMeta =
      const VerificationMeta('lastCheckSuccessAt');
  @override
  late final GeneratedColumn<DateTime> lastCheckSuccessAt =
      GeneratedColumn<DateTime>(
        'last_check_success_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastCheckErrorMeta = const VerificationMeta(
    'lastCheckError',
  );
  @override
  late final GeneratedColumn<String> lastCheckError = GeneratedColumn<String>(
    'last_check_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastCheckResultMeta = const VerificationMeta(
    'lastCheckResult',
  );
  @override
  late final GeneratedColumn<String> lastCheckResult = GeneratedColumn<String>(
    'last_check_result',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
  static const VerificationMeta _archivedAtMeta = const VerificationMeta(
    'archivedAt',
  );
  @override
  late final GeneratedColumn<DateTime> archivedAt = GeneratedColumn<DateTime>(
    'archived_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cleanupPreferenceMeta = const VerificationMeta(
    'cleanupPreference',
  );
  @override
  late final GeneratedColumn<String> cleanupPreference =
      GeneratedColumn<String>(
        'cleanup_preference',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _preferredCaptureModeMeta =
      const VerificationMeta('preferredCaptureMode');
  @override
  late final GeneratedColumn<String> preferredCaptureMode =
      GeneratedColumn<String>(
        'preferred_capture_mode',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    userTitle,
    sourceUrl,
    host,
    collectionKey,
    collectionIndexUrl,
    identityBasis,
    identityConfidence,
    contentKind,
    sequenceKind,
    orderingBasis,
    shapeConfidence,
    knownEntryTotal,
    createdAt,
    lastOpenedAt,
    lastSavedAt,
    lastOpenedEntryId,
    lastCompletedEntryId,
    lastReadAt,
    lastCheckAt,
    lastCheckSuccessAt,
    lastCheckError,
    lastCheckResult,
    lifecycle,
    archivedAt,
    cleanupPreference,
    preferredCaptureMode,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'collections';
  @override
  VerificationContext validateIntegrity(
    Insertable<Collection> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
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
    if (data.containsKey('source_url')) {
      context.handle(
        _sourceUrlMeta,
        sourceUrl.isAcceptableOrUnknown(data['source_url']!, _sourceUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceUrlMeta);
    }
    if (data.containsKey('host')) {
      context.handle(
        _hostMeta,
        host.isAcceptableOrUnknown(data['host']!, _hostMeta),
      );
    } else if (isInserting) {
      context.missing(_hostMeta);
    }
    if (data.containsKey('collection_key')) {
      context.handle(
        _collectionKeyMeta,
        collectionKey.isAcceptableOrUnknown(
          data['collection_key']!,
          _collectionKeyMeta,
        ),
      );
    }
    if (data.containsKey('collection_index_url')) {
      context.handle(
        _collectionIndexUrlMeta,
        collectionIndexUrl.isAcceptableOrUnknown(
          data['collection_index_url']!,
          _collectionIndexUrlMeta,
        ),
      );
    }
    if (data.containsKey('identity_basis')) {
      context.handle(
        _identityBasisMeta,
        identityBasis.isAcceptableOrUnknown(
          data['identity_basis']!,
          _identityBasisMeta,
        ),
      );
    }
    if (data.containsKey('identity_confidence')) {
      context.handle(
        _identityConfidenceMeta,
        identityConfidence.isAcceptableOrUnknown(
          data['identity_confidence']!,
          _identityConfidenceMeta,
        ),
      );
    }
    if (data.containsKey('content_kind')) {
      context.handle(
        _contentKindMeta,
        contentKind.isAcceptableOrUnknown(
          data['content_kind']!,
          _contentKindMeta,
        ),
      );
    }
    if (data.containsKey('sequence_kind')) {
      context.handle(
        _sequenceKindMeta,
        sequenceKind.isAcceptableOrUnknown(
          data['sequence_kind']!,
          _sequenceKindMeta,
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
    }
    if (data.containsKey('shape_confidence')) {
      context.handle(
        _shapeConfidenceMeta,
        shapeConfidence.isAcceptableOrUnknown(
          data['shape_confidence']!,
          _shapeConfidenceMeta,
        ),
      );
    }
    if (data.containsKey('known_entry_total')) {
      context.handle(
        _knownEntryTotalMeta,
        knownEntryTotal.isAcceptableOrUnknown(
          data['known_entry_total']!,
          _knownEntryTotalMeta,
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
    if (data.containsKey('last_opened_at')) {
      context.handle(
        _lastOpenedAtMeta,
        lastOpenedAt.isAcceptableOrUnknown(
          data['last_opened_at']!,
          _lastOpenedAtMeta,
        ),
      );
    }
    if (data.containsKey('last_saved_at')) {
      context.handle(
        _lastSavedAtMeta,
        lastSavedAt.isAcceptableOrUnknown(
          data['last_saved_at']!,
          _lastSavedAtMeta,
        ),
      );
    }
    if (data.containsKey('last_opened_entry_id')) {
      context.handle(
        _lastOpenedEntryIdMeta,
        lastOpenedEntryId.isAcceptableOrUnknown(
          data['last_opened_entry_id']!,
          _lastOpenedEntryIdMeta,
        ),
      );
    }
    if (data.containsKey('last_completed_entry_id')) {
      context.handle(
        _lastCompletedEntryIdMeta,
        lastCompletedEntryId.isAcceptableOrUnknown(
          data['last_completed_entry_id']!,
          _lastCompletedEntryIdMeta,
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
    if (data.containsKey('last_check_at')) {
      context.handle(
        _lastCheckAtMeta,
        lastCheckAt.isAcceptableOrUnknown(
          data['last_check_at']!,
          _lastCheckAtMeta,
        ),
      );
    }
    if (data.containsKey('last_check_success_at')) {
      context.handle(
        _lastCheckSuccessAtMeta,
        lastCheckSuccessAt.isAcceptableOrUnknown(
          data['last_check_success_at']!,
          _lastCheckSuccessAtMeta,
        ),
      );
    }
    if (data.containsKey('last_check_error')) {
      context.handle(
        _lastCheckErrorMeta,
        lastCheckError.isAcceptableOrUnknown(
          data['last_check_error']!,
          _lastCheckErrorMeta,
        ),
      );
    }
    if (data.containsKey('last_check_result')) {
      context.handle(
        _lastCheckResultMeta,
        lastCheckResult.isAcceptableOrUnknown(
          data['last_check_result']!,
          _lastCheckResultMeta,
        ),
      );
    }
    if (data.containsKey('lifecycle')) {
      context.handle(
        _lifecycleMeta,
        lifecycle.isAcceptableOrUnknown(data['lifecycle']!, _lifecycleMeta),
      );
    }
    if (data.containsKey('archived_at')) {
      context.handle(
        _archivedAtMeta,
        archivedAt.isAcceptableOrUnknown(data['archived_at']!, _archivedAtMeta),
      );
    }
    if (data.containsKey('cleanup_preference')) {
      context.handle(
        _cleanupPreferenceMeta,
        cleanupPreference.isAcceptableOrUnknown(
          data['cleanup_preference']!,
          _cleanupPreferenceMeta,
        ),
      );
    }
    if (data.containsKey('preferred_capture_mode')) {
      context.handle(
        _preferredCaptureModeMeta,
        preferredCaptureMode.isAcceptableOrUnknown(
          data['preferred_capture_mode']!,
          _preferredCaptureModeMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {host, collectionKey},
  ];
  @override
  Collection map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Collection(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      userTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_title'],
      ),
      sourceUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_url'],
      )!,
      host: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host'],
      )!,
      collectionKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}collection_key'],
      ),
      collectionIndexUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}collection_index_url'],
      ),
      identityBasis: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}identity_basis'],
      ),
      identityConfidence: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}identity_confidence'],
      ),
      contentKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_kind'],
      )!,
      sequenceKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sequence_kind'],
      )!,
      orderingBasis: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ordering_basis'],
      )!,
      shapeConfidence: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shape_confidence'],
      )!,
      knownEntryTotal: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}known_entry_total'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      lastOpenedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_opened_at'],
      ),
      lastSavedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_saved_at'],
      ),
      lastOpenedEntryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_opened_entry_id'],
      ),
      lastCompletedEntryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_completed_entry_id'],
      ),
      lastReadAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_read_at'],
      ),
      lastCheckAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_check_at'],
      ),
      lastCheckSuccessAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_check_success_at'],
      ),
      lastCheckError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_check_error'],
      ),
      lastCheckResult: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_check_result'],
      ),
      lifecycle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lifecycle'],
      )!,
      archivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}archived_at'],
      ),
      cleanupPreference: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cleanup_preference'],
      ),
      preferredCaptureMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}preferred_capture_mode'],
      ),
    );
  }

  @override
  $CollectionsTable createAlias(String alias) {
    return $CollectionsTable(attachedDatabase, alias);
  }
}

class Collection extends DataClass implements Insertable<Collection> {
  final String id;

  /// Detected title, as the source wrote it.
  final String title;

  /// What the user renamed it to. Presentation only — never part of matching,
  /// never part of a storage path.
  final String? userTitle;
  final String sourceUrl;
  final String host;

  /// Identity within a host. What a later save matches against, so a rename can
  /// never split a collection or create a second one.
  final String? collectionKey;

  /// A stable URL for the collection's index page, when the source offered one.
  final String? collectionIndexUrl;

  /// Which signal produced the key, and how much it can be trusted. Kept so a
  /// wrong grouping is explainable rather than mysterious.
  final String? identityBasis;
  final String? identityConfidence;

  /// `ContentKind.name`. What the entries in this collection are.
  final String contentKind;

  /// `SequenceKind.name`. How the entries continue into one another — including
  /// `none`, which is a real answer.
  final String sequenceKind;

  /// `OrderingBasis.name`. What decides the reading order.
  final String orderingBasis;

  /// `ShapeConfidence.name` for the two above. Low means the UI says
  /// "saved items" instead of naming a structure the source never declared.
  final String shapeConfidence;

  /// How many entries the source says exist, when it said so at all.
  ///
  /// **Nullable, and usually null.** An open-ended sequence has no total, and a
  /// number here that was never published is a lie the whole UI then repeats.
  final int? knownEntryTotal;
  final DateTime createdAt;
  final DateTime? lastOpenedAt;
  final DateTime? lastSavedAt;

  /// Denormalised reading pointers. Derivable, but every library query orders on
  /// them, and recomputing a per-collection aggregate for each row on every
  /// stream emission is the difference between a snappy list and a stuttery one.
  /// Written in the same call as the entry change that causes them.
  final String? lastOpenedEntryId;
  final String? lastCompletedEntryId;
  final DateTime? lastReadAt;
  final DateTime? lastCheckAt;
  final DateTime? lastCheckSuccessAt;
  final String? lastCheckError;

  /// upToDate / updatesAvailable / failed / cancelled / needsUserInput.
  final String? lastCheckResult;

  /// `active` | `archived`. Archiving hides a collection and excludes it from
  /// checks; it never touches entries or files.
  final String lifecycle;
  final DateTime? archivedAt;

  /// What to do with a finished entry's offline files when the reader moves
  /// forward inside this collection: `remove` · `keep`, or **null** while this
  /// collection has never been asked.
  ///
  /// The only source of truth. There is no app-wide default and no per-entry
  /// copy: null means "ask on the next eligible transition", and an unrecognised
  /// value reads as null, which asks rather than guessing at removal.
  final String? cleanupPreference;

  /// `CaptureMode.name` the user asked to reuse for this collection, or null
  /// while they never said.
  ///
  /// **A proposal, never an instruction.** Every save re-measures the page and
  /// runs this through `CaptureCapabilities.resolve`, so a remembered "text
  /// and images" cannot force a document out of a page that has no text — it
  /// falls back and the run says why. An unrecognised value reads as null,
  /// which means "detect", not "guess".
  final String? preferredCaptureMode;
  const Collection({
    required this.id,
    required this.title,
    this.userTitle,
    required this.sourceUrl,
    required this.host,
    this.collectionKey,
    this.collectionIndexUrl,
    this.identityBasis,
    this.identityConfidence,
    required this.contentKind,
    required this.sequenceKind,
    required this.orderingBasis,
    required this.shapeConfidence,
    this.knownEntryTotal,
    required this.createdAt,
    this.lastOpenedAt,
    this.lastSavedAt,
    this.lastOpenedEntryId,
    this.lastCompletedEntryId,
    this.lastReadAt,
    this.lastCheckAt,
    this.lastCheckSuccessAt,
    this.lastCheckError,
    this.lastCheckResult,
    required this.lifecycle,
    this.archivedAt,
    this.cleanupPreference,
    this.preferredCaptureMode,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || userTitle != null) {
      map['user_title'] = Variable<String>(userTitle);
    }
    map['source_url'] = Variable<String>(sourceUrl);
    map['host'] = Variable<String>(host);
    if (!nullToAbsent || collectionKey != null) {
      map['collection_key'] = Variable<String>(collectionKey);
    }
    if (!nullToAbsent || collectionIndexUrl != null) {
      map['collection_index_url'] = Variable<String>(collectionIndexUrl);
    }
    if (!nullToAbsent || identityBasis != null) {
      map['identity_basis'] = Variable<String>(identityBasis);
    }
    if (!nullToAbsent || identityConfidence != null) {
      map['identity_confidence'] = Variable<String>(identityConfidence);
    }
    map['content_kind'] = Variable<String>(contentKind);
    map['sequence_kind'] = Variable<String>(sequenceKind);
    map['ordering_basis'] = Variable<String>(orderingBasis);
    map['shape_confidence'] = Variable<String>(shapeConfidence);
    if (!nullToAbsent || knownEntryTotal != null) {
      map['known_entry_total'] = Variable<int>(knownEntryTotal);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || lastOpenedAt != null) {
      map['last_opened_at'] = Variable<DateTime>(lastOpenedAt);
    }
    if (!nullToAbsent || lastSavedAt != null) {
      map['last_saved_at'] = Variable<DateTime>(lastSavedAt);
    }
    if (!nullToAbsent || lastOpenedEntryId != null) {
      map['last_opened_entry_id'] = Variable<String>(lastOpenedEntryId);
    }
    if (!nullToAbsent || lastCompletedEntryId != null) {
      map['last_completed_entry_id'] = Variable<String>(lastCompletedEntryId);
    }
    if (!nullToAbsent || lastReadAt != null) {
      map['last_read_at'] = Variable<DateTime>(lastReadAt);
    }
    if (!nullToAbsent || lastCheckAt != null) {
      map['last_check_at'] = Variable<DateTime>(lastCheckAt);
    }
    if (!nullToAbsent || lastCheckSuccessAt != null) {
      map['last_check_success_at'] = Variable<DateTime>(lastCheckSuccessAt);
    }
    if (!nullToAbsent || lastCheckError != null) {
      map['last_check_error'] = Variable<String>(lastCheckError);
    }
    if (!nullToAbsent || lastCheckResult != null) {
      map['last_check_result'] = Variable<String>(lastCheckResult);
    }
    map['lifecycle'] = Variable<String>(lifecycle);
    if (!nullToAbsent || archivedAt != null) {
      map['archived_at'] = Variable<DateTime>(archivedAt);
    }
    if (!nullToAbsent || cleanupPreference != null) {
      map['cleanup_preference'] = Variable<String>(cleanupPreference);
    }
    if (!nullToAbsent || preferredCaptureMode != null) {
      map['preferred_capture_mode'] = Variable<String>(preferredCaptureMode);
    }
    return map;
  }

  CollectionsCompanion toCompanion(bool nullToAbsent) {
    return CollectionsCompanion(
      id: Value(id),
      title: Value(title),
      userTitle: userTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(userTitle),
      sourceUrl: Value(sourceUrl),
      host: Value(host),
      collectionKey: collectionKey == null && nullToAbsent
          ? const Value.absent()
          : Value(collectionKey),
      collectionIndexUrl: collectionIndexUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(collectionIndexUrl),
      identityBasis: identityBasis == null && nullToAbsent
          ? const Value.absent()
          : Value(identityBasis),
      identityConfidence: identityConfidence == null && nullToAbsent
          ? const Value.absent()
          : Value(identityConfidence),
      contentKind: Value(contentKind),
      sequenceKind: Value(sequenceKind),
      orderingBasis: Value(orderingBasis),
      shapeConfidence: Value(shapeConfidence),
      knownEntryTotal: knownEntryTotal == null && nullToAbsent
          ? const Value.absent()
          : Value(knownEntryTotal),
      createdAt: Value(createdAt),
      lastOpenedAt: lastOpenedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastOpenedAt),
      lastSavedAt: lastSavedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSavedAt),
      lastOpenedEntryId: lastOpenedEntryId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastOpenedEntryId),
      lastCompletedEntryId: lastCompletedEntryId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCompletedEntryId),
      lastReadAt: lastReadAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReadAt),
      lastCheckAt: lastCheckAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCheckAt),
      lastCheckSuccessAt: lastCheckSuccessAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCheckSuccessAt),
      lastCheckError: lastCheckError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCheckError),
      lastCheckResult: lastCheckResult == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCheckResult),
      lifecycle: Value(lifecycle),
      archivedAt: archivedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(archivedAt),
      cleanupPreference: cleanupPreference == null && nullToAbsent
          ? const Value.absent()
          : Value(cleanupPreference),
      preferredCaptureMode: preferredCaptureMode == null && nullToAbsent
          ? const Value.absent()
          : Value(preferredCaptureMode),
    );
  }

  factory Collection.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Collection(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      userTitle: serializer.fromJson<String?>(json['userTitle']),
      sourceUrl: serializer.fromJson<String>(json['sourceUrl']),
      host: serializer.fromJson<String>(json['host']),
      collectionKey: serializer.fromJson<String?>(json['collectionKey']),
      collectionIndexUrl: serializer.fromJson<String?>(
        json['collectionIndexUrl'],
      ),
      identityBasis: serializer.fromJson<String?>(json['identityBasis']),
      identityConfidence: serializer.fromJson<String?>(
        json['identityConfidence'],
      ),
      contentKind: serializer.fromJson<String>(json['contentKind']),
      sequenceKind: serializer.fromJson<String>(json['sequenceKind']),
      orderingBasis: serializer.fromJson<String>(json['orderingBasis']),
      shapeConfidence: serializer.fromJson<String>(json['shapeConfidence']),
      knownEntryTotal: serializer.fromJson<int?>(json['knownEntryTotal']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      lastOpenedAt: serializer.fromJson<DateTime?>(json['lastOpenedAt']),
      lastSavedAt: serializer.fromJson<DateTime?>(json['lastSavedAt']),
      lastOpenedEntryId: serializer.fromJson<String?>(
        json['lastOpenedEntryId'],
      ),
      lastCompletedEntryId: serializer.fromJson<String?>(
        json['lastCompletedEntryId'],
      ),
      lastReadAt: serializer.fromJson<DateTime?>(json['lastReadAt']),
      lastCheckAt: serializer.fromJson<DateTime?>(json['lastCheckAt']),
      lastCheckSuccessAt: serializer.fromJson<DateTime?>(
        json['lastCheckSuccessAt'],
      ),
      lastCheckError: serializer.fromJson<String?>(json['lastCheckError']),
      lastCheckResult: serializer.fromJson<String?>(json['lastCheckResult']),
      lifecycle: serializer.fromJson<String>(json['lifecycle']),
      archivedAt: serializer.fromJson<DateTime?>(json['archivedAt']),
      cleanupPreference: serializer.fromJson<String?>(
        json['cleanupPreference'],
      ),
      preferredCaptureMode: serializer.fromJson<String?>(
        json['preferredCaptureMode'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'userTitle': serializer.toJson<String?>(userTitle),
      'sourceUrl': serializer.toJson<String>(sourceUrl),
      'host': serializer.toJson<String>(host),
      'collectionKey': serializer.toJson<String?>(collectionKey),
      'collectionIndexUrl': serializer.toJson<String?>(collectionIndexUrl),
      'identityBasis': serializer.toJson<String?>(identityBasis),
      'identityConfidence': serializer.toJson<String?>(identityConfidence),
      'contentKind': serializer.toJson<String>(contentKind),
      'sequenceKind': serializer.toJson<String>(sequenceKind),
      'orderingBasis': serializer.toJson<String>(orderingBasis),
      'shapeConfidence': serializer.toJson<String>(shapeConfidence),
      'knownEntryTotal': serializer.toJson<int?>(knownEntryTotal),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'lastOpenedAt': serializer.toJson<DateTime?>(lastOpenedAt),
      'lastSavedAt': serializer.toJson<DateTime?>(lastSavedAt),
      'lastOpenedEntryId': serializer.toJson<String?>(lastOpenedEntryId),
      'lastCompletedEntryId': serializer.toJson<String?>(lastCompletedEntryId),
      'lastReadAt': serializer.toJson<DateTime?>(lastReadAt),
      'lastCheckAt': serializer.toJson<DateTime?>(lastCheckAt),
      'lastCheckSuccessAt': serializer.toJson<DateTime?>(lastCheckSuccessAt),
      'lastCheckError': serializer.toJson<String?>(lastCheckError),
      'lastCheckResult': serializer.toJson<String?>(lastCheckResult),
      'lifecycle': serializer.toJson<String>(lifecycle),
      'archivedAt': serializer.toJson<DateTime?>(archivedAt),
      'cleanupPreference': serializer.toJson<String?>(cleanupPreference),
      'preferredCaptureMode': serializer.toJson<String?>(preferredCaptureMode),
    };
  }

  Collection copyWith({
    String? id,
    String? title,
    Value<String?> userTitle = const Value.absent(),
    String? sourceUrl,
    String? host,
    Value<String?> collectionKey = const Value.absent(),
    Value<String?> collectionIndexUrl = const Value.absent(),
    Value<String?> identityBasis = const Value.absent(),
    Value<String?> identityConfidence = const Value.absent(),
    String? contentKind,
    String? sequenceKind,
    String? orderingBasis,
    String? shapeConfidence,
    Value<int?> knownEntryTotal = const Value.absent(),
    DateTime? createdAt,
    Value<DateTime?> lastOpenedAt = const Value.absent(),
    Value<DateTime?> lastSavedAt = const Value.absent(),
    Value<String?> lastOpenedEntryId = const Value.absent(),
    Value<String?> lastCompletedEntryId = const Value.absent(),
    Value<DateTime?> lastReadAt = const Value.absent(),
    Value<DateTime?> lastCheckAt = const Value.absent(),
    Value<DateTime?> lastCheckSuccessAt = const Value.absent(),
    Value<String?> lastCheckError = const Value.absent(),
    Value<String?> lastCheckResult = const Value.absent(),
    String? lifecycle,
    Value<DateTime?> archivedAt = const Value.absent(),
    Value<String?> cleanupPreference = const Value.absent(),
    Value<String?> preferredCaptureMode = const Value.absent(),
  }) => Collection(
    id: id ?? this.id,
    title: title ?? this.title,
    userTitle: userTitle.present ? userTitle.value : this.userTitle,
    sourceUrl: sourceUrl ?? this.sourceUrl,
    host: host ?? this.host,
    collectionKey: collectionKey.present
        ? collectionKey.value
        : this.collectionKey,
    collectionIndexUrl: collectionIndexUrl.present
        ? collectionIndexUrl.value
        : this.collectionIndexUrl,
    identityBasis: identityBasis.present
        ? identityBasis.value
        : this.identityBasis,
    identityConfidence: identityConfidence.present
        ? identityConfidence.value
        : this.identityConfidence,
    contentKind: contentKind ?? this.contentKind,
    sequenceKind: sequenceKind ?? this.sequenceKind,
    orderingBasis: orderingBasis ?? this.orderingBasis,
    shapeConfidence: shapeConfidence ?? this.shapeConfidence,
    knownEntryTotal: knownEntryTotal.present
        ? knownEntryTotal.value
        : this.knownEntryTotal,
    createdAt: createdAt ?? this.createdAt,
    lastOpenedAt: lastOpenedAt.present ? lastOpenedAt.value : this.lastOpenedAt,
    lastSavedAt: lastSavedAt.present ? lastSavedAt.value : this.lastSavedAt,
    lastOpenedEntryId: lastOpenedEntryId.present
        ? lastOpenedEntryId.value
        : this.lastOpenedEntryId,
    lastCompletedEntryId: lastCompletedEntryId.present
        ? lastCompletedEntryId.value
        : this.lastCompletedEntryId,
    lastReadAt: lastReadAt.present ? lastReadAt.value : this.lastReadAt,
    lastCheckAt: lastCheckAt.present ? lastCheckAt.value : this.lastCheckAt,
    lastCheckSuccessAt: lastCheckSuccessAt.present
        ? lastCheckSuccessAt.value
        : this.lastCheckSuccessAt,
    lastCheckError: lastCheckError.present
        ? lastCheckError.value
        : this.lastCheckError,
    lastCheckResult: lastCheckResult.present
        ? lastCheckResult.value
        : this.lastCheckResult,
    lifecycle: lifecycle ?? this.lifecycle,
    archivedAt: archivedAt.present ? archivedAt.value : this.archivedAt,
    cleanupPreference: cleanupPreference.present
        ? cleanupPreference.value
        : this.cleanupPreference,
    preferredCaptureMode: preferredCaptureMode.present
        ? preferredCaptureMode.value
        : this.preferredCaptureMode,
  );
  Collection copyWithCompanion(CollectionsCompanion data) {
    return Collection(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      userTitle: data.userTitle.present ? data.userTitle.value : this.userTitle,
      sourceUrl: data.sourceUrl.present ? data.sourceUrl.value : this.sourceUrl,
      host: data.host.present ? data.host.value : this.host,
      collectionKey: data.collectionKey.present
          ? data.collectionKey.value
          : this.collectionKey,
      collectionIndexUrl: data.collectionIndexUrl.present
          ? data.collectionIndexUrl.value
          : this.collectionIndexUrl,
      identityBasis: data.identityBasis.present
          ? data.identityBasis.value
          : this.identityBasis,
      identityConfidence: data.identityConfidence.present
          ? data.identityConfidence.value
          : this.identityConfidence,
      contentKind: data.contentKind.present
          ? data.contentKind.value
          : this.contentKind,
      sequenceKind: data.sequenceKind.present
          ? data.sequenceKind.value
          : this.sequenceKind,
      orderingBasis: data.orderingBasis.present
          ? data.orderingBasis.value
          : this.orderingBasis,
      shapeConfidence: data.shapeConfidence.present
          ? data.shapeConfidence.value
          : this.shapeConfidence,
      knownEntryTotal: data.knownEntryTotal.present
          ? data.knownEntryTotal.value
          : this.knownEntryTotal,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastOpenedAt: data.lastOpenedAt.present
          ? data.lastOpenedAt.value
          : this.lastOpenedAt,
      lastSavedAt: data.lastSavedAt.present
          ? data.lastSavedAt.value
          : this.lastSavedAt,
      lastOpenedEntryId: data.lastOpenedEntryId.present
          ? data.lastOpenedEntryId.value
          : this.lastOpenedEntryId,
      lastCompletedEntryId: data.lastCompletedEntryId.present
          ? data.lastCompletedEntryId.value
          : this.lastCompletedEntryId,
      lastReadAt: data.lastReadAt.present
          ? data.lastReadAt.value
          : this.lastReadAt,
      lastCheckAt: data.lastCheckAt.present
          ? data.lastCheckAt.value
          : this.lastCheckAt,
      lastCheckSuccessAt: data.lastCheckSuccessAt.present
          ? data.lastCheckSuccessAt.value
          : this.lastCheckSuccessAt,
      lastCheckError: data.lastCheckError.present
          ? data.lastCheckError.value
          : this.lastCheckError,
      lastCheckResult: data.lastCheckResult.present
          ? data.lastCheckResult.value
          : this.lastCheckResult,
      lifecycle: data.lifecycle.present ? data.lifecycle.value : this.lifecycle,
      archivedAt: data.archivedAt.present
          ? data.archivedAt.value
          : this.archivedAt,
      cleanupPreference: data.cleanupPreference.present
          ? data.cleanupPreference.value
          : this.cleanupPreference,
      preferredCaptureMode: data.preferredCaptureMode.present
          ? data.preferredCaptureMode.value
          : this.preferredCaptureMode,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Collection(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('userTitle: $userTitle, ')
          ..write('sourceUrl: $sourceUrl, ')
          ..write('host: $host, ')
          ..write('collectionKey: $collectionKey, ')
          ..write('collectionIndexUrl: $collectionIndexUrl, ')
          ..write('identityBasis: $identityBasis, ')
          ..write('identityConfidence: $identityConfidence, ')
          ..write('contentKind: $contentKind, ')
          ..write('sequenceKind: $sequenceKind, ')
          ..write('orderingBasis: $orderingBasis, ')
          ..write('shapeConfidence: $shapeConfidence, ')
          ..write('knownEntryTotal: $knownEntryTotal, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastOpenedAt: $lastOpenedAt, ')
          ..write('lastSavedAt: $lastSavedAt, ')
          ..write('lastOpenedEntryId: $lastOpenedEntryId, ')
          ..write('lastCompletedEntryId: $lastCompletedEntryId, ')
          ..write('lastReadAt: $lastReadAt, ')
          ..write('lastCheckAt: $lastCheckAt, ')
          ..write('lastCheckSuccessAt: $lastCheckSuccessAt, ')
          ..write('lastCheckError: $lastCheckError, ')
          ..write('lastCheckResult: $lastCheckResult, ')
          ..write('lifecycle: $lifecycle, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('cleanupPreference: $cleanupPreference, ')
          ..write('preferredCaptureMode: $preferredCaptureMode')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    title,
    userTitle,
    sourceUrl,
    host,
    collectionKey,
    collectionIndexUrl,
    identityBasis,
    identityConfidence,
    contentKind,
    sequenceKind,
    orderingBasis,
    shapeConfidence,
    knownEntryTotal,
    createdAt,
    lastOpenedAt,
    lastSavedAt,
    lastOpenedEntryId,
    lastCompletedEntryId,
    lastReadAt,
    lastCheckAt,
    lastCheckSuccessAt,
    lastCheckError,
    lastCheckResult,
    lifecycle,
    archivedAt,
    cleanupPreference,
    preferredCaptureMode,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Collection &&
          other.id == this.id &&
          other.title == this.title &&
          other.userTitle == this.userTitle &&
          other.sourceUrl == this.sourceUrl &&
          other.host == this.host &&
          other.collectionKey == this.collectionKey &&
          other.collectionIndexUrl == this.collectionIndexUrl &&
          other.identityBasis == this.identityBasis &&
          other.identityConfidence == this.identityConfidence &&
          other.contentKind == this.contentKind &&
          other.sequenceKind == this.sequenceKind &&
          other.orderingBasis == this.orderingBasis &&
          other.shapeConfidence == this.shapeConfidence &&
          other.knownEntryTotal == this.knownEntryTotal &&
          other.createdAt == this.createdAt &&
          other.lastOpenedAt == this.lastOpenedAt &&
          other.lastSavedAt == this.lastSavedAt &&
          other.lastOpenedEntryId == this.lastOpenedEntryId &&
          other.lastCompletedEntryId == this.lastCompletedEntryId &&
          other.lastReadAt == this.lastReadAt &&
          other.lastCheckAt == this.lastCheckAt &&
          other.lastCheckSuccessAt == this.lastCheckSuccessAt &&
          other.lastCheckError == this.lastCheckError &&
          other.lastCheckResult == this.lastCheckResult &&
          other.lifecycle == this.lifecycle &&
          other.archivedAt == this.archivedAt &&
          other.cleanupPreference == this.cleanupPreference &&
          other.preferredCaptureMode == this.preferredCaptureMode);
}

class CollectionsCompanion extends UpdateCompanion<Collection> {
  final Value<String> id;
  final Value<String> title;
  final Value<String?> userTitle;
  final Value<String> sourceUrl;
  final Value<String> host;
  final Value<String?> collectionKey;
  final Value<String?> collectionIndexUrl;
  final Value<String?> identityBasis;
  final Value<String?> identityConfidence;
  final Value<String> contentKind;
  final Value<String> sequenceKind;
  final Value<String> orderingBasis;
  final Value<String> shapeConfidence;
  final Value<int?> knownEntryTotal;
  final Value<DateTime> createdAt;
  final Value<DateTime?> lastOpenedAt;
  final Value<DateTime?> lastSavedAt;
  final Value<String?> lastOpenedEntryId;
  final Value<String?> lastCompletedEntryId;
  final Value<DateTime?> lastReadAt;
  final Value<DateTime?> lastCheckAt;
  final Value<DateTime?> lastCheckSuccessAt;
  final Value<String?> lastCheckError;
  final Value<String?> lastCheckResult;
  final Value<String> lifecycle;
  final Value<DateTime?> archivedAt;
  final Value<String?> cleanupPreference;
  final Value<String?> preferredCaptureMode;
  final Value<int> rowid;
  const CollectionsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.userTitle = const Value.absent(),
    this.sourceUrl = const Value.absent(),
    this.host = const Value.absent(),
    this.collectionKey = const Value.absent(),
    this.collectionIndexUrl = const Value.absent(),
    this.identityBasis = const Value.absent(),
    this.identityConfidence = const Value.absent(),
    this.contentKind = const Value.absent(),
    this.sequenceKind = const Value.absent(),
    this.orderingBasis = const Value.absent(),
    this.shapeConfidence = const Value.absent(),
    this.knownEntryTotal = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastOpenedAt = const Value.absent(),
    this.lastSavedAt = const Value.absent(),
    this.lastOpenedEntryId = const Value.absent(),
    this.lastCompletedEntryId = const Value.absent(),
    this.lastReadAt = const Value.absent(),
    this.lastCheckAt = const Value.absent(),
    this.lastCheckSuccessAt = const Value.absent(),
    this.lastCheckError = const Value.absent(),
    this.lastCheckResult = const Value.absent(),
    this.lifecycle = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.cleanupPreference = const Value.absent(),
    this.preferredCaptureMode = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CollectionsCompanion.insert({
    required String id,
    required String title,
    this.userTitle = const Value.absent(),
    required String sourceUrl,
    required String host,
    this.collectionKey = const Value.absent(),
    this.collectionIndexUrl = const Value.absent(),
    this.identityBasis = const Value.absent(),
    this.identityConfidence = const Value.absent(),
    this.contentKind = const Value.absent(),
    this.sequenceKind = const Value.absent(),
    this.orderingBasis = const Value.absent(),
    this.shapeConfidence = const Value.absent(),
    this.knownEntryTotal = const Value.absent(),
    required DateTime createdAt,
    this.lastOpenedAt = const Value.absent(),
    this.lastSavedAt = const Value.absent(),
    this.lastOpenedEntryId = const Value.absent(),
    this.lastCompletedEntryId = const Value.absent(),
    this.lastReadAt = const Value.absent(),
    this.lastCheckAt = const Value.absent(),
    this.lastCheckSuccessAt = const Value.absent(),
    this.lastCheckError = const Value.absent(),
    this.lastCheckResult = const Value.absent(),
    this.lifecycle = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.cleanupPreference = const Value.absent(),
    this.preferredCaptureMode = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       sourceUrl = Value(sourceUrl),
       host = Value(host),
       createdAt = Value(createdAt);
  static Insertable<Collection> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? userTitle,
    Expression<String>? sourceUrl,
    Expression<String>? host,
    Expression<String>? collectionKey,
    Expression<String>? collectionIndexUrl,
    Expression<String>? identityBasis,
    Expression<String>? identityConfidence,
    Expression<String>? contentKind,
    Expression<String>? sequenceKind,
    Expression<String>? orderingBasis,
    Expression<String>? shapeConfidence,
    Expression<int>? knownEntryTotal,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? lastOpenedAt,
    Expression<DateTime>? lastSavedAt,
    Expression<String>? lastOpenedEntryId,
    Expression<String>? lastCompletedEntryId,
    Expression<DateTime>? lastReadAt,
    Expression<DateTime>? lastCheckAt,
    Expression<DateTime>? lastCheckSuccessAt,
    Expression<String>? lastCheckError,
    Expression<String>? lastCheckResult,
    Expression<String>? lifecycle,
    Expression<DateTime>? archivedAt,
    Expression<String>? cleanupPreference,
    Expression<String>? preferredCaptureMode,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (userTitle != null) 'user_title': userTitle,
      if (sourceUrl != null) 'source_url': sourceUrl,
      if (host != null) 'host': host,
      if (collectionKey != null) 'collection_key': collectionKey,
      if (collectionIndexUrl != null)
        'collection_index_url': collectionIndexUrl,
      if (identityBasis != null) 'identity_basis': identityBasis,
      if (identityConfidence != null) 'identity_confidence': identityConfidence,
      if (contentKind != null) 'content_kind': contentKind,
      if (sequenceKind != null) 'sequence_kind': sequenceKind,
      if (orderingBasis != null) 'ordering_basis': orderingBasis,
      if (shapeConfidence != null) 'shape_confidence': shapeConfidence,
      if (knownEntryTotal != null) 'known_entry_total': knownEntryTotal,
      if (createdAt != null) 'created_at': createdAt,
      if (lastOpenedAt != null) 'last_opened_at': lastOpenedAt,
      if (lastSavedAt != null) 'last_saved_at': lastSavedAt,
      if (lastOpenedEntryId != null) 'last_opened_entry_id': lastOpenedEntryId,
      if (lastCompletedEntryId != null)
        'last_completed_entry_id': lastCompletedEntryId,
      if (lastReadAt != null) 'last_read_at': lastReadAt,
      if (lastCheckAt != null) 'last_check_at': lastCheckAt,
      if (lastCheckSuccessAt != null)
        'last_check_success_at': lastCheckSuccessAt,
      if (lastCheckError != null) 'last_check_error': lastCheckError,
      if (lastCheckResult != null) 'last_check_result': lastCheckResult,
      if (lifecycle != null) 'lifecycle': lifecycle,
      if (archivedAt != null) 'archived_at': archivedAt,
      if (cleanupPreference != null) 'cleanup_preference': cleanupPreference,
      if (preferredCaptureMode != null)
        'preferred_capture_mode': preferredCaptureMode,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CollectionsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String?>? userTitle,
    Value<String>? sourceUrl,
    Value<String>? host,
    Value<String?>? collectionKey,
    Value<String?>? collectionIndexUrl,
    Value<String?>? identityBasis,
    Value<String?>? identityConfidence,
    Value<String>? contentKind,
    Value<String>? sequenceKind,
    Value<String>? orderingBasis,
    Value<String>? shapeConfidence,
    Value<int?>? knownEntryTotal,
    Value<DateTime>? createdAt,
    Value<DateTime?>? lastOpenedAt,
    Value<DateTime?>? lastSavedAt,
    Value<String?>? lastOpenedEntryId,
    Value<String?>? lastCompletedEntryId,
    Value<DateTime?>? lastReadAt,
    Value<DateTime?>? lastCheckAt,
    Value<DateTime?>? lastCheckSuccessAt,
    Value<String?>? lastCheckError,
    Value<String?>? lastCheckResult,
    Value<String>? lifecycle,
    Value<DateTime?>? archivedAt,
    Value<String?>? cleanupPreference,
    Value<String?>? preferredCaptureMode,
    Value<int>? rowid,
  }) {
    return CollectionsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      userTitle: userTitle ?? this.userTitle,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      host: host ?? this.host,
      collectionKey: collectionKey ?? this.collectionKey,
      collectionIndexUrl: collectionIndexUrl ?? this.collectionIndexUrl,
      identityBasis: identityBasis ?? this.identityBasis,
      identityConfidence: identityConfidence ?? this.identityConfidence,
      contentKind: contentKind ?? this.contentKind,
      sequenceKind: sequenceKind ?? this.sequenceKind,
      orderingBasis: orderingBasis ?? this.orderingBasis,
      shapeConfidence: shapeConfidence ?? this.shapeConfidence,
      knownEntryTotal: knownEntryTotal ?? this.knownEntryTotal,
      createdAt: createdAt ?? this.createdAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      lastSavedAt: lastSavedAt ?? this.lastSavedAt,
      lastOpenedEntryId: lastOpenedEntryId ?? this.lastOpenedEntryId,
      lastCompletedEntryId: lastCompletedEntryId ?? this.lastCompletedEntryId,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      lastCheckAt: lastCheckAt ?? this.lastCheckAt,
      lastCheckSuccessAt: lastCheckSuccessAt ?? this.lastCheckSuccessAt,
      lastCheckError: lastCheckError ?? this.lastCheckError,
      lastCheckResult: lastCheckResult ?? this.lastCheckResult,
      lifecycle: lifecycle ?? this.lifecycle,
      archivedAt: archivedAt ?? this.archivedAt,
      cleanupPreference: cleanupPreference ?? this.cleanupPreference,
      preferredCaptureMode: preferredCaptureMode ?? this.preferredCaptureMode,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (userTitle.present) {
      map['user_title'] = Variable<String>(userTitle.value);
    }
    if (sourceUrl.present) {
      map['source_url'] = Variable<String>(sourceUrl.value);
    }
    if (host.present) {
      map['host'] = Variable<String>(host.value);
    }
    if (collectionKey.present) {
      map['collection_key'] = Variable<String>(collectionKey.value);
    }
    if (collectionIndexUrl.present) {
      map['collection_index_url'] = Variable<String>(collectionIndexUrl.value);
    }
    if (identityBasis.present) {
      map['identity_basis'] = Variable<String>(identityBasis.value);
    }
    if (identityConfidence.present) {
      map['identity_confidence'] = Variable<String>(identityConfidence.value);
    }
    if (contentKind.present) {
      map['content_kind'] = Variable<String>(contentKind.value);
    }
    if (sequenceKind.present) {
      map['sequence_kind'] = Variable<String>(sequenceKind.value);
    }
    if (orderingBasis.present) {
      map['ordering_basis'] = Variable<String>(orderingBasis.value);
    }
    if (shapeConfidence.present) {
      map['shape_confidence'] = Variable<String>(shapeConfidence.value);
    }
    if (knownEntryTotal.present) {
      map['known_entry_total'] = Variable<int>(knownEntryTotal.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (lastOpenedAt.present) {
      map['last_opened_at'] = Variable<DateTime>(lastOpenedAt.value);
    }
    if (lastSavedAt.present) {
      map['last_saved_at'] = Variable<DateTime>(lastSavedAt.value);
    }
    if (lastOpenedEntryId.present) {
      map['last_opened_entry_id'] = Variable<String>(lastOpenedEntryId.value);
    }
    if (lastCompletedEntryId.present) {
      map['last_completed_entry_id'] = Variable<String>(
        lastCompletedEntryId.value,
      );
    }
    if (lastReadAt.present) {
      map['last_read_at'] = Variable<DateTime>(lastReadAt.value);
    }
    if (lastCheckAt.present) {
      map['last_check_at'] = Variable<DateTime>(lastCheckAt.value);
    }
    if (lastCheckSuccessAt.present) {
      map['last_check_success_at'] = Variable<DateTime>(
        lastCheckSuccessAt.value,
      );
    }
    if (lastCheckError.present) {
      map['last_check_error'] = Variable<String>(lastCheckError.value);
    }
    if (lastCheckResult.present) {
      map['last_check_result'] = Variable<String>(lastCheckResult.value);
    }
    if (lifecycle.present) {
      map['lifecycle'] = Variable<String>(lifecycle.value);
    }
    if (archivedAt.present) {
      map['archived_at'] = Variable<DateTime>(archivedAt.value);
    }
    if (cleanupPreference.present) {
      map['cleanup_preference'] = Variable<String>(cleanupPreference.value);
    }
    if (preferredCaptureMode.present) {
      map['preferred_capture_mode'] = Variable<String>(
        preferredCaptureMode.value,
      );
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
          ..write('title: $title, ')
          ..write('userTitle: $userTitle, ')
          ..write('sourceUrl: $sourceUrl, ')
          ..write('host: $host, ')
          ..write('collectionKey: $collectionKey, ')
          ..write('collectionIndexUrl: $collectionIndexUrl, ')
          ..write('identityBasis: $identityBasis, ')
          ..write('identityConfidence: $identityConfidence, ')
          ..write('contentKind: $contentKind, ')
          ..write('sequenceKind: $sequenceKind, ')
          ..write('orderingBasis: $orderingBasis, ')
          ..write('shapeConfidence: $shapeConfidence, ')
          ..write('knownEntryTotal: $knownEntryTotal, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastOpenedAt: $lastOpenedAt, ')
          ..write('lastSavedAt: $lastSavedAt, ')
          ..write('lastOpenedEntryId: $lastOpenedEntryId, ')
          ..write('lastCompletedEntryId: $lastCompletedEntryId, ')
          ..write('lastReadAt: $lastReadAt, ')
          ..write('lastCheckAt: $lastCheckAt, ')
          ..write('lastCheckSuccessAt: $lastCheckSuccessAt, ')
          ..write('lastCheckError: $lastCheckError, ')
          ..write('lastCheckResult: $lastCheckResult, ')
          ..write('lifecycle: $lifecycle, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('cleanupPreference: $cleanupPreference, ')
          ..write('preferredCaptureMode: $preferredCaptureMode, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EntriesTable extends Entries with TableInfo<$EntriesTable, Entry> {
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
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES collections (id)',
    ),
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
  static const VerificationMeta _sourceUrlMeta = const VerificationMeta(
    'sourceUrl',
  );
  @override
  late final GeneratedColumn<String> sourceUrl = GeneratedColumn<String>(
    'source_url',
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
  static const VerificationMeta _canonicalUrlMeta = const VerificationMeta(
    'canonicalUrl',
  );
  @override
  late final GeneratedColumn<String> canonicalUrl = GeneratedColumn<String>(
    'canonical_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hostMeta = const VerificationMeta('host');
  @override
  late final GeneratedColumn<String> host = GeneratedColumn<String>(
    'host',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sourceTitleMeta = const VerificationMeta(
    'sourceTitle',
  );
  @override
  late final GeneratedColumn<String> sourceTitle = GeneratedColumn<String>(
    'source_title',
    aliasedName,
    true,
    type: DriftSqlType.string,
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
  static const VerificationMeta _contentKindMeta = const VerificationMeta(
    'contentKind',
  );
  @override
  late final GeneratedColumn<String> contentKind = GeneratedColumn<String>(
    'content_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('unknownWebContent'),
  );
  static const VerificationMeta _contentKindConfidenceMeta =
      const VerificationMeta('contentKindConfidence');
  @override
  late final GeneratedColumn<String> contentKindConfidence =
      GeneratedColumn<String>(
        'content_kind_confidence',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('low'),
      );
  static const VerificationMeta _contentKindIsUserSetMeta =
      const VerificationMeta('contentKindIsUserSet');
  @override
  late final GeneratedColumn<bool> contentKindIsUserSet = GeneratedColumn<bool>(
    'content_kind_is_user_set',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("content_kind_is_user_set" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
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
    requiredDuringInsert: false,
    defaultValue: const Constant('imageSequence'),
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
  static const VerificationMeta _saveStatusMeta = const VerificationMeta(
    'saveStatus',
  );
  @override
  late final GeneratedColumn<String> saveStatus = GeneratedColumn<String>(
    'save_status',
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
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _savedAtMeta = const VerificationMeta(
    'savedAt',
  );
  @override
  late final GeneratedColumn<DateTime> savedAt = GeneratedColumn<DateTime>(
    'saved_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _detectedAssetCountMeta =
      const VerificationMeta('detectedAssetCount');
  @override
  late final GeneratedColumn<int> detectedAssetCount = GeneratedColumn<int>(
    'detected_asset_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _storedAssetCountMeta = const VerificationMeta(
    'storedAssetCount',
  );
  @override
  late final GeneratedColumn<int> storedAssetCount = GeneratedColumn<int>(
    'stored_asset_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextSourceUrlMeta = const VerificationMeta(
    'nextSourceUrl',
  );
  @override
  late final GeneratedColumn<String> nextSourceUrl = GeneratedColumn<String>(
    'next_source_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _entryOrderMeta = const VerificationMeta(
    'entryOrder',
  );
  @override
  late final GeneratedColumn<int> entryOrder = GeneratedColumn<int>(
    'entry_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _saveErrorMeta = const VerificationMeta(
    'saveError',
  );
  @override
  late final GeneratedColumn<String> saveError = GeneratedColumn<String>(
    'save_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
  static const VerificationMeta _entryNumberMeta = const VerificationMeta(
    'entryNumber',
  );
  @override
  late final GeneratedColumn<double> entryNumber = GeneratedColumn<double>(
    'entry_number',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceMarkerMeta = const VerificationMeta(
    'sourceMarker',
  );
  @override
  late final GeneratedColumn<String> sourceMarker = GeneratedColumn<String>(
    'source_marker',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _readStatusMeta = const VerificationMeta(
    'readStatus',
  );
  @override
  late final GeneratedColumn<String> readStatus = GeneratedColumn<String>(
    'read_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('unread'),
  );
  static const VerificationMeta _progressFractionMeta = const VerificationMeta(
    'progressFraction',
  );
  @override
  late final GeneratedColumn<double> progressFraction = GeneratedColumn<double>(
    'progress_fraction',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _progressPageIndexMeta = const VerificationMeta(
    'progressPageIndex',
  );
  @override
  late final GeneratedColumn<int> progressPageIndex = GeneratedColumn<int>(
    'progress_page_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _progressOffsetInPageMeta =
      const VerificationMeta('progressOffsetInPage');
  @override
  late final GeneratedColumn<double> progressOffsetInPage =
      GeneratedColumn<double>(
        'progress_offset_in_page',
        aliasedName,
        false,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
        defaultValue: const Constant(0),
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
  static const VerificationMeta _progressUpdatedAtMeta = const VerificationMeta(
    'progressUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> progressUpdatedAt =
      GeneratedColumn<DateTime>(
        'progress_updated_at',
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
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _discoveryBasisMeta = const VerificationMeta(
    'discoveryBasis',
  );
  @override
  late final GeneratedColumn<String> discoveryBasis = GeneratedColumn<String>(
    'discovery_basis',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _discoveryConfidenceMeta =
      const VerificationMeta('discoveryConfidence');
  @override
  late final GeneratedColumn<String> discoveryConfidence =
      GeneratedColumn<String>(
        'discovery_confidence',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _offlineRemovedAtMeta = const VerificationMeta(
    'offlineRemovedAt',
  );
  @override
  late final GeneratedColumn<DateTime> offlineRemovedAt =
      GeneratedColumn<DateTime>(
        'offline_removed_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    collectionId,
    title,
    sourceUrl,
    urlKey,
    canonicalUrl,
    host,
    sourceTitle,
    publishedAt,
    contentKind,
    contentKindConfidence,
    contentKindIsUserSet,
    artifactFormat,
    captureMode,
    saveStatus,
    contentPath,
    savedAt,
    detectedAssetCount,
    storedAssetCount,
    nextSourceUrl,
    entryOrder,
    saveError,
    byteSize,
    entryNumber,
    sourceMarker,
    readStatus,
    progressFraction,
    progressPageIndex,
    progressOffsetInPage,
    firstOpenedAt,
    lastReadAt,
    completedAt,
    progressUpdatedAt,
    discoveredAt,
    discoveryBasis,
    discoveryConfidence,
    offlineRemovedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<Entry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
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
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('source_url')) {
      context.handle(
        _sourceUrlMeta,
        sourceUrl.isAcceptableOrUnknown(data['source_url']!, _sourceUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceUrlMeta);
    }
    if (data.containsKey('url_key')) {
      context.handle(
        _urlKeyMeta,
        urlKey.isAcceptableOrUnknown(data['url_key']!, _urlKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_urlKeyMeta);
    }
    if (data.containsKey('canonical_url')) {
      context.handle(
        _canonicalUrlMeta,
        canonicalUrl.isAcceptableOrUnknown(
          data['canonical_url']!,
          _canonicalUrlMeta,
        ),
      );
    }
    if (data.containsKey('host')) {
      context.handle(
        _hostMeta,
        host.isAcceptableOrUnknown(data['host']!, _hostMeta),
      );
    }
    if (data.containsKey('source_title')) {
      context.handle(
        _sourceTitleMeta,
        sourceTitle.isAcceptableOrUnknown(
          data['source_title']!,
          _sourceTitleMeta,
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
    if (data.containsKey('content_kind')) {
      context.handle(
        _contentKindMeta,
        contentKind.isAcceptableOrUnknown(
          data['content_kind']!,
          _contentKindMeta,
        ),
      );
    }
    if (data.containsKey('content_kind_confidence')) {
      context.handle(
        _contentKindConfidenceMeta,
        contentKindConfidence.isAcceptableOrUnknown(
          data['content_kind_confidence']!,
          _contentKindConfidenceMeta,
        ),
      );
    }
    if (data.containsKey('content_kind_is_user_set')) {
      context.handle(
        _contentKindIsUserSetMeta,
        contentKindIsUserSet.isAcceptableOrUnknown(
          data['content_kind_is_user_set']!,
          _contentKindIsUserSetMeta,
        ),
      );
    }
    if (data.containsKey('artifact_format')) {
      context.handle(
        _artifactFormatMeta,
        artifactFormat.isAcceptableOrUnknown(
          data['artifact_format']!,
          _artifactFormatMeta,
        ),
      );
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
    if (data.containsKey('save_status')) {
      context.handle(
        _saveStatusMeta,
        saveStatus.isAcceptableOrUnknown(data['save_status']!, _saveStatusMeta),
      );
    } else if (isInserting) {
      context.missing(_saveStatusMeta);
    }
    if (data.containsKey('content_path')) {
      context.handle(
        _contentPathMeta,
        contentPath.isAcceptableOrUnknown(
          data['content_path']!,
          _contentPathMeta,
        ),
      );
    }
    if (data.containsKey('saved_at')) {
      context.handle(
        _savedAtMeta,
        savedAt.isAcceptableOrUnknown(data['saved_at']!, _savedAtMeta),
      );
    }
    if (data.containsKey('detected_asset_count')) {
      context.handle(
        _detectedAssetCountMeta,
        detectedAssetCount.isAcceptableOrUnknown(
          data['detected_asset_count']!,
          _detectedAssetCountMeta,
        ),
      );
    }
    if (data.containsKey('stored_asset_count')) {
      context.handle(
        _storedAssetCountMeta,
        storedAssetCount.isAcceptableOrUnknown(
          data['stored_asset_count']!,
          _storedAssetCountMeta,
        ),
      );
    }
    if (data.containsKey('next_source_url')) {
      context.handle(
        _nextSourceUrlMeta,
        nextSourceUrl.isAcceptableOrUnknown(
          data['next_source_url']!,
          _nextSourceUrlMeta,
        ),
      );
    }
    if (data.containsKey('entry_order')) {
      context.handle(
        _entryOrderMeta,
        entryOrder.isAcceptableOrUnknown(data['entry_order']!, _entryOrderMeta),
      );
    }
    if (data.containsKey('save_error')) {
      context.handle(
        _saveErrorMeta,
        saveError.isAcceptableOrUnknown(data['save_error']!, _saveErrorMeta),
      );
    }
    if (data.containsKey('byte_size')) {
      context.handle(
        _byteSizeMeta,
        byteSize.isAcceptableOrUnknown(data['byte_size']!, _byteSizeMeta),
      );
    }
    if (data.containsKey('entry_number')) {
      context.handle(
        _entryNumberMeta,
        entryNumber.isAcceptableOrUnknown(
          data['entry_number']!,
          _entryNumberMeta,
        ),
      );
    }
    if (data.containsKey('source_marker')) {
      context.handle(
        _sourceMarkerMeta,
        sourceMarker.isAcceptableOrUnknown(
          data['source_marker']!,
          _sourceMarkerMeta,
        ),
      );
    }
    if (data.containsKey('read_status')) {
      context.handle(
        _readStatusMeta,
        readStatus.isAcceptableOrUnknown(data['read_status']!, _readStatusMeta),
      );
    }
    if (data.containsKey('progress_fraction')) {
      context.handle(
        _progressFractionMeta,
        progressFraction.isAcceptableOrUnknown(
          data['progress_fraction']!,
          _progressFractionMeta,
        ),
      );
    }
    if (data.containsKey('progress_page_index')) {
      context.handle(
        _progressPageIndexMeta,
        progressPageIndex.isAcceptableOrUnknown(
          data['progress_page_index']!,
          _progressPageIndexMeta,
        ),
      );
    }
    if (data.containsKey('progress_offset_in_page')) {
      context.handle(
        _progressOffsetInPageMeta,
        progressOffsetInPage.isAcceptableOrUnknown(
          data['progress_offset_in_page']!,
          _progressOffsetInPageMeta,
        ),
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
    if (data.containsKey('progress_updated_at')) {
      context.handle(
        _progressUpdatedAtMeta,
        progressUpdatedAt.isAcceptableOrUnknown(
          data['progress_updated_at']!,
          _progressUpdatedAtMeta,
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
    if (data.containsKey('discovery_confidence')) {
      context.handle(
        _discoveryConfidenceMeta,
        discoveryConfidence.isAcceptableOrUnknown(
          data['discovery_confidence']!,
          _discoveryConfidenceMeta,
        ),
      );
    }
    if (data.containsKey('offline_removed_at')) {
      context.handle(
        _offlineRemovedAtMeta,
        offlineRemovedAt.isAcceptableOrUnknown(
          data['offline_removed_at']!,
          _offlineRemovedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {collectionId, urlKey},
  ];
  @override
  Entry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Entry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      collectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}collection_id'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      sourceUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_url'],
      )!,
      urlKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url_key'],
      )!,
      canonicalUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}canonical_url'],
      ),
      host: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host'],
      )!,
      sourceTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_title'],
      ),
      publishedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}published_at'],
      ),
      contentKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_kind'],
      )!,
      contentKindConfidence: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_kind_confidence'],
      )!,
      contentKindIsUserSet: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}content_kind_is_user_set'],
      )!,
      artifactFormat: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artifact_format'],
      )!,
      captureMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}capture_mode'],
      ),
      saveStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}save_status'],
      )!,
      contentPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_path'],
      ),
      savedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}saved_at'],
      ),
      detectedAssetCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}detected_asset_count'],
      )!,
      storedAssetCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}stored_asset_count'],
      )!,
      nextSourceUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}next_source_url'],
      ),
      entryOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}entry_order'],
      )!,
      saveError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}save_error'],
      ),
      byteSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}byte_size'],
      )!,
      entryNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}entry_number'],
      ),
      sourceMarker: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_marker'],
      ),
      readStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}read_status'],
      )!,
      progressFraction: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}progress_fraction'],
      )!,
      progressPageIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}progress_page_index'],
      )!,
      progressOffsetInPage: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}progress_offset_in_page'],
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
      progressUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}progress_updated_at'],
      ),
      discoveredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}discovered_at'],
      ),
      discoveryBasis: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}discovery_basis'],
      ),
      discoveryConfidence: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}discovery_confidence'],
      ),
      offlineRemovedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}offline_removed_at'],
      ),
    );
  }

  @override
  $EntriesTable createAlias(String alias) {
    return $EntriesTable(attachedDatabase, alias);
  }
}

class Entry extends DataClass implements Insertable<Entry> {
  final String id;

  /// The collection this entry belongs to, or **null for a standalone entry**.
  ///
  /// Nullable is the whole point: a single saved article is a library item in
  /// its own right. Wrapping it in a one-entry collection would put a group in
  /// the library that the user never made and cannot meaningfully open.
  final String? collectionId;
  final String title;

  /// The address this entry was saved from. Durable metadata: it survives
  /// removal of the offline files, archiving, restoring, re-saving and every
  /// reading-state write, because every writer names its columns. It is what
  /// "Open original page" stands on.
  final String sourceUrl;

  /// Normalised [sourceUrl] — identity.
  final String urlKey;

  /// `<link rel=canonical>` when the page declared one. A second identity
  /// signal, and the one that catches a navigation loop that changes the address
  /// while serving the same document.
  final String? canonicalUrl;

  /// Registrable host of [sourceUrl], lowercased. Denormalised onto the entry
  /// because a standalone entry has no collection to read it from, and because
  /// source attribution shows the domain on every screen.
  final String host;

  /// The page's own `<title>`, kept verbatim. [title] may be cleaned up for
  /// display; this is what the source actually called it.
  final String? sourceTitle;

  /// Publication date, only when it was parsed from the page with confidence.
  /// Null means "not published, as far as we can honestly tell".
  final DateTime? publishedAt;

  /// `ContentKind.name` for this entry, and how much that is trusted.
  final String contentKind;
  final String contentKindConfidence;

  /// True once the user corrected the detected kind. Detection must never
  /// overwrite a human answer on a later re-save.
  final bool contentKindIsUserSet;

  /// `ArtifactFormat.name`. Mirrors the entry's `manifest.json`, which stays
  /// the authority — this copy exists so the library can describe an entry
  /// without opening a file per row.
  final String artifactFormat;

  /// `CaptureMode.name` actually used, or null for an entry that was only ever
  /// discovered. What was *used*, never what was requested: a run that fell
  /// back records the fallback.
  ///
  /// There is deliberately no `capture_mode_is_user_set` beside it. Whether a
  /// person picked the mode is a fact about the *save*, and it is recorded on
  /// the run, the queue row and the entry's manifest. A fourth copy on the row
  /// would be one more place for the same fact to drift out of agreement,
  /// and nothing reads it that the manifest cannot answer.
  final String? captureMode;
  final String saveStatus;

  /// Relative to the FileStore root. Never absolute.
  final String? contentPath;
  final DateTime? savedAt;
  final int detectedAssetCount;
  final int storedAssetCount;
  final String? nextSourceUrl;

  /// Authoritative position within the collection. Its *meaning* is given by the
  /// collection's `orderingBasis`, which is why the basis is stored rather than
  /// assumed.
  final int entryOrder;
  final String? saveError;
  final int byteSize;

  /// The number the *source* printed for this entry, when it printed one. `REAL`
  /// so `12.5` works. Null for anything not numeric — and null is never filled
  /// in by guessing.
  final double? entryNumber;

  /// The marker as the source wrote it: `Part 3`, `Prologue`, `Page 12 of 40`.
  /// Kept verbatim; the display label is derived in `entry_labels.dart`.
  final String? sourceMarker;
  final String readStatus;

  /// 0..1 through the entry. The durable half of the position — content
  /// independent, so it still means something after a re-save.
  final double progressFraction;

  /// Anchor: page index within the entry plus how far down it. Precise, but goes
  /// stale if the page count changes — which is what the fraction covers.
  final int progressPageIndex;
  final double progressOffsetInPage;
  final DateTime? firstOpenedAt;
  final DateTime? lastReadAt;
  final DateTime? completedAt;
  final DateTime? progressUpdatedAt;
  final DateTime? discoveredAt;

  /// entryList / nextChain / userPageHint / manual.
  final String? discoveryBasis;
  final String? discoveryConfidence;

  /// When the USER removed this entry's offline files. Distinct from files the
  /// system lost: a removed entry reads as "not available offline — save again",
  /// never as an error. Cleared explicitly on re-save.
  final DateTime? offlineRemovedAt;
  const Entry({
    required this.id,
    this.collectionId,
    required this.title,
    required this.sourceUrl,
    required this.urlKey,
    this.canonicalUrl,
    required this.host,
    this.sourceTitle,
    this.publishedAt,
    required this.contentKind,
    required this.contentKindConfidence,
    required this.contentKindIsUserSet,
    required this.artifactFormat,
    this.captureMode,
    required this.saveStatus,
    this.contentPath,
    this.savedAt,
    required this.detectedAssetCount,
    required this.storedAssetCount,
    this.nextSourceUrl,
    required this.entryOrder,
    this.saveError,
    required this.byteSize,
    this.entryNumber,
    this.sourceMarker,
    required this.readStatus,
    required this.progressFraction,
    required this.progressPageIndex,
    required this.progressOffsetInPage,
    this.firstOpenedAt,
    this.lastReadAt,
    this.completedAt,
    this.progressUpdatedAt,
    this.discoveredAt,
    this.discoveryBasis,
    this.discoveryConfidence,
    this.offlineRemovedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || collectionId != null) {
      map['collection_id'] = Variable<String>(collectionId);
    }
    map['title'] = Variable<String>(title);
    map['source_url'] = Variable<String>(sourceUrl);
    map['url_key'] = Variable<String>(urlKey);
    if (!nullToAbsent || canonicalUrl != null) {
      map['canonical_url'] = Variable<String>(canonicalUrl);
    }
    map['host'] = Variable<String>(host);
    if (!nullToAbsent || sourceTitle != null) {
      map['source_title'] = Variable<String>(sourceTitle);
    }
    if (!nullToAbsent || publishedAt != null) {
      map['published_at'] = Variable<DateTime>(publishedAt);
    }
    map['content_kind'] = Variable<String>(contentKind);
    map['content_kind_confidence'] = Variable<String>(contentKindConfidence);
    map['content_kind_is_user_set'] = Variable<bool>(contentKindIsUserSet);
    map['artifact_format'] = Variable<String>(artifactFormat);
    if (!nullToAbsent || captureMode != null) {
      map['capture_mode'] = Variable<String>(captureMode);
    }
    map['save_status'] = Variable<String>(saveStatus);
    if (!nullToAbsent || contentPath != null) {
      map['content_path'] = Variable<String>(contentPath);
    }
    if (!nullToAbsent || savedAt != null) {
      map['saved_at'] = Variable<DateTime>(savedAt);
    }
    map['detected_asset_count'] = Variable<int>(detectedAssetCount);
    map['stored_asset_count'] = Variable<int>(storedAssetCount);
    if (!nullToAbsent || nextSourceUrl != null) {
      map['next_source_url'] = Variable<String>(nextSourceUrl);
    }
    map['entry_order'] = Variable<int>(entryOrder);
    if (!nullToAbsent || saveError != null) {
      map['save_error'] = Variable<String>(saveError);
    }
    map['byte_size'] = Variable<int>(byteSize);
    if (!nullToAbsent || entryNumber != null) {
      map['entry_number'] = Variable<double>(entryNumber);
    }
    if (!nullToAbsent || sourceMarker != null) {
      map['source_marker'] = Variable<String>(sourceMarker);
    }
    map['read_status'] = Variable<String>(readStatus);
    map['progress_fraction'] = Variable<double>(progressFraction);
    map['progress_page_index'] = Variable<int>(progressPageIndex);
    map['progress_offset_in_page'] = Variable<double>(progressOffsetInPage);
    if (!nullToAbsent || firstOpenedAt != null) {
      map['first_opened_at'] = Variable<DateTime>(firstOpenedAt);
    }
    if (!nullToAbsent || lastReadAt != null) {
      map['last_read_at'] = Variable<DateTime>(lastReadAt);
    }
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    if (!nullToAbsent || progressUpdatedAt != null) {
      map['progress_updated_at'] = Variable<DateTime>(progressUpdatedAt);
    }
    if (!nullToAbsent || discoveredAt != null) {
      map['discovered_at'] = Variable<DateTime>(discoveredAt);
    }
    if (!nullToAbsent || discoveryBasis != null) {
      map['discovery_basis'] = Variable<String>(discoveryBasis);
    }
    if (!nullToAbsent || discoveryConfidence != null) {
      map['discovery_confidence'] = Variable<String>(discoveryConfidence);
    }
    if (!nullToAbsent || offlineRemovedAt != null) {
      map['offline_removed_at'] = Variable<DateTime>(offlineRemovedAt);
    }
    return map;
  }

  EntriesCompanion toCompanion(bool nullToAbsent) {
    return EntriesCompanion(
      id: Value(id),
      collectionId: collectionId == null && nullToAbsent
          ? const Value.absent()
          : Value(collectionId),
      title: Value(title),
      sourceUrl: Value(sourceUrl),
      urlKey: Value(urlKey),
      canonicalUrl: canonicalUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(canonicalUrl),
      host: Value(host),
      sourceTitle: sourceTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceTitle),
      publishedAt: publishedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(publishedAt),
      contentKind: Value(contentKind),
      contentKindConfidence: Value(contentKindConfidence),
      contentKindIsUserSet: Value(contentKindIsUserSet),
      artifactFormat: Value(artifactFormat),
      captureMode: captureMode == null && nullToAbsent
          ? const Value.absent()
          : Value(captureMode),
      saveStatus: Value(saveStatus),
      contentPath: contentPath == null && nullToAbsent
          ? const Value.absent()
          : Value(contentPath),
      savedAt: savedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(savedAt),
      detectedAssetCount: Value(detectedAssetCount),
      storedAssetCount: Value(storedAssetCount),
      nextSourceUrl: nextSourceUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(nextSourceUrl),
      entryOrder: Value(entryOrder),
      saveError: saveError == null && nullToAbsent
          ? const Value.absent()
          : Value(saveError),
      byteSize: Value(byteSize),
      entryNumber: entryNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(entryNumber),
      sourceMarker: sourceMarker == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceMarker),
      readStatus: Value(readStatus),
      progressFraction: Value(progressFraction),
      progressPageIndex: Value(progressPageIndex),
      progressOffsetInPage: Value(progressOffsetInPage),
      firstOpenedAt: firstOpenedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(firstOpenedAt),
      lastReadAt: lastReadAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReadAt),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      progressUpdatedAt: progressUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(progressUpdatedAt),
      discoveredAt: discoveredAt == null && nullToAbsent
          ? const Value.absent()
          : Value(discoveredAt),
      discoveryBasis: discoveryBasis == null && nullToAbsent
          ? const Value.absent()
          : Value(discoveryBasis),
      discoveryConfidence: discoveryConfidence == null && nullToAbsent
          ? const Value.absent()
          : Value(discoveryConfidence),
      offlineRemovedAt: offlineRemovedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(offlineRemovedAt),
    );
  }

  factory Entry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Entry(
      id: serializer.fromJson<String>(json['id']),
      collectionId: serializer.fromJson<String?>(json['collectionId']),
      title: serializer.fromJson<String>(json['title']),
      sourceUrl: serializer.fromJson<String>(json['sourceUrl']),
      urlKey: serializer.fromJson<String>(json['urlKey']),
      canonicalUrl: serializer.fromJson<String?>(json['canonicalUrl']),
      host: serializer.fromJson<String>(json['host']),
      sourceTitle: serializer.fromJson<String?>(json['sourceTitle']),
      publishedAt: serializer.fromJson<DateTime?>(json['publishedAt']),
      contentKind: serializer.fromJson<String>(json['contentKind']),
      contentKindConfidence: serializer.fromJson<String>(
        json['contentKindConfidence'],
      ),
      contentKindIsUserSet: serializer.fromJson<bool>(
        json['contentKindIsUserSet'],
      ),
      artifactFormat: serializer.fromJson<String>(json['artifactFormat']),
      captureMode: serializer.fromJson<String?>(json['captureMode']),
      saveStatus: serializer.fromJson<String>(json['saveStatus']),
      contentPath: serializer.fromJson<String?>(json['contentPath']),
      savedAt: serializer.fromJson<DateTime?>(json['savedAt']),
      detectedAssetCount: serializer.fromJson<int>(json['detectedAssetCount']),
      storedAssetCount: serializer.fromJson<int>(json['storedAssetCount']),
      nextSourceUrl: serializer.fromJson<String?>(json['nextSourceUrl']),
      entryOrder: serializer.fromJson<int>(json['entryOrder']),
      saveError: serializer.fromJson<String?>(json['saveError']),
      byteSize: serializer.fromJson<int>(json['byteSize']),
      entryNumber: serializer.fromJson<double?>(json['entryNumber']),
      sourceMarker: serializer.fromJson<String?>(json['sourceMarker']),
      readStatus: serializer.fromJson<String>(json['readStatus']),
      progressFraction: serializer.fromJson<double>(json['progressFraction']),
      progressPageIndex: serializer.fromJson<int>(json['progressPageIndex']),
      progressOffsetInPage: serializer.fromJson<double>(
        json['progressOffsetInPage'],
      ),
      firstOpenedAt: serializer.fromJson<DateTime?>(json['firstOpenedAt']),
      lastReadAt: serializer.fromJson<DateTime?>(json['lastReadAt']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
      progressUpdatedAt: serializer.fromJson<DateTime?>(
        json['progressUpdatedAt'],
      ),
      discoveredAt: serializer.fromJson<DateTime?>(json['discoveredAt']),
      discoveryBasis: serializer.fromJson<String?>(json['discoveryBasis']),
      discoveryConfidence: serializer.fromJson<String?>(
        json['discoveryConfidence'],
      ),
      offlineRemovedAt: serializer.fromJson<DateTime?>(
        json['offlineRemovedAt'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'collectionId': serializer.toJson<String?>(collectionId),
      'title': serializer.toJson<String>(title),
      'sourceUrl': serializer.toJson<String>(sourceUrl),
      'urlKey': serializer.toJson<String>(urlKey),
      'canonicalUrl': serializer.toJson<String?>(canonicalUrl),
      'host': serializer.toJson<String>(host),
      'sourceTitle': serializer.toJson<String?>(sourceTitle),
      'publishedAt': serializer.toJson<DateTime?>(publishedAt),
      'contentKind': serializer.toJson<String>(contentKind),
      'contentKindConfidence': serializer.toJson<String>(contentKindConfidence),
      'contentKindIsUserSet': serializer.toJson<bool>(contentKindIsUserSet),
      'artifactFormat': serializer.toJson<String>(artifactFormat),
      'captureMode': serializer.toJson<String?>(captureMode),
      'saveStatus': serializer.toJson<String>(saveStatus),
      'contentPath': serializer.toJson<String?>(contentPath),
      'savedAt': serializer.toJson<DateTime?>(savedAt),
      'detectedAssetCount': serializer.toJson<int>(detectedAssetCount),
      'storedAssetCount': serializer.toJson<int>(storedAssetCount),
      'nextSourceUrl': serializer.toJson<String?>(nextSourceUrl),
      'entryOrder': serializer.toJson<int>(entryOrder),
      'saveError': serializer.toJson<String?>(saveError),
      'byteSize': serializer.toJson<int>(byteSize),
      'entryNumber': serializer.toJson<double?>(entryNumber),
      'sourceMarker': serializer.toJson<String?>(sourceMarker),
      'readStatus': serializer.toJson<String>(readStatus),
      'progressFraction': serializer.toJson<double>(progressFraction),
      'progressPageIndex': serializer.toJson<int>(progressPageIndex),
      'progressOffsetInPage': serializer.toJson<double>(progressOffsetInPage),
      'firstOpenedAt': serializer.toJson<DateTime?>(firstOpenedAt),
      'lastReadAt': serializer.toJson<DateTime?>(lastReadAt),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
      'progressUpdatedAt': serializer.toJson<DateTime?>(progressUpdatedAt),
      'discoveredAt': serializer.toJson<DateTime?>(discoveredAt),
      'discoveryBasis': serializer.toJson<String?>(discoveryBasis),
      'discoveryConfidence': serializer.toJson<String?>(discoveryConfidence),
      'offlineRemovedAt': serializer.toJson<DateTime?>(offlineRemovedAt),
    };
  }

  Entry copyWith({
    String? id,
    Value<String?> collectionId = const Value.absent(),
    String? title,
    String? sourceUrl,
    String? urlKey,
    Value<String?> canonicalUrl = const Value.absent(),
    String? host,
    Value<String?> sourceTitle = const Value.absent(),
    Value<DateTime?> publishedAt = const Value.absent(),
    String? contentKind,
    String? contentKindConfidence,
    bool? contentKindIsUserSet,
    String? artifactFormat,
    Value<String?> captureMode = const Value.absent(),
    String? saveStatus,
    Value<String?> contentPath = const Value.absent(),
    Value<DateTime?> savedAt = const Value.absent(),
    int? detectedAssetCount,
    int? storedAssetCount,
    Value<String?> nextSourceUrl = const Value.absent(),
    int? entryOrder,
    Value<String?> saveError = const Value.absent(),
    int? byteSize,
    Value<double?> entryNumber = const Value.absent(),
    Value<String?> sourceMarker = const Value.absent(),
    String? readStatus,
    double? progressFraction,
    int? progressPageIndex,
    double? progressOffsetInPage,
    Value<DateTime?> firstOpenedAt = const Value.absent(),
    Value<DateTime?> lastReadAt = const Value.absent(),
    Value<DateTime?> completedAt = const Value.absent(),
    Value<DateTime?> progressUpdatedAt = const Value.absent(),
    Value<DateTime?> discoveredAt = const Value.absent(),
    Value<String?> discoveryBasis = const Value.absent(),
    Value<String?> discoveryConfidence = const Value.absent(),
    Value<DateTime?> offlineRemovedAt = const Value.absent(),
  }) => Entry(
    id: id ?? this.id,
    collectionId: collectionId.present ? collectionId.value : this.collectionId,
    title: title ?? this.title,
    sourceUrl: sourceUrl ?? this.sourceUrl,
    urlKey: urlKey ?? this.urlKey,
    canonicalUrl: canonicalUrl.present ? canonicalUrl.value : this.canonicalUrl,
    host: host ?? this.host,
    sourceTitle: sourceTitle.present ? sourceTitle.value : this.sourceTitle,
    publishedAt: publishedAt.present ? publishedAt.value : this.publishedAt,
    contentKind: contentKind ?? this.contentKind,
    contentKindConfidence: contentKindConfidence ?? this.contentKindConfidence,
    contentKindIsUserSet: contentKindIsUserSet ?? this.contentKindIsUserSet,
    artifactFormat: artifactFormat ?? this.artifactFormat,
    captureMode: captureMode.present ? captureMode.value : this.captureMode,
    saveStatus: saveStatus ?? this.saveStatus,
    contentPath: contentPath.present ? contentPath.value : this.contentPath,
    savedAt: savedAt.present ? savedAt.value : this.savedAt,
    detectedAssetCount: detectedAssetCount ?? this.detectedAssetCount,
    storedAssetCount: storedAssetCount ?? this.storedAssetCount,
    nextSourceUrl: nextSourceUrl.present
        ? nextSourceUrl.value
        : this.nextSourceUrl,
    entryOrder: entryOrder ?? this.entryOrder,
    saveError: saveError.present ? saveError.value : this.saveError,
    byteSize: byteSize ?? this.byteSize,
    entryNumber: entryNumber.present ? entryNumber.value : this.entryNumber,
    sourceMarker: sourceMarker.present ? sourceMarker.value : this.sourceMarker,
    readStatus: readStatus ?? this.readStatus,
    progressFraction: progressFraction ?? this.progressFraction,
    progressPageIndex: progressPageIndex ?? this.progressPageIndex,
    progressOffsetInPage: progressOffsetInPage ?? this.progressOffsetInPage,
    firstOpenedAt: firstOpenedAt.present
        ? firstOpenedAt.value
        : this.firstOpenedAt,
    lastReadAt: lastReadAt.present ? lastReadAt.value : this.lastReadAt,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
    progressUpdatedAt: progressUpdatedAt.present
        ? progressUpdatedAt.value
        : this.progressUpdatedAt,
    discoveredAt: discoveredAt.present ? discoveredAt.value : this.discoveredAt,
    discoveryBasis: discoveryBasis.present
        ? discoveryBasis.value
        : this.discoveryBasis,
    discoveryConfidence: discoveryConfidence.present
        ? discoveryConfidence.value
        : this.discoveryConfidence,
    offlineRemovedAt: offlineRemovedAt.present
        ? offlineRemovedAt.value
        : this.offlineRemovedAt,
  );
  Entry copyWithCompanion(EntriesCompanion data) {
    return Entry(
      id: data.id.present ? data.id.value : this.id,
      collectionId: data.collectionId.present
          ? data.collectionId.value
          : this.collectionId,
      title: data.title.present ? data.title.value : this.title,
      sourceUrl: data.sourceUrl.present ? data.sourceUrl.value : this.sourceUrl,
      urlKey: data.urlKey.present ? data.urlKey.value : this.urlKey,
      canonicalUrl: data.canonicalUrl.present
          ? data.canonicalUrl.value
          : this.canonicalUrl,
      host: data.host.present ? data.host.value : this.host,
      sourceTitle: data.sourceTitle.present
          ? data.sourceTitle.value
          : this.sourceTitle,
      publishedAt: data.publishedAt.present
          ? data.publishedAt.value
          : this.publishedAt,
      contentKind: data.contentKind.present
          ? data.contentKind.value
          : this.contentKind,
      contentKindConfidence: data.contentKindConfidence.present
          ? data.contentKindConfidence.value
          : this.contentKindConfidence,
      contentKindIsUserSet: data.contentKindIsUserSet.present
          ? data.contentKindIsUserSet.value
          : this.contentKindIsUserSet,
      artifactFormat: data.artifactFormat.present
          ? data.artifactFormat.value
          : this.artifactFormat,
      captureMode: data.captureMode.present
          ? data.captureMode.value
          : this.captureMode,
      saveStatus: data.saveStatus.present
          ? data.saveStatus.value
          : this.saveStatus,
      contentPath: data.contentPath.present
          ? data.contentPath.value
          : this.contentPath,
      savedAt: data.savedAt.present ? data.savedAt.value : this.savedAt,
      detectedAssetCount: data.detectedAssetCount.present
          ? data.detectedAssetCount.value
          : this.detectedAssetCount,
      storedAssetCount: data.storedAssetCount.present
          ? data.storedAssetCount.value
          : this.storedAssetCount,
      nextSourceUrl: data.nextSourceUrl.present
          ? data.nextSourceUrl.value
          : this.nextSourceUrl,
      entryOrder: data.entryOrder.present
          ? data.entryOrder.value
          : this.entryOrder,
      saveError: data.saveError.present ? data.saveError.value : this.saveError,
      byteSize: data.byteSize.present ? data.byteSize.value : this.byteSize,
      entryNumber: data.entryNumber.present
          ? data.entryNumber.value
          : this.entryNumber,
      sourceMarker: data.sourceMarker.present
          ? data.sourceMarker.value
          : this.sourceMarker,
      readStatus: data.readStatus.present
          ? data.readStatus.value
          : this.readStatus,
      progressFraction: data.progressFraction.present
          ? data.progressFraction.value
          : this.progressFraction,
      progressPageIndex: data.progressPageIndex.present
          ? data.progressPageIndex.value
          : this.progressPageIndex,
      progressOffsetInPage: data.progressOffsetInPage.present
          ? data.progressOffsetInPage.value
          : this.progressOffsetInPage,
      firstOpenedAt: data.firstOpenedAt.present
          ? data.firstOpenedAt.value
          : this.firstOpenedAt,
      lastReadAt: data.lastReadAt.present
          ? data.lastReadAt.value
          : this.lastReadAt,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      progressUpdatedAt: data.progressUpdatedAt.present
          ? data.progressUpdatedAt.value
          : this.progressUpdatedAt,
      discoveredAt: data.discoveredAt.present
          ? data.discoveredAt.value
          : this.discoveredAt,
      discoveryBasis: data.discoveryBasis.present
          ? data.discoveryBasis.value
          : this.discoveryBasis,
      discoveryConfidence: data.discoveryConfidence.present
          ? data.discoveryConfidence.value
          : this.discoveryConfidence,
      offlineRemovedAt: data.offlineRemovedAt.present
          ? data.offlineRemovedAt.value
          : this.offlineRemovedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Entry(')
          ..write('id: $id, ')
          ..write('collectionId: $collectionId, ')
          ..write('title: $title, ')
          ..write('sourceUrl: $sourceUrl, ')
          ..write('urlKey: $urlKey, ')
          ..write('canonicalUrl: $canonicalUrl, ')
          ..write('host: $host, ')
          ..write('sourceTitle: $sourceTitle, ')
          ..write('publishedAt: $publishedAt, ')
          ..write('contentKind: $contentKind, ')
          ..write('contentKindConfidence: $contentKindConfidence, ')
          ..write('contentKindIsUserSet: $contentKindIsUserSet, ')
          ..write('artifactFormat: $artifactFormat, ')
          ..write('captureMode: $captureMode, ')
          ..write('saveStatus: $saveStatus, ')
          ..write('contentPath: $contentPath, ')
          ..write('savedAt: $savedAt, ')
          ..write('detectedAssetCount: $detectedAssetCount, ')
          ..write('storedAssetCount: $storedAssetCount, ')
          ..write('nextSourceUrl: $nextSourceUrl, ')
          ..write('entryOrder: $entryOrder, ')
          ..write('saveError: $saveError, ')
          ..write('byteSize: $byteSize, ')
          ..write('entryNumber: $entryNumber, ')
          ..write('sourceMarker: $sourceMarker, ')
          ..write('readStatus: $readStatus, ')
          ..write('progressFraction: $progressFraction, ')
          ..write('progressPageIndex: $progressPageIndex, ')
          ..write('progressOffsetInPage: $progressOffsetInPage, ')
          ..write('firstOpenedAt: $firstOpenedAt, ')
          ..write('lastReadAt: $lastReadAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('progressUpdatedAt: $progressUpdatedAt, ')
          ..write('discoveredAt: $discoveredAt, ')
          ..write('discoveryBasis: $discoveryBasis, ')
          ..write('discoveryConfidence: $discoveryConfidence, ')
          ..write('offlineRemovedAt: $offlineRemovedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    collectionId,
    title,
    sourceUrl,
    urlKey,
    canonicalUrl,
    host,
    sourceTitle,
    publishedAt,
    contentKind,
    contentKindConfidence,
    contentKindIsUserSet,
    artifactFormat,
    captureMode,
    saveStatus,
    contentPath,
    savedAt,
    detectedAssetCount,
    storedAssetCount,
    nextSourceUrl,
    entryOrder,
    saveError,
    byteSize,
    entryNumber,
    sourceMarker,
    readStatus,
    progressFraction,
    progressPageIndex,
    progressOffsetInPage,
    firstOpenedAt,
    lastReadAt,
    completedAt,
    progressUpdatedAt,
    discoveredAt,
    discoveryBasis,
    discoveryConfidence,
    offlineRemovedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Entry &&
          other.id == this.id &&
          other.collectionId == this.collectionId &&
          other.title == this.title &&
          other.sourceUrl == this.sourceUrl &&
          other.urlKey == this.urlKey &&
          other.canonicalUrl == this.canonicalUrl &&
          other.host == this.host &&
          other.sourceTitle == this.sourceTitle &&
          other.publishedAt == this.publishedAt &&
          other.contentKind == this.contentKind &&
          other.contentKindConfidence == this.contentKindConfidence &&
          other.contentKindIsUserSet == this.contentKindIsUserSet &&
          other.artifactFormat == this.artifactFormat &&
          other.captureMode == this.captureMode &&
          other.saveStatus == this.saveStatus &&
          other.contentPath == this.contentPath &&
          other.savedAt == this.savedAt &&
          other.detectedAssetCount == this.detectedAssetCount &&
          other.storedAssetCount == this.storedAssetCount &&
          other.nextSourceUrl == this.nextSourceUrl &&
          other.entryOrder == this.entryOrder &&
          other.saveError == this.saveError &&
          other.byteSize == this.byteSize &&
          other.entryNumber == this.entryNumber &&
          other.sourceMarker == this.sourceMarker &&
          other.readStatus == this.readStatus &&
          other.progressFraction == this.progressFraction &&
          other.progressPageIndex == this.progressPageIndex &&
          other.progressOffsetInPage == this.progressOffsetInPage &&
          other.firstOpenedAt == this.firstOpenedAt &&
          other.lastReadAt == this.lastReadAt &&
          other.completedAt == this.completedAt &&
          other.progressUpdatedAt == this.progressUpdatedAt &&
          other.discoveredAt == this.discoveredAt &&
          other.discoveryBasis == this.discoveryBasis &&
          other.discoveryConfidence == this.discoveryConfidence &&
          other.offlineRemovedAt == this.offlineRemovedAt);
}

class EntriesCompanion extends UpdateCompanion<Entry> {
  final Value<String> id;
  final Value<String?> collectionId;
  final Value<String> title;
  final Value<String> sourceUrl;
  final Value<String> urlKey;
  final Value<String?> canonicalUrl;
  final Value<String> host;
  final Value<String?> sourceTitle;
  final Value<DateTime?> publishedAt;
  final Value<String> contentKind;
  final Value<String> contentKindConfidence;
  final Value<bool> contentKindIsUserSet;
  final Value<String> artifactFormat;
  final Value<String?> captureMode;
  final Value<String> saveStatus;
  final Value<String?> contentPath;
  final Value<DateTime?> savedAt;
  final Value<int> detectedAssetCount;
  final Value<int> storedAssetCount;
  final Value<String?> nextSourceUrl;
  final Value<int> entryOrder;
  final Value<String?> saveError;
  final Value<int> byteSize;
  final Value<double?> entryNumber;
  final Value<String?> sourceMarker;
  final Value<String> readStatus;
  final Value<double> progressFraction;
  final Value<int> progressPageIndex;
  final Value<double> progressOffsetInPage;
  final Value<DateTime?> firstOpenedAt;
  final Value<DateTime?> lastReadAt;
  final Value<DateTime?> completedAt;
  final Value<DateTime?> progressUpdatedAt;
  final Value<DateTime?> discoveredAt;
  final Value<String?> discoveryBasis;
  final Value<String?> discoveryConfidence;
  final Value<DateTime?> offlineRemovedAt;
  final Value<int> rowid;
  const EntriesCompanion({
    this.id = const Value.absent(),
    this.collectionId = const Value.absent(),
    this.title = const Value.absent(),
    this.sourceUrl = const Value.absent(),
    this.urlKey = const Value.absent(),
    this.canonicalUrl = const Value.absent(),
    this.host = const Value.absent(),
    this.sourceTitle = const Value.absent(),
    this.publishedAt = const Value.absent(),
    this.contentKind = const Value.absent(),
    this.contentKindConfidence = const Value.absent(),
    this.contentKindIsUserSet = const Value.absent(),
    this.artifactFormat = const Value.absent(),
    this.captureMode = const Value.absent(),
    this.saveStatus = const Value.absent(),
    this.contentPath = const Value.absent(),
    this.savedAt = const Value.absent(),
    this.detectedAssetCount = const Value.absent(),
    this.storedAssetCount = const Value.absent(),
    this.nextSourceUrl = const Value.absent(),
    this.entryOrder = const Value.absent(),
    this.saveError = const Value.absent(),
    this.byteSize = const Value.absent(),
    this.entryNumber = const Value.absent(),
    this.sourceMarker = const Value.absent(),
    this.readStatus = const Value.absent(),
    this.progressFraction = const Value.absent(),
    this.progressPageIndex = const Value.absent(),
    this.progressOffsetInPage = const Value.absent(),
    this.firstOpenedAt = const Value.absent(),
    this.lastReadAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.progressUpdatedAt = const Value.absent(),
    this.discoveredAt = const Value.absent(),
    this.discoveryBasis = const Value.absent(),
    this.discoveryConfidence = const Value.absent(),
    this.offlineRemovedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EntriesCompanion.insert({
    required String id,
    this.collectionId = const Value.absent(),
    required String title,
    required String sourceUrl,
    required String urlKey,
    this.canonicalUrl = const Value.absent(),
    this.host = const Value.absent(),
    this.sourceTitle = const Value.absent(),
    this.publishedAt = const Value.absent(),
    this.contentKind = const Value.absent(),
    this.contentKindConfidence = const Value.absent(),
    this.contentKindIsUserSet = const Value.absent(),
    this.artifactFormat = const Value.absent(),
    this.captureMode = const Value.absent(),
    required String saveStatus,
    this.contentPath = const Value.absent(),
    this.savedAt = const Value.absent(),
    this.detectedAssetCount = const Value.absent(),
    this.storedAssetCount = const Value.absent(),
    this.nextSourceUrl = const Value.absent(),
    this.entryOrder = const Value.absent(),
    this.saveError = const Value.absent(),
    this.byteSize = const Value.absent(),
    this.entryNumber = const Value.absent(),
    this.sourceMarker = const Value.absent(),
    this.readStatus = const Value.absent(),
    this.progressFraction = const Value.absent(),
    this.progressPageIndex = const Value.absent(),
    this.progressOffsetInPage = const Value.absent(),
    this.firstOpenedAt = const Value.absent(),
    this.lastReadAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.progressUpdatedAt = const Value.absent(),
    this.discoveredAt = const Value.absent(),
    this.discoveryBasis = const Value.absent(),
    this.discoveryConfidence = const Value.absent(),
    this.offlineRemovedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       sourceUrl = Value(sourceUrl),
       urlKey = Value(urlKey),
       saveStatus = Value(saveStatus);
  static Insertable<Entry> custom({
    Expression<String>? id,
    Expression<String>? collectionId,
    Expression<String>? title,
    Expression<String>? sourceUrl,
    Expression<String>? urlKey,
    Expression<String>? canonicalUrl,
    Expression<String>? host,
    Expression<String>? sourceTitle,
    Expression<DateTime>? publishedAt,
    Expression<String>? contentKind,
    Expression<String>? contentKindConfidence,
    Expression<bool>? contentKindIsUserSet,
    Expression<String>? artifactFormat,
    Expression<String>? captureMode,
    Expression<String>? saveStatus,
    Expression<String>? contentPath,
    Expression<DateTime>? savedAt,
    Expression<int>? detectedAssetCount,
    Expression<int>? storedAssetCount,
    Expression<String>? nextSourceUrl,
    Expression<int>? entryOrder,
    Expression<String>? saveError,
    Expression<int>? byteSize,
    Expression<double>? entryNumber,
    Expression<String>? sourceMarker,
    Expression<String>? readStatus,
    Expression<double>? progressFraction,
    Expression<int>? progressPageIndex,
    Expression<double>? progressOffsetInPage,
    Expression<DateTime>? firstOpenedAt,
    Expression<DateTime>? lastReadAt,
    Expression<DateTime>? completedAt,
    Expression<DateTime>? progressUpdatedAt,
    Expression<DateTime>? discoveredAt,
    Expression<String>? discoveryBasis,
    Expression<String>? discoveryConfidence,
    Expression<DateTime>? offlineRemovedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (collectionId != null) 'collection_id': collectionId,
      if (title != null) 'title': title,
      if (sourceUrl != null) 'source_url': sourceUrl,
      if (urlKey != null) 'url_key': urlKey,
      if (canonicalUrl != null) 'canonical_url': canonicalUrl,
      if (host != null) 'host': host,
      if (sourceTitle != null) 'source_title': sourceTitle,
      if (publishedAt != null) 'published_at': publishedAt,
      if (contentKind != null) 'content_kind': contentKind,
      if (contentKindConfidence != null)
        'content_kind_confidence': contentKindConfidence,
      if (contentKindIsUserSet != null)
        'content_kind_is_user_set': contentKindIsUserSet,
      if (artifactFormat != null) 'artifact_format': artifactFormat,
      if (captureMode != null) 'capture_mode': captureMode,
      if (saveStatus != null) 'save_status': saveStatus,
      if (contentPath != null) 'content_path': contentPath,
      if (savedAt != null) 'saved_at': savedAt,
      if (detectedAssetCount != null)
        'detected_asset_count': detectedAssetCount,
      if (storedAssetCount != null) 'stored_asset_count': storedAssetCount,
      if (nextSourceUrl != null) 'next_source_url': nextSourceUrl,
      if (entryOrder != null) 'entry_order': entryOrder,
      if (saveError != null) 'save_error': saveError,
      if (byteSize != null) 'byte_size': byteSize,
      if (entryNumber != null) 'entry_number': entryNumber,
      if (sourceMarker != null) 'source_marker': sourceMarker,
      if (readStatus != null) 'read_status': readStatus,
      if (progressFraction != null) 'progress_fraction': progressFraction,
      if (progressPageIndex != null) 'progress_page_index': progressPageIndex,
      if (progressOffsetInPage != null)
        'progress_offset_in_page': progressOffsetInPage,
      if (firstOpenedAt != null) 'first_opened_at': firstOpenedAt,
      if (lastReadAt != null) 'last_read_at': lastReadAt,
      if (completedAt != null) 'completed_at': completedAt,
      if (progressUpdatedAt != null) 'progress_updated_at': progressUpdatedAt,
      if (discoveredAt != null) 'discovered_at': discoveredAt,
      if (discoveryBasis != null) 'discovery_basis': discoveryBasis,
      if (discoveryConfidence != null)
        'discovery_confidence': discoveryConfidence,
      if (offlineRemovedAt != null) 'offline_removed_at': offlineRemovedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EntriesCompanion copyWith({
    Value<String>? id,
    Value<String?>? collectionId,
    Value<String>? title,
    Value<String>? sourceUrl,
    Value<String>? urlKey,
    Value<String?>? canonicalUrl,
    Value<String>? host,
    Value<String?>? sourceTitle,
    Value<DateTime?>? publishedAt,
    Value<String>? contentKind,
    Value<String>? contentKindConfidence,
    Value<bool>? contentKindIsUserSet,
    Value<String>? artifactFormat,
    Value<String?>? captureMode,
    Value<String>? saveStatus,
    Value<String?>? contentPath,
    Value<DateTime?>? savedAt,
    Value<int>? detectedAssetCount,
    Value<int>? storedAssetCount,
    Value<String?>? nextSourceUrl,
    Value<int>? entryOrder,
    Value<String?>? saveError,
    Value<int>? byteSize,
    Value<double?>? entryNumber,
    Value<String?>? sourceMarker,
    Value<String>? readStatus,
    Value<double>? progressFraction,
    Value<int>? progressPageIndex,
    Value<double>? progressOffsetInPage,
    Value<DateTime?>? firstOpenedAt,
    Value<DateTime?>? lastReadAt,
    Value<DateTime?>? completedAt,
    Value<DateTime?>? progressUpdatedAt,
    Value<DateTime?>? discoveredAt,
    Value<String?>? discoveryBasis,
    Value<String?>? discoveryConfidence,
    Value<DateTime?>? offlineRemovedAt,
    Value<int>? rowid,
  }) {
    return EntriesCompanion(
      id: id ?? this.id,
      collectionId: collectionId ?? this.collectionId,
      title: title ?? this.title,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      urlKey: urlKey ?? this.urlKey,
      canonicalUrl: canonicalUrl ?? this.canonicalUrl,
      host: host ?? this.host,
      sourceTitle: sourceTitle ?? this.sourceTitle,
      publishedAt: publishedAt ?? this.publishedAt,
      contentKind: contentKind ?? this.contentKind,
      contentKindConfidence:
          contentKindConfidence ?? this.contentKindConfidence,
      contentKindIsUserSet: contentKindIsUserSet ?? this.contentKindIsUserSet,
      artifactFormat: artifactFormat ?? this.artifactFormat,
      captureMode: captureMode ?? this.captureMode,
      saveStatus: saveStatus ?? this.saveStatus,
      contentPath: contentPath ?? this.contentPath,
      savedAt: savedAt ?? this.savedAt,
      detectedAssetCount: detectedAssetCount ?? this.detectedAssetCount,
      storedAssetCount: storedAssetCount ?? this.storedAssetCount,
      nextSourceUrl: nextSourceUrl ?? this.nextSourceUrl,
      entryOrder: entryOrder ?? this.entryOrder,
      saveError: saveError ?? this.saveError,
      byteSize: byteSize ?? this.byteSize,
      entryNumber: entryNumber ?? this.entryNumber,
      sourceMarker: sourceMarker ?? this.sourceMarker,
      readStatus: readStatus ?? this.readStatus,
      progressFraction: progressFraction ?? this.progressFraction,
      progressPageIndex: progressPageIndex ?? this.progressPageIndex,
      progressOffsetInPage: progressOffsetInPage ?? this.progressOffsetInPage,
      firstOpenedAt: firstOpenedAt ?? this.firstOpenedAt,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      completedAt: completedAt ?? this.completedAt,
      progressUpdatedAt: progressUpdatedAt ?? this.progressUpdatedAt,
      discoveredAt: discoveredAt ?? this.discoveredAt,
      discoveryBasis: discoveryBasis ?? this.discoveryBasis,
      discoveryConfidence: discoveryConfidence ?? this.discoveryConfidence,
      offlineRemovedAt: offlineRemovedAt ?? this.offlineRemovedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (collectionId.present) {
      map['collection_id'] = Variable<String>(collectionId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (sourceUrl.present) {
      map['source_url'] = Variable<String>(sourceUrl.value);
    }
    if (urlKey.present) {
      map['url_key'] = Variable<String>(urlKey.value);
    }
    if (canonicalUrl.present) {
      map['canonical_url'] = Variable<String>(canonicalUrl.value);
    }
    if (host.present) {
      map['host'] = Variable<String>(host.value);
    }
    if (sourceTitle.present) {
      map['source_title'] = Variable<String>(sourceTitle.value);
    }
    if (publishedAt.present) {
      map['published_at'] = Variable<DateTime>(publishedAt.value);
    }
    if (contentKind.present) {
      map['content_kind'] = Variable<String>(contentKind.value);
    }
    if (contentKindConfidence.present) {
      map['content_kind_confidence'] = Variable<String>(
        contentKindConfidence.value,
      );
    }
    if (contentKindIsUserSet.present) {
      map['content_kind_is_user_set'] = Variable<bool>(
        contentKindIsUserSet.value,
      );
    }
    if (artifactFormat.present) {
      map['artifact_format'] = Variable<String>(artifactFormat.value);
    }
    if (captureMode.present) {
      map['capture_mode'] = Variable<String>(captureMode.value);
    }
    if (saveStatus.present) {
      map['save_status'] = Variable<String>(saveStatus.value);
    }
    if (contentPath.present) {
      map['content_path'] = Variable<String>(contentPath.value);
    }
    if (savedAt.present) {
      map['saved_at'] = Variable<DateTime>(savedAt.value);
    }
    if (detectedAssetCount.present) {
      map['detected_asset_count'] = Variable<int>(detectedAssetCount.value);
    }
    if (storedAssetCount.present) {
      map['stored_asset_count'] = Variable<int>(storedAssetCount.value);
    }
    if (nextSourceUrl.present) {
      map['next_source_url'] = Variable<String>(nextSourceUrl.value);
    }
    if (entryOrder.present) {
      map['entry_order'] = Variable<int>(entryOrder.value);
    }
    if (saveError.present) {
      map['save_error'] = Variable<String>(saveError.value);
    }
    if (byteSize.present) {
      map['byte_size'] = Variable<int>(byteSize.value);
    }
    if (entryNumber.present) {
      map['entry_number'] = Variable<double>(entryNumber.value);
    }
    if (sourceMarker.present) {
      map['source_marker'] = Variable<String>(sourceMarker.value);
    }
    if (readStatus.present) {
      map['read_status'] = Variable<String>(readStatus.value);
    }
    if (progressFraction.present) {
      map['progress_fraction'] = Variable<double>(progressFraction.value);
    }
    if (progressPageIndex.present) {
      map['progress_page_index'] = Variable<int>(progressPageIndex.value);
    }
    if (progressOffsetInPage.present) {
      map['progress_offset_in_page'] = Variable<double>(
        progressOffsetInPage.value,
      );
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
    if (progressUpdatedAt.present) {
      map['progress_updated_at'] = Variable<DateTime>(progressUpdatedAt.value);
    }
    if (discoveredAt.present) {
      map['discovered_at'] = Variable<DateTime>(discoveredAt.value);
    }
    if (discoveryBasis.present) {
      map['discovery_basis'] = Variable<String>(discoveryBasis.value);
    }
    if (discoveryConfidence.present) {
      map['discovery_confidence'] = Variable<String>(discoveryConfidence.value);
    }
    if (offlineRemovedAt.present) {
      map['offline_removed_at'] = Variable<DateTime>(offlineRemovedAt.value);
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
          ..write('collectionId: $collectionId, ')
          ..write('title: $title, ')
          ..write('sourceUrl: $sourceUrl, ')
          ..write('urlKey: $urlKey, ')
          ..write('canonicalUrl: $canonicalUrl, ')
          ..write('host: $host, ')
          ..write('sourceTitle: $sourceTitle, ')
          ..write('publishedAt: $publishedAt, ')
          ..write('contentKind: $contentKind, ')
          ..write('contentKindConfidence: $contentKindConfidence, ')
          ..write('contentKindIsUserSet: $contentKindIsUserSet, ')
          ..write('artifactFormat: $artifactFormat, ')
          ..write('captureMode: $captureMode, ')
          ..write('saveStatus: $saveStatus, ')
          ..write('contentPath: $contentPath, ')
          ..write('savedAt: $savedAt, ')
          ..write('detectedAssetCount: $detectedAssetCount, ')
          ..write('storedAssetCount: $storedAssetCount, ')
          ..write('nextSourceUrl: $nextSourceUrl, ')
          ..write('entryOrder: $entryOrder, ')
          ..write('saveError: $saveError, ')
          ..write('byteSize: $byteSize, ')
          ..write('entryNumber: $entryNumber, ')
          ..write('sourceMarker: $sourceMarker, ')
          ..write('readStatus: $readStatus, ')
          ..write('progressFraction: $progressFraction, ')
          ..write('progressPageIndex: $progressPageIndex, ')
          ..write('progressOffsetInPage: $progressOffsetInPage, ')
          ..write('firstOpenedAt: $firstOpenedAt, ')
          ..write('lastReadAt: $lastReadAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('progressUpdatedAt: $progressUpdatedAt, ')
          ..write('discoveredAt: $discoveredAt, ')
          ..write('discoveryBasis: $discoveryBasis, ')
          ..write('discoveryConfidence: $discoveryConfidence, ')
          ..write('offlineRemovedAt: $offlineRemovedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SaveRunsTable extends SaveRuns with TableInfo<$SaveRunsTable, SaveRun> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SaveRunsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _startUrlMeta = const VerificationMeta(
    'startUrl',
  );
  @override
  late final GeneratedColumn<String> startUrl = GeneratedColumn<String>(
    'start_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currentUrlMeta = const VerificationMeta(
    'currentUrl',
  );
  @override
  late final GeneratedColumn<String> currentUrl = GeneratedColumn<String>(
    'current_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _requestedEntriesMeta = const VerificationMeta(
    'requestedEntries',
  );
  @override
  late final GeneratedColumn<int> requestedEntries = GeneratedColumn<int>(
    'requested_entries',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completedEntriesMeta = const VerificationMeta(
    'completedEntries',
  );
  @override
  late final GeneratedColumn<int> completedEntries = GeneratedColumn<int>(
    'completed_entries',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
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
  static const VerificationMeta _visitedUrlsMeta = const VerificationMeta(
    'visitedUrls',
  );
  @override
  late final GeneratedColumn<String> visitedUrls = GeneratedColumn<String>(
    'visited_urls',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _visitedCanonicalsMeta = const VerificationMeta(
    'visitedCanonicals',
  );
  @override
  late final GeneratedColumn<String> visitedCanonicals =
      GeneratedColumn<String>(
        'visited_canonicals',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant(''),
      );
  static const VerificationMeta _duplicatePolicyMeta = const VerificationMeta(
    'duplicatePolicy',
  );
  @override
  late final GeneratedColumn<String> duplicatePolicy = GeneratedColumn<String>(
    'duplicate_policy',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sessionDuplicateDecisionMeta =
      const VerificationMeta('sessionDuplicateDecision');
  @override
  late final GeneratedColumn<String> sessionDuplicateDecision =
      GeneratedColumn<String>(
        'session_duplicate_decision',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _sessionPartialDecisionMeta =
      const VerificationMeta('sessionPartialDecision');
  @override
  late final GeneratedColumn<String> sessionPartialDecision =
      GeneratedColumn<String>(
        'session_partial_decision',
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
    requiredDuringInsert: false,
    defaultValue: const Constant('currentPageOnly'),
  );
  static const VerificationMeta _maxBytesMeta = const VerificationMeta(
    'maxBytes',
  );
  @override
  late final GeneratedColumn<int> maxBytes = GeneratedColumn<int>(
    'max_bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
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
  static const VerificationMeta _pauseReasonMeta = const VerificationMeta(
    'pauseReason',
  );
  @override
  late final GeneratedColumn<String> pauseReason = GeneratedColumn<String>(
    'pause_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    collectionId,
    startUrl,
    currentUrl,
    requestedEntries,
    completedEntries,
    state,
    lastError,
    stopReason,
    visitedUrls,
    visitedCanonicals,
    duplicatePolicy,
    sessionDuplicateDecision,
    sessionPartialDecision,
    scope,
    maxBytes,
    captureMode,
    captureModeIsUserSet,
    pauseReason,
    origin,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'save_runs';
  @override
  VerificationContext validateIntegrity(
    Insertable<SaveRun> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
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
    if (data.containsKey('start_url')) {
      context.handle(
        _startUrlMeta,
        startUrl.isAcceptableOrUnknown(data['start_url']!, _startUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_startUrlMeta);
    }
    if (data.containsKey('current_url')) {
      context.handle(
        _currentUrlMeta,
        currentUrl.isAcceptableOrUnknown(data['current_url']!, _currentUrlMeta),
      );
    }
    if (data.containsKey('requested_entries')) {
      context.handle(
        _requestedEntriesMeta,
        requestedEntries.isAcceptableOrUnknown(
          data['requested_entries']!,
          _requestedEntriesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_requestedEntriesMeta);
    }
    if (data.containsKey('completed_entries')) {
      context.handle(
        _completedEntriesMeta,
        completedEntries.isAcceptableOrUnknown(
          data['completed_entries']!,
          _completedEntriesMeta,
        ),
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
    if (data.containsKey('visited_urls')) {
      context.handle(
        _visitedUrlsMeta,
        visitedUrls.isAcceptableOrUnknown(
          data['visited_urls']!,
          _visitedUrlsMeta,
        ),
      );
    }
    if (data.containsKey('visited_canonicals')) {
      context.handle(
        _visitedCanonicalsMeta,
        visitedCanonicals.isAcceptableOrUnknown(
          data['visited_canonicals']!,
          _visitedCanonicalsMeta,
        ),
      );
    }
    if (data.containsKey('duplicate_policy')) {
      context.handle(
        _duplicatePolicyMeta,
        duplicatePolicy.isAcceptableOrUnknown(
          data['duplicate_policy']!,
          _duplicatePolicyMeta,
        ),
      );
    }
    if (data.containsKey('session_duplicate_decision')) {
      context.handle(
        _sessionDuplicateDecisionMeta,
        sessionDuplicateDecision.isAcceptableOrUnknown(
          data['session_duplicate_decision']!,
          _sessionDuplicateDecisionMeta,
        ),
      );
    }
    if (data.containsKey('session_partial_decision')) {
      context.handle(
        _sessionPartialDecisionMeta,
        sessionPartialDecision.isAcceptableOrUnknown(
          data['session_partial_decision']!,
          _sessionPartialDecisionMeta,
        ),
      );
    }
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    }
    if (data.containsKey('max_bytes')) {
      context.handle(
        _maxBytesMeta,
        maxBytes.isAcceptableOrUnknown(data['max_bytes']!, _maxBytesMeta),
      );
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
    if (data.containsKey('pause_reason')) {
      context.handle(
        _pauseReasonMeta,
        pauseReason.isAcceptableOrUnknown(
          data['pause_reason']!,
          _pauseReasonMeta,
        ),
      );
    }
    if (data.containsKey('origin')) {
      context.handle(
        _originMeta,
        origin.isAcceptableOrUnknown(data['origin']!, _originMeta),
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SaveRun map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SaveRun(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      collectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}collection_id'],
      ),
      startUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}start_url'],
      )!,
      currentUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}current_url'],
      ),
      requestedEntries: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}requested_entries'],
      )!,
      completedEntries: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completed_entries'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      stopReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stop_reason'],
      ),
      visitedUrls: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}visited_urls'],
      )!,
      visitedCanonicals: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}visited_canonicals'],
      )!,
      duplicatePolicy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}duplicate_policy'],
      ),
      sessionDuplicateDecision: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_duplicate_decision'],
      ),
      sessionPartialDecision: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_partial_decision'],
      ),
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
      maxBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_bytes'],
      ),
      captureMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}capture_mode'],
      ),
      captureModeIsUserSet: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}capture_mode_is_user_set'],
      )!,
      pauseReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pause_reason'],
      ),
      origin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SaveRunsTable createAlias(String alias) {
    return $SaveRunsTable(attachedDatabase, alias);
  }
}

class SaveRun extends DataClass implements Insertable<SaveRun> {
  final String id;
  final String? collectionId;
  final String startUrl;
  final String? currentUrl;

  /// How many *new* entries this run was authorised to save. Always a real
  /// number, including for open-ended sequences — there is no "unlimited".
  final int requestedEntries;
  final int completedEntries;
  final String state;
  final String? lastError;

  /// Which stopping condition ended the run (`StopReason.name`), or null while
  /// it is still going. Named rather than inferred, so "stopped because the site
  /// asked for a login" can never be reported as "finished".
  final String? stopReason;

  /// Newline-separated normalised URLs already walked in this run.
  final String visitedUrls;

  /// Newline-separated canonical URLs already seen. Kept separately from
  /// [visitedUrls] because the loop that matters most is the one where the
  /// address changes and the document does not.
  final String visitedCanonicals;

  /// The duplicate policy the run started with, so a resume applies the same one
  /// instead of silently reverting to the default.
  final String? duplicatePolicy;

  /// Session-scoped answers to "this entry is already saved". Persisted on the
  /// run — they survive an interrupted-session resume — and die with it. Never a
  /// global preference.
  final String? sessionDuplicateDecision;
  final String? sessionPartialDecision;

  /// `SaveScope.name` — currentPageOnly | selectedEntries | fixedCount.
  /// A resume continues in the same mode, and an unrecognised value (a row
  /// written before the open-ended scope was removed) reads as the safest
  /// one rather than saving more than was asked for.
  final String scope;

  /// The user's explicit storage ceiling in bytes, when they set one. Required
  /// alongside a count for open-ended sequences.
  final int? maxBytes;

  /// `CaptureMode.name` the run was started with — image sequence, text only,
  /// or text and images.
  ///
  /// Replaced the old `include_images` boolean, which could not express the
  /// difference between "an ordered sequence of full-size images" and "an
  /// article with pictures in it" and which nothing ever read. Nullable
  /// because a resume of a run started before the mode was chosen re-detects
  /// rather than assuming one.
  final String? captureMode;

  /// Whether the user picked the mode themselves, so a resume does not quietly
  /// re-detect over a deliberate choice.
  final bool captureModeIsUserSet;

  /// Why a running save is paused (`browserHidden` today; null otherwise).
  final String? pauseReason;

  /// `direct` | `queue` — how this run was launched. Persisted so an interrupted
  /// direct save resumes as a direct save rather than being quietly turned into
  /// pending queue work.
  final String origin;
  final DateTime createdAt;
  final DateTime updatedAt;
  const SaveRun({
    required this.id,
    this.collectionId,
    required this.startUrl,
    this.currentUrl,
    required this.requestedEntries,
    required this.completedEntries,
    required this.state,
    this.lastError,
    this.stopReason,
    required this.visitedUrls,
    required this.visitedCanonicals,
    this.duplicatePolicy,
    this.sessionDuplicateDecision,
    this.sessionPartialDecision,
    required this.scope,
    this.maxBytes,
    this.captureMode,
    required this.captureModeIsUserSet,
    this.pauseReason,
    required this.origin,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || collectionId != null) {
      map['collection_id'] = Variable<String>(collectionId);
    }
    map['start_url'] = Variable<String>(startUrl);
    if (!nullToAbsent || currentUrl != null) {
      map['current_url'] = Variable<String>(currentUrl);
    }
    map['requested_entries'] = Variable<int>(requestedEntries);
    map['completed_entries'] = Variable<int>(completedEntries);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    if (!nullToAbsent || stopReason != null) {
      map['stop_reason'] = Variable<String>(stopReason);
    }
    map['visited_urls'] = Variable<String>(visitedUrls);
    map['visited_canonicals'] = Variable<String>(visitedCanonicals);
    if (!nullToAbsent || duplicatePolicy != null) {
      map['duplicate_policy'] = Variable<String>(duplicatePolicy);
    }
    if (!nullToAbsent || sessionDuplicateDecision != null) {
      map['session_duplicate_decision'] = Variable<String>(
        sessionDuplicateDecision,
      );
    }
    if (!nullToAbsent || sessionPartialDecision != null) {
      map['session_partial_decision'] = Variable<String>(
        sessionPartialDecision,
      );
    }
    map['scope'] = Variable<String>(scope);
    if (!nullToAbsent || maxBytes != null) {
      map['max_bytes'] = Variable<int>(maxBytes);
    }
    if (!nullToAbsent || captureMode != null) {
      map['capture_mode'] = Variable<String>(captureMode);
    }
    map['capture_mode_is_user_set'] = Variable<bool>(captureModeIsUserSet);
    if (!nullToAbsent || pauseReason != null) {
      map['pause_reason'] = Variable<String>(pauseReason);
    }
    map['origin'] = Variable<String>(origin);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SaveRunsCompanion toCompanion(bool nullToAbsent) {
    return SaveRunsCompanion(
      id: Value(id),
      collectionId: collectionId == null && nullToAbsent
          ? const Value.absent()
          : Value(collectionId),
      startUrl: Value(startUrl),
      currentUrl: currentUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(currentUrl),
      requestedEntries: Value(requestedEntries),
      completedEntries: Value(completedEntries),
      state: Value(state),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      stopReason: stopReason == null && nullToAbsent
          ? const Value.absent()
          : Value(stopReason),
      visitedUrls: Value(visitedUrls),
      visitedCanonicals: Value(visitedCanonicals),
      duplicatePolicy: duplicatePolicy == null && nullToAbsent
          ? const Value.absent()
          : Value(duplicatePolicy),
      sessionDuplicateDecision: sessionDuplicateDecision == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionDuplicateDecision),
      sessionPartialDecision: sessionPartialDecision == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionPartialDecision),
      scope: Value(scope),
      maxBytes: maxBytes == null && nullToAbsent
          ? const Value.absent()
          : Value(maxBytes),
      captureMode: captureMode == null && nullToAbsent
          ? const Value.absent()
          : Value(captureMode),
      captureModeIsUserSet: Value(captureModeIsUserSet),
      pauseReason: pauseReason == null && nullToAbsent
          ? const Value.absent()
          : Value(pauseReason),
      origin: Value(origin),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory SaveRun.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SaveRun(
      id: serializer.fromJson<String>(json['id']),
      collectionId: serializer.fromJson<String?>(json['collectionId']),
      startUrl: serializer.fromJson<String>(json['startUrl']),
      currentUrl: serializer.fromJson<String?>(json['currentUrl']),
      requestedEntries: serializer.fromJson<int>(json['requestedEntries']),
      completedEntries: serializer.fromJson<int>(json['completedEntries']),
      state: serializer.fromJson<String>(json['state']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      stopReason: serializer.fromJson<String?>(json['stopReason']),
      visitedUrls: serializer.fromJson<String>(json['visitedUrls']),
      visitedCanonicals: serializer.fromJson<String>(json['visitedCanonicals']),
      duplicatePolicy: serializer.fromJson<String?>(json['duplicatePolicy']),
      sessionDuplicateDecision: serializer.fromJson<String?>(
        json['sessionDuplicateDecision'],
      ),
      sessionPartialDecision: serializer.fromJson<String?>(
        json['sessionPartialDecision'],
      ),
      scope: serializer.fromJson<String>(json['scope']),
      maxBytes: serializer.fromJson<int?>(json['maxBytes']),
      captureMode: serializer.fromJson<String?>(json['captureMode']),
      captureModeIsUserSet: serializer.fromJson<bool>(
        json['captureModeIsUserSet'],
      ),
      pauseReason: serializer.fromJson<String?>(json['pauseReason']),
      origin: serializer.fromJson<String>(json['origin']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'collectionId': serializer.toJson<String?>(collectionId),
      'startUrl': serializer.toJson<String>(startUrl),
      'currentUrl': serializer.toJson<String?>(currentUrl),
      'requestedEntries': serializer.toJson<int>(requestedEntries),
      'completedEntries': serializer.toJson<int>(completedEntries),
      'state': serializer.toJson<String>(state),
      'lastError': serializer.toJson<String?>(lastError),
      'stopReason': serializer.toJson<String?>(stopReason),
      'visitedUrls': serializer.toJson<String>(visitedUrls),
      'visitedCanonicals': serializer.toJson<String>(visitedCanonicals),
      'duplicatePolicy': serializer.toJson<String?>(duplicatePolicy),
      'sessionDuplicateDecision': serializer.toJson<String?>(
        sessionDuplicateDecision,
      ),
      'sessionPartialDecision': serializer.toJson<String?>(
        sessionPartialDecision,
      ),
      'scope': serializer.toJson<String>(scope),
      'maxBytes': serializer.toJson<int?>(maxBytes),
      'captureMode': serializer.toJson<String?>(captureMode),
      'captureModeIsUserSet': serializer.toJson<bool>(captureModeIsUserSet),
      'pauseReason': serializer.toJson<String?>(pauseReason),
      'origin': serializer.toJson<String>(origin),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SaveRun copyWith({
    String? id,
    Value<String?> collectionId = const Value.absent(),
    String? startUrl,
    Value<String?> currentUrl = const Value.absent(),
    int? requestedEntries,
    int? completedEntries,
    String? state,
    Value<String?> lastError = const Value.absent(),
    Value<String?> stopReason = const Value.absent(),
    String? visitedUrls,
    String? visitedCanonicals,
    Value<String?> duplicatePolicy = const Value.absent(),
    Value<String?> sessionDuplicateDecision = const Value.absent(),
    Value<String?> sessionPartialDecision = const Value.absent(),
    String? scope,
    Value<int?> maxBytes = const Value.absent(),
    Value<String?> captureMode = const Value.absent(),
    bool? captureModeIsUserSet,
    Value<String?> pauseReason = const Value.absent(),
    String? origin,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => SaveRun(
    id: id ?? this.id,
    collectionId: collectionId.present ? collectionId.value : this.collectionId,
    startUrl: startUrl ?? this.startUrl,
    currentUrl: currentUrl.present ? currentUrl.value : this.currentUrl,
    requestedEntries: requestedEntries ?? this.requestedEntries,
    completedEntries: completedEntries ?? this.completedEntries,
    state: state ?? this.state,
    lastError: lastError.present ? lastError.value : this.lastError,
    stopReason: stopReason.present ? stopReason.value : this.stopReason,
    visitedUrls: visitedUrls ?? this.visitedUrls,
    visitedCanonicals: visitedCanonicals ?? this.visitedCanonicals,
    duplicatePolicy: duplicatePolicy.present
        ? duplicatePolicy.value
        : this.duplicatePolicy,
    sessionDuplicateDecision: sessionDuplicateDecision.present
        ? sessionDuplicateDecision.value
        : this.sessionDuplicateDecision,
    sessionPartialDecision: sessionPartialDecision.present
        ? sessionPartialDecision.value
        : this.sessionPartialDecision,
    scope: scope ?? this.scope,
    maxBytes: maxBytes.present ? maxBytes.value : this.maxBytes,
    captureMode: captureMode.present ? captureMode.value : this.captureMode,
    captureModeIsUserSet: captureModeIsUserSet ?? this.captureModeIsUserSet,
    pauseReason: pauseReason.present ? pauseReason.value : this.pauseReason,
    origin: origin ?? this.origin,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SaveRun copyWithCompanion(SaveRunsCompanion data) {
    return SaveRun(
      id: data.id.present ? data.id.value : this.id,
      collectionId: data.collectionId.present
          ? data.collectionId.value
          : this.collectionId,
      startUrl: data.startUrl.present ? data.startUrl.value : this.startUrl,
      currentUrl: data.currentUrl.present
          ? data.currentUrl.value
          : this.currentUrl,
      requestedEntries: data.requestedEntries.present
          ? data.requestedEntries.value
          : this.requestedEntries,
      completedEntries: data.completedEntries.present
          ? data.completedEntries.value
          : this.completedEntries,
      state: data.state.present ? data.state.value : this.state,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      stopReason: data.stopReason.present
          ? data.stopReason.value
          : this.stopReason,
      visitedUrls: data.visitedUrls.present
          ? data.visitedUrls.value
          : this.visitedUrls,
      visitedCanonicals: data.visitedCanonicals.present
          ? data.visitedCanonicals.value
          : this.visitedCanonicals,
      duplicatePolicy: data.duplicatePolicy.present
          ? data.duplicatePolicy.value
          : this.duplicatePolicy,
      sessionDuplicateDecision: data.sessionDuplicateDecision.present
          ? data.sessionDuplicateDecision.value
          : this.sessionDuplicateDecision,
      sessionPartialDecision: data.sessionPartialDecision.present
          ? data.sessionPartialDecision.value
          : this.sessionPartialDecision,
      scope: data.scope.present ? data.scope.value : this.scope,
      maxBytes: data.maxBytes.present ? data.maxBytes.value : this.maxBytes,
      captureMode: data.captureMode.present
          ? data.captureMode.value
          : this.captureMode,
      captureModeIsUserSet: data.captureModeIsUserSet.present
          ? data.captureModeIsUserSet.value
          : this.captureModeIsUserSet,
      pauseReason: data.pauseReason.present
          ? data.pauseReason.value
          : this.pauseReason,
      origin: data.origin.present ? data.origin.value : this.origin,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SaveRun(')
          ..write('id: $id, ')
          ..write('collectionId: $collectionId, ')
          ..write('startUrl: $startUrl, ')
          ..write('currentUrl: $currentUrl, ')
          ..write('requestedEntries: $requestedEntries, ')
          ..write('completedEntries: $completedEntries, ')
          ..write('state: $state, ')
          ..write('lastError: $lastError, ')
          ..write('stopReason: $stopReason, ')
          ..write('visitedUrls: $visitedUrls, ')
          ..write('visitedCanonicals: $visitedCanonicals, ')
          ..write('duplicatePolicy: $duplicatePolicy, ')
          ..write('sessionDuplicateDecision: $sessionDuplicateDecision, ')
          ..write('sessionPartialDecision: $sessionPartialDecision, ')
          ..write('scope: $scope, ')
          ..write('maxBytes: $maxBytes, ')
          ..write('captureMode: $captureMode, ')
          ..write('captureModeIsUserSet: $captureModeIsUserSet, ')
          ..write('pauseReason: $pauseReason, ')
          ..write('origin: $origin, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    collectionId,
    startUrl,
    currentUrl,
    requestedEntries,
    completedEntries,
    state,
    lastError,
    stopReason,
    visitedUrls,
    visitedCanonicals,
    duplicatePolicy,
    sessionDuplicateDecision,
    sessionPartialDecision,
    scope,
    maxBytes,
    captureMode,
    captureModeIsUserSet,
    pauseReason,
    origin,
    createdAt,
    updatedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SaveRun &&
          other.id == this.id &&
          other.collectionId == this.collectionId &&
          other.startUrl == this.startUrl &&
          other.currentUrl == this.currentUrl &&
          other.requestedEntries == this.requestedEntries &&
          other.completedEntries == this.completedEntries &&
          other.state == this.state &&
          other.lastError == this.lastError &&
          other.stopReason == this.stopReason &&
          other.visitedUrls == this.visitedUrls &&
          other.visitedCanonicals == this.visitedCanonicals &&
          other.duplicatePolicy == this.duplicatePolicy &&
          other.sessionDuplicateDecision == this.sessionDuplicateDecision &&
          other.sessionPartialDecision == this.sessionPartialDecision &&
          other.scope == this.scope &&
          other.maxBytes == this.maxBytes &&
          other.captureMode == this.captureMode &&
          other.captureModeIsUserSet == this.captureModeIsUserSet &&
          other.pauseReason == this.pauseReason &&
          other.origin == this.origin &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SaveRunsCompanion extends UpdateCompanion<SaveRun> {
  final Value<String> id;
  final Value<String?> collectionId;
  final Value<String> startUrl;
  final Value<String?> currentUrl;
  final Value<int> requestedEntries;
  final Value<int> completedEntries;
  final Value<String> state;
  final Value<String?> lastError;
  final Value<String?> stopReason;
  final Value<String> visitedUrls;
  final Value<String> visitedCanonicals;
  final Value<String?> duplicatePolicy;
  final Value<String?> sessionDuplicateDecision;
  final Value<String?> sessionPartialDecision;
  final Value<String> scope;
  final Value<int?> maxBytes;
  final Value<String?> captureMode;
  final Value<bool> captureModeIsUserSet;
  final Value<String?> pauseReason;
  final Value<String> origin;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SaveRunsCompanion({
    this.id = const Value.absent(),
    this.collectionId = const Value.absent(),
    this.startUrl = const Value.absent(),
    this.currentUrl = const Value.absent(),
    this.requestedEntries = const Value.absent(),
    this.completedEntries = const Value.absent(),
    this.state = const Value.absent(),
    this.lastError = const Value.absent(),
    this.stopReason = const Value.absent(),
    this.visitedUrls = const Value.absent(),
    this.visitedCanonicals = const Value.absent(),
    this.duplicatePolicy = const Value.absent(),
    this.sessionDuplicateDecision = const Value.absent(),
    this.sessionPartialDecision = const Value.absent(),
    this.scope = const Value.absent(),
    this.maxBytes = const Value.absent(),
    this.captureMode = const Value.absent(),
    this.captureModeIsUserSet = const Value.absent(),
    this.pauseReason = const Value.absent(),
    this.origin = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SaveRunsCompanion.insert({
    required String id,
    this.collectionId = const Value.absent(),
    required String startUrl,
    this.currentUrl = const Value.absent(),
    required int requestedEntries,
    this.completedEntries = const Value.absent(),
    required String state,
    this.lastError = const Value.absent(),
    this.stopReason = const Value.absent(),
    this.visitedUrls = const Value.absent(),
    this.visitedCanonicals = const Value.absent(),
    this.duplicatePolicy = const Value.absent(),
    this.sessionDuplicateDecision = const Value.absent(),
    this.sessionPartialDecision = const Value.absent(),
    this.scope = const Value.absent(),
    this.maxBytes = const Value.absent(),
    this.captureMode = const Value.absent(),
    this.captureModeIsUserSet = const Value.absent(),
    this.pauseReason = const Value.absent(),
    this.origin = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       startUrl = Value(startUrl),
       requestedEntries = Value(requestedEntries),
       state = Value(state),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<SaveRun> custom({
    Expression<String>? id,
    Expression<String>? collectionId,
    Expression<String>? startUrl,
    Expression<String>? currentUrl,
    Expression<int>? requestedEntries,
    Expression<int>? completedEntries,
    Expression<String>? state,
    Expression<String>? lastError,
    Expression<String>? stopReason,
    Expression<String>? visitedUrls,
    Expression<String>? visitedCanonicals,
    Expression<String>? duplicatePolicy,
    Expression<String>? sessionDuplicateDecision,
    Expression<String>? sessionPartialDecision,
    Expression<String>? scope,
    Expression<int>? maxBytes,
    Expression<String>? captureMode,
    Expression<bool>? captureModeIsUserSet,
    Expression<String>? pauseReason,
    Expression<String>? origin,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (collectionId != null) 'collection_id': collectionId,
      if (startUrl != null) 'start_url': startUrl,
      if (currentUrl != null) 'current_url': currentUrl,
      if (requestedEntries != null) 'requested_entries': requestedEntries,
      if (completedEntries != null) 'completed_entries': completedEntries,
      if (state != null) 'state': state,
      if (lastError != null) 'last_error': lastError,
      if (stopReason != null) 'stop_reason': stopReason,
      if (visitedUrls != null) 'visited_urls': visitedUrls,
      if (visitedCanonicals != null) 'visited_canonicals': visitedCanonicals,
      if (duplicatePolicy != null) 'duplicate_policy': duplicatePolicy,
      if (sessionDuplicateDecision != null)
        'session_duplicate_decision': sessionDuplicateDecision,
      if (sessionPartialDecision != null)
        'session_partial_decision': sessionPartialDecision,
      if (scope != null) 'scope': scope,
      if (maxBytes != null) 'max_bytes': maxBytes,
      if (captureMode != null) 'capture_mode': captureMode,
      if (captureModeIsUserSet != null)
        'capture_mode_is_user_set': captureModeIsUserSet,
      if (pauseReason != null) 'pause_reason': pauseReason,
      if (origin != null) 'origin': origin,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SaveRunsCompanion copyWith({
    Value<String>? id,
    Value<String?>? collectionId,
    Value<String>? startUrl,
    Value<String?>? currentUrl,
    Value<int>? requestedEntries,
    Value<int>? completedEntries,
    Value<String>? state,
    Value<String?>? lastError,
    Value<String?>? stopReason,
    Value<String>? visitedUrls,
    Value<String>? visitedCanonicals,
    Value<String?>? duplicatePolicy,
    Value<String?>? sessionDuplicateDecision,
    Value<String?>? sessionPartialDecision,
    Value<String>? scope,
    Value<int?>? maxBytes,
    Value<String?>? captureMode,
    Value<bool>? captureModeIsUserSet,
    Value<String?>? pauseReason,
    Value<String>? origin,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SaveRunsCompanion(
      id: id ?? this.id,
      collectionId: collectionId ?? this.collectionId,
      startUrl: startUrl ?? this.startUrl,
      currentUrl: currentUrl ?? this.currentUrl,
      requestedEntries: requestedEntries ?? this.requestedEntries,
      completedEntries: completedEntries ?? this.completedEntries,
      state: state ?? this.state,
      lastError: lastError ?? this.lastError,
      stopReason: stopReason ?? this.stopReason,
      visitedUrls: visitedUrls ?? this.visitedUrls,
      visitedCanonicals: visitedCanonicals ?? this.visitedCanonicals,
      duplicatePolicy: duplicatePolicy ?? this.duplicatePolicy,
      sessionDuplicateDecision:
          sessionDuplicateDecision ?? this.sessionDuplicateDecision,
      sessionPartialDecision:
          sessionPartialDecision ?? this.sessionPartialDecision,
      scope: scope ?? this.scope,
      maxBytes: maxBytes ?? this.maxBytes,
      captureMode: captureMode ?? this.captureMode,
      captureModeIsUserSet: captureModeIsUserSet ?? this.captureModeIsUserSet,
      pauseReason: pauseReason ?? this.pauseReason,
      origin: origin ?? this.origin,
      createdAt: createdAt ?? this.createdAt,
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
    if (collectionId.present) {
      map['collection_id'] = Variable<String>(collectionId.value);
    }
    if (startUrl.present) {
      map['start_url'] = Variable<String>(startUrl.value);
    }
    if (currentUrl.present) {
      map['current_url'] = Variable<String>(currentUrl.value);
    }
    if (requestedEntries.present) {
      map['requested_entries'] = Variable<int>(requestedEntries.value);
    }
    if (completedEntries.present) {
      map['completed_entries'] = Variable<int>(completedEntries.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (stopReason.present) {
      map['stop_reason'] = Variable<String>(stopReason.value);
    }
    if (visitedUrls.present) {
      map['visited_urls'] = Variable<String>(visitedUrls.value);
    }
    if (visitedCanonicals.present) {
      map['visited_canonicals'] = Variable<String>(visitedCanonicals.value);
    }
    if (duplicatePolicy.present) {
      map['duplicate_policy'] = Variable<String>(duplicatePolicy.value);
    }
    if (sessionDuplicateDecision.present) {
      map['session_duplicate_decision'] = Variable<String>(
        sessionDuplicateDecision.value,
      );
    }
    if (sessionPartialDecision.present) {
      map['session_partial_decision'] = Variable<String>(
        sessionPartialDecision.value,
      );
    }
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (maxBytes.present) {
      map['max_bytes'] = Variable<int>(maxBytes.value);
    }
    if (captureMode.present) {
      map['capture_mode'] = Variable<String>(captureMode.value);
    }
    if (captureModeIsUserSet.present) {
      map['capture_mode_is_user_set'] = Variable<bool>(
        captureModeIsUserSet.value,
      );
    }
    if (pauseReason.present) {
      map['pause_reason'] = Variable<String>(pauseReason.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
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
    return (StringBuffer('SaveRunsCompanion(')
          ..write('id: $id, ')
          ..write('collectionId: $collectionId, ')
          ..write('startUrl: $startUrl, ')
          ..write('currentUrl: $currentUrl, ')
          ..write('requestedEntries: $requestedEntries, ')
          ..write('completedEntries: $completedEntries, ')
          ..write('state: $state, ')
          ..write('lastError: $lastError, ')
          ..write('stopReason: $stopReason, ')
          ..write('visitedUrls: $visitedUrls, ')
          ..write('visitedCanonicals: $visitedCanonicals, ')
          ..write('duplicatePolicy: $duplicatePolicy, ')
          ..write('sessionDuplicateDecision: $sessionDuplicateDecision, ')
          ..write('sessionPartialDecision: $sessionPartialDecision, ')
          ..write('scope: $scope, ')
          ..write('maxBytes: $maxBytes, ')
          ..write('captureMode: $captureMode, ')
          ..write('captureModeIsUserSet: $captureModeIsUserSet, ')
          ..write('pauseReason: $pauseReason, ')
          ..write('origin: $origin, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UserPageHintsTable extends UserPageHints
    with TableInfo<$UserPageHintsTable, UserPageHintRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UserPageHintsTable(this.attachedDatabase, [this._alias]);
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
  static const String $name = 'user_page_hints';
  @override
  VerificationContext validateIntegrity(
    Insertable<UserPageHintRow> instance, {
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
  UserPageHintRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UserPageHintRow(
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
  $UserPageHintsTable createAlias(String alias) {
    return $UserPageHintsTable(attachedDatabase, alias);
  }
}

class UserPageHintRow extends DataClass implements Insertable<UserPageHintRow> {
  final String id;
  final String host;

  /// Collection fingerprint, or a path shape for `pathShape` scope. Null only
  /// for site-wide hints, which the user has to opt into explicitly.
  final String? hintPath;
  final String scope;
  final String kind;

  /// Serialised `DomLocator` — a bag of independent signals, not one selector.
  final String locatorJson;
  final String? exampleSourceUrl;
  final String? exampleTargetUrl;
  final bool sameHostOnly;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final int successCount;
  final int failureCount;
  const UserPageHintRow({
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

  UserPageHintsCompanion toCompanion(bool nullToAbsent) {
    return UserPageHintsCompanion(
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

  factory UserPageHintRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UserPageHintRow(
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

  UserPageHintRow copyWith({
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
  }) => UserPageHintRow(
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
  UserPageHintRow copyWithCompanion(UserPageHintsCompanion data) {
    return UserPageHintRow(
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
    return (StringBuffer('UserPageHintRow(')
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
      (other is UserPageHintRow &&
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

class UserPageHintsCompanion extends UpdateCompanion<UserPageHintRow> {
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
  const UserPageHintsCompanion({
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
  UserPageHintsCompanion.insert({
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
  static Insertable<UserPageHintRow> custom({
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

  UserPageHintsCompanion copyWith({
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
    return UserPageHintsCompanion(
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
    return (StringBuffer('UserPageHintsCompanion(')
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

class $SettingsTable extends Settings with TableInfo<$SettingsTable, Setting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
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
    Insertable<Setting> instance, {
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
  Setting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Setting(
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
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class Setting extends DataClass implements Insertable<Setting> {
  final String key;
  final String value;
  const Setting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), value: Value(value));
  }

  factory Setting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Setting(
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

  Setting copyWith({String? key, String? value}) =>
      Setting(key: key ?? this.key, value: value ?? this.value);
  Setting copyWithCompanion(SettingsCompanion data) {
    return Setting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Setting(')
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
      (other is Setting && other.key == this.key && other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<Setting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<Setting> custom({
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

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
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
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $QueueTasksTable extends QueueTasks
    with TableInfo<$QueueTasksTable, QueueTask> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $QueueTasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _taskTypeMeta = const VerificationMeta(
    'taskType',
  );
  @override
  late final GeneratedColumn<String> taskType = GeneratedColumn<String>(
    'task_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _startUrlMeta = const VerificationMeta(
    'startUrl',
  );
  @override
  late final GeneratedColumn<String> startUrl = GeneratedColumn<String>(
    'start_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _entryLimitMeta = const VerificationMeta(
    'entryLimit',
  );
  @override
  late final GeneratedColumn<int> entryLimit = GeneratedColumn<int>(
    'entry_limit',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _maxBytesMeta = const VerificationMeta(
    'maxBytes',
  );
  @override
  late final GeneratedColumn<int> maxBytes = GeneratedColumn<int>(
    'max_bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
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
  static const VerificationMeta _duplicatePolicyMeta = const VerificationMeta(
    'duplicatePolicy',
  );
  @override
  late final GeneratedColumn<String> duplicatePolicy = GeneratedColumn<String>(
    'duplicate_policy',
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
    taskType,
    collectionId,
    startUrl,
    entryLimit,
    maxBytes,
    captureMode,
    captureModeIsUserSet,
    duplicatePolicy,
    scope,
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
  static const String $name = 'queue_tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<QueueTask> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('task_type')) {
      context.handle(
        _taskTypeMeta,
        taskType.isAcceptableOrUnknown(data['task_type']!, _taskTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_taskTypeMeta);
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
    if (data.containsKey('start_url')) {
      context.handle(
        _startUrlMeta,
        startUrl.isAcceptableOrUnknown(data['start_url']!, _startUrlMeta),
      );
    }
    if (data.containsKey('entry_limit')) {
      context.handle(
        _entryLimitMeta,
        entryLimit.isAcceptableOrUnknown(data['entry_limit']!, _entryLimitMeta),
      );
    }
    if (data.containsKey('max_bytes')) {
      context.handle(
        _maxBytesMeta,
        maxBytes.isAcceptableOrUnknown(data['max_bytes']!, _maxBytesMeta),
      );
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
    if (data.containsKey('duplicate_policy')) {
      context.handle(
        _duplicatePolicyMeta,
        duplicatePolicy.isAcceptableOrUnknown(
          data['duplicate_policy']!,
          _duplicatePolicyMeta,
        ),
      );
    }
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
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
  QueueTask map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return QueueTask(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      taskType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_type'],
      )!,
      collectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}collection_id'],
      ),
      startUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}start_url'],
      ),
      entryLimit: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}entry_limit'],
      ),
      maxBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_bytes'],
      ),
      captureMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}capture_mode'],
      ),
      captureModeIsUserSet: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}capture_mode_is_user_set'],
      )!,
      duplicatePolicy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}duplicate_policy'],
      ),
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      ),
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
  $QueueTasksTable createAlias(String alias) {
    return $QueueTasksTable(attachedDatabase, alias);
  }
}

class QueueTask extends DataClass implements Insertable<QueueTask> {
  final String id;

  /// entrySave | sequenceSave | collectionCheck | checkAllCollections |
  /// offlineCleanup
  final String taskType;
  final String? collectionId;
  final String? startUrl;

  /// The explicit ceiling on new entries. Never null for a multi-entry task.
  final int? entryLimit;
  final int? maxBytes;

  /// `CaptureMode.name` for a save task, or null for a task that stores
  /// nothing (a check, a cleanup) and for one queued before a mode was chosen.
  final String? captureMode;

  /// Whether that mode was the user's explicit choice.
  final bool captureModeIsUserSet;
  final String? duplicatePolicy;

  /// `SaveScope.name`.
  final String? scope;

  /// queued | running | completed | failed | cancelled
  final String state;

  /// `queue` | `direct` — whether this row is queued work or the record of a
  /// save the user started straight from the Browser.
  ///
  /// A `direct` row is **only ever terminal**: a direct save creates no pending
  /// entry, so nothing here can be released by the queue pump. It exists for
  /// Activity history and error reporting.
  final String origin;

  /// Short human summary of how it ended.
  final String? outcome;
  final String? lastError;

  /// Which stopping condition ended it (`StopReason.name`), when one did.
  final String? stopReason;

  /// FIFO order within the queue.
  final int orderIndex;
  final DateTime queuedAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  const QueueTask({
    required this.id,
    required this.taskType,
    this.collectionId,
    this.startUrl,
    this.entryLimit,
    this.maxBytes,
    this.captureMode,
    required this.captureModeIsUserSet,
    this.duplicatePolicy,
    this.scope,
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
    map['task_type'] = Variable<String>(taskType);
    if (!nullToAbsent || collectionId != null) {
      map['collection_id'] = Variable<String>(collectionId);
    }
    if (!nullToAbsent || startUrl != null) {
      map['start_url'] = Variable<String>(startUrl);
    }
    if (!nullToAbsent || entryLimit != null) {
      map['entry_limit'] = Variable<int>(entryLimit);
    }
    if (!nullToAbsent || maxBytes != null) {
      map['max_bytes'] = Variable<int>(maxBytes);
    }
    if (!nullToAbsent || captureMode != null) {
      map['capture_mode'] = Variable<String>(captureMode);
    }
    map['capture_mode_is_user_set'] = Variable<bool>(captureModeIsUserSet);
    if (!nullToAbsent || duplicatePolicy != null) {
      map['duplicate_policy'] = Variable<String>(duplicatePolicy);
    }
    if (!nullToAbsent || scope != null) {
      map['scope'] = Variable<String>(scope);
    }
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

  QueueTasksCompanion toCompanion(bool nullToAbsent) {
    return QueueTasksCompanion(
      id: Value(id),
      taskType: Value(taskType),
      collectionId: collectionId == null && nullToAbsent
          ? const Value.absent()
          : Value(collectionId),
      startUrl: startUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(startUrl),
      entryLimit: entryLimit == null && nullToAbsent
          ? const Value.absent()
          : Value(entryLimit),
      maxBytes: maxBytes == null && nullToAbsent
          ? const Value.absent()
          : Value(maxBytes),
      captureMode: captureMode == null && nullToAbsent
          ? const Value.absent()
          : Value(captureMode),
      captureModeIsUserSet: Value(captureModeIsUserSet),
      duplicatePolicy: duplicatePolicy == null && nullToAbsent
          ? const Value.absent()
          : Value(duplicatePolicy),
      scope: scope == null && nullToAbsent
          ? const Value.absent()
          : Value(scope),
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

  factory QueueTask.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return QueueTask(
      id: serializer.fromJson<String>(json['id']),
      taskType: serializer.fromJson<String>(json['taskType']),
      collectionId: serializer.fromJson<String?>(json['collectionId']),
      startUrl: serializer.fromJson<String?>(json['startUrl']),
      entryLimit: serializer.fromJson<int?>(json['entryLimit']),
      maxBytes: serializer.fromJson<int?>(json['maxBytes']),
      captureMode: serializer.fromJson<String?>(json['captureMode']),
      captureModeIsUserSet: serializer.fromJson<bool>(
        json['captureModeIsUserSet'],
      ),
      duplicatePolicy: serializer.fromJson<String?>(json['duplicatePolicy']),
      scope: serializer.fromJson<String?>(json['scope']),
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
      'taskType': serializer.toJson<String>(taskType),
      'collectionId': serializer.toJson<String?>(collectionId),
      'startUrl': serializer.toJson<String?>(startUrl),
      'entryLimit': serializer.toJson<int?>(entryLimit),
      'maxBytes': serializer.toJson<int?>(maxBytes),
      'captureMode': serializer.toJson<String?>(captureMode),
      'captureModeIsUserSet': serializer.toJson<bool>(captureModeIsUserSet),
      'duplicatePolicy': serializer.toJson<String?>(duplicatePolicy),
      'scope': serializer.toJson<String?>(scope),
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

  QueueTask copyWith({
    String? id,
    String? taskType,
    Value<String?> collectionId = const Value.absent(),
    Value<String?> startUrl = const Value.absent(),
    Value<int?> entryLimit = const Value.absent(),
    Value<int?> maxBytes = const Value.absent(),
    Value<String?> captureMode = const Value.absent(),
    bool? captureModeIsUserSet,
    Value<String?> duplicatePolicy = const Value.absent(),
    Value<String?> scope = const Value.absent(),
    String? state,
    String? origin,
    Value<String?> outcome = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
    Value<String?> stopReason = const Value.absent(),
    int? orderIndex,
    DateTime? queuedAt,
    Value<DateTime?> startedAt = const Value.absent(),
    Value<DateTime?> finishedAt = const Value.absent(),
  }) => QueueTask(
    id: id ?? this.id,
    taskType: taskType ?? this.taskType,
    collectionId: collectionId.present ? collectionId.value : this.collectionId,
    startUrl: startUrl.present ? startUrl.value : this.startUrl,
    entryLimit: entryLimit.present ? entryLimit.value : this.entryLimit,
    maxBytes: maxBytes.present ? maxBytes.value : this.maxBytes,
    captureMode: captureMode.present ? captureMode.value : this.captureMode,
    captureModeIsUserSet: captureModeIsUserSet ?? this.captureModeIsUserSet,
    duplicatePolicy: duplicatePolicy.present
        ? duplicatePolicy.value
        : this.duplicatePolicy,
    scope: scope.present ? scope.value : this.scope,
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
  QueueTask copyWithCompanion(QueueTasksCompanion data) {
    return QueueTask(
      id: data.id.present ? data.id.value : this.id,
      taskType: data.taskType.present ? data.taskType.value : this.taskType,
      collectionId: data.collectionId.present
          ? data.collectionId.value
          : this.collectionId,
      startUrl: data.startUrl.present ? data.startUrl.value : this.startUrl,
      entryLimit: data.entryLimit.present
          ? data.entryLimit.value
          : this.entryLimit,
      maxBytes: data.maxBytes.present ? data.maxBytes.value : this.maxBytes,
      captureMode: data.captureMode.present
          ? data.captureMode.value
          : this.captureMode,
      captureModeIsUserSet: data.captureModeIsUserSet.present
          ? data.captureModeIsUserSet.value
          : this.captureModeIsUserSet,
      duplicatePolicy: data.duplicatePolicy.present
          ? data.duplicatePolicy.value
          : this.duplicatePolicy,
      scope: data.scope.present ? data.scope.value : this.scope,
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
    return (StringBuffer('QueueTask(')
          ..write('id: $id, ')
          ..write('taskType: $taskType, ')
          ..write('collectionId: $collectionId, ')
          ..write('startUrl: $startUrl, ')
          ..write('entryLimit: $entryLimit, ')
          ..write('maxBytes: $maxBytes, ')
          ..write('captureMode: $captureMode, ')
          ..write('captureModeIsUserSet: $captureModeIsUserSet, ')
          ..write('duplicatePolicy: $duplicatePolicy, ')
          ..write('scope: $scope, ')
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
    taskType,
    collectionId,
    startUrl,
    entryLimit,
    maxBytes,
    captureMode,
    captureModeIsUserSet,
    duplicatePolicy,
    scope,
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
      (other is QueueTask &&
          other.id == this.id &&
          other.taskType == this.taskType &&
          other.collectionId == this.collectionId &&
          other.startUrl == this.startUrl &&
          other.entryLimit == this.entryLimit &&
          other.maxBytes == this.maxBytes &&
          other.captureMode == this.captureMode &&
          other.captureModeIsUserSet == this.captureModeIsUserSet &&
          other.duplicatePolicy == this.duplicatePolicy &&
          other.scope == this.scope &&
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

class QueueTasksCompanion extends UpdateCompanion<QueueTask> {
  final Value<String> id;
  final Value<String> taskType;
  final Value<String?> collectionId;
  final Value<String?> startUrl;
  final Value<int?> entryLimit;
  final Value<int?> maxBytes;
  final Value<String?> captureMode;
  final Value<bool> captureModeIsUserSet;
  final Value<String?> duplicatePolicy;
  final Value<String?> scope;
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
  const QueueTasksCompanion({
    this.id = const Value.absent(),
    this.taskType = const Value.absent(),
    this.collectionId = const Value.absent(),
    this.startUrl = const Value.absent(),
    this.entryLimit = const Value.absent(),
    this.maxBytes = const Value.absent(),
    this.captureMode = const Value.absent(),
    this.captureModeIsUserSet = const Value.absent(),
    this.duplicatePolicy = const Value.absent(),
    this.scope = const Value.absent(),
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
  QueueTasksCompanion.insert({
    required String id,
    required String taskType,
    this.collectionId = const Value.absent(),
    this.startUrl = const Value.absent(),
    this.entryLimit = const Value.absent(),
    this.maxBytes = const Value.absent(),
    this.captureMode = const Value.absent(),
    this.captureModeIsUserSet = const Value.absent(),
    this.duplicatePolicy = const Value.absent(),
    this.scope = const Value.absent(),
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
       taskType = Value(taskType),
       queuedAt = Value(queuedAt);
  static Insertable<QueueTask> custom({
    Expression<String>? id,
    Expression<String>? taskType,
    Expression<String>? collectionId,
    Expression<String>? startUrl,
    Expression<int>? entryLimit,
    Expression<int>? maxBytes,
    Expression<String>? captureMode,
    Expression<bool>? captureModeIsUserSet,
    Expression<String>? duplicatePolicy,
    Expression<String>? scope,
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
      if (taskType != null) 'task_type': taskType,
      if (collectionId != null) 'collection_id': collectionId,
      if (startUrl != null) 'start_url': startUrl,
      if (entryLimit != null) 'entry_limit': entryLimit,
      if (maxBytes != null) 'max_bytes': maxBytes,
      if (captureMode != null) 'capture_mode': captureMode,
      if (captureModeIsUserSet != null)
        'capture_mode_is_user_set': captureModeIsUserSet,
      if (duplicatePolicy != null) 'duplicate_policy': duplicatePolicy,
      if (scope != null) 'scope': scope,
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

  QueueTasksCompanion copyWith({
    Value<String>? id,
    Value<String>? taskType,
    Value<String?>? collectionId,
    Value<String?>? startUrl,
    Value<int?>? entryLimit,
    Value<int?>? maxBytes,
    Value<String?>? captureMode,
    Value<bool>? captureModeIsUserSet,
    Value<String?>? duplicatePolicy,
    Value<String?>? scope,
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
    return QueueTasksCompanion(
      id: id ?? this.id,
      taskType: taskType ?? this.taskType,
      collectionId: collectionId ?? this.collectionId,
      startUrl: startUrl ?? this.startUrl,
      entryLimit: entryLimit ?? this.entryLimit,
      maxBytes: maxBytes ?? this.maxBytes,
      captureMode: captureMode ?? this.captureMode,
      captureModeIsUserSet: captureModeIsUserSet ?? this.captureModeIsUserSet,
      duplicatePolicy: duplicatePolicy ?? this.duplicatePolicy,
      scope: scope ?? this.scope,
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
    if (taskType.present) {
      map['task_type'] = Variable<String>(taskType.value);
    }
    if (collectionId.present) {
      map['collection_id'] = Variable<String>(collectionId.value);
    }
    if (startUrl.present) {
      map['start_url'] = Variable<String>(startUrl.value);
    }
    if (entryLimit.present) {
      map['entry_limit'] = Variable<int>(entryLimit.value);
    }
    if (maxBytes.present) {
      map['max_bytes'] = Variable<int>(maxBytes.value);
    }
    if (captureMode.present) {
      map['capture_mode'] = Variable<String>(captureMode.value);
    }
    if (captureModeIsUserSet.present) {
      map['capture_mode_is_user_set'] = Variable<bool>(
        captureModeIsUserSet.value,
      );
    }
    if (duplicatePolicy.present) {
      map['duplicate_policy'] = Variable<String>(duplicatePolicy.value);
    }
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
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
    return (StringBuffer('QueueTasksCompanion(')
          ..write('id: $id, ')
          ..write('taskType: $taskType, ')
          ..write('collectionId: $collectionId, ')
          ..write('startUrl: $startUrl, ')
          ..write('entryLimit: $entryLimit, ')
          ..write('maxBytes: $maxBytes, ')
          ..write('captureMode: $captureMode, ')
          ..write('captureModeIsUserSet: $captureModeIsUserSet, ')
          ..write('duplicatePolicy: $duplicatePolicy, ')
          ..write('scope: $scope, ')
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

class $BrowsingHistoryTable extends BrowsingHistory
    with TableInfo<$BrowsingHistoryTable, BrowsingHistoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BrowsingHistoryTable(this.attachedDatabase, [this._alias]);
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
  static const String $name = 'browsing_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<BrowsingHistoryData> instance, {
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
  BrowsingHistoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BrowsingHistoryData(
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
  $BrowsingHistoryTable createAlias(String alias) {
    return $BrowsingHistoryTable(attachedDatabase, alias);
  }
}

class BrowsingHistoryData extends DataClass
    implements Insertable<BrowsingHistoryData> {
  final String id;
  final String url;

  /// Normalised [url]. Grouping, dedup-within-a-window and "remove every visit
  /// to this page" all key off this, never the raw text.
  final String urlKey;
  final String host;
  final String title;

  /// Where the visit came from. Persisted even though the UI only ever shows
  /// `manual`: a row that says how it got here is debuggable, and a filter is
  /// cheaper to widen than a lost column is to reconstruct.
  final String source;

  /// The address the load actually settled on, when a redirect moved it.
  final String? finalUrl;

  /// Only completed, user-visible destinations are recorded, so this is true for
  /// every row written today. Kept because "the load finished" is the property
  /// the recording rule turns on, and an explicit column is what makes that rule
  /// inspectable rather than implied by absence.
  final bool completed;
  final DateTime visitedAt;
  const BrowsingHistoryData({
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

  BrowsingHistoryCompanion toCompanion(bool nullToAbsent) {
    return BrowsingHistoryCompanion(
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

  factory BrowsingHistoryData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BrowsingHistoryData(
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

  BrowsingHistoryData copyWith({
    String? id,
    String? url,
    String? urlKey,
    String? host,
    String? title,
    String? source,
    Value<String?> finalUrl = const Value.absent(),
    bool? completed,
    DateTime? visitedAt,
  }) => BrowsingHistoryData(
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
  BrowsingHistoryData copyWithCompanion(BrowsingHistoryCompanion data) {
    return BrowsingHistoryData(
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
    return (StringBuffer('BrowsingHistoryData(')
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
      (other is BrowsingHistoryData &&
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

class BrowsingHistoryCompanion extends UpdateCompanion<BrowsingHistoryData> {
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
  const BrowsingHistoryCompanion({
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
  BrowsingHistoryCompanion.insert({
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
  static Insertable<BrowsingHistoryData> custom({
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

  BrowsingHistoryCompanion copyWith({
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
    return BrowsingHistoryCompanion(
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
    return (StringBuffer('BrowsingHistoryCompanion(')
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

class $SavedSitesTable extends SavedSites
    with TableInfo<$SavedSitesTable, SavedSite> {
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
    Insertable<SavedSite> instance, {
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
  SavedSite map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SavedSite(
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

class SavedSite extends DataClass implements Insertable<SavedSite> {
  final String id;
  final String url;

  /// Identity for duplicate detection. Two saved sites may share a host; they
  /// may not share a normalised URL.
  final String urlKey;
  final String host;
  final String title;

  /// What the user typed instead. Presentation only — [title] is kept so
  /// clearing a rename falls back to something real.
  final String? userTitle;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastOpenedAt;

  /// Hand-ordered position. Ties fall back to [createdAt], so a row that was
  /// never reordered still has a stable place.
  final int orderIndex;
  const SavedSite({
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

  factory SavedSite.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SavedSite(
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

  SavedSite copyWith({
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
  }) => SavedSite(
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
  SavedSite copyWithCompanion(SavedSitesCompanion data) {
    return SavedSite(
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
    return (StringBuffer('SavedSite(')
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
      (other is SavedSite &&
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

class SavedSitesCompanion extends UpdateCompanion<SavedSite> {
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
  static Insertable<SavedSite> custom({
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

class $FaviconCacheTable extends FaviconCache
    with TableInfo<$FaviconCacheTable, FaviconCacheData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FaviconCacheTable(this.attachedDatabase, [this._alias]);
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
  static const String $name = 'favicon_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<FaviconCacheData> instance, {
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
  FaviconCacheData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FaviconCacheData(
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
  $FaviconCacheTable createAlias(String alias) {
    return $FaviconCacheTable(attachedDatabase, alias);
  }
}

class FaviconCacheData extends DataClass
    implements Insertable<FaviconCacheData> {
  final String host;

  /// The icon bytes, or null when the last attempt failed. A null row is a
  /// *negative* cache entry — it stops every list rebuild from re-requesting an
  /// icon the site does not have.
  final Uint8List? bytes;
  final String? sourceUrl;
  final DateTime fetchedAt;
  const FaviconCacheData({
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

  FaviconCacheCompanion toCompanion(bool nullToAbsent) {
    return FaviconCacheCompanion(
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

  factory FaviconCacheData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FaviconCacheData(
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

  FaviconCacheData copyWith({
    String? host,
    Value<Uint8List?> bytes = const Value.absent(),
    Value<String?> sourceUrl = const Value.absent(),
    DateTime? fetchedAt,
  }) => FaviconCacheData(
    host: host ?? this.host,
    bytes: bytes.present ? bytes.value : this.bytes,
    sourceUrl: sourceUrl.present ? sourceUrl.value : this.sourceUrl,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  FaviconCacheData copyWithCompanion(FaviconCacheCompanion data) {
    return FaviconCacheData(
      host: data.host.present ? data.host.value : this.host,
      bytes: data.bytes.present ? data.bytes.value : this.bytes,
      sourceUrl: data.sourceUrl.present ? data.sourceUrl.value : this.sourceUrl,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FaviconCacheData(')
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
      (other is FaviconCacheData &&
          other.host == this.host &&
          $driftBlobEquality.equals(other.bytes, this.bytes) &&
          other.sourceUrl == this.sourceUrl &&
          other.fetchedAt == this.fetchedAt);
}

class FaviconCacheCompanion extends UpdateCompanion<FaviconCacheData> {
  final Value<String> host;
  final Value<Uint8List?> bytes;
  final Value<String?> sourceUrl;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const FaviconCacheCompanion({
    this.host = const Value.absent(),
    this.bytes = const Value.absent(),
    this.sourceUrl = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FaviconCacheCompanion.insert({
    required String host,
    this.bytes = const Value.absent(),
    this.sourceUrl = const Value.absent(),
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  }) : host = Value(host),
       fetchedAt = Value(fetchedAt);
  static Insertable<FaviconCacheData> custom({
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

  FaviconCacheCompanion copyWith({
    Value<String>? host,
    Value<Uint8List?>? bytes,
    Value<String?>? sourceUrl,
    Value<DateTime>? fetchedAt,
    Value<int>? rowid,
  }) {
    return FaviconCacheCompanion(
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
    return (StringBuffer('FaviconCacheCompanion(')
          ..write('host: $host, ')
          ..write('bytes: $bytes, ')
          ..write('sourceUrl: $sourceUrl, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CollectionsTable collections = $CollectionsTable(this);
  late final $EntriesTable entries = $EntriesTable(this);
  late final $SaveRunsTable saveRuns = $SaveRunsTable(this);
  late final $UserPageHintsTable userPageHints = $UserPageHintsTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final $QueueTasksTable queueTasks = $QueueTasksTable(this);
  late final $BrowsingHistoryTable browsingHistory = $BrowsingHistoryTable(
    this,
  );
  late final $SavedSitesTable savedSites = $SavedSitesTable(this);
  late final $FaviconCacheTable faviconCache = $FaviconCacheTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    collections,
    entries,
    saveRuns,
    userPageHints,
    settings,
    queueTasks,
    browsingHistory,
    savedSites,
    faviconCache,
  ];
}

typedef $$CollectionsTableCreateCompanionBuilder =
    CollectionsCompanion Function({
      required String id,
      required String title,
      Value<String?> userTitle,
      required String sourceUrl,
      required String host,
      Value<String?> collectionKey,
      Value<String?> collectionIndexUrl,
      Value<String?> identityBasis,
      Value<String?> identityConfidence,
      Value<String> contentKind,
      Value<String> sequenceKind,
      Value<String> orderingBasis,
      Value<String> shapeConfidence,
      Value<int?> knownEntryTotal,
      required DateTime createdAt,
      Value<DateTime?> lastOpenedAt,
      Value<DateTime?> lastSavedAt,
      Value<String?> lastOpenedEntryId,
      Value<String?> lastCompletedEntryId,
      Value<DateTime?> lastReadAt,
      Value<DateTime?> lastCheckAt,
      Value<DateTime?> lastCheckSuccessAt,
      Value<String?> lastCheckError,
      Value<String?> lastCheckResult,
      Value<String> lifecycle,
      Value<DateTime?> archivedAt,
      Value<String?> cleanupPreference,
      Value<String?> preferredCaptureMode,
      Value<int> rowid,
    });
typedef $$CollectionsTableUpdateCompanionBuilder =
    CollectionsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String?> userTitle,
      Value<String> sourceUrl,
      Value<String> host,
      Value<String?> collectionKey,
      Value<String?> collectionIndexUrl,
      Value<String?> identityBasis,
      Value<String?> identityConfidence,
      Value<String> contentKind,
      Value<String> sequenceKind,
      Value<String> orderingBasis,
      Value<String> shapeConfidence,
      Value<int?> knownEntryTotal,
      Value<DateTime> createdAt,
      Value<DateTime?> lastOpenedAt,
      Value<DateTime?> lastSavedAt,
      Value<String?> lastOpenedEntryId,
      Value<String?> lastCompletedEntryId,
      Value<DateTime?> lastReadAt,
      Value<DateTime?> lastCheckAt,
      Value<DateTime?> lastCheckSuccessAt,
      Value<String?> lastCheckError,
      Value<String?> lastCheckResult,
      Value<String> lifecycle,
      Value<DateTime?> archivedAt,
      Value<String?> cleanupPreference,
      Value<String?> preferredCaptureMode,
      Value<int> rowid,
    });

final class $$CollectionsTableReferences
    extends BaseReferences<_$AppDatabase, $CollectionsTable, Collection> {
  $$CollectionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$EntriesTable, List<Entry>> _entriesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.entries,
    aliasName: 'collections__id__entries__collection_id',
  );

  $$EntriesTableProcessedTableManager get entriesRefs {
    final manager = $$EntriesTableTableManager(
      $_db,
      $_db.entries,
    ).filter((f) => f.collectionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_entriesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CollectionsTableFilterComposer
    extends Composer<_$AppDatabase, $CollectionsTable> {
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

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userTitle => $composableBuilder(
    column: $table.userTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceUrl => $composableBuilder(
    column: $table.sourceUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get collectionKey => $composableBuilder(
    column: $table.collectionKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get collectionIndexUrl => $composableBuilder(
    column: $table.collectionIndexUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get identityBasis => $composableBuilder(
    column: $table.identityBasis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get identityConfidence => $composableBuilder(
    column: $table.identityConfidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentKind => $composableBuilder(
    column: $table.contentKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sequenceKind => $composableBuilder(
    column: $table.sequenceKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get orderingBasis => $composableBuilder(
    column: $table.orderingBasis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get shapeConfidence => $composableBuilder(
    column: $table.shapeConfidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get knownEntryTotal => $composableBuilder(
    column: $table.knownEntryTotal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastOpenedAt => $composableBuilder(
    column: $table.lastOpenedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSavedAt => $composableBuilder(
    column: $table.lastSavedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastOpenedEntryId => $composableBuilder(
    column: $table.lastOpenedEntryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastCompletedEntryId => $composableBuilder(
    column: $table.lastCompletedEntryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastCheckAt => $composableBuilder(
    column: $table.lastCheckAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastCheckSuccessAt => $composableBuilder(
    column: $table.lastCheckSuccessAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastCheckError => $composableBuilder(
    column: $table.lastCheckError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastCheckResult => $composableBuilder(
    column: $table.lastCheckResult,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lifecycle => $composableBuilder(
    column: $table.lifecycle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cleanupPreference => $composableBuilder(
    column: $table.cleanupPreference,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get preferredCaptureMode => $composableBuilder(
    column: $table.preferredCaptureMode,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> entriesRefs(
    Expression<bool> Function($$EntriesTableFilterComposer f) f,
  ) {
    final $$EntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.entries,
      getReferencedColumn: (t) => t.collectionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EntriesTableFilterComposer(
            $db: $db,
            $table: $db.entries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CollectionsTableOrderingComposer
    extends Composer<_$AppDatabase, $CollectionsTable> {
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

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userTitle => $composableBuilder(
    column: $table.userTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceUrl => $composableBuilder(
    column: $table.sourceUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get collectionKey => $composableBuilder(
    column: $table.collectionKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get collectionIndexUrl => $composableBuilder(
    column: $table.collectionIndexUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get identityBasis => $composableBuilder(
    column: $table.identityBasis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get identityConfidence => $composableBuilder(
    column: $table.identityConfidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentKind => $composableBuilder(
    column: $table.contentKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sequenceKind => $composableBuilder(
    column: $table.sequenceKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get orderingBasis => $composableBuilder(
    column: $table.orderingBasis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get shapeConfidence => $composableBuilder(
    column: $table.shapeConfidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get knownEntryTotal => $composableBuilder(
    column: $table.knownEntryTotal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastOpenedAt => $composableBuilder(
    column: $table.lastOpenedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSavedAt => $composableBuilder(
    column: $table.lastSavedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastOpenedEntryId => $composableBuilder(
    column: $table.lastOpenedEntryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastCompletedEntryId => $composableBuilder(
    column: $table.lastCompletedEntryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastCheckAt => $composableBuilder(
    column: $table.lastCheckAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastCheckSuccessAt => $composableBuilder(
    column: $table.lastCheckSuccessAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastCheckError => $composableBuilder(
    column: $table.lastCheckError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastCheckResult => $composableBuilder(
    column: $table.lastCheckResult,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lifecycle => $composableBuilder(
    column: $table.lifecycle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cleanupPreference => $composableBuilder(
    column: $table.cleanupPreference,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get preferredCaptureMode => $composableBuilder(
    column: $table.preferredCaptureMode,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CollectionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CollectionsTable> {
  $$CollectionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get userTitle =>
      $composableBuilder(column: $table.userTitle, builder: (column) => column);

  GeneratedColumn<String> get sourceUrl =>
      $composableBuilder(column: $table.sourceUrl, builder: (column) => column);

  GeneratedColumn<String> get host =>
      $composableBuilder(column: $table.host, builder: (column) => column);

  GeneratedColumn<String> get collectionKey => $composableBuilder(
    column: $table.collectionKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get collectionIndexUrl => $composableBuilder(
    column: $table.collectionIndexUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get identityBasis => $composableBuilder(
    column: $table.identityBasis,
    builder: (column) => column,
  );

  GeneratedColumn<String> get identityConfidence => $composableBuilder(
    column: $table.identityConfidence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contentKind => $composableBuilder(
    column: $table.contentKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sequenceKind => $composableBuilder(
    column: $table.sequenceKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get orderingBasis => $composableBuilder(
    column: $table.orderingBasis,
    builder: (column) => column,
  );

  GeneratedColumn<String> get shapeConfidence => $composableBuilder(
    column: $table.shapeConfidence,
    builder: (column) => column,
  );

  GeneratedColumn<int> get knownEntryTotal => $composableBuilder(
    column: $table.knownEntryTotal,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastOpenedAt => $composableBuilder(
    column: $table.lastOpenedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastSavedAt => $composableBuilder(
    column: $table.lastSavedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastOpenedEntryId => $composableBuilder(
    column: $table.lastOpenedEntryId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastCompletedEntryId => $composableBuilder(
    column: $table.lastCompletedEntryId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastCheckAt => $composableBuilder(
    column: $table.lastCheckAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastCheckSuccessAt => $composableBuilder(
    column: $table.lastCheckSuccessAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastCheckError => $composableBuilder(
    column: $table.lastCheckError,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastCheckResult => $composableBuilder(
    column: $table.lastCheckResult,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lifecycle =>
      $composableBuilder(column: $table.lifecycle, builder: (column) => column);

  GeneratedColumn<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cleanupPreference => $composableBuilder(
    column: $table.cleanupPreference,
    builder: (column) => column,
  );

  GeneratedColumn<String> get preferredCaptureMode => $composableBuilder(
    column: $table.preferredCaptureMode,
    builder: (column) => column,
  );

  Expression<T> entriesRefs<T extends Object>(
    Expression<T> Function($$EntriesTableAnnotationComposer a) f,
  ) {
    final $$EntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.entries,
      getReferencedColumn: (t) => t.collectionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.entries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CollectionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CollectionsTable,
          Collection,
          $$CollectionsTableFilterComposer,
          $$CollectionsTableOrderingComposer,
          $$CollectionsTableAnnotationComposer,
          $$CollectionsTableCreateCompanionBuilder,
          $$CollectionsTableUpdateCompanionBuilder,
          (Collection, $$CollectionsTableReferences),
          Collection,
          PrefetchHooks Function({bool entriesRefs})
        > {
  $$CollectionsTableTableManager(_$AppDatabase db, $CollectionsTable table)
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
                Value<String> title = const Value.absent(),
                Value<String?> userTitle = const Value.absent(),
                Value<String> sourceUrl = const Value.absent(),
                Value<String> host = const Value.absent(),
                Value<String?> collectionKey = const Value.absent(),
                Value<String?> collectionIndexUrl = const Value.absent(),
                Value<String?> identityBasis = const Value.absent(),
                Value<String?> identityConfidence = const Value.absent(),
                Value<String> contentKind = const Value.absent(),
                Value<String> sequenceKind = const Value.absent(),
                Value<String> orderingBasis = const Value.absent(),
                Value<String> shapeConfidence = const Value.absent(),
                Value<int?> knownEntryTotal = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> lastOpenedAt = const Value.absent(),
                Value<DateTime?> lastSavedAt = const Value.absent(),
                Value<String?> lastOpenedEntryId = const Value.absent(),
                Value<String?> lastCompletedEntryId = const Value.absent(),
                Value<DateTime?> lastReadAt = const Value.absent(),
                Value<DateTime?> lastCheckAt = const Value.absent(),
                Value<DateTime?> lastCheckSuccessAt = const Value.absent(),
                Value<String?> lastCheckError = const Value.absent(),
                Value<String?> lastCheckResult = const Value.absent(),
                Value<String> lifecycle = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<String?> cleanupPreference = const Value.absent(),
                Value<String?> preferredCaptureMode = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CollectionsCompanion(
                id: id,
                title: title,
                userTitle: userTitle,
                sourceUrl: sourceUrl,
                host: host,
                collectionKey: collectionKey,
                collectionIndexUrl: collectionIndexUrl,
                identityBasis: identityBasis,
                identityConfidence: identityConfidence,
                contentKind: contentKind,
                sequenceKind: sequenceKind,
                orderingBasis: orderingBasis,
                shapeConfidence: shapeConfidence,
                knownEntryTotal: knownEntryTotal,
                createdAt: createdAt,
                lastOpenedAt: lastOpenedAt,
                lastSavedAt: lastSavedAt,
                lastOpenedEntryId: lastOpenedEntryId,
                lastCompletedEntryId: lastCompletedEntryId,
                lastReadAt: lastReadAt,
                lastCheckAt: lastCheckAt,
                lastCheckSuccessAt: lastCheckSuccessAt,
                lastCheckError: lastCheckError,
                lastCheckResult: lastCheckResult,
                lifecycle: lifecycle,
                archivedAt: archivedAt,
                cleanupPreference: cleanupPreference,
                preferredCaptureMode: preferredCaptureMode,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                Value<String?> userTitle = const Value.absent(),
                required String sourceUrl,
                required String host,
                Value<String?> collectionKey = const Value.absent(),
                Value<String?> collectionIndexUrl = const Value.absent(),
                Value<String?> identityBasis = const Value.absent(),
                Value<String?> identityConfidence = const Value.absent(),
                Value<String> contentKind = const Value.absent(),
                Value<String> sequenceKind = const Value.absent(),
                Value<String> orderingBasis = const Value.absent(),
                Value<String> shapeConfidence = const Value.absent(),
                Value<int?> knownEntryTotal = const Value.absent(),
                required DateTime createdAt,
                Value<DateTime?> lastOpenedAt = const Value.absent(),
                Value<DateTime?> lastSavedAt = const Value.absent(),
                Value<String?> lastOpenedEntryId = const Value.absent(),
                Value<String?> lastCompletedEntryId = const Value.absent(),
                Value<DateTime?> lastReadAt = const Value.absent(),
                Value<DateTime?> lastCheckAt = const Value.absent(),
                Value<DateTime?> lastCheckSuccessAt = const Value.absent(),
                Value<String?> lastCheckError = const Value.absent(),
                Value<String?> lastCheckResult = const Value.absent(),
                Value<String> lifecycle = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<String?> cleanupPreference = const Value.absent(),
                Value<String?> preferredCaptureMode = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CollectionsCompanion.insert(
                id: id,
                title: title,
                userTitle: userTitle,
                sourceUrl: sourceUrl,
                host: host,
                collectionKey: collectionKey,
                collectionIndexUrl: collectionIndexUrl,
                identityBasis: identityBasis,
                identityConfidence: identityConfidence,
                contentKind: contentKind,
                sequenceKind: sequenceKind,
                orderingBasis: orderingBasis,
                shapeConfidence: shapeConfidence,
                knownEntryTotal: knownEntryTotal,
                createdAt: createdAt,
                lastOpenedAt: lastOpenedAt,
                lastSavedAt: lastSavedAt,
                lastOpenedEntryId: lastOpenedEntryId,
                lastCompletedEntryId: lastCompletedEntryId,
                lastReadAt: lastReadAt,
                lastCheckAt: lastCheckAt,
                lastCheckSuccessAt: lastCheckSuccessAt,
                lastCheckError: lastCheckError,
                lastCheckResult: lastCheckResult,
                lifecycle: lifecycle,
                archivedAt: archivedAt,
                cleanupPreference: cleanupPreference,
                preferredCaptureMode: preferredCaptureMode,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CollectionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({entriesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (entriesRefs) db.entries],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (entriesRefs)
                    await $_getPrefetchedData<
                      Collection,
                      $CollectionsTable,
                      Entry
                    >(
                      currentTable: table,
                      referencedTable: $$CollectionsTableReferences
                          ._entriesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$CollectionsTableReferences(
                            db,
                            table,
                            p0,
                          ).entriesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.collectionId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$CollectionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CollectionsTable,
      Collection,
      $$CollectionsTableFilterComposer,
      $$CollectionsTableOrderingComposer,
      $$CollectionsTableAnnotationComposer,
      $$CollectionsTableCreateCompanionBuilder,
      $$CollectionsTableUpdateCompanionBuilder,
      (Collection, $$CollectionsTableReferences),
      Collection,
      PrefetchHooks Function({bool entriesRefs})
    >;
typedef $$EntriesTableCreateCompanionBuilder =
    EntriesCompanion Function({
      required String id,
      Value<String?> collectionId,
      required String title,
      required String sourceUrl,
      required String urlKey,
      Value<String?> canonicalUrl,
      Value<String> host,
      Value<String?> sourceTitle,
      Value<DateTime?> publishedAt,
      Value<String> contentKind,
      Value<String> contentKindConfidence,
      Value<bool> contentKindIsUserSet,
      Value<String> artifactFormat,
      Value<String?> captureMode,
      required String saveStatus,
      Value<String?> contentPath,
      Value<DateTime?> savedAt,
      Value<int> detectedAssetCount,
      Value<int> storedAssetCount,
      Value<String?> nextSourceUrl,
      Value<int> entryOrder,
      Value<String?> saveError,
      Value<int> byteSize,
      Value<double?> entryNumber,
      Value<String?> sourceMarker,
      Value<String> readStatus,
      Value<double> progressFraction,
      Value<int> progressPageIndex,
      Value<double> progressOffsetInPage,
      Value<DateTime?> firstOpenedAt,
      Value<DateTime?> lastReadAt,
      Value<DateTime?> completedAt,
      Value<DateTime?> progressUpdatedAt,
      Value<DateTime?> discoveredAt,
      Value<String?> discoveryBasis,
      Value<String?> discoveryConfidence,
      Value<DateTime?> offlineRemovedAt,
      Value<int> rowid,
    });
typedef $$EntriesTableUpdateCompanionBuilder =
    EntriesCompanion Function({
      Value<String> id,
      Value<String?> collectionId,
      Value<String> title,
      Value<String> sourceUrl,
      Value<String> urlKey,
      Value<String?> canonicalUrl,
      Value<String> host,
      Value<String?> sourceTitle,
      Value<DateTime?> publishedAt,
      Value<String> contentKind,
      Value<String> contentKindConfidence,
      Value<bool> contentKindIsUserSet,
      Value<String> artifactFormat,
      Value<String?> captureMode,
      Value<String> saveStatus,
      Value<String?> contentPath,
      Value<DateTime?> savedAt,
      Value<int> detectedAssetCount,
      Value<int> storedAssetCount,
      Value<String?> nextSourceUrl,
      Value<int> entryOrder,
      Value<String?> saveError,
      Value<int> byteSize,
      Value<double?> entryNumber,
      Value<String?> sourceMarker,
      Value<String> readStatus,
      Value<double> progressFraction,
      Value<int> progressPageIndex,
      Value<double> progressOffsetInPage,
      Value<DateTime?> firstOpenedAt,
      Value<DateTime?> lastReadAt,
      Value<DateTime?> completedAt,
      Value<DateTime?> progressUpdatedAt,
      Value<DateTime?> discoveredAt,
      Value<String?> discoveryBasis,
      Value<String?> discoveryConfidence,
      Value<DateTime?> offlineRemovedAt,
      Value<int> rowid,
    });

final class $$EntriesTableReferences
    extends BaseReferences<_$AppDatabase, $EntriesTable, Entry> {
  $$EntriesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CollectionsTable _collectionIdTable(_$AppDatabase db) =>
      db.collections.createAlias('entries__collection_id__collections__id');

  $$CollectionsTableProcessedTableManager? get collectionId {
    final $_column = $_itemColumn<String>('collection_id');
    if ($_column == null) return null;
    final manager = $$CollectionsTableTableManager(
      $_db,
      $_db.collections,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_collectionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$EntriesTableFilterComposer
    extends Composer<_$AppDatabase, $EntriesTable> {
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

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceUrl => $composableBuilder(
    column: $table.sourceUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get urlKey => $composableBuilder(
    column: $table.urlKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get canonicalUrl => $composableBuilder(
    column: $table.canonicalUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceTitle => $composableBuilder(
    column: $table.sourceTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get publishedAt => $composableBuilder(
    column: $table.publishedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentKind => $composableBuilder(
    column: $table.contentKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentKindConfidence => $composableBuilder(
    column: $table.contentKindConfidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get contentKindIsUserSet => $composableBuilder(
    column: $table.contentKindIsUserSet,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artifactFormat => $composableBuilder(
    column: $table.artifactFormat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get captureMode => $composableBuilder(
    column: $table.captureMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get saveStatus => $composableBuilder(
    column: $table.saveStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentPath => $composableBuilder(
    column: $table.contentPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get savedAt => $composableBuilder(
    column: $table.savedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get detectedAssetCount => $composableBuilder(
    column: $table.detectedAssetCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get storedAssetCount => $composableBuilder(
    column: $table.storedAssetCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nextSourceUrl => $composableBuilder(
    column: $table.nextSourceUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get entryOrder => $composableBuilder(
    column: $table.entryOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get saveError => $composableBuilder(
    column: $table.saveError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get entryNumber => $composableBuilder(
    column: $table.entryNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceMarker => $composableBuilder(
    column: $table.sourceMarker,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get readStatus => $composableBuilder(
    column: $table.readStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get progressFraction => $composableBuilder(
    column: $table.progressFraction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get progressPageIndex => $composableBuilder(
    column: $table.progressPageIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get progressOffsetInPage => $composableBuilder(
    column: $table.progressOffsetInPage,
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

  ColumnFilters<DateTime> get progressUpdatedAt => $composableBuilder(
    column: $table.progressUpdatedAt,
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

  ColumnFilters<String> get discoveryConfidence => $composableBuilder(
    column: $table.discoveryConfidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get offlineRemovedAt => $composableBuilder(
    column: $table.offlineRemovedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$CollectionsTableFilterComposer get collectionId {
    final $$CollectionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableFilterComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $EntriesTable> {
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

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceUrl => $composableBuilder(
    column: $table.sourceUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get urlKey => $composableBuilder(
    column: $table.urlKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get canonicalUrl => $composableBuilder(
    column: $table.canonicalUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceTitle => $composableBuilder(
    column: $table.sourceTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get publishedAt => $composableBuilder(
    column: $table.publishedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentKind => $composableBuilder(
    column: $table.contentKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentKindConfidence => $composableBuilder(
    column: $table.contentKindConfidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get contentKindIsUserSet => $composableBuilder(
    column: $table.contentKindIsUserSet,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artifactFormat => $composableBuilder(
    column: $table.artifactFormat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get captureMode => $composableBuilder(
    column: $table.captureMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get saveStatus => $composableBuilder(
    column: $table.saveStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentPath => $composableBuilder(
    column: $table.contentPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get savedAt => $composableBuilder(
    column: $table.savedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get detectedAssetCount => $composableBuilder(
    column: $table.detectedAssetCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get storedAssetCount => $composableBuilder(
    column: $table.storedAssetCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nextSourceUrl => $composableBuilder(
    column: $table.nextSourceUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get entryOrder => $composableBuilder(
    column: $table.entryOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get saveError => $composableBuilder(
    column: $table.saveError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get entryNumber => $composableBuilder(
    column: $table.entryNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceMarker => $composableBuilder(
    column: $table.sourceMarker,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get readStatus => $composableBuilder(
    column: $table.readStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get progressFraction => $composableBuilder(
    column: $table.progressFraction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get progressPageIndex => $composableBuilder(
    column: $table.progressPageIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get progressOffsetInPage => $composableBuilder(
    column: $table.progressOffsetInPage,
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

  ColumnOrderings<DateTime> get progressUpdatedAt => $composableBuilder(
    column: $table.progressUpdatedAt,
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

  ColumnOrderings<String> get discoveryConfidence => $composableBuilder(
    column: $table.discoveryConfidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get offlineRemovedAt => $composableBuilder(
    column: $table.offlineRemovedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$CollectionsTableOrderingComposer get collectionId {
    final $$CollectionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableOrderingComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $EntriesTable> {
  $$EntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get sourceUrl =>
      $composableBuilder(column: $table.sourceUrl, builder: (column) => column);

  GeneratedColumn<String> get urlKey =>
      $composableBuilder(column: $table.urlKey, builder: (column) => column);

  GeneratedColumn<String> get canonicalUrl => $composableBuilder(
    column: $table.canonicalUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get host =>
      $composableBuilder(column: $table.host, builder: (column) => column);

  GeneratedColumn<String> get sourceTitle => $composableBuilder(
    column: $table.sourceTitle,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get publishedAt => $composableBuilder(
    column: $table.publishedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contentKind => $composableBuilder(
    column: $table.contentKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contentKindConfidence => $composableBuilder(
    column: $table.contentKindConfidence,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get contentKindIsUserSet => $composableBuilder(
    column: $table.contentKindIsUserSet,
    builder: (column) => column,
  );

  GeneratedColumn<String> get artifactFormat => $composableBuilder(
    column: $table.artifactFormat,
    builder: (column) => column,
  );

  GeneratedColumn<String> get captureMode => $composableBuilder(
    column: $table.captureMode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get saveStatus => $composableBuilder(
    column: $table.saveStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contentPath => $composableBuilder(
    column: $table.contentPath,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get savedAt =>
      $composableBuilder(column: $table.savedAt, builder: (column) => column);

  GeneratedColumn<int> get detectedAssetCount => $composableBuilder(
    column: $table.detectedAssetCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get storedAssetCount => $composableBuilder(
    column: $table.storedAssetCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nextSourceUrl => $composableBuilder(
    column: $table.nextSourceUrl,
    builder: (column) => column,
  );

  GeneratedColumn<int> get entryOrder => $composableBuilder(
    column: $table.entryOrder,
    builder: (column) => column,
  );

  GeneratedColumn<String> get saveError =>
      $composableBuilder(column: $table.saveError, builder: (column) => column);

  GeneratedColumn<int> get byteSize =>
      $composableBuilder(column: $table.byteSize, builder: (column) => column);

  GeneratedColumn<double> get entryNumber => $composableBuilder(
    column: $table.entryNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceMarker => $composableBuilder(
    column: $table.sourceMarker,
    builder: (column) => column,
  );

  GeneratedColumn<String> get readStatus => $composableBuilder(
    column: $table.readStatus,
    builder: (column) => column,
  );

  GeneratedColumn<double> get progressFraction => $composableBuilder(
    column: $table.progressFraction,
    builder: (column) => column,
  );

  GeneratedColumn<int> get progressPageIndex => $composableBuilder(
    column: $table.progressPageIndex,
    builder: (column) => column,
  );

  GeneratedColumn<double> get progressOffsetInPage => $composableBuilder(
    column: $table.progressOffsetInPage,
    builder: (column) => column,
  );

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

  GeneratedColumn<DateTime> get progressUpdatedAt => $composableBuilder(
    column: $table.progressUpdatedAt,
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

  GeneratedColumn<String> get discoveryConfidence => $composableBuilder(
    column: $table.discoveryConfidence,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get offlineRemovedAt => $composableBuilder(
    column: $table.offlineRemovedAt,
    builder: (column) => column,
  );

  $$CollectionsTableAnnotationComposer get collectionId {
    final $$CollectionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableAnnotationComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EntriesTable,
          Entry,
          $$EntriesTableFilterComposer,
          $$EntriesTableOrderingComposer,
          $$EntriesTableAnnotationComposer,
          $$EntriesTableCreateCompanionBuilder,
          $$EntriesTableUpdateCompanionBuilder,
          (Entry, $$EntriesTableReferences),
          Entry,
          PrefetchHooks Function({bool collectionId})
        > {
  $$EntriesTableTableManager(_$AppDatabase db, $EntriesTable table)
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
                Value<String?> collectionId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> sourceUrl = const Value.absent(),
                Value<String> urlKey = const Value.absent(),
                Value<String?> canonicalUrl = const Value.absent(),
                Value<String> host = const Value.absent(),
                Value<String?> sourceTitle = const Value.absent(),
                Value<DateTime?> publishedAt = const Value.absent(),
                Value<String> contentKind = const Value.absent(),
                Value<String> contentKindConfidence = const Value.absent(),
                Value<bool> contentKindIsUserSet = const Value.absent(),
                Value<String> artifactFormat = const Value.absent(),
                Value<String?> captureMode = const Value.absent(),
                Value<String> saveStatus = const Value.absent(),
                Value<String?> contentPath = const Value.absent(),
                Value<DateTime?> savedAt = const Value.absent(),
                Value<int> detectedAssetCount = const Value.absent(),
                Value<int> storedAssetCount = const Value.absent(),
                Value<String?> nextSourceUrl = const Value.absent(),
                Value<int> entryOrder = const Value.absent(),
                Value<String?> saveError = const Value.absent(),
                Value<int> byteSize = const Value.absent(),
                Value<double?> entryNumber = const Value.absent(),
                Value<String?> sourceMarker = const Value.absent(),
                Value<String> readStatus = const Value.absent(),
                Value<double> progressFraction = const Value.absent(),
                Value<int> progressPageIndex = const Value.absent(),
                Value<double> progressOffsetInPage = const Value.absent(),
                Value<DateTime?> firstOpenedAt = const Value.absent(),
                Value<DateTime?> lastReadAt = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<DateTime?> progressUpdatedAt = const Value.absent(),
                Value<DateTime?> discoveredAt = const Value.absent(),
                Value<String?> discoveryBasis = const Value.absent(),
                Value<String?> discoveryConfidence = const Value.absent(),
                Value<DateTime?> offlineRemovedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EntriesCompanion(
                id: id,
                collectionId: collectionId,
                title: title,
                sourceUrl: sourceUrl,
                urlKey: urlKey,
                canonicalUrl: canonicalUrl,
                host: host,
                sourceTitle: sourceTitle,
                publishedAt: publishedAt,
                contentKind: contentKind,
                contentKindConfidence: contentKindConfidence,
                contentKindIsUserSet: contentKindIsUserSet,
                artifactFormat: artifactFormat,
                captureMode: captureMode,
                saveStatus: saveStatus,
                contentPath: contentPath,
                savedAt: savedAt,
                detectedAssetCount: detectedAssetCount,
                storedAssetCount: storedAssetCount,
                nextSourceUrl: nextSourceUrl,
                entryOrder: entryOrder,
                saveError: saveError,
                byteSize: byteSize,
                entryNumber: entryNumber,
                sourceMarker: sourceMarker,
                readStatus: readStatus,
                progressFraction: progressFraction,
                progressPageIndex: progressPageIndex,
                progressOffsetInPage: progressOffsetInPage,
                firstOpenedAt: firstOpenedAt,
                lastReadAt: lastReadAt,
                completedAt: completedAt,
                progressUpdatedAt: progressUpdatedAt,
                discoveredAt: discoveredAt,
                discoveryBasis: discoveryBasis,
                discoveryConfidence: discoveryConfidence,
                offlineRemovedAt: offlineRemovedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> collectionId = const Value.absent(),
                required String title,
                required String sourceUrl,
                required String urlKey,
                Value<String?> canonicalUrl = const Value.absent(),
                Value<String> host = const Value.absent(),
                Value<String?> sourceTitle = const Value.absent(),
                Value<DateTime?> publishedAt = const Value.absent(),
                Value<String> contentKind = const Value.absent(),
                Value<String> contentKindConfidence = const Value.absent(),
                Value<bool> contentKindIsUserSet = const Value.absent(),
                Value<String> artifactFormat = const Value.absent(),
                Value<String?> captureMode = const Value.absent(),
                required String saveStatus,
                Value<String?> contentPath = const Value.absent(),
                Value<DateTime?> savedAt = const Value.absent(),
                Value<int> detectedAssetCount = const Value.absent(),
                Value<int> storedAssetCount = const Value.absent(),
                Value<String?> nextSourceUrl = const Value.absent(),
                Value<int> entryOrder = const Value.absent(),
                Value<String?> saveError = const Value.absent(),
                Value<int> byteSize = const Value.absent(),
                Value<double?> entryNumber = const Value.absent(),
                Value<String?> sourceMarker = const Value.absent(),
                Value<String> readStatus = const Value.absent(),
                Value<double> progressFraction = const Value.absent(),
                Value<int> progressPageIndex = const Value.absent(),
                Value<double> progressOffsetInPage = const Value.absent(),
                Value<DateTime?> firstOpenedAt = const Value.absent(),
                Value<DateTime?> lastReadAt = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<DateTime?> progressUpdatedAt = const Value.absent(),
                Value<DateTime?> discoveredAt = const Value.absent(),
                Value<String?> discoveryBasis = const Value.absent(),
                Value<String?> discoveryConfidence = const Value.absent(),
                Value<DateTime?> offlineRemovedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EntriesCompanion.insert(
                id: id,
                collectionId: collectionId,
                title: title,
                sourceUrl: sourceUrl,
                urlKey: urlKey,
                canonicalUrl: canonicalUrl,
                host: host,
                sourceTitle: sourceTitle,
                publishedAt: publishedAt,
                contentKind: contentKind,
                contentKindConfidence: contentKindConfidence,
                contentKindIsUserSet: contentKindIsUserSet,
                artifactFormat: artifactFormat,
                captureMode: captureMode,
                saveStatus: saveStatus,
                contentPath: contentPath,
                savedAt: savedAt,
                detectedAssetCount: detectedAssetCount,
                storedAssetCount: storedAssetCount,
                nextSourceUrl: nextSourceUrl,
                entryOrder: entryOrder,
                saveError: saveError,
                byteSize: byteSize,
                entryNumber: entryNumber,
                sourceMarker: sourceMarker,
                readStatus: readStatus,
                progressFraction: progressFraction,
                progressPageIndex: progressPageIndex,
                progressOffsetInPage: progressOffsetInPage,
                firstOpenedAt: firstOpenedAt,
                lastReadAt: lastReadAt,
                completedAt: completedAt,
                progressUpdatedAt: progressUpdatedAt,
                discoveredAt: discoveredAt,
                discoveryBasis: discoveryBasis,
                discoveryConfidence: discoveryConfidence,
                offlineRemovedAt: offlineRemovedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$EntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({collectionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (collectionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.collectionId,
                                referencedTable: $$EntriesTableReferences
                                    ._collectionIdTable(db),
                                referencedColumn: $$EntriesTableReferences
                                    ._collectionIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$EntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EntriesTable,
      Entry,
      $$EntriesTableFilterComposer,
      $$EntriesTableOrderingComposer,
      $$EntriesTableAnnotationComposer,
      $$EntriesTableCreateCompanionBuilder,
      $$EntriesTableUpdateCompanionBuilder,
      (Entry, $$EntriesTableReferences),
      Entry,
      PrefetchHooks Function({bool collectionId})
    >;
typedef $$SaveRunsTableCreateCompanionBuilder =
    SaveRunsCompanion Function({
      required String id,
      Value<String?> collectionId,
      required String startUrl,
      Value<String?> currentUrl,
      required int requestedEntries,
      Value<int> completedEntries,
      required String state,
      Value<String?> lastError,
      Value<String?> stopReason,
      Value<String> visitedUrls,
      Value<String> visitedCanonicals,
      Value<String?> duplicatePolicy,
      Value<String?> sessionDuplicateDecision,
      Value<String?> sessionPartialDecision,
      Value<String> scope,
      Value<int?> maxBytes,
      Value<String?> captureMode,
      Value<bool> captureModeIsUserSet,
      Value<String?> pauseReason,
      Value<String> origin,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$SaveRunsTableUpdateCompanionBuilder =
    SaveRunsCompanion Function({
      Value<String> id,
      Value<String?> collectionId,
      Value<String> startUrl,
      Value<String?> currentUrl,
      Value<int> requestedEntries,
      Value<int> completedEntries,
      Value<String> state,
      Value<String?> lastError,
      Value<String?> stopReason,
      Value<String> visitedUrls,
      Value<String> visitedCanonicals,
      Value<String?> duplicatePolicy,
      Value<String?> sessionDuplicateDecision,
      Value<String?> sessionPartialDecision,
      Value<String> scope,
      Value<int?> maxBytes,
      Value<String?> captureMode,
      Value<bool> captureModeIsUserSet,
      Value<String?> pauseReason,
      Value<String> origin,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$SaveRunsTableFilterComposer
    extends Composer<_$AppDatabase, $SaveRunsTable> {
  $$SaveRunsTableFilterComposer({
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

  ColumnFilters<String> get collectionId => $composableBuilder(
    column: $table.collectionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startUrl => $composableBuilder(
    column: $table.startUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currentUrl => $composableBuilder(
    column: $table.currentUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get requestedEntries => $composableBuilder(
    column: $table.requestedEntries,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completedEntries => $composableBuilder(
    column: $table.completedEntries,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
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

  ColumnFilters<String> get visitedUrls => $composableBuilder(
    column: $table.visitedUrls,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get visitedCanonicals => $composableBuilder(
    column: $table.visitedCanonicals,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get duplicatePolicy => $composableBuilder(
    column: $table.duplicatePolicy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionDuplicateDecision => $composableBuilder(
    column: $table.sessionDuplicateDecision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionPartialDecision => $composableBuilder(
    column: $table.sessionPartialDecision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maxBytes => $composableBuilder(
    column: $table.maxBytes,
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

  ColumnFilters<String> get pauseReason => $composableBuilder(
    column: $table.pauseReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get origin => $composableBuilder(
    column: $table.origin,
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
}

class $$SaveRunsTableOrderingComposer
    extends Composer<_$AppDatabase, $SaveRunsTable> {
  $$SaveRunsTableOrderingComposer({
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

  ColumnOrderings<String> get collectionId => $composableBuilder(
    column: $table.collectionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startUrl => $composableBuilder(
    column: $table.startUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currentUrl => $composableBuilder(
    column: $table.currentUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get requestedEntries => $composableBuilder(
    column: $table.requestedEntries,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completedEntries => $composableBuilder(
    column: $table.completedEntries,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
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

  ColumnOrderings<String> get visitedUrls => $composableBuilder(
    column: $table.visitedUrls,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get visitedCanonicals => $composableBuilder(
    column: $table.visitedCanonicals,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get duplicatePolicy => $composableBuilder(
    column: $table.duplicatePolicy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionDuplicateDecision => $composableBuilder(
    column: $table.sessionDuplicateDecision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionPartialDecision => $composableBuilder(
    column: $table.sessionPartialDecision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maxBytes => $composableBuilder(
    column: $table.maxBytes,
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

  ColumnOrderings<String> get pauseReason => $composableBuilder(
    column: $table.pauseReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get origin => $composableBuilder(
    column: $table.origin,
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
}

class $$SaveRunsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SaveRunsTable> {
  $$SaveRunsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get collectionId => $composableBuilder(
    column: $table.collectionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get startUrl =>
      $composableBuilder(column: $table.startUrl, builder: (column) => column);

  GeneratedColumn<String> get currentUrl => $composableBuilder(
    column: $table.currentUrl,
    builder: (column) => column,
  );

  GeneratedColumn<int> get requestedEntries => $composableBuilder(
    column: $table.requestedEntries,
    builder: (column) => column,
  );

  GeneratedColumn<int> get completedEntries => $composableBuilder(
    column: $table.completedEntries,
    builder: (column) => column,
  );

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<String> get stopReason => $composableBuilder(
    column: $table.stopReason,
    builder: (column) => column,
  );

  GeneratedColumn<String> get visitedUrls => $composableBuilder(
    column: $table.visitedUrls,
    builder: (column) => column,
  );

  GeneratedColumn<String> get visitedCanonicals => $composableBuilder(
    column: $table.visitedCanonicals,
    builder: (column) => column,
  );

  GeneratedColumn<String> get duplicatePolicy => $composableBuilder(
    column: $table.duplicatePolicy,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sessionDuplicateDecision => $composableBuilder(
    column: $table.sessionDuplicateDecision,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sessionPartialDecision => $composableBuilder(
    column: $table.sessionPartialDecision,
    builder: (column) => column,
  );

  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<int> get maxBytes =>
      $composableBuilder(column: $table.maxBytes, builder: (column) => column);

  GeneratedColumn<String> get captureMode => $composableBuilder(
    column: $table.captureMode,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get captureModeIsUserSet => $composableBuilder(
    column: $table.captureModeIsUserSet,
    builder: (column) => column,
  );

  GeneratedColumn<String> get pauseReason => $composableBuilder(
    column: $table.pauseReason,
    builder: (column) => column,
  );

  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SaveRunsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SaveRunsTable,
          SaveRun,
          $$SaveRunsTableFilterComposer,
          $$SaveRunsTableOrderingComposer,
          $$SaveRunsTableAnnotationComposer,
          $$SaveRunsTableCreateCompanionBuilder,
          $$SaveRunsTableUpdateCompanionBuilder,
          (SaveRun, BaseReferences<_$AppDatabase, $SaveRunsTable, SaveRun>),
          SaveRun,
          PrefetchHooks Function()
        > {
  $$SaveRunsTableTableManager(_$AppDatabase db, $SaveRunsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SaveRunsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SaveRunsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SaveRunsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> collectionId = const Value.absent(),
                Value<String> startUrl = const Value.absent(),
                Value<String?> currentUrl = const Value.absent(),
                Value<int> requestedEntries = const Value.absent(),
                Value<int> completedEntries = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<String?> stopReason = const Value.absent(),
                Value<String> visitedUrls = const Value.absent(),
                Value<String> visitedCanonicals = const Value.absent(),
                Value<String?> duplicatePolicy = const Value.absent(),
                Value<String?> sessionDuplicateDecision = const Value.absent(),
                Value<String?> sessionPartialDecision = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<int?> maxBytes = const Value.absent(),
                Value<String?> captureMode = const Value.absent(),
                Value<bool> captureModeIsUserSet = const Value.absent(),
                Value<String?> pauseReason = const Value.absent(),
                Value<String> origin = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SaveRunsCompanion(
                id: id,
                collectionId: collectionId,
                startUrl: startUrl,
                currentUrl: currentUrl,
                requestedEntries: requestedEntries,
                completedEntries: completedEntries,
                state: state,
                lastError: lastError,
                stopReason: stopReason,
                visitedUrls: visitedUrls,
                visitedCanonicals: visitedCanonicals,
                duplicatePolicy: duplicatePolicy,
                sessionDuplicateDecision: sessionDuplicateDecision,
                sessionPartialDecision: sessionPartialDecision,
                scope: scope,
                maxBytes: maxBytes,
                captureMode: captureMode,
                captureModeIsUserSet: captureModeIsUserSet,
                pauseReason: pauseReason,
                origin: origin,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> collectionId = const Value.absent(),
                required String startUrl,
                Value<String?> currentUrl = const Value.absent(),
                required int requestedEntries,
                Value<int> completedEntries = const Value.absent(),
                required String state,
                Value<String?> lastError = const Value.absent(),
                Value<String?> stopReason = const Value.absent(),
                Value<String> visitedUrls = const Value.absent(),
                Value<String> visitedCanonicals = const Value.absent(),
                Value<String?> duplicatePolicy = const Value.absent(),
                Value<String?> sessionDuplicateDecision = const Value.absent(),
                Value<String?> sessionPartialDecision = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<int?> maxBytes = const Value.absent(),
                Value<String?> captureMode = const Value.absent(),
                Value<bool> captureModeIsUserSet = const Value.absent(),
                Value<String?> pauseReason = const Value.absent(),
                Value<String> origin = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SaveRunsCompanion.insert(
                id: id,
                collectionId: collectionId,
                startUrl: startUrl,
                currentUrl: currentUrl,
                requestedEntries: requestedEntries,
                completedEntries: completedEntries,
                state: state,
                lastError: lastError,
                stopReason: stopReason,
                visitedUrls: visitedUrls,
                visitedCanonicals: visitedCanonicals,
                duplicatePolicy: duplicatePolicy,
                sessionDuplicateDecision: sessionDuplicateDecision,
                sessionPartialDecision: sessionPartialDecision,
                scope: scope,
                maxBytes: maxBytes,
                captureMode: captureMode,
                captureModeIsUserSet: captureModeIsUserSet,
                pauseReason: pauseReason,
                origin: origin,
                createdAt: createdAt,
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

typedef $$SaveRunsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SaveRunsTable,
      SaveRun,
      $$SaveRunsTableFilterComposer,
      $$SaveRunsTableOrderingComposer,
      $$SaveRunsTableAnnotationComposer,
      $$SaveRunsTableCreateCompanionBuilder,
      $$SaveRunsTableUpdateCompanionBuilder,
      (SaveRun, BaseReferences<_$AppDatabase, $SaveRunsTable, SaveRun>),
      SaveRun,
      PrefetchHooks Function()
    >;
typedef $$UserPageHintsTableCreateCompanionBuilder =
    UserPageHintsCompanion Function({
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
typedef $$UserPageHintsTableUpdateCompanionBuilder =
    UserPageHintsCompanion Function({
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

class $$UserPageHintsTableFilterComposer
    extends Composer<_$AppDatabase, $UserPageHintsTable> {
  $$UserPageHintsTableFilterComposer({
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

class $$UserPageHintsTableOrderingComposer
    extends Composer<_$AppDatabase, $UserPageHintsTable> {
  $$UserPageHintsTableOrderingComposer({
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

class $$UserPageHintsTableAnnotationComposer
    extends Composer<_$AppDatabase, $UserPageHintsTable> {
  $$UserPageHintsTableAnnotationComposer({
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

class $$UserPageHintsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UserPageHintsTable,
          UserPageHintRow,
          $$UserPageHintsTableFilterComposer,
          $$UserPageHintsTableOrderingComposer,
          $$UserPageHintsTableAnnotationComposer,
          $$UserPageHintsTableCreateCompanionBuilder,
          $$UserPageHintsTableUpdateCompanionBuilder,
          (
            UserPageHintRow,
            BaseReferences<_$AppDatabase, $UserPageHintsTable, UserPageHintRow>,
          ),
          UserPageHintRow,
          PrefetchHooks Function()
        > {
  $$UserPageHintsTableTableManager(_$AppDatabase db, $UserPageHintsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UserPageHintsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UserPageHintsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UserPageHintsTableAnnotationComposer($db: db, $table: table),
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
              }) => UserPageHintsCompanion(
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
              }) => UserPageHintsCompanion.insert(
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

typedef $$UserPageHintsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UserPageHintsTable,
      UserPageHintRow,
      $$UserPageHintsTableFilterComposer,
      $$UserPageHintsTableOrderingComposer,
      $$UserPageHintsTableAnnotationComposer,
      $$UserPageHintsTableCreateCompanionBuilder,
      $$UserPageHintsTableUpdateCompanionBuilder,
      (
        UserPageHintRow,
        BaseReferences<_$AppDatabase, $UserPageHintsTable, UserPageHintRow>,
      ),
      UserPageHintRow,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableCreateCompanionBuilder =
    SettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$SettingsTableUpdateCompanionBuilder =
    SettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$SettingsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
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

class $$SettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
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

class $$SettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
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

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsTable,
          Setting,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
          Setting,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$AppDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion.insert(
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

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsTable,
      Setting,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
      Setting,
      PrefetchHooks Function()
    >;
typedef $$QueueTasksTableCreateCompanionBuilder =
    QueueTasksCompanion Function({
      required String id,
      required String taskType,
      Value<String?> collectionId,
      Value<String?> startUrl,
      Value<int?> entryLimit,
      Value<int?> maxBytes,
      Value<String?> captureMode,
      Value<bool> captureModeIsUserSet,
      Value<String?> duplicatePolicy,
      Value<String?> scope,
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
typedef $$QueueTasksTableUpdateCompanionBuilder =
    QueueTasksCompanion Function({
      Value<String> id,
      Value<String> taskType,
      Value<String?> collectionId,
      Value<String?> startUrl,
      Value<int?> entryLimit,
      Value<int?> maxBytes,
      Value<String?> captureMode,
      Value<bool> captureModeIsUserSet,
      Value<String?> duplicatePolicy,
      Value<String?> scope,
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

class $$QueueTasksTableFilterComposer
    extends Composer<_$AppDatabase, $QueueTasksTable> {
  $$QueueTasksTableFilterComposer({
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

  ColumnFilters<String> get taskType => $composableBuilder(
    column: $table.taskType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get collectionId => $composableBuilder(
    column: $table.collectionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startUrl => $composableBuilder(
    column: $table.startUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get entryLimit => $composableBuilder(
    column: $table.entryLimit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maxBytes => $composableBuilder(
    column: $table.maxBytes,
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

  ColumnFilters<String> get duplicatePolicy => $composableBuilder(
    column: $table.duplicatePolicy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
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

class $$QueueTasksTableOrderingComposer
    extends Composer<_$AppDatabase, $QueueTasksTable> {
  $$QueueTasksTableOrderingComposer({
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

  ColumnOrderings<String> get taskType => $composableBuilder(
    column: $table.taskType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get collectionId => $composableBuilder(
    column: $table.collectionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startUrl => $composableBuilder(
    column: $table.startUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get entryLimit => $composableBuilder(
    column: $table.entryLimit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maxBytes => $composableBuilder(
    column: $table.maxBytes,
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

  ColumnOrderings<String> get duplicatePolicy => $composableBuilder(
    column: $table.duplicatePolicy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
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

class $$QueueTasksTableAnnotationComposer
    extends Composer<_$AppDatabase, $QueueTasksTable> {
  $$QueueTasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get taskType =>
      $composableBuilder(column: $table.taskType, builder: (column) => column);

  GeneratedColumn<String> get collectionId => $composableBuilder(
    column: $table.collectionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get startUrl =>
      $composableBuilder(column: $table.startUrl, builder: (column) => column);

  GeneratedColumn<int> get entryLimit => $composableBuilder(
    column: $table.entryLimit,
    builder: (column) => column,
  );

  GeneratedColumn<int> get maxBytes =>
      $composableBuilder(column: $table.maxBytes, builder: (column) => column);

  GeneratedColumn<String> get captureMode => $composableBuilder(
    column: $table.captureMode,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get captureModeIsUserSet => $composableBuilder(
    column: $table.captureModeIsUserSet,
    builder: (column) => column,
  );

  GeneratedColumn<String> get duplicatePolicy => $composableBuilder(
    column: $table.duplicatePolicy,
    builder: (column) => column,
  );

  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

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

class $$QueueTasksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $QueueTasksTable,
          QueueTask,
          $$QueueTasksTableFilterComposer,
          $$QueueTasksTableOrderingComposer,
          $$QueueTasksTableAnnotationComposer,
          $$QueueTasksTableCreateCompanionBuilder,
          $$QueueTasksTableUpdateCompanionBuilder,
          (
            QueueTask,
            BaseReferences<_$AppDatabase, $QueueTasksTable, QueueTask>,
          ),
          QueueTask,
          PrefetchHooks Function()
        > {
  $$QueueTasksTableTableManager(_$AppDatabase db, $QueueTasksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$QueueTasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$QueueTasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$QueueTasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> taskType = const Value.absent(),
                Value<String?> collectionId = const Value.absent(),
                Value<String?> startUrl = const Value.absent(),
                Value<int?> entryLimit = const Value.absent(),
                Value<int?> maxBytes = const Value.absent(),
                Value<String?> captureMode = const Value.absent(),
                Value<bool> captureModeIsUserSet = const Value.absent(),
                Value<String?> duplicatePolicy = const Value.absent(),
                Value<String?> scope = const Value.absent(),
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
              }) => QueueTasksCompanion(
                id: id,
                taskType: taskType,
                collectionId: collectionId,
                startUrl: startUrl,
                entryLimit: entryLimit,
                maxBytes: maxBytes,
                captureMode: captureMode,
                captureModeIsUserSet: captureModeIsUserSet,
                duplicatePolicy: duplicatePolicy,
                scope: scope,
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
                required String taskType,
                Value<String?> collectionId = const Value.absent(),
                Value<String?> startUrl = const Value.absent(),
                Value<int?> entryLimit = const Value.absent(),
                Value<int?> maxBytes = const Value.absent(),
                Value<String?> captureMode = const Value.absent(),
                Value<bool> captureModeIsUserSet = const Value.absent(),
                Value<String?> duplicatePolicy = const Value.absent(),
                Value<String?> scope = const Value.absent(),
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
              }) => QueueTasksCompanion.insert(
                id: id,
                taskType: taskType,
                collectionId: collectionId,
                startUrl: startUrl,
                entryLimit: entryLimit,
                maxBytes: maxBytes,
                captureMode: captureMode,
                captureModeIsUserSet: captureModeIsUserSet,
                duplicatePolicy: duplicatePolicy,
                scope: scope,
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

typedef $$QueueTasksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $QueueTasksTable,
      QueueTask,
      $$QueueTasksTableFilterComposer,
      $$QueueTasksTableOrderingComposer,
      $$QueueTasksTableAnnotationComposer,
      $$QueueTasksTableCreateCompanionBuilder,
      $$QueueTasksTableUpdateCompanionBuilder,
      (QueueTask, BaseReferences<_$AppDatabase, $QueueTasksTable, QueueTask>),
      QueueTask,
      PrefetchHooks Function()
    >;
typedef $$BrowsingHistoryTableCreateCompanionBuilder =
    BrowsingHistoryCompanion Function({
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
typedef $$BrowsingHistoryTableUpdateCompanionBuilder =
    BrowsingHistoryCompanion Function({
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

class $$BrowsingHistoryTableFilterComposer
    extends Composer<_$AppDatabase, $BrowsingHistoryTable> {
  $$BrowsingHistoryTableFilterComposer({
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

class $$BrowsingHistoryTableOrderingComposer
    extends Composer<_$AppDatabase, $BrowsingHistoryTable> {
  $$BrowsingHistoryTableOrderingComposer({
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

class $$BrowsingHistoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $BrowsingHistoryTable> {
  $$BrowsingHistoryTableAnnotationComposer({
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

class $$BrowsingHistoryTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BrowsingHistoryTable,
          BrowsingHistoryData,
          $$BrowsingHistoryTableFilterComposer,
          $$BrowsingHistoryTableOrderingComposer,
          $$BrowsingHistoryTableAnnotationComposer,
          $$BrowsingHistoryTableCreateCompanionBuilder,
          $$BrowsingHistoryTableUpdateCompanionBuilder,
          (
            BrowsingHistoryData,
            BaseReferences<
              _$AppDatabase,
              $BrowsingHistoryTable,
              BrowsingHistoryData
            >,
          ),
          BrowsingHistoryData,
          PrefetchHooks Function()
        > {
  $$BrowsingHistoryTableTableManager(
    _$AppDatabase db,
    $BrowsingHistoryTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BrowsingHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BrowsingHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BrowsingHistoryTableAnnotationComposer($db: db, $table: table),
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
              }) => BrowsingHistoryCompanion(
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
              }) => BrowsingHistoryCompanion.insert(
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

typedef $$BrowsingHistoryTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BrowsingHistoryTable,
      BrowsingHistoryData,
      $$BrowsingHistoryTableFilterComposer,
      $$BrowsingHistoryTableOrderingComposer,
      $$BrowsingHistoryTableAnnotationComposer,
      $$BrowsingHistoryTableCreateCompanionBuilder,
      $$BrowsingHistoryTableUpdateCompanionBuilder,
      (
        BrowsingHistoryData,
        BaseReferences<
          _$AppDatabase,
          $BrowsingHistoryTable,
          BrowsingHistoryData
        >,
      ),
      BrowsingHistoryData,
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
    extends Composer<_$AppDatabase, $SavedSitesTable> {
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
    extends Composer<_$AppDatabase, $SavedSitesTable> {
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
    extends Composer<_$AppDatabase, $SavedSitesTable> {
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
          _$AppDatabase,
          $SavedSitesTable,
          SavedSite,
          $$SavedSitesTableFilterComposer,
          $$SavedSitesTableOrderingComposer,
          $$SavedSitesTableAnnotationComposer,
          $$SavedSitesTableCreateCompanionBuilder,
          $$SavedSitesTableUpdateCompanionBuilder,
          (
            SavedSite,
            BaseReferences<_$AppDatabase, $SavedSitesTable, SavedSite>,
          ),
          SavedSite,
          PrefetchHooks Function()
        > {
  $$SavedSitesTableTableManager(_$AppDatabase db, $SavedSitesTable table)
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
      _$AppDatabase,
      $SavedSitesTable,
      SavedSite,
      $$SavedSitesTableFilterComposer,
      $$SavedSitesTableOrderingComposer,
      $$SavedSitesTableAnnotationComposer,
      $$SavedSitesTableCreateCompanionBuilder,
      $$SavedSitesTableUpdateCompanionBuilder,
      (SavedSite, BaseReferences<_$AppDatabase, $SavedSitesTable, SavedSite>),
      SavedSite,
      PrefetchHooks Function()
    >;
typedef $$FaviconCacheTableCreateCompanionBuilder =
    FaviconCacheCompanion Function({
      required String host,
      Value<Uint8List?> bytes,
      Value<String?> sourceUrl,
      required DateTime fetchedAt,
      Value<int> rowid,
    });
typedef $$FaviconCacheTableUpdateCompanionBuilder =
    FaviconCacheCompanion Function({
      Value<String> host,
      Value<Uint8List?> bytes,
      Value<String?> sourceUrl,
      Value<DateTime> fetchedAt,
      Value<int> rowid,
    });

class $$FaviconCacheTableFilterComposer
    extends Composer<_$AppDatabase, $FaviconCacheTable> {
  $$FaviconCacheTableFilterComposer({
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

class $$FaviconCacheTableOrderingComposer
    extends Composer<_$AppDatabase, $FaviconCacheTable> {
  $$FaviconCacheTableOrderingComposer({
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

class $$FaviconCacheTableAnnotationComposer
    extends Composer<_$AppDatabase, $FaviconCacheTable> {
  $$FaviconCacheTableAnnotationComposer({
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

class $$FaviconCacheTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FaviconCacheTable,
          FaviconCacheData,
          $$FaviconCacheTableFilterComposer,
          $$FaviconCacheTableOrderingComposer,
          $$FaviconCacheTableAnnotationComposer,
          $$FaviconCacheTableCreateCompanionBuilder,
          $$FaviconCacheTableUpdateCompanionBuilder,
          (
            FaviconCacheData,
            BaseReferences<_$AppDatabase, $FaviconCacheTable, FaviconCacheData>,
          ),
          FaviconCacheData,
          PrefetchHooks Function()
        > {
  $$FaviconCacheTableTableManager(_$AppDatabase db, $FaviconCacheTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FaviconCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FaviconCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FaviconCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> host = const Value.absent(),
                Value<Uint8List?> bytes = const Value.absent(),
                Value<String?> sourceUrl = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FaviconCacheCompanion(
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
              }) => FaviconCacheCompanion.insert(
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

typedef $$FaviconCacheTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FaviconCacheTable,
      FaviconCacheData,
      $$FaviconCacheTableFilterComposer,
      $$FaviconCacheTableOrderingComposer,
      $$FaviconCacheTableAnnotationComposer,
      $$FaviconCacheTableCreateCompanionBuilder,
      $$FaviconCacheTableUpdateCompanionBuilder,
      (
        FaviconCacheData,
        BaseReferences<_$AppDatabase, $FaviconCacheTable, FaviconCacheData>,
      ),
      FaviconCacheData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CollectionsTableTableManager get collections =>
      $$CollectionsTableTableManager(_db, _db.collections);
  $$EntriesTableTableManager get entries =>
      $$EntriesTableTableManager(_db, _db.entries);
  $$SaveRunsTableTableManager get saveRuns =>
      $$SaveRunsTableTableManager(_db, _db.saveRuns);
  $$UserPageHintsTableTableManager get userPageHints =>
      $$UserPageHintsTableTableManager(_db, _db.userPageHints);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
  $$QueueTasksTableTableManager get queueTasks =>
      $$QueueTasksTableTableManager(_db, _db.queueTasks);
  $$BrowsingHistoryTableTableManager get browsingHistory =>
      $$BrowsingHistoryTableTableManager(_db, _db.browsingHistory);
  $$SavedSitesTableTableManager get savedSites =>
      $$SavedSitesTableTableManager(_db, _db.savedSites);
  $$FaviconCacheTableTableManager get faviconCache =>
      $$FaviconCacheTableTableManager(_db, _db.faviconCache);
}
