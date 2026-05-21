import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart' show InkWell;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pax/models/remote_config/goodcollective_config.dart';
import 'package:pax/theming/colors.dart';
import 'package:pax/utils/url_handler.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class ChangeGoodCollectiveCard extends ConsumerStatefulWidget {
  const ChangeGoodCollectiveCard(
    this.collective, {
    super.key,
    this.onChangeTap,
    this.fallbackRoute,
  });

  final GoodCollective collective;
  final VoidCallback? onChangeTap;
  final String? fallbackRoute;

  @override
  ConsumerState<ChangeGoodCollectiveCard> createState() =>
      _ChangeGoodCollectiveCardState();
}

class _ChangeGoodCollectiveCardState
    extends ConsumerState<ChangeGoodCollectiveCard> {
  @override
  Widget build(BuildContext context) {
    final contract = widget.collective.donationContract;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child:
              (widget.collective.coverURI ?? '').isNotEmpty
                  ? CachedNetworkImage(
                    imageUrl: widget.collective.coverURI!,
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) {
                      return SvgPicture.asset(
                        'lib/assets/svgs/goodcollective.svg',
                        width: 52,
                        height: 52,
                      );
                    },
                    placeholder: (context, url) {
                      return SvgPicture.asset(
                        'lib/assets/svgs/goodcollective.svg',
                        width: 52,
                        height: 52,
                      );
                    },
                  )
                  : SvgPicture.asset(
                    'lib/assets/svgs/goodcollective.svg',
                    width: 52,
                    height: 52,
                  ),
        ).withPadding(right: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.collective.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: PaxColors.black,
                ),
              ).withPadding(bottom: 12),
              InkWell(
                onTap:
                    () => UrlHandler.launchCustomTab(
                      context,
                      'https://goodcollective.xyz/collective/$contract',
                    ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${contract.substring(0, 20)}...',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: PaxColors.lilac,
                        decoration: TextDecoration.underline,
                        decorationColor: PaxColors.lilac,
                      ),
                    ).withPadding(right: 4),
                    const FaIcon(
                      FontAwesomeIcons.arrowUpRightFromSquare,
                      size: 10,
                      color: PaxColors.lilac,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        InkWell(
          onTap: () {
            if (widget.onChangeTap != null) {
              widget.onChangeTap!();
            } else {
              if (context.canPop()) {
                context.pop();
              } else if (widget.fallbackRoute != null &&
                  widget.fallbackRoute!.isNotEmpty) {
                context.push(widget.fallbackRoute!);
              }
            }
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                child: Row(children: [Text('Change')]).withPadding(bottom: 8),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
