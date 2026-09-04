/// The wire vocabulary, read out of `contracts/openapi.yaml` itself.
///
/// **Why the contract and not a list in this file.** The drift this guards
/// against is a field that exists in the app and not on the service: the
/// service's sparse-upsert merge is an allowlist and *rejects* what it does not
/// know, and a rejected intent is parked on the device permanently. A list
/// restated here would drift in exactly the same way as the one it is meant to
/// catch. So the contract is the input, and the fake service refuses whatever
/// it refuses.
///
/// The Go side holds its own allowlist against the same file
/// (`internal/sync/vocabulary_test.go`); between them, the two halves cannot
/// disagree about what a mutation may carry without a test saying so.
///
/// **The reader is deliberately small.** `yaml` is a transitive dependency and
/// not one this package declares, and one test's convenience is not a reason to
/// take on a direct one. What is needed is the property names under a named
/// schema, and the file's shape makes that a scan: `properties:` at six spaces,
/// then keys at eight, ending where the indentation returns. Folded prose sits
/// deeper than the key that owns it, so it cannot be mistaken for a key.
library;

import 'dart:io';

/// Which `components.schemas` entry defines each mutable entity kind.
const Map<String, String> contractSchemaFor = {
  'folder': 'Folder',
  'collection': 'Collection',
  'source': 'Source',
  'entry': 'Entry',
  'location': 'Location',
  'readingState': 'ReadingState',
  'measurement': 'Measurement',
};

/// Fields the server owns and a client never sends.
const Set<String> serverOwnedFields = {'id', 'revision', 'updated_at'};

/// Keys the envelope already carries, so they are not part of `fields`.
/// `measurement.source_id` is deliberately absent: it is the merge key *and* a
/// field the client must send.
const Map<String, Set<String>> envelopeKeys = {
  'readingState': {'entry_id'},
  'measurement': {'entry_id'},
};

/// Every property the contract defines for [schema], in file order.
List<String> contractProperties(String schema) {
  final lines = File('contracts/openapi.yaml').readAsLinesSync();
  var inSchema = false;
  var inProperties = false;
  final names = <String>[];
  for (final line in lines) {
    if (RegExp('^    $schema:\$').hasMatch(line)) {
      inSchema = true;
      continue;
    }
    if (!inSchema) continue;
    if (!inProperties) {
      // Another schema began before this one declared any properties.
      if (RegExp(r'^    \S').hasMatch(line)) break;
      if (line == '      properties:') inProperties = true;
      continue;
    }
    if (line.trim().isEmpty) continue;
    // Back out to six spaces or less: the properties block has ended.
    if (!line.startsWith('       ')) break;
    final key = RegExp(r'^ {8}([a-z][a-z0-9_]*):').firstMatch(line);
    if (key != null) names.add(key.group(1)!);
  }
  if (names.isEmpty) {
    throw StateError('no properties found for schema $schema');
  }
  return names;
}

/// What a client may put in a sparse `fields` payload, per entity kind.
Map<String, Set<String>> contractMutableFields() => {
  for (final MapEntry(key: kind, value: schema) in contractSchemaFor.entries)
    kind: contractProperties(schema)
        .where(
          (name) =>
              !serverOwnedFields.contains(name) &&
              !(envelopeKeys[kind] ?? const <String>{}).contains(name),
        )
        .toSet(),
};
