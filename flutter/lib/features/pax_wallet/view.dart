// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:flutter_svg/flutter_svg.dart';
// import 'package:pax/providers/local/pax_wallet_view_provider.dart';
// import 'package:pax/providers/analytics/analytics_provider.dart';
// import 'package:pax/providers/db/pax_wallet/pax_wallet_provider.dart';
// import 'package:pax/services/blockchain/blockchain_service.dart';
// import 'package:pax/theming/colors.dart';
// import 'package:shadcn_flutter/shadcn_flutter.dart';

// class PaxWalletView extends ConsumerStatefulWidget {
//   const PaxWalletView({super.key});

//   @override
//   ConsumerState<PaxWalletView> createState() => _PaxWalletViewState();
// }

// class _PaxWalletViewState extends ConsumerState<PaxWalletView> {
//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       _loadBalance();
//       ref.read(analyticsProvider).v2PaxWalletRouteVisited();
//     });
//   }

//   void _loadBalance() {
//     final walletState = ref.read(paxWalletProvider);
//     final eoAddress = walletState.wallet?.eoAddress;
//     if (eoAddress != null) {
//       ref.read(paxWalletViewProvider.notifier).fetchBalance(eoAddress);
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final walletState = ref.watch(paxWalletProvider);
//     final viewState = ref.watch(paxWalletViewProvider);
//     final wallet = walletState.wallet;

//     return Scaffold(
//       headers: [
//         AppBar(
//           title: const Text('PaxWallet'),
//         ),
//       ],
//       child: SafeArea(
//         child: SingleChildScrollView(
//           padding: const EdgeInsets.all(24.0),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               // Balance card
//               Container(
//                 width: double.infinity,
//                 padding: const EdgeInsets.all(24),
//                 decoration: BoxDecoration(
//                   gradient: LinearGradient(
//                     colors: [PaxColors.deepPurple, PaxColors.lilac],
//                     begin: Alignment.topLeft,
//                     end: Alignment.bottomRight,
//                   ),
//                   borderRadius: BorderRadius.circular(16),
//                 ),
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Row(
//                       children: [
//                         SvgPicture.asset(
//                           'lib/assets/svgs/wallets/pax_wallet.svg',
//                           width: 32,
//                           height: 32,
//                         ),
//                         const SizedBox(width: 12),
//                         Text(
//                           'PaxWallet',
//                           style: TextStyle(
//                             fontSize: 18,
//                             fontWeight: FontWeight.w600,
//                             color: PaxColors.white,
//                           ),
//                         ),
//                       ],
//                     ),
//                     const SizedBox(height: 20),
//                     Text(
//                       'G\$ Balance',
//                       style: TextStyle(
//                         fontSize: 14,
//                         color: PaxColors.white.withValues(alpha: 0.7),
//                       ),
//                     ),
//                     const SizedBox(height: 4),
//                     viewState.state == PaxWalletViewState.loading
//                         ? const CircularProgressIndicator()
//                         : Text(
//                           BlockchainService.formatBalance(
//                             viewState.gdBalance,
//                             1,
//                           ),
//                           style: TextStyle(
//                             fontSize: 32,
//                             fontWeight: FontWeight.bold,
//                             color: PaxColors.white,
//                           ),
//                         ),
//                   ],
//                 ),
//               ),
//               const SizedBox(height: 24),

//               // Wallet details
//               Text(
//                 'Wallet Details',
//                 style: TextStyle(
//                   fontSize: 18,
//                   fontWeight: FontWeight.bold,
//                   color: PaxColors.deepPurple,
//                 ),
//               ),
//               const SizedBox(height: 16),

//               _buildDetailRow('Address', wallet?.eoAddress ?? 'N/A'),
//               const SizedBox(height: 12),
//               _buildDetailRow(
//                 'Created',
//                 wallet?.timeCreated != null
//                     ? wallet!.timeCreated!.toDate().toString().split('.').first
//                     : 'N/A',
//               ),
//               const SizedBox(height: 12),
//               if (wallet?.logTxnHash != null)
//                 _buildDetailRow(
//                   'Registry Tx',
//                   '${wallet!.logTxnHash!.substring(0, 10)}...${wallet.logTxnHash!.substring(wallet.logTxnHash!.length - 8)}',
//                 ),

//               const SizedBox(height: 24),

//               // Refresh button
//               SizedBox(
//                 width: double.infinity,
//                 height: 48,
//                 child: OutlineButton(
//                   onPressed: _loadBalance,
//                   child: const Text('Refresh Balance'),
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildDetailRow(String label, String value) {
//     return Row(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         SizedBox(
//           width: 100,
//           child: Text(
//             label,
//             style: TextStyle(
//               fontSize: 14,
//               fontWeight: FontWeight.w600,
//               color: PaxColors.darkGrey,
//             ),
//           ),
//         ),
//         Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
//       ],
//     );
//   }
// }
