import 'package:flutter/material.dart' show Divider, InkWell;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/data/forum_reports.dart';
import 'package:pax/theming/colors.dart';
import 'package:pax/widgets/published_reports_card.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide Divider;

class ReportsView extends ConsumerWidget {
  const ReportsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      headers: [
        AppBar(
          padding: EdgeInsets.all(8),
          backgroundColor: PaxColors.white,
          child: Row(
            children: [
              InkWell(
                onTap: () => context.pop(),
                child: FaIcon(FontAwesomeIcons.arrowLeftLong, size: 20, color: PaxColors.deepPurple),
              ),
              const Spacer(),
              Text(
                'Published Reports',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, color: PaxColors.deepPurple),
              ).withPadding(right: 16),
              const Spacer(),
            ],
          ),
        ).withPadding(top: 16, horizontal: 8),
        Divider(color: PaxColors.lightGrey),
      ],
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(8, 0, 8, 24),
        itemCount: forumReports.length,
        itemBuilder: (context, index) {
          return ForumReportCard(
            forumReports[index],
          ).withPadding(bottom: index < forumReports.length - 1 ? 8 : 0);
        },
      ),
    );
  }
}
