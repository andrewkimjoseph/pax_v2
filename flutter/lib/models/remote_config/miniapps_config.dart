import 'package:flutter/foundation.dart';

@immutable
class PaxMiniApp {
  final int id;
  final String name;
  final String title;
  final String? imageURI;
  final String url;
  final bool isMiniappAvailable;

  const PaxMiniApp({
    required this.id,
    required this.name,
    required this.title,
    this.imageURI,
    required this.url,
    required this.isMiniappAvailable,
  });

  factory PaxMiniApp.fromJson(Map<String, dynamic> json) {
    return PaxMiniApp(
      id: (json['id'] is int) ? json['id'] as int : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      name: (json['name'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      imageURI: json['imageURI'] as String?,
      url: (json['url'] as String?) ?? '',
      isMiniappAvailable: json['is_miniapp_available'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'title': title,
      'imageURI': imageURI,
      'url': url,
      'is_miniapp_available': isMiniappAvailable,
    };
  }
}

@immutable
class MiniappsConfig {
  final bool areMiniappsAvailable;
  final List<PaxMiniApp> miniapps;

  const MiniappsConfig({
    required this.areMiniappsAvailable,
    required this.miniapps,
  });

  factory MiniappsConfig.fromJson(Map<String, dynamic> json) {
    final rawList = json['miniapps'];
    final List<PaxMiniApp> list = [];
    if (rawList is List) {
      for (final item in rawList) {
        if (item is Map<String, dynamic>) {
          final app = PaxMiniApp.fromJson(item);
          if (app.isMiniappAvailable) {
            list.add(app);
          }
        }
      }
    }
    return MiniappsConfig(
      areMiniappsAvailable: json['are_miniapps_available'] == true,
      miniapps: list,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'are_miniapps_available': areMiniappsAvailable,
      'miniapps': miniapps.map((e) => e.toJson()).toList(),
    };
  }
}
