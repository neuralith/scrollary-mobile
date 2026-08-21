import 'dart:convert';

/// What an entry package actually holds — the **artifact discriminator**.
///
/// This is deliberately not the same question as "what kind of page was this"
/// ([ContentKind]) or "what did the user ask for" (`CaptureMode`). Those two
/// are claims about the source and the request; this one is a fact about the
/// bytes on disk, and it is the only thing the reader and recovery are allowed
/// to switch on. Inferring the format from file extensions or asset counts is
/// exactly the guess this field exists to remove.
///
/// A future video artifact becomes another value here. Nothing else about the
/// image and document formats has to move for that to happen, which is the
/// whole point of storing the discriminator rather than deriving it.
enum ArtifactFormat {
  /// An ordered list of full-size images. The original format, and what every
  /// manifest written before schema 2 holds.
  imageSequence,

  /// A `document.json` of typed text blocks, optionally with inline images in
  /// the `assets/` directory.
  structuredDocument,

  /// A format this build does not know. **Only ever produced by parsing**, and
  /// only by a package a newer version wrote. The reader shows an honest
  /// "saved in a format this version cannot open" state rather than
  /// misreading it as one of the formats above.
  unknown;

  static ArtifactFormat fromName(String? name) => ArtifactFormat.values
      .firstWhere((f) => f.name == name, orElse: () => ArtifactFormat.unknown);

  bool get isReadable => this != ArtifactFormat.unknown;
}

/// Save outcome for an entry. `complete` is only ever written after every
/// required asset is on disk and verified.
enum SaveStatus { saving, complete, partial, failed }

SaveStatus saveStatusFromName(String? name) => SaveStatus.values.firstWhere(
  (s) => s.name == name,
  orElse: () => SaveStatus.failed,
);

enum AssetStatus { pending, fetching, stored, failed }

AssetStatus assetStatusFromName(String? name) => AssetStatus.values.firstWhere(
  (s) => s.name == name,
  orElse: () => AssetStatus.failed,
);

class EntryAsset {
  const EntryAsset({
    required this.index,
    required this.sourceUrl,
    required this.status,
    this.relativePath,
    this.mimeType,
    this.byteSize,
    this.width,
    this.height,
    this.domWidth,
    this.domHeight,
    this.dimensionsVerified = false,
    this.error,
  });

  factory EntryAsset.fromJson(Map<String, dynamic> json) => EntryAsset(
    index: (json['index'] as num).toInt(),
    sourceUrl: json['sourceUrl'] as String,
    status: assetStatusFromName(json['status'] as String?),
    relativePath: json['relativePath'] as String?,
    mimeType: json['mimeType'] as String?,
    byteSize: (json['byteSize'] as num?)?.toInt(),
    width: (json['width'] as num?)?.toInt(),
    height: (json['height'] as num?)?.toInt(),
    domWidth: (json['domWidth'] as num?)?.toInt(),
    domHeight: (json['domHeight'] as num?)?.toInt(),
    dimensionsVerified: json['dimensionsVerified'] == true,
    error: json['error'] as String?,
  );

  /// 1-based position in reading order (DOM order, not filename order).
  final int index;
  final String sourceUrl;
  final AssetStatus status;

  /// Relative to the entry directory, e.g. `assets/001.png`. Never absolute:
  /// the iOS app-container path changes between installs.
  final String? relativePath;
  final String? mimeType;
  final int? byteSize;

  /// Intrinsic pixel size. Once [dimensionsVerified] is true these were read
  /// from the stored file's own header — the source of truth for layout. Until
  /// then they are whatever the page reported, kept only as a best guess.
  final int? width;
  final int? height;

  /// What the page's DOM reported at probe time. Diagnostics only: attributes
  /// and rendered boxes routinely disagree with the actual file, which is
  /// exactly the disagreement this field makes visible.
  final int? domWidth;
  final int? domHeight;

  /// True once width/height were decoded from the downloaded bytes rather
  /// than trusted from the DOM.
  final bool dimensionsVerified;
  final String? error;

  bool get isStored => status == AssetStatus.stored && relativePath != null;

  EntryAsset copyWith({
    AssetStatus? status,
    String? relativePath,
    String? mimeType,
    int? byteSize,
    int? width,
    int? height,
    int? domWidth,
    int? domHeight,
    bool? dimensionsVerified,
    String? error,
  }) => EntryAsset(
    index: index,
    sourceUrl: sourceUrl,
    status: status ?? this.status,
    relativePath: relativePath ?? this.relativePath,
    mimeType: mimeType ?? this.mimeType,
    byteSize: byteSize ?? this.byteSize,
    width: width ?? this.width,
    height: height ?? this.height,
    domWidth: domWidth ?? this.domWidth,
    domHeight: domHeight ?? this.domHeight,
    dimensionsVerified: dimensionsVerified ?? this.dimensionsVerified,
    error: error ?? this.error,
  );

  Map<String, dynamic> toJson() => {
    'index': index,
    'sourceUrl': sourceUrl,
    'status': status.name,
    if (relativePath != null) 'relativePath': relativePath,
    if (mimeType != null) 'mimeType': mimeType,
    if (byteSize != null) 'byteSize': byteSize,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (domWidth != null) 'domWidth': domWidth,
    if (domHeight != null) 'domHeight': domHeight,
    if (dimensionsVerified) 'dimensionsVerified': true,
    if (error != null) 'error': error,
  };
}

/// Where an entry's structured document lives, and how big it is.
///
/// A reference rather than the document itself: startup recovery reads every
/// manifest on disk, and inlining a long run of prose into each one would
/// make that scan proportional to the size of the library's text instead of to
/// the number of entries.
class DocumentRef {
  const DocumentRef({
    required this.relativePath,
    required this.blockCount,
    required this.textLength,
  });

  factory DocumentRef.fromJson(Map<String, dynamic> json) => DocumentRef(
    relativePath: json['relativePath']?.toString() ?? 'document.json',
    blockCount: (json['blockCount'] as num?)?.toInt() ?? 0,
    textLength: (json['textLength'] as num?)?.toInt() ?? 0,
  );

  /// Relative to the entry directory, like every asset path. Never absolute.
  final String relativePath;

  /// Counts, so the details sheet and the storage screen can describe the
  /// entry without opening and parsing the document.
  final int blockCount;
  final int textLength;

  Map<String, dynamic> toJson() => {
    'relativePath': relativePath,
    'blockCount': blockCount,
    'textLength': textLength,
  };
}

/// Self-describing entry package descriptor, written into the entry directory.
///
/// This is also where an entry's **pages** live: [assets] is the ordered page
/// list, next to the bytes it describes, rather than a second copy in SQLite
/// that could disagree with the files. It is what lets the app reconcile files
/// against the database after a crash, and what would let an export work
/// without the database at all.
///
/// **Schema 2** added [artifact], [captureMode] and [document]. Schema 1
/// packages are still read exactly as written and are never rewritten in
/// place: a manifest with no `artifact` field is an image sequence, because
/// that is the only thing this app could produce when it wrote one.
class EntryManifest {
  const EntryManifest({
    required this.schemaVersion,
    required this.entryId,
    required this.sourceUrl,
    required this.title,
    required this.savedAt,
    required this.status,
    required this.detectedAssetCount,
    required this.storedAssetCount,
    required this.assets,
    this.artifact = ArtifactFormat.imageSequence,
    this.captureMode,
    this.captureModeIsUserSet,
    this.document,
    this.collectionId,
    this.canonicalUrl,
    this.nextUrl,
    this.entryOrder,
    this.statusReason,
    this.contentKind,
    this.contentKindConfidence,
    this.contentKindIsUserSet,
    this.host,
    this.publishedAt,
    this.sourceMarker,
    this.entryNumber,
  });

  factory EntryManifest.fromJson(Map<String, dynamic> json) {
    final version = (json['schemaVersion'] as num).toInt();
    return EntryManifest(
      schemaVersion: version,
      // Version 1 predates the discriminator, and every package it could
      // describe is an ordered image list. Reading it as `unknown` — which is
      // what `fromName(null)` would give — would make every previously saved
      // entry unopenable, so the version is what decides here, not the
      // absence of a field.
      artifact: version >= 2
          ? ArtifactFormat.fromName(json['artifact'] as String?)
          : ArtifactFormat.imageSequence,
      captureMode:
          json['captureMode'] as String? ??
          (version >= 2 ? null : 'imageSequence'),
      captureModeIsUserSet: json['captureModeIsUserSet'] as bool?,
      document: json['document'] is Map
          ? DocumentRef.fromJson(
              Map<String, dynamic>.from(json['document'] as Map),
            )
          : null,
      entryId: json['entryId'] as String,
      collectionId: json['collectionId'] as String?,
      sourceUrl: json['sourceUrl'] as String,
      host: json['host'] as String?,
      canonicalUrl: json['canonicalUrl'] as String?,
      title: json['title'] as String,
      savedAt: DateTime.parse(json['savedAt'] as String),
      status: saveStatusFromName(json['status'] as String?),
      statusReason: json['statusReason'] as String?,
      detectedAssetCount: (json['detectedAssetCount'] as num).toInt(),
      storedAssetCount: (json['storedAssetCount'] as num).toInt(),
      nextUrl: json['nextUrl'] as String?,
      entryOrder: (json['entryOrder'] as num?)?.toInt(),
      contentKind: json['contentKind'] as String?,
      contentKindConfidence: json['contentKindConfidence'] as String?,
      contentKindIsUserSet: json['contentKindIsUserSet'] as bool?,
      publishedAt: json['publishedAt'] == null
          ? null
          : DateTime.tryParse(json['publishedAt'] as String),
      sourceMarker: json['sourceMarker'] as String?,
      entryNumber: (json['entryNumber'] as num?)?.toDouble(),
      assets: (json['assets'] as List<dynamic>? ?? const [])
          .map((e) => EntryAsset.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }

  factory EntryManifest.decode(String jsonText) =>
      EntryManifest.fromJson(jsonDecode(jsonText) as Map<String, dynamic>);

  /// **Two.** Schema 1 is still read; nothing writes it any more.
  static const int currentSchemaVersion = 2;

  final int schemaVersion;

  /// What this package holds. The one field the reader and recovery switch on.
  final ArtifactFormat artifact;

  /// `CaptureMode.name` — what the save was *asked* to produce. Kept beside
  /// [artifact] rather than instead of it: "the user asked for text and
  /// images" and "this package holds a document with two stored images" are
  /// different facts, and only the second one can be trusted by a reader.
  final String? captureMode;

  /// True when a person chose the mode rather than detection picking it.
  final bool? captureModeIsUserSet;

  /// The document, when [artifact] is [ArtifactFormat.structuredDocument].
  /// Null for an image sequence.
  final DocumentRef? document;

  final String entryId;

  /// Null for a standalone entry. The manifest records the same nullable
  /// relationship the schema does, so a recovered entry stays standalone
  /// instead of being adopted by whichever collection happens to be nearby.
  final String? collectionId;
  final String sourceUrl;

  /// Source domain, for attribution when the database row is gone.
  final String? host;
  final String? canonicalUrl;
  final String title;
  final DateTime savedAt;
  final SaveStatus status;
  final String? statusReason;
  final int detectedAssetCount;
  final int storedAssetCount;
  final String? nextUrl;
  final int? entryOrder;

  /// The detected content shape at save time (`ContentKind.name`), how much it
  /// was trusted, and whether a person set it. Recorded rather than re-derived:
  /// a guess made later, with no page to look at, would be weaker than the one
  /// the save already made.
  final String? contentKind;
  final String? contentKindConfidence;
  final bool? contentKindIsUserSet;

  /// Publication date, only when the page stated one unambiguously.
  final DateTime? publishedAt;

  /// The marker the source printed, kept verbatim, and the number it carried.
  final String? sourceMarker;
  final double? entryNumber;

  /// The entry's ordered pages, or — for a structured document — its stored
  /// inline images, which the document's image blocks point at by `index`.
  final List<EntryAsset> assets;

  /// How many pages this entry has. The honest count comes from the files.
  int get pageCount => storedAssets.length;

  List<EntryAsset> get storedAssets =>
      assets.where((a) => a.isStored).toList(growable: false);

  bool get isDocument => artifact == ArtifactFormat.structuredDocument;
  bool get isImageSequence => artifact == ArtifactFormat.imageSequence;

  /// Look up a stored asset by its manifest index — how a document image block
  /// finds its bytes.
  EntryAsset? assetByIndex(int index) {
    for (final a in assets) {
      if (a.index == index) return a;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'artifact': artifact.name,
    if (captureMode != null) 'captureMode': captureMode,
    if (captureModeIsUserSet == true) 'captureModeIsUserSet': true,
    if (document != null) 'document': document!.toJson(),
    'entryId': entryId,
    if (collectionId != null) 'collectionId': collectionId,
    'sourceUrl': sourceUrl,
    if (host != null) 'host': host,
    if (canonicalUrl != null) 'canonicalUrl': canonicalUrl,
    'title': title,
    'savedAt': savedAt.toUtc().toIso8601String(),
    'status': status.name,
    if (statusReason != null) 'statusReason': statusReason,
    'detectedAssetCount': detectedAssetCount,
    'storedAssetCount': storedAssetCount,
    if (nextUrl != null) 'nextUrl': nextUrl,
    if (entryOrder != null) 'entryOrder': entryOrder,
    if (contentKind != null) 'contentKind': contentKind,
    if (contentKindConfidence != null)
      'contentKindConfidence': contentKindConfidence,
    if (contentKindIsUserSet == true) 'contentKindIsUserSet': true,
    if (publishedAt != null)
      'publishedAt': publishedAt!.toUtc().toIso8601String(),
    if (sourceMarker != null) 'sourceMarker': sourceMarker,
    if (entryNumber != null) 'entryNumber': entryNumber,
    'assets': assets.map((a) => a.toJson()).toList(),
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  EntryManifest copyWith({
    SaveStatus? status,
    String? statusReason,
    int? storedAssetCount,
    String? nextUrl,
    List<EntryAsset>? assets,
    DocumentRef? document,
  }) => EntryManifest(
    schemaVersion: schemaVersion,
    artifact: artifact,
    captureMode: captureMode,
    captureModeIsUserSet: captureModeIsUserSet,
    document: document ?? this.document,
    entryId: entryId,
    collectionId: collectionId,
    sourceUrl: sourceUrl,
    canonicalUrl: canonicalUrl,
    title: title,
    savedAt: savedAt,
    status: status ?? this.status,
    statusReason: statusReason ?? this.statusReason,
    detectedAssetCount: detectedAssetCount,
    storedAssetCount: storedAssetCount ?? this.storedAssetCount,
    nextUrl: nextUrl ?? this.nextUrl,
    entryOrder: entryOrder,
    contentKind: contentKind,
    contentKindConfidence: contentKindConfidence,
    contentKindIsUserSet: contentKindIsUserSet,
    host: host,
    publishedAt: publishedAt,
    sourceMarker: sourceMarker,
    entryNumber: entryNumber,
    assets: assets ?? this.assets,
  );
}
