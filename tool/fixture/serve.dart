// Standalone fixture server, for driving the app by hand in the Simulator.
//
//   dart tool/fixture/serve.dart [port]
//   then browse to http://localhost:8099/entry/1 inside Scrollary
//
// The automated integration test does NOT need this: it serves the same
// fixture in-process so it can shut the source down mid-test.
import 'dart:io';

import 'fixture_site.dart';

Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? int.parse(args.first) : 8099;
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);

  stdout.writeln('Fixture server on http://localhost:$port/entry/1');
  stdout.writeln(
    'Entries: 1..$kEntryCount · '
    '$kContentImagesPerEntry panels each · '
    'entry $kBrokenEntry panel $kBrokenPanel returns 503 on purpose',
  );
  stdout.writeln(
    'Multi-source scenarios under /s/<site>/ · '
    'manifest at /scenarios.json',
  );

  await for (final req in server) {
    try {
      await handleFixtureRequest(req);
    } catch (e) {
      stderr.writeln('fixture error: $e');
      try {
        req.response.statusCode = 500;
        await req.response.close();
      } catch (_) {}
    }
  }
}
