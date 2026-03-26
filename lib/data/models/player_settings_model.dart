class PlayerSettings {
  final PlayerConfig player1;
  final PlayerConfig player2;
  final PlayerConfig player3;
  final DownloadSettings downloads;

  PlayerSettings({
    required this.player1,
    required this.player2,
    required this.player3,
    required this.downloads,
  });

  factory PlayerSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return PlayerSettings.defaultSettings();
    return PlayerSettings(
      player1: PlayerConfig.fromJson(json['player_1']),
      player2: PlayerConfig.fromJson(json['player_2']),
      player3: PlayerConfig.fromJson(json['player_3']),
      downloads: DownloadSettings.fromJson(json['downloads']),
    );
  }

  static PlayerSettings defaultSettings() {
    return PlayerSettings(
      player1: PlayerConfig(enabled: true, name: "المشغل الأساسي", description: "سريع ومستقر"),
      player2: PlayerConfig(enabled: true, name: "سيرفر احتياطي", description: "استخدمه في حال التقطيع"),
      player3: PlayerConfig(enabled: false, name: "مشغل يوتيوب", description: "جوده تلقائية"),
      downloads: DownloadSettings(videoEnabled: true, pdfEnabled: true),
    );
  }
}

class PlayerConfig {
  final bool enabled;
  final String name;
  final String description;

  PlayerConfig({
    required this.enabled,
    required this.name,
    required this.description,
  });

  factory PlayerConfig.fromJson(Map<String, dynamic>? json) {
    return PlayerConfig(
      enabled: json?['enabled'] ?? false,
      name: json?['name'] ?? '',
      description: json?['description'] ?? '',
    );
  }
}

class DownloadSettings {
  final bool videoEnabled;
  final bool pdfEnabled;

  DownloadSettings({
    required this.videoEnabled,
    required this.pdfEnabled,
  });

  factory DownloadSettings.fromJson(Map<String, dynamic>? json) {
    return DownloadSettings(
      videoEnabled: json?['video_enabled'] ?? false,
      pdfEnabled: json?['pdf_enabled'] ?? false,
    );
  }
}
