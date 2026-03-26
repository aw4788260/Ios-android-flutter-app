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
      player1: PlayerConfig.fromJson(json['player_1'], 'player_1', 1),
      player2: PlayerConfig.fromJson(json['player_2'], 'player_2', 2),
      player3: PlayerConfig.fromJson(json['player_3'], 'player_3', 3),
      downloads: DownloadSettings.fromJson(json['downloads']),
    );
  }

  static PlayerSettings defaultSettings() {
    return PlayerSettings(
      player1: PlayerConfig(id: 'player_1', enabled: true, name: "المشغل الأساسي", description: "سريع ومستقر", order: 1),
      player2: PlayerConfig(id: 'player_2', enabled: true, name: "سيرفر احتياطي", description: "استخدمه في حال التقطيع", order: 2),
      player3: PlayerConfig(id: 'player_3', enabled: false, name: "مشغل احتياطي ٢", description: "جودة تلقائية", order: 3),
      downloads: DownloadSettings(videoEnabled: true, pdfEnabled: true),
    );
  }

  // ✅ دالة ذكية لجلب المشغلات المفعلة فقط وترتيبها حسب رقم الـ order
  List<PlayerConfig> getSortedEnabledPlayers(bool hasYoutubeId) {
    List<PlayerConfig> list = [];
    
    if (player1.enabled) list.add(player1);
    if (player2.enabled) list.add(player2);
    if (player3.enabled && hasYoutubeId) list.add(player3); // التأكد أن الفيديو يمتلك رابط يوتيوب
    
    // ترتيب القائمة تصاعدياً بناءً على قيمة order
    list.sort((a, b) => a.order.compareTo(b.order));
    
    return list;
  }
}

class PlayerConfig {
  final String id;
  final bool enabled;
  final String name;
  final String description;
  final int order; // ✅ إضافة الترتيب

  PlayerConfig({
    required this.id,
    required this.enabled,
    required this.name,
    required this.description,
    required this.order,
  });

  factory PlayerConfig.fromJson(Map<String, dynamic>? json, String id, int defaultOrder) {
    return PlayerConfig(
      id: id,
      enabled: json?['enabled'] ?? false,
      name: json?['name'] ?? '',
      description: json?['description'] ?? '',
      order: json?['order'] ?? defaultOrder,
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
