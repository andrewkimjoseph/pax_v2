import 'package:flutter/material.dart' show InkWell;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart' show SvgPicture;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/providers/local/donation_context_provider.dart';
import 'package:pax/theming/colors.dart';
import 'package:pax/utils/currency_symbol.dart';
import 'package:pax/utils/token_balance_util.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class DonateView extends ConsumerStatefulWidget {
  const DonateView({super.key});

  @override
  ConsumerState<DonateView> createState() => _DonateViewState();
}

class _DonateViewState extends ConsumerState<DonateView> {
  static const num minDonation = 500;
  final _donationAmountKey = const TextFieldKey(#amount);
  late final TextEditingController _amountController;
  num? _lastAmount;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final donationContext = ref.watch(donationContextProvider);
    final balance = donationContext?.balance ?? 0;
    final tokenId = donationContext?.tokenId ?? 1;

    if (donationContext != null && balance != _lastAmount) {
      _amountController.text =
          balance % 1 == 0 ? balance.toInt().toString() : balance.toString();
      _lastAmount = balance;
    }

    final amountValidator = ConditionalValidator((String? value) {
      if (value == null || value.isEmpty) {
        return false;
      }

      try {
        if (value.contains('.')) {
          final decimalPart = value.split('.')[1];
          if (decimalPart.length > 2) {
            final extraDecimals = decimalPart.substring(2);
            final allZeros = extraDecimals.split('').every((c) => c == '0');
            if (!allZeros || decimalPart.length > 4) {
              return false;
            }
          }
        }
        final amount = double.parse(value);
        return amount >= minDonation && amount <= balance;
      } catch (_) {
        return false;
      }
    }, message: '');

    return Scaffold(
      backgroundColor: PaxColors.deepPurple,
      headers: [
        AppBar(
          padding: const EdgeInsets.all(8),
          backgroundColor: PaxColors.deepPurple,
          child: Row(
            children: [
              InkWell(
                onTap: context.pop,
                child: const FaIcon(
                  FontAwesomeIcons.arrowLeftLong,
                  size: 20,
                  color: PaxColors.deepPurple,
                ),
              ),
              const Spacer(),
              const Text(
                'Donate',
                style: TextStyle(fontSize: 20, color: PaxColors.white),
              ),
              const Spacer(),
            ],
          ),
        ).withPadding(top: 16),
      ],
      child: Form(
        onSubmit: (context, values) {
          final rawAmount = values[_donationAmountKey];
          if (rawAmount == null || rawAmount.isEmpty) return;
          final amount = double.tryParse(rawAmount);
          if (amount == null) return;
          ref.read(donationContextProvider.notifier).setAmountToDonate(amount);
          context.push('/wallet/donate/select-goodcollective');
        },
        child: InkWell(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Enter amount',
                    style: TextStyle(fontSize: 16, color: PaxColors.white),
                  ).withPadding(right: 4),
                  const FaIcon(
                    FontAwesomeIcons.handHoldingHeart,
                    color: PaxColors.white,
                  ),
                ],
              ).withPadding(top: 16),
              const Spacer(flex: 1),
              FormField(
                label: const SizedBox.shrink(),
                key: _donationAmountKey,
                validator: amountValidator,
                showErrors: const {FormValidationMode.submitted},
                child: TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textAlign: TextAlign.center,
                  placeholder: const Text('Enter amount'),
                  style: const TextStyle(
                    fontSize: 32,
                    color: PaxColors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  border: false,
                  cursorColor: PaxColors.white,
                ).withAlign(Alignment.center),
              ).withPadding(all: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Available balance:',
                    style: TextStyle(fontSize: 12, color: PaxColors.white),
                  ).withPadding(right: 4),
                  Text(
                    TokenBalanceUtil.getLocaleFormattedAmount(balance),
                    style: const TextStyle(
                      fontSize: 16,
                      color: PaxColors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SvgPicture.asset(
                    'lib/assets/svgs/currencies/${CurrencySymbolUtil.getNameForCurrency(tokenId)}.svg',
                    height: 25,
                  ).withPadding(left: 4),
                ],
              ).withPadding(top: 8),
              const Text(
                'Minimum donation is 500 G\$',
                style: TextStyle(fontSize: 12, color: PaxColors.white),
              ).withPadding(top: 8),
              const Spacer(flex: 2),
              Container(
                width: double.infinity,
                padding: EdgeInsets.only(
                  top: 16,
                  bottom: MediaQuery.of(context).padding.bottom + 16,
                ),
                color: Colors.white,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FormErrorBuilder(
                          builder: (context, errors, child) {
                            return PrimaryButton(
                              onPressed:
                                  errors.isEmpty ? context.submitForm : null,
                              child: Text(
                                'Continue',
                                style: Theme.of(
                                  context,
                                ).typography.base.copyWith(
                                  fontWeight: FontWeight.normal,
                                  fontSize: 14,
                                  color: PaxColors.white,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
