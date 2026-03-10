// providers/db/pax_account_provider.dart - Updated with balance sync
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pax/models/auth/auth_state_model.dart';
import 'package:pax/models/firestore/pax_account/pax_account_model.dart';
import 'package:pax/providers/auth/auth_provider.dart';
import 'package:pax/providers/db/participant/participant_provider.dart';
import 'package:pax/repositories/firestore/pax_account/pax_account_repository.dart';
import 'package:pax/services/blockchain/blockchain_service.dart';
import 'package:pax/utils/local_db_helper.dart';

// State for the pax account provider
enum PaxAccountState {
  initial,
  loading,
  loaded,
  syncing, // New state for blockchain sync
  error,
}

// Account state model
class PaxAccountStateModel {
  final PaxAccount? account;
  final Map<int, num> balances;
  final PaxAccountState state;
  final String? errorMessage;
  final bool isBalanceSynced;

  PaxAccountStateModel({
    this.account,
    required this.balances,
    required this.state,
    this.errorMessage,
    this.isBalanceSynced = false,
  });

  // Initial state factory
  factory PaxAccountStateModel.initial() {
    return PaxAccountStateModel(state: PaxAccountState.initial, balances: {});
  }

  // Copy with method
  PaxAccountStateModel copyWith({
    PaxAccount? account,
    Map<int, num>? balances,
    PaxAccountState? state,
    String? errorMessage,
    bool? isBalanceSynced,
  }) {
    return PaxAccountStateModel(
      account: account ?? this.account,
      balances: balances ?? this.balances,
      state: state ?? this.state,
      errorMessage: errorMessage ?? this.errorMessage,
      isBalanceSynced: isBalanceSynced ?? this.isBalanceSynced,
    );
  }
}

// Pax Account notifier with new Notifier syntax
class PaxAccountNotifier extends Notifier<PaxAccountStateModel> {
  late final PaxAccountRepository _repository;

  @override
  PaxAccountStateModel build() {
    _repository = ref.watch(paxAccountRepositoryProvider);

    // Set up auth state listener
    ref.listen(authProvider, (previous, next) {
      // When auth state changes
      if (previous?.state != next.state) {
        if (next.state == AuthState.authenticated) {
          // User just signed in, sync account data
          syncWithAuthState(next);
        } else if (next.state == AuthState.unauthenticated) {
          // User signed out, clear account data
          clearAccount();
        }
      }
    });

    // Check initial auth state
    final authState = ref.read(authProvider);

    // Automatically sync with auth state if user is authenticated
    if (authState.state == AuthState.authenticated) {
      // We need to use Future.microtask because we can't use async in build
      Future.microtask(() => syncWithAuthState(authState));
    }

    return PaxAccountStateModel.initial();
  }

  // Sync Participant.accountType to "v2" when PaxAccount is V2 (fixes existing users with stale "v1").
  Future<void> _syncParticipantAccountTypeIfV2(PaxAccount? account) async {
    if (account == null || !account.isV2) return;
    final participant = ref.read(participantProvider).participant;
    if (participant == null || participant.accountType == 'v2') return;
    await ref
        .read(participantProvider.notifier)
        .updateProfile({'accountType': 'v2'});
  }

  // Sync account data with auth state
  Future<void> syncWithAuthState([AuthStateModel? authStateModel]) async {
    // Get auth state from provider if not provided
    final authState = authStateModel ?? ref.read(authProvider);

    // Skip if not authenticated
    if (authState?.state != AuthState.authenticated) {
      state = PaxAccountStateModel.initial();
      return;
    }

    try {
      // Set loading state
      state = state.copyWith(state: PaxAccountState.loading, isBalanceSynced: false);

      // Handle signup - create or get account
      final account = await _repository.handleUserSignup(authState!.user.uid);

      // Fetch balances from local DB (prefer wallet_balances for the four currencies)
      var balances = await LocalDBHelper().getWalletBalances(account.id);
      if (balances.isEmpty) {
        balances = await LocalDBHelper().getBalances(account.id);
      }

      // Update state with loaded account and balances
      state = state.copyWith(
        account: account,
        balances: balances,
        state: PaxAccountState.loaded,
        isBalanceSynced: true,
      );

      await _syncParticipantAccountTypeIfV2(account);

      // Try to fetch balances from blockchain if payout wallet exists (V1 or V2)
      if (account.payoutWalletAddress != null &&
          account.payoutWalletAddress!.isNotEmpty) {
        // Don't await this to avoid blocking the UI; silent so we stay in loaded and redirect works
        syncBalancesFromBlockchain(silent: true);
      }
    } catch (e) {
      // Handle error
      state = state.copyWith(
        state: PaxAccountState.error,
        errorMessage: e.toString(),
      );
    }
  }

  // Update balance for a token
  Future<void> updateBalance(int tokenId, num amount) async {
    final authState = ref.read(authProvider);
    try {
      if (authState.state != AuthState.authenticated || state.account == null) {
        throw Exception('User must be authenticated to update balance');
      }
      state = state.copyWith(state: PaxAccountState.loading, isBalanceSynced: false);
      await _repository.updateBalance(authState.user.uid, tokenId, amount);
      var balances = await LocalDBHelper().getWalletBalances(state.account!.id);
      if (balances.isEmpty) {
        balances = await LocalDBHelper().getBalances(state.account!.id);
      }
      state = state.copyWith(balances: balances, state: PaxAccountState.loaded, isBalanceSynced: true);
    } catch (e) {
      state = state.copyWith(
        state: PaxAccountState.error,
        errorMessage: e.toString(),
      );
    }
  }

  // Update account fields
  Future<void> updateAccount(Map<String, dynamic> data) async {
    final authState = ref.read(authProvider);
    try {
      if (authState.state != AuthState.authenticated || state.account == null) {
        throw Exception('User must be authenticated to update account');
      }
      state = state.copyWith(state: PaxAccountState.loading, isBalanceSynced: false);
      final updatedAccount = await _repository.updateAccount(
        authState.user.uid,
        data,
      );
      var balances = await LocalDBHelper().getWalletBalances(updatedAccount.id);
      if (balances.isEmpty) {
        balances = await LocalDBHelper().getBalances(updatedAccount.id);
      }
      state = state.copyWith(
        account: updatedAccount,
        balances: balances,
        state: PaxAccountState.loaded,
        isBalanceSynced: true,
      );
      await _syncParticipantAccountTypeIfV2(updatedAccount);
    } catch (e) {
      state = state.copyWith(
        state: PaxAccountState.error,
        errorMessage: e.toString(),
      );
    }
  }

  // Fetch and sync balances from blockchain
  Future<void> syncBalancesFromBlockchain({bool silent = false}) async {
    final authState = ref.read(authProvider);
    try {
      if (authState.state != AuthState.authenticated || state.account == null) {
        throw Exception('User must be authenticated to sync balances');
      }

      // Skip if refreshed too recently (within 30 seconds) based on local DB.
      final accountId = state.account!.id;
      if (accountId.isNotEmpty) {
        try {
          final info =
              await LocalDBHelper().getRefreshments(accountId);
          final lastMillis = info['accountRefreshTime'];
          if (lastMillis != null) {
            final last =
                DateTime.fromMillisecondsSinceEpoch(lastMillis);
            if (DateTime.now().difference(last) <
                const Duration(seconds: 30)) {
              return;
            }
          }
        } catch (_) {
          // If refreshments lookup fails, fall back to normal behavior.
        }
      }

      if (!silent) {
        state = state.copyWith(state: PaxAccountState.syncing, isBalanceSynced: false);
      }
      await _repository.syncBalancesFromBlockchain(authState.user.uid);
      var balances = await LocalDBHelper().getWalletBalances(state.account!.id);
      if (balances.isEmpty) {
        balances = await LocalDBHelper().getBalances(state.account!.id);
      }
      state = state.copyWith(
        balances: balances,
        state: PaxAccountState.loaded,
        isBalanceSynced: true,
      );
      if (accountId.isNotEmpty) {
        await LocalDBHelper().upsertRefreshments(
          participantId: accountId,
          accountRefreshTime: DateTime.now().millisecondsSinceEpoch,
        );
      }
    } catch (e) {
      if (silent) {
        if (kDebugMode) {
          debugPrint('Silent balance sync failed: $e');
        }
        return;
      }
      state = state.copyWith(
        state: PaxAccountState.error,
        errorMessage: e.toString(),
      );
    }
  }

  // Fetch a specific token balance from blockchain (doesn't update Firestore)
  Future<double> fetchTokenBalance(int tokenId) async {
    final authState = ref.read(authProvider);

    try {
      // Ensure user is authenticated and we have an account
      if (authState.state != AuthState.authenticated || state.account == null) {
        throw Exception('User must be authenticated to fetch token balance');
      }

      // Fetch token balance from repository
      return await _repository.fetchTokenBalance(authState.user.uid, tokenId);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error fetching token balance: $e');
      }
      return 0.0;
    }
  }

  // Get formatted balance for a token
  String getFormattedBalance(int tokenId) {
    final balance = state.balances[tokenId]?.toDouble() ?? 0.0;
    return BlockchainService.formatBalance(balance, tokenId);
  }

  // Refresh account data from Firestore
  Future<void> refreshAccount() async {
    final authState = ref.read(authProvider);

    try {
      // Ensure user is authenticated
      if (authState.state != AuthState.authenticated) {
        throw Exception('User must be authenticated to refresh account');
      }

      // Set loading state
      state = state.copyWith(state: PaxAccountState.loading, isBalanceSynced: false);

      // Get account from repository
      final account = await _repository.getAccount(authState.user.uid);

      if (account != null) {
        var balances = await LocalDBHelper().getWalletBalances(account.id);
        if (balances.isEmpty) {
          balances = await LocalDBHelper().getBalances(account.id);
        }

        // Update state with refreshed account and balances
        state = state.copyWith(
          account: account,
          balances: balances,
          state: PaxAccountState.loaded,
          isBalanceSynced: true,
        );
        await _syncParticipantAccountTypeIfV2(account);
      } else {
        // Account not found, create a new one
        await syncWithAuthState();
      }
    } catch (e) {
      // Handle error
      state = state.copyWith(
        state: PaxAccountState.error,
        errorMessage: e.toString(),
      );
    }
  }

  // Clear account data (used when signing out)
  void clearAccount() {
    state = PaxAccountStateModel.initial();
  }
}

// Provider for the pax account repository
final paxAccountRepositoryProvider = Provider<PaxAccountRepository>((ref) {
  return PaxAccountRepository();
});

// NotifierProvider for pax account state
final paxAccountProvider =
    NotifierProvider<PaxAccountNotifier, PaxAccountStateModel>(() {
      return PaxAccountNotifier();
    });

// Provider for blockchain service
final blockchainServiceProvider = Provider<BlockchainService>((ref) {
  return BlockchainService();
});
