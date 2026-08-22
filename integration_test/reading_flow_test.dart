///
/// TODO(H-lane): this suite drove the retired V1 flows (queue/save-run/check
/// UI). Rebuild it over the V2 surfaces — shelf, collection screen, V2 save
/// queue, SourceCheck — keeping every scenario named in the original header.
/// The original body is in git history at the cutover commits.
library;

import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Intentionally empty until the H-lane rebuild: a device suite that
  // pretended to pass against deleted screens would be worse than an honest
  // placeholder.
}
