import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' show Divider, InkWell;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart' show SvgPicture;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/providers/local/complete_profile_provider.dart';
import 'package:pax/providers/db/participant/participant_provider.dart';
import 'package:pax/routing/routes.dart';
import 'package:pax/theming/colors.dart';
import 'package:pax/utils/country_util.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide Divider;

class CompleteProfileView extends ConsumerStatefulWidget {
  const CompleteProfileView({super.key});

  @override
  ConsumerState<CompleteProfileView> createState() =>
      _CompleteProfileViewState();
}

class _CompleteProfileViewState extends ConsumerState<CompleteProfileView> {
  DateTime? dateTime;
  String? genderValue;
  String? selectedCountry;

  Future<void> _saveProfile() async {
    if (selectedCountry == null || genderValue == null || dateTime == null) {
      return;
    }

    final viewModel = ref.read(completeProfileProvider.notifier);
    viewModel.setSaving();

    try {
      final updateData = <String, dynamic>{
        'country': selectedCountry,
        'gender': genderValue,
        'dateOfBirth': Timestamp.fromDate(dateTime!),
      };

      await ref.read(participantProvider.notifier).updateProfile(updateData);

      viewModel.setCompleted();

      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        context.go(Routes.home);
      }
    } catch (e) {
      viewModel.setError(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(completeProfileProvider);
    final participant = ref.watch(participantProvider).participant;

    final isComplete =
        selectedCountry != null && genderValue != null && dateTime != null;

    return Scaffold(
      headers: [
        AppBar(
          padding: const EdgeInsets.all(8),
          backgroundColor: PaxColors.white,
          child: Row(
            children: [
              InkWell(
                onTap: () {
                  context.pop();
                },
                child: FaIcon(FontAwesomeIcons.arrowLeftLong, size: 20, color: PaxColors.deepPurple),
              ),
              const Spacer(),
              Text(
                'Complete Your Profile',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, color: PaxColors.deepPurple),
              ),
              const Spacer(),
            ],
          ),
        ).withPadding(top: 16),
        Divider(color: PaxColors.lightGrey),
      ],
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text(
                    'Tell us about yourself',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: PaxColors.deepPurple,
                    ),
                  ).withPadding(bottom: 16),

                  // Display Name (disabled)
                  Text(
                    'Display Name',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ).withPadding(bottom: 8),
                  TextField(
                    enabled: false,
                    enableInteractiveSelection: false,
                    placeholder:
                        participant != null && participant.displayName != null
                            ? Text(
                              participant.displayName!,
                              style: TextStyle(
                                color: PaxColors.mediumPurple,
                                fontSize: 14,
                              ),
                            )
                            : null,
                    features: [],
                  ).withPadding(bottom: 24),

                  // Email (disabled)
                  Text(
                    'Email',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ).withPadding(bottom: 8),
                  TextField(
                    enabled: false,
                    enableInteractiveSelection: false,
                    keyboardType: TextInputType.emailAddress,
                    placeholder:
                        participant != null && participant.emailAddress != null
                            ? Text(
                              participant.emailAddress!,
                              style: TextStyle(
                                color: PaxColors.mediumPurple,
                                fontSize: 14,
                              ),
                            )
                            : null,
                    features: [
                      InputFeature.leading(
                        SvgPicture.asset(
                          'lib/assets/svgs/email.svg',
                          height: 20,
                          width: 20,
                        ),
                      ),
                    ],
                  ).withPadding(bottom: 24),

                  // Country
                  Text(
                    'Country',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ).withPadding(bottom: 8),
                  SizedBox(
                    width: double.infinity,
                    child: Select<String>(
                      itemBuilder: (context, item) {
                        final country =
                            CountryUtil.allCountries
                                .where((c) => c.name == item)
                                .firstOrNull;
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (country != null) ...[
                              Text(country.flag).withPadding(right: 8),
                            ],
                            Text(item),
                          ],
                        );
                      },
                      popup: (context) {
                        return SelectPopup.builder(
                          searchPlaceholder: const Text('Search country'),
                          emptyBuilder: (context) {
                            return const Center(
                              child: Text('No country found'),
                            );
                          },
                          builder: (context, searchQuery) async {
                            final allCountries = CountryUtil.allCountries;
                            final filteredCountries =
                                searchQuery == null
                                    ? allCountries
                                    : allCountries
                                        .where(
                                          (c) => CountryUtil.filterCountry(
                                            c,
                                            searchQuery.toLowerCase(),
                                          ),
                                        )
                                        .toList();
                            return SelectItemBuilder(
                              childCount:
                                  filteredCountries.isEmpty
                                      ? 0
                                      : filteredCountries.length,
                              builder: (context, index) {
                                final country = filteredCountries[index];
                                return SelectItemButton(
                                  value: country.name,
                                  child: Row(
                                    children: [
                                      Text(country.flag).withPadding(right: 8),
                                      Expanded(child: Text(country.name)),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                      onChanged: (value) {
                        setState(() => selectedCountry = value);
                      },
                      value: selectedCountry,
                      placeholder: const Text('Select a country'),
                    ),
                  ).withPadding(bottom: 24),

                  // Gender
                  Text(
                    'Gender',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ).withPadding(bottom: 8),
                  SizedBox(
                    width: double.infinity,
                    child: Select<String>(
                      disableHoverEffect: true,
                      itemBuilder: (context, item) {
                        String displayText = item;
                        if (item == 'Male') {
                          displayText = '♂️  Male';
                        } else if (item == 'Female') {
                          displayText = '♀️  Female';
                        }
                        return Text(displayText);
                      },
                      onChanged: (value) {
                        setState(() => genderValue = value);
                      },
                      value: genderValue,
                      placeholder: const Text('Select gender'),
                      popup: (context) {
                        return SelectPopup(
                          items: SelectItemList(
                            children: const [
                              SelectItemButton(
                                value: 'Male',
                                child: Text('♂️ Male'),
                              ),
                              SelectItemButton(
                                value: 'Female',
                                child: Text('♀️ Female'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ).withPadding(bottom: 24),

                  // Date of Birth
                  Text(
                    'Date of Birth',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ).withPadding(bottom: 8),
                  SizedBox(
                    width: double.infinity,
                    child: DatePicker(
                      value: dateTime,
                      mode: PromptMode.dialog,
                      placeholder: const Text('Select date'),
                      onChanged: (value) {
                        setState(() => dateTime = value);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Bottom section: button and skip link (pinned to bottom)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: PrimaryButton(
                    onPressed:
                        isComplete &&
                                profileState.step != CompleteProfileStep.saving
                            ? _saveProfile
                            : null,
                    child:
                        profileState.step == CompleteProfileStep.saving
                            ? const CircularProgressIndicator(onSurface: true)
                            : const Text('Save & Continue'),
                  ),
                ),
                if (profileState.step == CompleteProfileStep.error)
                  Text(
                    profileState.errorMessage ?? 'An error occurred',
                    style: TextStyle(color: PaxColors.red, fontSize: 14),
                    textAlign: TextAlign.center,
                  ).withPadding(top: 16, bottom: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlineButton(
                    onPressed: () => context.go(Routes.home),
                    child: Text(
                      'Skip for now',
                      style: TextStyle(color: PaxColors.darkGrey),
                    ),
                  ),
                ).withPadding(top: 8, bottom: 16),
              ],
            ).withPadding(all: 8),
        ],
      ),
    );
  }
}
