import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../storage/database.dart';
import 'collection_identity.dart';
import 'content_shape.dart';

const _uuid = Uuid();

/// The display name for a collection, strongest source first:
/// user-edited → detected title → host.
String displayNameFor(Collection collection) {
  final user = collection.userTitle?.trim();
  if (user != null && user.isNotEmpty) return user;
  final detected = collection.title.trim();
  if (detected.isNotEmpty) return detected;
  return collection.host.isEmpty ? 'Unknown source' : collection.host;
}

/// What the app is about to create, handed to whoever can ask the user.
///
/// [suggestedName] is exactly what the app would have used on its own, so
/// accepting it reproduces the previous behaviour and declining it is not an
/// argument with a hidden default. It is empty when nothing was detected — the
/// page carried no usable title and the alternative was the bare host.
class NewCollectionProposal {
  const NewCollectionProposal({
    required this.suggestedName,
    required this.host,
    required this.entryUrl,
  });

  final String suggestedName;
  final String host;

  /// The page the save started on, for a prompt that wants to show it.
  final String entryUrl;
}

/// Owns collection membership: which collection an entry belongs to, whether it
/// belongs to one at all, and what shape that collection has.
///
/// There is deliberately no backfill, regrouping or repair routine here. The
/// schema is version 1 and every row in it was written by this code, so a
/// routine that fixes rows written by an older build would have nothing to fix
/// and would quietly become the place future bugs get papered over.
class CollectionRepository {
  CollectionRepository(this.db);

  final AppDatabase db;

  /// The collection an entry belongs to, creating it when it is new — or
  /// **null**, when this page is a standalone entry.
  ///
  /// Returning null is the point. A single saved article is a library item in
  /// its own right; wrapping it in a collection of one would put a group in the
  /// library that the user never made and cannot meaningfully open, and would
  /// make "3 collections" mean "3 unrelated articles".
  ///
  /// A collection is created only when there is a positive reason to believe
  /// this page is one of several related ones: the save is walking a sequence,
  /// or an update check found an index. `sequence` says which.
  Future<Collection?> resolveCollection({
    required String entryUrl,
    required SequenceShape sequence,
    String? pageTitle,
    PageHints hints = const PageHints(),
    void Function(String)? log,

    /// Asked once, immediately before a new collection row is written — never
    /// when an existing collection is joined, and never for a standalone entry.
    ///
    /// Returns the name to store on `user_title`, or null to decline, in which
    /// case **no row is written and null is returned**. Declining is not by
    /// itself a stop: the caller decides what a page with no collection means.
    /// `SaveRunController` stops the run rather than saving the page loose.
    Future<String?> Function(NewCollectionProposal)? confirmNewName,
  }) async {
    if (sequence.kind == SequenceKind.none) {
      log?.call(
        'standalone entry: no sequence detected, no collection created',
      );
      return null;
    }

    final identity = resolveCollectionIdentity(
      entryUrl: entryUrl,
      pageTitle: pageTitle,
      hints: hints,
    );

    // Low confidence means we could not tell one collection from another on this
    // host. Joining an existing one would risk mixing two unrelated groups,
    // which is far worse than an extra group, so keep it separate.
    if (identity.canMerge) {
      final existing = await db.findCollectionByKey(
        identity.host,
        identity.collectionKey,
      );
      if (existing != null) {
        log?.call(
          'collection: joined "${displayNameFor(existing)}" '
          '(${identity.host}${identity.collectionKey}, ${identity.basis})',
        );
        // Refresh the detected title if we had nothing before; never touch a
        // name the user chose.
        if (existing.title.trim().isEmpty &&
            (identity.detectedTitle ?? '').isNotEmpty) {
          await db.upsertCollection(
            existing.copyWith(title: identity.detectedTitle!),
          );
          return (await db.collectionById(existing.id))!;
        }
        return existing;
      }
    }

    // Nothing has been written yet, and this is the last moment before
    // something is: a group about to exist gets its name from the person
    // making it. The detected title is offered as the suggestion and stays on
    // `title` regardless — what the source called this is a fact worth
    // keeping, and it is not what the library will print.
    String? userTitle;
    if (confirmNewName != null) {
      final chosen = await confirmNewName(
        NewCollectionProposal(
          suggestedName: identity.detectedTitle ?? '',
          host: identity.host,
          entryUrl: entryUrl,
        ),
      );
      if (chosen == null || chosen.trim().isEmpty) {
        log?.call('no collection created: naming was declined');
        return null;
      }
      userTitle = chosen.trim();
    }

    final now = DateTime.now();
    final collection = Collection(
      id: _uuid.v4(),
      lifecycle: 'active',
      title: identity.detectedTitle ?? identity.host,
      userTitle: userTitle,
      sourceUrl: identity.collectionIndexUrl ?? entryUrl,
      host: identity.host,
      collectionKey: identity.canMerge
          ? identity.collectionKey
          // A low-confidence group gets a key nothing else can match, so it can
          // never silently absorb a later save.
          : '${identity.collectionKey}#${_uuid.v4()}',
      collectionIndexUrl: identity.collectionIndexUrl,
      identityBasis: identity.basis,
      identityConfidence: identity.confidence.name,
      // The shape is recorded as measured, including a `knownEntryTotal` that
      // stays null whenever the source never published one.
      contentKind: ContentKind.unknownWebContent.name,
      sequenceKind: sequence.kind.name,
      orderingBasis: sequence.ordering.name,
      shapeConfidence: sequence.confidence.name,
      knownEntryTotal: sequence.knownTotal,
      createdAt: now,
    );
    await db.upsertCollection(collection);
    log?.call(
      'collection: created "${displayNameFor(collection)}"'
      '${userTitle == null ? '' : ' (named by you)'} '
      '(${identity.basis}, ${identity.confidence.name} confidence, '
      '$sequence)',
    );
    return collection;
  }

  Future<void> rename(String collectionId, String? newName) =>
      db.renameCollection(collectionId, newName);

  /// Archiving hides the collection and stops its checks. Entries, files and
  /// reading state are untouched — restore puts it back exactly as it was.
  Future<void> archive(String collectionId) =>
      db.setCollectionLifecycle(collectionId, 'archived');

  Future<void> restore(String collectionId) =>
      db.setCollectionLifecycle(collectionId, 'active');

  /// Record what a save or an update check learned about a collection's shape.
  ///
  /// Only ever *raises* certainty: a low-confidence re-detection never
  /// overwrites a high-confidence answer, and `knownEntryTotal` is never
  /// replaced by null — losing a published total to one unhelpful page load
  /// would turn a finite collection back into an open-ended one.
  Future<void> recordShape({
    required String collectionId,
    ContentKind? kind,
    SequenceShape? sequence,
    void Function(String)? log,
  }) async {
    final current = await db.collectionById(collectionId);
    if (current == null) return;

    final currentConfidence = ShapeConfidence.fromName(current.shapeConfidence);
    final nextConfidence = sequence?.confidence ?? currentConfidence;
    final improves = nextConfidence.index <= currentConfidence.index;

    await db.writeCollectionShape(
      collectionId,
      CollectionsCompanion(
        contentKind: kind == null ? const Value.absent() : Value(kind.name),
        sequenceKind: sequence == null || !improves
            ? const Value.absent()
            : Value(sequence.kind.name),
        orderingBasis: sequence == null || !improves
            ? const Value.absent()
            : Value(sequence.ordering.name),
        shapeConfidence: sequence == null || !improves
            ? const Value.absent()
            : Value(sequence.confidence.name),
        knownEntryTotal: sequence?.knownTotal == null
            ? const Value.absent()
            : Value(sequence!.knownTotal),
      ),
    );
    log?.call(
      'collection shape: ${kind?.name ?? current.contentKind} · '
      '${sequence ?? current.sequenceKind}'
      '${improves ? '' : ' (kept: existing answer was more certain)'}',
    );
  }

  /// Move an entry into a collection, or out of every collection.
  ///
  /// Both directions are supported on purpose: the user can group standalone
  /// entries they decide are related, and can pull an entry back out when the
  /// detection was wrong. Empty collections are swept afterwards so ungrouping
  /// the last entry does not leave a phantom row in the library.
  Future<void> setCollection({
    required String entryId,
    required String? collectionId,
  }) async {
    await db.reassignEntry(entryId, collectionId);
    await db.deleteEmptyCollections();
  }

  /// Group a hand-picked set of standalone entries into a new collection.
  ///
  /// Ordering basis is `userDefinedManualOrder`, because that is what it is —
  /// the app must not later re-sort them by a number it parsed out of a URL.
  Future<Collection> groupManually({
    required String title,
    required List<Entry> members,
  }) async {
    final now = DateTime.now();
    final first = members.isEmpty ? null : members.first;
    final collection = Collection(
      id: _uuid.v4(),
      lifecycle: 'active',
      title: title,
      sourceUrl: first?.sourceUrl ?? '',
      host: first?.host ?? '',
      // A hand-made group has no source identity to match against, and must
      // never absorb a later automatic save.
      collectionKey: 'manual:${_uuid.v4()}',
      identityBasis: 'user grouping',
      identityConfidence: IdentityConfidence.high.name,
      contentKind: ContentKind.unknownWebContent.name,
      sequenceKind: SequenceKind.manualSelection.name,
      orderingBasis: OrderingBasis.userDefinedManualOrder.name,
      shapeConfidence: ShapeConfidence.high.name,
      knownEntryTotal: members.length,
      createdAt: now,
    );
    await db.upsertCollection(collection);
    for (var i = 0; i < members.length; i++) {
      await db.reassignEntry(members[i].id, collection.id);
      await db.setEntryOrdering(members[i].id, order: Value(i + 1));
    }
    await db.deleteEmptyCollections();
    return collection;
  }
}
