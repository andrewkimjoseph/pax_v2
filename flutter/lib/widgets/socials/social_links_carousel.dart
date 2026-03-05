import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pax/providers/analytics/analytics_provider.dart';
import 'package:pax/theming/colors.dart';
import 'package:pax/utils/secret_constants.dart';
import 'package:pax/utils/url_handler.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter/material.dart' show InkWell;

class SocialLinksRow extends ConsumerWidget {
  const SocialLinksRow({super.key});

  static const _socials = [
    (
      icon: FontAwesomeIcons.xTwitter,
      color: PaxColors.black,
      name: 'X',
      url: 'https://x.com/thecanvassing',
    ),
    (
      icon: FontAwesomeIcons.whatsapp,
      color: PaxColors.green,
      name: 'WhatsApp',
      url: null, // resolved at runtime from secret_constants
    ),
    (
      icon: FontAwesomeIcons.telegram,
      color: Color(0xFF24A1DE),
      name: 'Telegram',
      url: null,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: PaxColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PaxColors.lightLilac, width: 1),
      ),
      child: Row(
        children: [
          FaIcon(
            FontAwesomeIcons.users,
            color: PaxColors.deepPurple,
            size: 16,
          ).withPadding(right: 8),
          Text(
            'Join the tribe!',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: PaxColors.deepPurple,
            ),
          ),
          const Spacer(),
          for (final social in _socials) ...[
            social != _socials.last
                ? _socialButton(
                  context,
                  ref,
                  icon: social.icon,
                  color: social.color,
                  name: social.name,
                  url: _resolveUrl(social.name, social.url),
                ).withPadding(right: 10)
                : _socialButton(
                  context,
                  ref,
                  icon: social.icon,
                  color: social.color,
                  name: social.name,
                  url: _resolveUrl(social.name, social.url),
                ),
          ],
        ],
      ),
    );
  }

  String _resolveUrl(String name, String? url) {
    if (url != null) return url;
    if (name == 'WhatsApp') return whatsappChannelLink;
    if (name == 'Telegram') return telegramChannelLink;
    return '';
  }

  Widget _socialButton(
    BuildContext context,
    WidgetRef ref, {
    required IconData icon,
    required Color color,
    required String name,
    required String url,
  }) {
    return InkWell(
      onTap: () {
        ref.read(analyticsProvider).joinTribeTapped({'social': name});
        UrlHandler.launchCustomTab(context, url);
      },
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(child: FaIcon(icon, color: PaxColors.white, size: 18)),
      ),
    );
  }
}
