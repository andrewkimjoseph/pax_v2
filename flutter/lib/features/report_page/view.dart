import 'package:flutter/material.dart' show InkWell;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_svg/svg.dart' show SvgPicture;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/theming/colors.dart';

class ReportPageView extends StatefulWidget {
  const ReportPageView(this.reportLink, {super.key});

  final String reportLink;

  @override
  State<ReportPageView> createState() => _ReportPageViewState();
}

class _ReportPageViewState extends State<ReportPageView> {
  bool isLoading = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      headers: [
        AppBar(
          padding: EdgeInsets.all(8),
          backgroundColor: PaxColors.white,
          child: Row(
            children: [
              InkWell(
                onTap: () {
                  context.pop();
                },
                child: FaIcon(
                  FontAwesomeIcons.arrowLeftLong,
                  size: 20,
                  color: PaxColors.deepPurple,
                ),
              ),
              Spacer(),

              SvgPicture.asset('lib/assets/svgs/canvassing.svg', height: 24),
              Spacer(),
            ],
          ),
        ).withPadding(top: 16),
        Divider(color: PaxColors.lightGrey),
      ],
      child: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(widget.reportLink)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              useWideViewPort: true,
            ),
            onLoadStart: (controller, url) {
              setState(() {
                isLoading = true;
              });
            },
            onLoadStop: (controller, url) {
              setState(() {
                isLoading = false;
              });
            },
          ),
          if (isLoading) Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
