/// Evidence and arbitration payloads (F2): what a client observed, in the
/// contract's shape, with nothing invented.
///
/// The fidelity assertions read `contracts/evidence.yaml` and
/// `contracts/errors.yaml` from disk rather than a copy: a contract change
/// that this client has not followed should fail here, which a copied field
/// list could never do.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/library/collection_identity.dart';
import 'package:web_reader/recognition/evidence.dart';
import 'package:web_reader/recognition/recognise.dart';

import 'support/recognition_harness.dart';

/// A deliberately small reader for the exact shape these two contract files
/// take: `components: → schemas: → <Name>:` with `required:`, `properties:`
/// and `enum:` members. It is not a YAML parser and does not pretend to be —
/// it exists so the assertions below read the real contract.
class ContractSchema {
  factory ContractSchema.read(List<String> lines, String name) {
    final start = lines.indexOf('    $name:');
    if (start < 0) throw StateError('contract has no schema named $name');
    var end = lines.length;
    for (var i = start + 1; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) continue;
      if (_indent(lines[i]) <= 4) {
        end = i;
        break;
      }
    }

    final required = <String>{};
    final properties = <String>[];
    final propertyEnums = <String, List<String>>{};
    final schemaEnum = <String>[];

    var inProperties = false;
    String? property;
    List<String>? sink;

    for (final line in lines.sublist(start + 1, end)) {
      if (line.trim().isEmpty) continue;
      final indent = _indent(line);
      final trimmed = line.trim();

      if (indent == 6) {
        sink = null;
        inProperties = false;
        if (trimmed.startsWith('required:')) {
          required.addAll(_inlineList(trimmed));
        } else if (trimmed == 'properties:') {
          inProperties = true;
        } else if (trimmed == 'enum:') {
          sink = schemaEnum;
        }
        continue;
      }
      if (inProperties && indent == 8) {
        final match = RegExp(r'^([a-z_]+):$').firstMatch(trimmed);
        if (match != null) {
          property = match.group(1);
          properties.add(property!);
          sink = null;
        }
        continue;
      }
      if (inProperties && indent == 10 && trimmed.startsWith('enum:')) {
        final inline = trimmed.substring('enum:'.length).trim();
        final values = propertyEnums.putIfAbsent(property!, () => []);
        if (inline.isEmpty) {
          sink = values;
        } else {
          values.addAll(_inlineList(inline));
        }
        continue;
      }
      if (sink != null && trimmed.startsWith('- ')) {
        sink.add(trimmed.substring(2).trim());
      }
    }

    return ContractSchema._(
      name,
      required,
      properties,
      propertyEnums,
      schemaEnum,
    );
  }

  ContractSchema._(
    this.name,
    this.required,
    this.properties,
    this.propertyEnums,
    this.schemaEnum,
  );

  final String name;
  final Set<String> required;
  final List<String> properties;
  final Map<String, List<String>> propertyEnums;
  final List<String> schemaEnum;

  static int _indent(String line) => line.length - line.trimLeft().length;

  static List<String> _inlineList(String text) {
    final open = text.indexOf('[');
    final close = text.lastIndexOf(']');
    if (open < 0 || close < 0) return const [];
    return text
        .substring(open + 1, close)
        .split(',')
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList();
  }
}

void main() {
  final evidenceYaml = File('contracts/evidence.yaml').readAsLinesSync();
  final errorsYaml = File('contracts/errors.yaml').readAsLinesSync();

  final evidenceSchema = ContractSchema.read(evidenceYaml, 'Evidence');
  final provisionalSchema = ContractSchema.read(
    evidenceYaml,
    'ProvisionalIdentity',
  );
  final requestSchema = ContractSchema.read(evidenceYaml, 'ArbitrationRequest');
  final mappingSchema = ContractSchema.read(evidenceYaml, 'IdentityMapping');
  final responseSchema = ContractSchema.read(
    evidenceYaml,
    'ArbitrationResponse',
  );
  final errorCodes = ContractSchema.read(errorsYaml, 'ErrorCode').schemaEnum;

  final observedAt = DateTime.utc(2026, 8, 21, 10, 15);

  Evidence fullEvidence() => Evidence.ofUrl(
    url: partUrl(kHostA, 5),
    pageTitle: 'Quiet Harbour Part 5 — Example Reader',
    hints: const PageHints(ogSiteName: 'Example Reader'),
    sourceLabel: 'Part 5',
    sourceNumber: 5,
    orderingBasis: OrderingBasis.explicitNumericIndex,
    ordinal: 5,
    language: 'en',
    observedAt: observedAt,
  );

  group('contract fidelity', () {
    test('the contract reader actually read the contract', () {
      // A guard on the guard: a reader that silently matched nothing would
      // make every assertion below pass for the wrong reason.
      expect(evidenceSchema.properties.length, greaterThanOrEqualTo(12));
      expect(evidenceSchema.required, isNotEmpty);
      expect(mappingSchema.propertyEnums['kind'], isNotEmpty);
      expect(errorCodes.length, greaterThanOrEqualTo(15));
    });

    test('every serialised Evidence field is in the contract', () {
      for (final key in fullEvidence().toJson().keys) {
        expect(
          evidenceSchema.properties,
          contains(key),
          reason: '$key is not a field of contracts/evidence.yaml Evidence',
        );
      }
    });

    test('the required Evidence fields are always present', () {
      final minimal = Evidence.ofUrl(
        url: 'https://$kHostA/',
        observedAt: observedAt,
      );
      for (final json in [minimal.toJson(), fullEvidence().toJson()]) {
        for (final field in evidenceSchema.required) {
          expect(json.keys, contains(field), reason: '$field is required');
          expect(json[field], isNotNull);
        }
      }
    });

    test('every ordering basis spells itself the contract way', () {
      final contractValues = evidenceSchema.propertyEnums['ordering_basis'];
      expect(contractValues, isNotNull);
      for (final basis in OrderingBasis.values) {
        expect(contractValues, contains(basis.name));
      }
      expect(contractValues!.length, OrderingBasis.values.length);
    });

    test('ArbitrationRequest and ProvisionalIdentity match the contract', () {
      final request = ArbitrationRequest(
        evidence: fullEvidence(),
        provisional: const ProvisionalIdentity(
          collectionId: 'c-1',
          sourceId: 's-1',
          entryId: 'e-1',
          locationId: 'l-1',
        ),
      ).toJson();

      for (final key in request.keys) {
        expect(requestSchema.properties, contains(key));
      }
      for (final field in requestSchema.required) {
        expect(request.keys, contains(field));
      }
      final provisional = request['provisional']! as Map<String, Object?>;
      for (final key in provisional.keys) {
        expect(provisionalSchema.properties, contains(key));
      }
    });

    test('an empty provisional identity is omitted, not sent empty', () {
      final json = ArbitrationRequest(
        evidence: fullEvidence(),
        provisional: const ProvisionalIdentity(),
      ).toJson();
      expect(json.keys, ['evidence']);
    });

    test('the identity and outcome vocabularies match the contract', () {
      expect(
        IdentityKind.values.map((k) => k.name).toSet(),
        mappingSchema.propertyEnums['kind']!.toSet(),
      );
      expect(
        ArbitrationOutcome.values.map((o) => o.name).toSet(),
        responseSchema.propertyEnums['outcome']!.toSet(),
      );
      for (final key in const IdentityMapping(
        kind: IdentityKind.entry,
        provisionalId: 'p',
        canonicalId: 'c',
      ).toJson().keys) {
        expect(mappingSchema.properties, contains(key));
      }
    });

    test('the refusal codes come from the shared error vocabulary', () {
      for (final code in kArbitrationRefusalCodes) {
        expect(errorCodes, contains(code));
      }
      expect(errorCodes, contains(evidenceOrdinalNeedsExplicitBasis.invariant));
    });
  });

  group('nothing is invented', () {
    test('an ordinal without an explicit numeric basis is refused', () {
      for (final basis in OrderingBasis.values) {
        if (basis == OrderingBasis.explicitNumericIndex) continue;
        expect(
          () => Evidence.ofUrl(
            url: partUrl(kHostA, 5),
            orderingBasis: basis,
            ordinal: 5,
            observedAt: observedAt,
          ),
          throwsA(
            isA<EvidenceViolation>().having(
              (e) => e.violation,
              'violation',
              evidenceOrdinalNeedsExplicitBasis,
            ),
          ),
          reason: '$basis has nothing for an ordinal to key on',
        );
      }
    });

    test('an ordinal with no ordering basis at all is refused', () {
      expect(
        () => Evidence.ofUrl(
          url: partUrl(kHostA, 5),
          ordinal: 5,
          observedAt: observedAt,
        ),
        throwsA(isA<EvidenceViolation>()),
      );
    });

    test('an ordinal under an explicit numeric index is carried', () {
      final json = fullEvidence().toJson();
      expect(json['ordering_basis'], 'explicitNumericIndex');
      expect(json['ordinal'], 5);
    });

    test('a number in the URL never becomes source_number', () {
      const url = 'https://$kHostA$kWorkPath/9912';
      // The digits are there and the frozen parser can read them — which is
      // exactly why the absence below has to be deliberate.
      expect(parseEntryNumber(url: url), 9912);

      final json = Evidence.ofUrl(
        url: url,
        sourceLabel: 'A lamp in the window',
        observedAt: observedAt,
      ).toJson();

      expect(json.containsKey('source_number'), isFalse);
      expect(json.containsKey('ordinal'), isFalse);
      expect(json['source_label'], 'A lamp in the window');
    });

    test('an underivable path key is omitted', () {
      final json = Evidence.ofUrl(
        url: 'https://$kHostA/part/5',
        observedAt: observedAt,
      ).toJson();
      expect(json.containsKey('path_key'), isFalse);
      expect(json['host'], kHostA);
    });

    test('a field the page did not offer is absent, not empty', () {
      final json = Evidence.ofUrl(
        url: partUrl(kHostA, 5),
        pageTitle: '   ',
        sourceLabel: '',
        language: '  ',
        observedAt: observedAt,
      ).toJson();
      for (final absent in [
        'page_title',
        'collection_title',
        'source_label',
        'language',
        'ordering_basis',
      ]) {
        expect(json.containsKey(absent), isFalse, reason: absent);
      }
    });

    test('there is no field for page content or an asset', () {
      const forbidden = ['body', 'html', 'text', 'content', 'images', 'assets'];
      for (final field in evidenceSchema.properties) {
        expect(forbidden, isNot(contains(field)));
      }
    });
  });

  group('the wire form', () {
    test('time is ISO-8601 UTC whatever the observation was stamped in', () {
      final local = DateTime.utc(2026, 8, 21, 10, 15).toLocal();
      final json = Evidence.ofUrl(
        url: partUrl(kHostA, 5),
        observedAt: local,
      ).toJson();
      expect(json['observed_at'], '2026-08-21T10:15:00.000Z');
    });

    test('the payload survives a JSON round trip unchanged', () {
      final json = fullEvidence().toJson();
      final decoded = jsonDecode(jsonEncode(json)) as Map<String, Object?>;
      expect(decoded['url_key'], 'https://$kHostA$kWorkPath/part-5');
      expect(decoded['path_key'], kWorkPath);
      expect(decoded['host'], kHostA);
      expect(decoded['collection_title'], 'Quiet Harbour');
      expect(decoded['source_number'], 5);
      expect(decoded['language'], 'en');
    });

    test('the keys are the ones recognition derived', () {
      final keys = RecognitionKeys.of(partUrl(kHostA, 5));
      final json = Evidence.observe(
        keys: keys,
        observedAt: observedAt,
      ).toJson();
      expect(json['url'], keys.url);
      expect(json['url_key'], keys.urlKey);
      expect(json['host'], keys.host);
      expect(json['path_key'], keys.pathKey);
    });
  });

  group('arbitration responses', () {
    test('resolved carries mappings the client can look up', () {
      final response = ArbitrationResponse.fromJson({
        'outcome': 'resolved',
        'mappings': [
          {
            'kind': 'collection',
            'provisional_id': 'local-collection',
            'canonical_id': 'server-collection',
          },
          {
            'kind': 'entry',
            'provisional_id': 'local-entry',
            'canonical_id': 'server-entry',
          },
        ],
      });

      expect(response.isResolved, isTrue);
      expect(response.mappings, hasLength(2));
      expect(
        response.canonicalFor(IdentityKind.entry, 'local-entry'),
        'server-entry',
      );
      expect(
        response.canonicalFor(IdentityKind.location, 'local-entry'),
        isNull,
      );
      expect(response.reason, isNull);
    });

    test('unresolved is an outcome and keeps its reason verbatim', () {
      final response = ArbitrationResponse.fromJson({
        'outcome': 'unresolved',
        'reason': 'conflicting_ordinals',
      });
      expect(response.isResolved, isFalse);
      expect(response.mappings, isEmpty);
      expect(response.reason, 'conflicting_ordinals');
      expect(kArbitrationRefusalCodes, contains(response.reason));
    });

    test('a refusal code this client does not know is passed through', () {
      final response = ArbitrationResponse.fromJson({
        'outcome': 'unresolved',
        'reason': 'internal',
      });
      expect(response.reason, 'internal');
      expect(errorCodes, contains('internal'));
    });

    test('an unrecognised outcome is never read as a known one', () {
      expect(
        () => ArbitrationResponse.fromJson({'outcome': 'probably'}),
        throwsA(
          isA<EvidenceViolation>().having(
            (e) => e.violation,
            'violation',
            arbitrationOutcomeUnrecognised,
          ),
        ),
      );
    });

    test('an unrecognised mapping kind is never read as a known one', () {
      expect(
        () => ArbitrationResponse.fromJson({
          'outcome': 'resolved',
          'mappings': [
            {'kind': 'folder', 'provisional_id': 'a', 'canonical_id': 'b'},
          ],
        }),
        throwsA(
          isA<EvidenceViolation>().having(
            (e) => e.violation,
            'violation',
            identityKindUnrecognised,
          ),
        ),
      );
    });
  });
}
