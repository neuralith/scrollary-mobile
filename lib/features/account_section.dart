/// The Settings section that signs in and out.
///
/// **The only entry point there is.** Nothing on launch, nothing modal, no
/// interstitial and no prompt on any reading, saving or organising path. A
/// person who never opens this screen never meets an account, and the app is
/// the same complete product it was before accounts existed (V2-D3).
///
/// What signing in buys is one thing: the network drain, which carries the
/// library between a person's own devices. Everything else was already theirs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_api.dart';
import '../account/account_controller.dart';
import '../account/firebase_sign_in.dart';
import '../providers.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart' show SectionLabel;

/// The ACCOUNT section, or nothing at all.
///
/// Absent entirely in a build with no service address: an account that could
/// not reach anything is not a door, it is a dead end, and the existing Sync
/// section already says what such a build does.
class AccountSection extends ConsumerStatefulWidget {
  const AccountSection({super.key});

  @override
  ConsumerState<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends ConsumerState<AccountSection> {
  AccountController? _account;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _account = ref.read(accountProvider);
    _account?.addListener(_onChanged);
  }

  @override
  void dispose() {
    _account?.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final account = _account;
    if (account == null || account.status == AccountStatus.unavailable) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('ACCOUNT'),
        if (account.isSignedIn)
          _signedInTile(context, account)
        else
          ..._signedOutTiles(context, account),
      ],
    );
  }

  Widget _signedInTile(BuildContext context, AccountController account) =>
      AccountSignedInTile(
        busy: _busy,
        onSignOut: () => _run(() => account.signOut()),
      );

  List<Widget> _signedOutTiles(
    BuildContext context,
    AccountController account,
  ) {
    final resolving = account.status == AccountStatus.resolving;
    return [
      ListTile(
        key: const ValueKey('accountSignedOut'),
        leading: const Icon(Icons.cloud_off),
        title: const Text('Not signed in'),
        subtitle: Text(
          resolving
              ? 'Checking your session…'
              : 'Everything works without an account. Sign in only if you '
                    'want your library on more than one device.',
          style: TextStyle(color: AppPalette.of(context).inkMuted),
        ),
      ),
      if (!resolving)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('accountSignInApple'),
                  onPressed: _busy
                      ? null
                      : () => _signIn(account, SignInProvider.apple),
                  icon: const Icon(Icons.apple, size: 20),
                  label: const Text('Apple'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('accountSignInGoogle'),
                  onPressed: _busy
                      ? null
                      : () => _signIn(account, SignInProvider.google),
                  icon: const Icon(Icons.g_mobiledata, size: 24),
                  label: const Text('Google'),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  Future<void> _signIn(
    AccountController account,
    SignInProvider provider,
  ) async {
    await _run(() async {
      try {
        await account.signIn(provider);
      } on SignInFailure catch (e) {
        // Cancelling is not a failure: the person changed their mind, and
        // telling them something went wrong says they did something wrong.
        if (e.cancelled) return;
        rethrow;
      }
    });
  }

  /// One sentence, saying what the app did — never what the person was trying
  /// to do, and never an opaque error string.
  void _say(String message) => ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on SignInFailure catch (e) {
      if (mounted) _say(e.message);
    } on AccountApiException catch (e) {
      if (mounted) {
        _say(
          e.unavailable
              ? 'This build has no sync service to sign in to.'
              : 'Sign-in could not be completed right now.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// The signed-in row.
///
/// Split out from [AccountSection] so what it says can be asserted without a
/// session, a service or a socket — the copy is the part that carries V2-D11
/// to the person deciding whether to sign out, and it must be testable on its
/// own.
class AccountSignedInTile extends StatelessWidget {
  const AccountSignedInTile({
    super.key,
    required this.busy,
    required this.onSignOut,
  });

  final bool busy;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: const ValueKey('accountSignedIn'),
      leading: const Icon(Icons.account_circle),
      title: const Text('Signed in'),
      subtitle: Text(
        // Never the account id: it is not something a person recognises, and
        // printing an opaque identifier in Settings is noise that looks like
        // information.
        //
        // The second sentence is V2-D11, said to the person it matters to.
        // Somebody deciding whether to sign out is deciding whether they lose
        // their library, and the answer is that they do not.
        'Your library syncs between your own devices. Signing out keeps '
        'everything on this device.',
        style: TextStyle(color: AppPalette.of(context).inkMuted),
      ),
      trailing: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : TextButton(onPressed: onSignOut, child: const Text('Sign out')),
    );
  }
}
