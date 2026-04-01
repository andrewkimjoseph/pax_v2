import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pax/models/forum_report.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/theming/colors.dart';
import 'package:pax/utils/gradient_border.dart';
import 'package:pax/utils/url_handler.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter/material.dart' show InkWell;

class PublishedReportCard extends ConsumerStatefulWidget {
  const PublishedReportCard(this.forumReports, {super.key});

  final List<ForumReport> forumReports;

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _PublishedReportCardState();
}

class _PublishedReportCardState extends ConsumerState<PublishedReportCard> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: ShapeDecoration(
        shape: GradientBorder(
          gradient: const LinearGradient(
            colors: PaxColors.orangeToPinkGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          width: 2,
          borderRadius: BorderRadius.circular(12),
        ),
        color: Colors.white,
      ),
      child: SizedBox(
        height: 200,
        child: ListView(
          scrollDirection: Axis.horizontal,
          shrinkWrap: true,
          padding: const EdgeInsets.all(8),
          children: <Widget>[
            for (final report in widget.forumReports)
              ForumReportCard(report).withPadding(right: 8),
          ],
        ),
      ),
    );
  }
}

class ForumReportCard extends ConsumerStatefulWidget {
  const ForumReportCard(this.report, {this.width, super.key});

  final ForumReport report;
  final double? width;

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _ForumReportCardState();
}

class _ForumReportCardState extends ConsumerState<ForumReportCard> {
  @override
  Widget build(BuildContext context) {
    final cardContent = Container(
      decoration: BoxDecoration(
        border: Border.all(color: PaxColors.lightLilac, width: 1),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        height: 125,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage(widget.report.coverImageURI!),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ).withPadding(right: 8),
            ),
            Expanded(
              flex: 2,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.report.title!,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            color: PaxColors.black,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ).withPadding(bottom: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.report.subtitle!,
                          style: const TextStyle(
                            fontWeight: FontWeight.normal,
                            fontSize: 12,
                            color: PaxColors.black,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ).withPadding(bottom: 4),
                  Row(
                    children: [
                      const FaIcon(
                        FontAwesomeIcons.calendarDays,
                        size: 12,
                        color: Color(0xFF737373),
                      ).withPadding(right: 4),
                      Expanded(
                        child: Text(
                          DateFormat(
                            'd MMM yyyy',
                          ).format(widget.report.timePublished!),
                          style: const TextStyle(
                            fontWeight: FontWeight.normal,
                            fontSize: 10,
                            color: Color(0xFF737373),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return InkWell(
      onTap: () {
        ref
            .read(analyticsProvider)
            .publishedReportTapped(widget.report.toMap());
        UrlHandler.launchInAppWebView(context, widget.report.postURI!);
      },
      child:
          widget.width != null
              ? SizedBox(width: widget.width, child: cardContent)
              : cardContent,
    );
  }
}
