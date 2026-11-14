import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';
import 'package:love_in_chat/service/AccountManager.dart';

const Color _brand = Colors.pinkAccent;

/// Full-screen account manager: shows saved accounts, lets the user switch,
/// add a new account, or remove one.
class AccountSwitcherScreen extends StatefulWidget {
  const AccountSwitcherScreen({super.key});

  @override
  State<AccountSwitcherScreen> createState() => _AccountSwitcherScreenState();
}

class _AccountSwitcherScreenState extends State<AccountSwitcherScreen> {
  List<SavedAccount> _accounts = [];
  String? _activeId;
  bool _loading = true;
  String? _switchingId; // which account is currently being switched to

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final accounts = await AccountManager.getAll();
    final activeId = context.read<AuthProvider>().currentUserId;
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _activeId = activeId;
      _loading = false;
    });
  }

  // ── Switch to a different saved account ───────────────────────────────────
  Future<void> _switch(SavedAccount account) async {
    if (account.userId == _activeId) return;
    setState(() => _switchingId = account.userId);

    final auth = context.read<AuthProvider>();
    final convos = context.read<ConversationProvider>();

    final ok = await auth.switchAccount(account.userId, convos.resetForAccountSwitch);

    if (!mounted) return;
    setState(() => _switchingId = null);

    if (ok) {
      // Pop all the way back to the root (HomeScreen rebuilds via Consumer).
      Navigator.of(context).popUntil((r) => r.isFirst);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Could not switch to ${account.username}. '
              'Please sign in again.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      // The session expired — reload the list (account was removed).
      await _load();
    }
  }

  // ── Add another account (opens login) ────────────────────────────────────
  Future<void> _addAccount() async {
    final auth = context.read<AuthProvider>();
    final convos = context.read<ConversationProvider>();

    // Soft-logout of the current account to free the token slots, but keep
    // the current account in the saved list so the user can switch back.
    final currentId = auth.currentUserId;
    final token = auth.accessToken;
    if (token != null && token.isNotEmpty) {
      try {
        await auth.softLogout();
      } catch (_) {}
    }
    convos.resetForAccountSwitch();

    if (!mounted) return;
    // AuthProvider.isAuthenticated is now false → main Consumer rebuilds to
    // show LoginScreen automatically, so just pop to root.
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  // ── Remove a saved account ────────────────────────────────────────────────
  Future<void> _remove(SavedAccount account) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove account?'),
        content: Text(
            'Remove ${account.username} from this device? '
            'You can sign in again to add it back.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    if (account.userId == _activeId) {
      // Logging out of the active account.
      await context.read<AuthProvider>().logout();
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
    } else {
      await AccountManager.removeAccount(account.userId);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _brand,
        foregroundColor: Colors.white,
        title: const Text('Accounts'),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Add account',
            icon: const Icon(Icons.person_add_outlined),
            onPressed: _addAccount,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _brand))
          : Column(
              children: [
                // ── Account list ─────────────────────────────────────────
                Expanded(
                  child: _accounts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.manage_accounts_outlined,
                                  size: 56,
                                  color: scheme.onSurfaceVariant),
                              const SizedBox(height: 12),
                              Text('No saved accounts',
                                  style: TextStyle(
                                      color: scheme.onSurfaceVariant)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _accounts.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, indent: 72),
                          itemBuilder: (context, i) {
                            final a = _accounts[i];
                            final isActive = a.userId == _activeId;
                            final isSwitching = _switchingId == a.userId;

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 4),
                              leading: Stack(
                                alignment: Alignment.bottomRight,
                                children: [
                                  _Avatar(
                                      name: a.username,
                                      url: a.profileImageUrl),
                                  if (isActive)
                                    Container(
                                      width: 14,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        color: Colors.green,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: scheme.surface,
                                            width: 2),
                                      ),
                                    ),
                                ],
                              ),
                              title: Text(
                                a.username,
                                style: TextStyle(
                                  fontWeight: isActive
                                      ? FontWeight.w700
                                      : FontWeight.normal,
                                  color: isActive
                                      ? _brand
                                      : scheme.onSurface,
                                ),
                              ),
                              subtitle: Text(a.email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              trailing: isSwitching
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: _brand))
                                  : isActive
                                      ? const Chip(
                                          label: Text('Active',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: _brand)),
                                          backgroundColor:
                                              Color(0x1FFF4081),
                                          side: BorderSide.none,
                                          padding: EdgeInsets.zero,
                                          labelPadding:
                                              EdgeInsets.symmetric(
                                                  horizontal: 8),
                                        )
                                      : IconButton(
                                          tooltip: 'Remove',
                                          icon: const Icon(
                                              Icons.close_rounded,
                                              size: 20),
                                          color: Colors.redAccent,
                                          onPressed: () => _remove(a),
                                        ),
                              onTap: isActive || isSwitching
                                  ? null
                                  : () => _switch(a),
                            );
                          },
                        ),
                ),

                // ── Add account button ───────────────────────────────────
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _brand,
                          side: const BorderSide(color: _brand),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _addAccount,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add another account'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ── Small avatar widget ───────────────────────────────────────────────────────
class _Avatar extends StatelessWidget {
  final String name;
  final String? url;

  const _Avatar({required this.name, this.url});

  @override
  Widget build(BuildContext context) {
    final hasUrl = url != null && url!.isNotEmpty;
    return CircleAvatar(
      radius: 24,
      backgroundColor: _brand.withValues(alpha: 0.15),
      backgroundImage: hasUrl ? NetworkImage(url!) : null,
      child: hasUrl
          ? null
          : Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                  color: _brand,
                  fontWeight: FontWeight.w700,
                  fontSize: 18),
            ),
    );
  }
}
