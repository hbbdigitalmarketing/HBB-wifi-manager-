import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class ExpiryItem {
  final String id;
  final String name;
  final DateTime expiresAt;
  final int durationDays;
  const ExpiryItem(this.id, this.name, this.expiresAt, this.durationDays);
}

class ExpiryNotifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'hbb_expiry',
      'Fin des forfaits Wi-Fi',
      channelDescription: 'Prévient quand un forfait client va se terminer',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  static Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _ready = true;
    } catch (e) {
      debugPrint('Notifications indisponibles : $e');
    }
  }

  static Future<void> _schedule(
      int id, String title, String body, DateTime when) {
    return _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(when, tz.UTC),
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Reprogramme tout : appelée à chaque enregistrement des clients.
  static Future<void> reschedule(List<ExpiryItem> items) async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      final p = await SharedPreferences.getInstance();
      final warned = p.getStringList('hbb_warned') ?? <String>[];
      final now = DateTime.now();

      for (final it in items) {
        if (!it.expiresAt.isAfter(now)) continue;

        final base = it.id.hashCode & 0x3fffffff;
        final warnId = base;
        final endId = base | 0x40000000;

        final longPlan = it.durationDays >= 2;
        final lead =
            longPlan ? const Duration(days: 1) : const Duration(hours: 3);
        final warnAt = it.expiresAt.subtract(lead);
        final key = '${it.id}_${it.expiresAt.millisecondsSinceEpoch}';
        final when = longPlan ? 'demain' : 'dans 3 heures';

        if (warnAt.isAfter(now)) {
          await _schedule(warnId, 'Forfait bientôt terminé',
              '${it.name} : le forfait se termine $when.', warnAt);
          if (!warned.contains(key)) warned.add(key);
        } else if (!warned.contains(key)) {
          // Déjà dans la fenêtre d'alerte : on prévient une seule fois.
          await _plugin.show(warnId, 'Forfait bientôt terminé',
              '${it.name} : le forfait se termine bientôt.', _details);
          warned.add(key);
        }

        await _schedule(endId, 'Forfait terminé',
            '${it.name} : le forfait vient de se terminer.', it.expiresAt);
      }

      if (warned.length > 300) {
        warned.removeRange(0, warned.length - 300);
      }
      await p.setStringList('hbb_warned', warned);
    } catch (e) {
      debugPrint('Programmation des notifications impossible : $e');
    }
  }
}
