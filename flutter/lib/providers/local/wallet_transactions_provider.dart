import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pax/providers/db/participant/participant_provider.dart';
import 'package:pax/services/etherscan/wallet_transactions_service.dart';
import 'package:pax/utils/local_db_helper.dart';

/// Cache-first wallet transactions. Fetches from backend only when cache is
/// stale (e.g. 5 min) or user taps refresh; does not auto-fetch when cache is empty.
class WalletTransactionsState {
  const WalletTransactionsState({
    this.transactions = const [],
    this.isRefreshing = false,
    this.errorMessage,
  });

  final List<Map<String, dynamic>> transactions;
  final bool isRefreshing;
  final String? errorMessage;

  WalletTransactionsState copyWith({
    List<Map<String, dynamic>>? transactions,
    bool? isRefreshing,
    String? errorMessage,
    bool clearError = false,
  }) {
    return WalletTransactionsState(
      transactions: transactions ?? this.transactions,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

const _staleThreshold = Duration(minutes: 5);
const _defaultPageSize = 20;

class WalletTransactionsNotifier extends Notifier<WalletTransactionsState> {
  @override
  WalletTransactionsState build() => const WalletTransactionsState();

  /// Call when the wallet view is shown with [eoAddress]. Reads from local DB
  /// first, then fetches from backend only if cache exists and is stale.
  Future<void> load(String? eoAddress) async {
    if (eoAddress == null || eoAddress.isEmpty) {
      state = const WalletTransactionsState();
      return;
    }

    final db = LocalDBHelper();
    try {
      final cached = await db.getWalletTransactions(eoAddress, limit: _defaultPageSize);
      state = state.copyWith(transactions: cached, clearError: true);
    } catch (_) {
      // Ignore DB errors; keep current state
    }

    final participantId = ref.read(participantProvider).participant?.id;
    if (participantId == null) return;

    final lastRefresh = await db.getTransactionsRefreshTime(participantId);
    // Only fetch when we have a previous refresh time and it's stale (or we have cache and it's stale).
    final isStale = lastRefresh == null
        ? false
        : DateTime.now().millisecondsSinceEpoch - lastRefresh > _staleThreshold.inMilliseconds;
    if (!isStale) return;

    await _fetchAndUpsert(eoAddress, participantId);
  }

  /// Force refresh from backend (tap-to-refresh). Ignores stale threshold.
  Future<void> refresh(String? eoAddress) async {
    if (eoAddress == null || eoAddress.isEmpty) return;

    final participantId = ref.read(participantProvider).participant?.id;
    await _fetchAndUpsert(eoAddress, participantId ?? '');
  }

  Future<void> _fetchAndUpsert(String eoAddress, String participantId) async {
    state = state.copyWith(isRefreshing: true, clearError: true);
    try {
      final response = await WalletTransactionsService().getTransactionList(
        eoAddress,
        page: 1,
        offset: _defaultPageSize,
      );
      await LocalDBHelper().upsertWalletTransactions(eoAddress, response.result);
      if (participantId.isNotEmpty) {
        await LocalDBHelper().setTransactionsRefreshTime(
          participantId,
          DateTime.now().millisecondsSinceEpoch,
        );
      }
      final updated = await LocalDBHelper().getWalletTransactions(eoAddress, limit: _defaultPageSize);
      state = state.copyWith(
        transactions: updated,
        isRefreshing: false,
        clearError: true,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('WalletTransactionsNotifier: fetch error $e');
      state = state.copyWith(
        isRefreshing: false,
        errorMessage: e.toString(),
      );
    }
  }
}

final walletTransactionsProvider =
    NotifierProvider<WalletTransactionsNotifier, WalletTransactionsState>(() {
  return WalletTransactionsNotifier();
});
