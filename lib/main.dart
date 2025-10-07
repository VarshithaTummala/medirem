// MEDIREM — Simple Telugu Medicine Reminder
// Single alarm screen with automatic Telugu audio

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

// ---------- App bootstrap ----------
// ✅ Simple English to Telugu medicine translation
class MedicineTranslator {
  static final Map<String, String> _translations = {
    // Common medicines
    'paracetamol': 'పారాసిటమాల్',
    'aspirin': 'ఆస్పిరిన్',
    'ibuprofen': 'ఇబుప్రోఫెన్',
    'amoxicillin': 'అమోక్సిసిలిన్',
    'metformin': 'మెట్‌ఫార్మిన్',
    'omeprazole': 'ఒమిప్రజోల్',
    'atorvastatin': 'అటోర్వాస్టాటిన్',
    'amlodipine': 'అమ్లోడిపైన్',
    'lisinopril': 'లిసినోప్రిల్',
    'gabapentin': 'గాబాపెంటిన్',
    'hydrochlorothiazide': 'హైడ్రోక్లోరోథియాజైడ్',
    'sertraline': 'సెర్ట్రాలైన్',
    'montelukast': 'మాంటెలుకాస్ట్',
    'furosemide': 'ఫ్యూరోసెమైడ్',
    'prednisone': 'ప్రెడ్నిసోన్',
    // Common words
    'tablet': 'మాత్ర',
    'capsule': 'కాప్సూల్',
    'syrup': 'సిరప్',
    'medicine': 'మందు',
    'pill': 'మాత్ర',
    'drops': 'చుక్కలు',
    'injection': 'ఇంజెక్షన్',
    // Add more as needed
  };

  static String translate(String englishName) {
    final lower = englishName.toLowerCase().trim();
    
    // Check for direct translation
    if (_translations.containsKey(lower)) {
      return _translations[lower]!;
    }
    
    // Check for partial matches
    for (final entry in _translations.entries) {
      if (lower.contains(entry.key)) {
        return englishName.replaceAll(RegExp(entry.key, caseSensitive: false), entry.value);
      }
    }
    
    // If no translation found, return original with Telugu prefix
    return '$englishName మందు';
  }

  static String getBilingualName(String name) {
    final teluguName = translate(name);
    if (teluguName == name || teluguName == '$name మందు') {
      return name; // Already in Telugu or no translation
    }
    return '$name\n$teluguName'; // Show both
  }
}


final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
  await NotificationService.instance.init();
  runApp(const MediremApp());
}

/// Handles action buttons when the app is killed (background isolate).
@pragma('vm:entry-point')
Future notificationTapBackground(NotificationResponse r) async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
  
  print('🎯 BACKGROUND ACTION: ${r.actionId} received');
  
  final payload = r.payload;
  if (payload == null) return;
  
  try {
    final data = jsonDecode(payload) as Map;
    final id = data['id'] as int? ?? 0;
    final name = data['name']?.toString() ?? '';

    if (r.actionId == 'taken') {
      print('✅ BACKGROUND: TAKEN action - stopping all alarms');
      
      await AudioService.instance.stopAudio();
      
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.cancelAll();
      
      await plugin.cancel(id);
      const burstOffset = 1000000;
      const snoozeOffset = 2000000;
      final total = 30 ~/ 2;
      
      for (int n = 1; n <= total; n++) {
        await plugin.cancel(id + burstOffset + n);
        await plugin.cancel(id + snoozeOffset + burstOffset + n);
      }
      await plugin.cancel(id + snoozeOffset);
      
      await _HistStore.add(MedHistory(id, name, DateTime.now()));
      print('✅ BACKGROUND: Medicine taken and logged');
      
    } else if (r.actionId == 'snooze') {
      print('😴 BACKGROUND: SNOOZE action - rescheduling for 5 minutes');
      
      await AudioService.instance.stopAudio();
      
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.cancelAll();
      
      final snoozeTime = tz.TZDateTime.now(tz.local).add(const Duration(minutes: 5));
      const snoozeOffset = 2000000;
      final snoozeId = id + snoozeOffset;
      
      await plugin.zonedSchedule(
        snoozeId,
        'మందు వేసుకునే సమయం / Time for your medicine (Snoozed)',
        '$name (5 నిమిషాల తర్వాత)',
        snoozeTime,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'medirem_alarm_channel_v70',
            'Medicine Reminders',
            channelDescription: 'Full-screen alarm with Telugu voice',
            importance: Importance.max,
            priority: Priority.max,
            playSound: true,
            sound: const RawResourceAndroidNotificationSound('alarm_te'),
            enableVibration: true,
            enableLights: true,
            category: AndroidNotificationCategory.alarm,
            fullScreenIntent: true,
            visibility: NotificationVisibility.public,
            ticker: 'MEDIREM - మందు సమయం',
            ongoing: false,
            autoCancel: false,
            additionalFlags: Int32List.fromList([1024, 2048, 4, 128]),
            actions: [
              AndroidNotificationAction(
                'snooze',
                '5 నిమిషాలు / Snooze 5m',
                showsUserInterface: false,
                cancelNotification: false,
              ),
              AndroidNotificationAction(
                'taken',
                'తీసుకున్నాను / Taken',
                showsUserInterface: false,
                cancelNotification: true,
              ),
            ],
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: jsonEncode({
          'id': id,
          'name': name,
          'type': 'snooze',
        }),
      );
      
    } else {
      // Normal notification tap - trigger alarm screen
      print('🔊 BACKGROUND: Notification tapped - triggering alarm screen');
      AlarmTriggerService.instance.triggerAlarm(data);
    }
  } catch (e) {
    print('❌ BACKGROUND ERROR: $e');
  }
}

// ---------- Alarm Trigger Service ----------

class AlarmTriggerService {
  AlarmTriggerService._();
  static final instance = AlarmTriggerService._();

  final StreamController<Map> _alarmStreamController = StreamController<Map>.broadcast();
  
  Stream<Map> get alarmStream => _alarmStreamController.stream;

  void triggerAlarm(Map alarmData) {
    print('🚨 ALARM TRIGGER: Broadcasting alarm data to stream');
    _alarmStreamController.add(alarmData);
  }

  void dispose() {
    _alarmStreamController.close();
  }
}

// ---------- Audio Service ----------

class AudioService {
  AudioService._();
  static final instance = AudioService._();
  
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  bool _isLooping = false;

  Future<void> playTeluguReminderLoop() async {
    try {
      print('🔄 Playing Telugu reminder audio in LOOP mode');
      
      if (_isPlaying) {
        await stopAudio();
      }
      
      _isPlaying = true;
      _isLooping = true;
      
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      
      try {
        await _audioPlayer.play(AssetSource('audio/alarm_te.mp3'));
        print('✅ Playing Telugu audio in LOOP from assets');
      } catch (e) {
        print('⚠️ Assets failed, trying system alarm with repeat: $e');
        await _playSystemAlarmLoop();
      }
      
      _audioPlayer.onPlayerStateChanged.listen((PlayerState state) {
        if (state == PlayerState.completed && _isLooping) {
          print('🔄 Audio completed, restarting loop...');
          _restartLoop();
        }
      });
      
    } catch (e) {
      print('❌ Error playing Telugu audio loop: $e');
      _isPlaying = false;
      _isLooping = false;
      await _playSystemAlarmLoop();
    }
  }

  Future<void> playTeluguReminder() async {
    try {
      print('🔊 Playing Telugu reminder audio ONCE');
      
      if (_isPlaying) {
        await stopAudio();
      }
      
      _isPlaying = true;
      _isLooping = false;
      
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      
      try {
        await _audioPlayer.play(AssetSource('audio/alarm_te.mp3'));
        print('✅ Playing Telugu audio ONCE from assets');
      } catch (e) {
        print('⚠️ Assets failed, trying system alarm: $e');
        await _playSystemAlarm();
      }
      
      _audioPlayer.onPlayerComplete.listen((event) {
        _isPlaying = false;
        print('🔊 Telugu audio playback completed');
      });
      
    } catch (e) {
      print('❌ Error playing Telugu audio: $e');
      _isPlaying = false;
      await _playSystemAlarm();
    }
  }

  Future<void> _restartLoop() async {
    if (_isLooping && !_isPlaying) {
      print('🔄 Restarting Telugu audio loop...');
      await Future.delayed(const Duration(milliseconds: 100));
      await playTeluguReminderLoop();
    }
  }

  Future<void> _playSystemAlarmLoop() async {
    try {
      print('🔔 Playing system alarm sound with vibration in LOOP');
      _isPlaying = true;
      _isLooping = true;
      
      _startVibrationLoop();
    } catch (e) {
      print('❌ Error with system alarm loop: $e');
    }
  }

  void _startVibrationLoop() async {
    while (_isLooping && _isPlaying) {
      await HapticFeedback.vibrate();
      await Future.delayed(const Duration(milliseconds: 1000));
      if (!_isLooping) break;
      
      await HapticFeedback.vibrate();
      await Future.delayed(const Duration(milliseconds: 1000));
      if (!_isLooping) break;
      
      await HapticFeedback.vibrate();
      await Future.delayed(const Duration(milliseconds: 2000));
    }
  }

  Future<void> _playSystemAlarm() async {
    try {
      print('🔔 Playing system alarm sound with vibration');
      await HapticFeedback.vibrate();
      await Future.delayed(const Duration(milliseconds: 500));
      await HapticFeedback.vibrate();
      await Future.delayed(const Duration(milliseconds: 500));
      await HapticFeedback.vibrate();
    } catch (e) {
      print('❌ Error with system alarm: $e');
    }
  }

  Future<void> stopAudio() async {
    try {
      print('🔇 Stopping Telugu audio and disabling loop');
      _isLooping = false;
      
      if (_isPlaying) {
        await _audioPlayer.stop();
        _isPlaying = false;
        print('✅ Stopped Telugu audio successfully');
      }
    } catch (e) {
      print('❌ Error stopping audio: $e');
      _isPlaying = false;
      _isLooping = false;
    }
  }

  bool get isPlaying => _isPlaying;
  bool get isLooping => _isLooping;
}

// ---------- Pill Photo Service ----------

class PillPhotoService {
  PillPhotoService._();
  static final instance = PillPhotoService._();
  
  final ImagePicker _picker = ImagePicker();

  Future<String?> takePillPhoto() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      
      if (photo != null) {
        final Directory appDir = await getApplicationDocumentsDirectory();
        final String pillPhotosDir = '${appDir.path}/pill_photos';
        final Directory dir = Directory(pillPhotosDir);
        
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        
        final String fileName = 'pill_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final String savedPath = '$pillPhotosDir/$fileName';
        
        final File savedFile = File(savedPath);
        await savedFile.writeAsBytes(await photo.readAsBytes());
        
        print('✅ Pill photo saved: $savedPath');
        return savedPath;
      }
    } catch (e) {
      print('❌ Error taking pill photo: $e');
    }
    return null;
  }

  Future<String?> selectPillPhoto() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      
      if (photo != null) {
        final Directory appDir = await getApplicationDocumentsDirectory();
        final String pillPhotosDir = '${appDir.path}/pill_photos';
        final Directory dir = Directory(pillPhotosDir);
        
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        
        final String fileName = 'pill_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final String savedPath = '$pillPhotosDir/$fileName';
        
        final File savedFile = File(savedPath);
        await savedFile.writeAsBytes(await photo.readAsBytes());
        
        print('✅ Pill photo selected and saved: $savedPath');
        return savedPath;
      }
    } catch (e) {
      print('❌ Error selecting pill photo: $e');
    }
    return null;
  }

  Widget buildPillImage(String? imagePath, {double size = 100}) {
    if (imagePath == null || imagePath.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[400]!, width: 2),
        ),
        child: Icon(
          Icons.medication,
          size: size * 0.5,
          color: Colors.grey[600],
        ),
      );
    }
    
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF0FA3B1), width: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          File(imagePath),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.grey[300],
              child: Icon(
                Icons.broken_image,
                size: size * 0.5,
                color: Colors.grey[600],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ---------- Models ----------

class Medireminder {
  final int id;
  final TimeOfDay time;
  final String name;
  final bool enabled;
  final String? pillImagePath;

  const Medireminder({
    required this.id,
    required this.time,
    required this.name,
    required this.enabled,
    this.pillImagePath,
  });

  Medireminder copyWith({
    int? id,
    TimeOfDay? time,
    String? name,
    bool? enabled,
    String? pillImagePath,
  }) => Medireminder(
    id: id ?? this.id,
    time: time ?? this.time,
    name: name ?? this.name,
    enabled: enabled ?? this.enabled,
    pillImagePath: pillImagePath ?? this.pillImagePath,
  );

  Map toJson() => {
    'id': id,
    'hour': time.hour,
    'minute': time.minute,
    'name': name,
    'enabled': enabled,
    'pillImagePath': pillImagePath,
  };

  static Medireminder fromJson(Map j) => Medireminder(
    id: j['id'] as int,
    time: TimeOfDay(hour: j['hour'] as int, minute: j['minute'] as int),
    name: (j['name'] ?? j['label'] ?? '') as String,
    enabled: j['enabled'] as bool? ?? true,
    pillImagePath: j['pillImagePath'] as String?,
  );
}

class MedHistory {
  final int id;
  final String name;
  final DateTime takenAt;

  const MedHistory(this.id, this.name, this.takenAt);

  Map toJson() => {'id': id, 'name': name, 'ts': takenAt.toIso8601String()};

  static MedHistory fromJson(Map j) => MedHistory(j['id'] as int, j['name'] as String, DateTime.parse(j['ts'] as String));
}

class _DeleteRequest {
  final int id;
  _DeleteRequest(this.id);
}

// ---------- Storage ----------

class AppStore {
  static const _kRem = 'reminders_v7';
  static const _kWelcomeSeen = 'welcome_seen_v1';

  static Future<List<Medireminder>> loadReminders() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kRem);
    if (raw == null) return [];
    return (json.decode(raw) as List).map((e) => Medireminder.fromJson(e)).toList();
  }

  static Future saveReminders(List<Medireminder> items) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kRem, json.encode(items.map((e) => e.toJson()).toList()));
  }

  static Future<bool> welcomeSeen() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kWelcomeSeen) ?? false;
  }

  static Future setWelcomeSeen() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kWelcomeSeen, true);
  }
}

class _HistStore {
  static const _kHist = 'history_v2';

  static Future<List<MedHistory>> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kHist);
    if (raw == null) return [];
    return (json.decode(raw) as List).map((e) => MedHistory.fromJson(e)).toList();
  }

  static Future add(MedHistory h) async {
    final sp = await SharedPreferences.getInstance();
    final list = await load();
    list.insert(0, h);
    await sp.setString(_kHist, json.encode(list.map((e) => e.toJson()).toList()));
  }
}

// ---------- Notifications Service ----------

// ---------- ✅ ENHANCED Notifications Service with Auto Trigger ----------

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();
  
  static const String channelId = 'medirem_alarm_channel_v80';
  static const String channelName = 'Medicine Reminders';
  static const String channelDesc = 'Full-screen alarm with Telugu voice';
  static const int repeatEveryMinutes = 2;
  static const int repeatTotalMinutes = 30;
  static const int burstOffset = 1000000;
  static const int snoozeOffset = 2000000;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  Map? _pendingLaunchPayload;
  Timer? _autoTriggerTimer;

  Future init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const init = InitializationSettings(android: androidInit, iOS: iosInit);

    await _plugin.initialize(
      init,
      onDidReceiveNotificationResponse: _onTap,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp == true && details?.notificationResponse?.payload != null) {
      try {
        _pendingLaunchPayload = jsonDecode(details!.notificationResponse!.payload!) as Map;
      } catch (_) {}
    }

    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    
    try {
      final hasFullScreenPermission = await android?.requestFullScreenIntentPermission() ?? false;
      print('📱 Full-screen intent permission: $hasFullScreenPermission');
    } catch (e) {
      print('⚠️ Full-screen intent permission request failed: $e');
    }
    
    const channel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDesc,
      importance: Importance.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('alarm_te'),
      enableVibration: true,
      enableLights: true,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      showBadge: false,
    );
    
    await android?.createNotificationChannel(channel);
    print('✅ Channel created: $channelId with auto-trigger capability');
  }

  Map? takeLaunchPayload() {
    final p = _pendingLaunchPayload;
    _pendingLaunchPayload = null;
    return p;
  }

  Future requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
    
    try {
      await android?.requestFullScreenIntentPermission();
      print('✅ Full-screen intent permissions requested');
    } catch (e) {
      print('⚠️ Full-screen intent permission request failed: $e');
    }
    
    await ios?.requestPermissions(alert: true, badge: true, sound: true);
    
    print('✅ All permissions requested');
  }

  int _repeatId(int base, int n) => base + burstOffset + n;
  int _snoozeId(int base) => base + snoozeOffset;

  NotificationDetails _createNotificationDetails(String title, String body) {
    print('🔊 Creating notification with phone-off support');
  
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDesc,
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('alarm_te'),
        enableVibration: true,
        enableLights: true,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        visibility: NotificationVisibility.public,
        ticker: 'MEDIREM - మందు సమయం',
        ongoing: false,
        autoCancel: false,
        largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        // ✅ ENHANCED: More aggressive flags for phone OFF
        additionalFlags: Int32List.fromList([
          1024,      // FLAG_TURN_SCREEN_ON
          2048,      // FLAG_SHOW_WHEN_LOCKED  
          4,         // FLAG_INSISTENT - Makes sound repeat
          128,       // FLAG_KEEP_SCREEN_ON
          268435456, // FLAG_ONGOING_EVENT
          32,        // FLAG_NO_CLEAR - Prevent dismissal
          16,        // FLAG_HIGH_PRIORITY
        ]),
        actions: [
          AndroidNotificationAction(
            'snooze',
            '5 నిమిషాలు / Snooze 5m',
            showsUserInterface: false,
            cancelNotification: false,
          ),
          AndroidNotificationAction(
            'taken',
            'తీసుకున్నాను / Taken',
            showsUserInterface: false,
            cancelNotification: true,
          ),
        ],
      ),
      iOS: const DarwinNotificationDetails(
        presentSound: true,
        presentAlert: true,
        presentBadge: true,
        interruptionLevel: InterruptionLevel.critical,
        sound: 'alarm_te.mp3',
      ),
    );
  }

  // ✅ ENHANCED: Schedule with auto-trigger timer
  Future scheduleDaily({required Medireminder r}) async {
    final now = tz.TZDateTime.now(tz.local);
    var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, r.time.hour, r.time.minute);
    if (at.isBefore(now)) at = at.add(const Duration(days: 1));

    final payload = jsonEncode({
      'id': r.id, 
      'name': r.name, 
      'type': 'alarm',
      'scheduledTime': at.millisecondsSinceEpoch,
    });

    print('🔔 Scheduling AUTO-TRIGGER Telugu alarm for ${r.name} at $at');

    // Schedule the notification
    await _plugin.zonedSchedule(
      r.id,
      'మందు వేసుకునే సమయం / Time for your medicine',
      r.name,
      at,
      _createNotificationDetails('మందు వేసుకునే సమయం / Time for your medicine', r.name),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: payload,
    );

    // ✅ CRITICAL: Set up auto-trigger timer for exact time
    _scheduleAutoTrigger(r.id, r.name, at);

    await scheduleBurstAt(
      id: r.id,
      when: at,
      title: 'మందు వేసుకునే సమయం / Time for your medicine',
      body: r.name,
      payloadMap: {'id': r.id, 'name': r.name, 'type': 'burst'},
    );
  }

  // ✅ NEW: Auto-trigger mechanism
  void _scheduleAutoTrigger(int id, String name, tz.TZDateTime scheduledTime) {
    final now = DateTime.now();
    final triggerTime = scheduledTime.toLocal();
    final difference = triggerTime.difference(now);

    // If the scheduled time is in the future, set up a timer
    if (difference.inMilliseconds > 0) {
      print('🎯 Setting auto-trigger timer for ${difference.inMilliseconds}ms');
      
      _autoTriggerTimer?.cancel(); // Cancel any existing timer
      _autoTriggerTimer = Timer(difference, () {
        print('🚨 AUTO-TRIGGER ACTIVATED: Starting Telugu audio and opening alarm screen');
        _autoTriggerAlarm(id, name);
      });
    } else if (difference.inMilliseconds > -60000) { // Within last minute
      // If we're very close to the scheduled time, trigger immediately
      print('🚨 IMMEDIATE AUTO-TRIGGER: Scheduled time just passed');
      _autoTriggerAlarm(id, name);
    }
  }

  // ✅ NEW: Auto-trigger method that runs exactly at scheduled time
  Future<void> _autoTriggerAlarm(int id, String name) async {
    print('🚨 AUTO-TRIGGERING: Telugu audio + alarm screen for $name');
    
    try {
      // 1. Start Telugu audio immediately
      await AudioService.instance.playTeluguReminderLoop();
      print('✅ Telugu audio started automatically');
      
      // 2. Trigger alarm screen via stream
      final alarmData = {
        'id': id,
        'name': name,
        'type': 'auto_trigger',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      
      AlarmTriggerService.instance.triggerAlarm(alarmData);
      print('✅ Alarm screen triggered automatically');
      
      // 3. Also show a prominent notification for backup
      await _plugin.show(
        99999990 + id, // Special ID for auto-trigger notifications
        '🚨 MEDICINE TIME - మందు సమయం',
        '⏰ $name - Take your medicine now!',
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: 'Auto-triggered medicine reminder',
            importance: Importance.max,
            priority: Priority.max,
            playSound: true,
            sound: const RawResourceAndroidNotificationSound('alarm_te'),
            enableVibration: true,
            enableLights: true,
            category: AndroidNotificationCategory.alarm,
            fullScreenIntent: true,
            visibility: NotificationVisibility.public,
            ongoing: true,
            autoCancel: false,
            largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
            additionalFlags: Int32List.fromList([1024, 2048, 4, 128]),
            actions: [
              AndroidNotificationAction(
                'taken',
                '✅ తీసుకున్నాను / TAKEN',
                showsUserInterface: false,
                cancelNotification: true,
              ),
              AndroidNotificationAction(
                'snooze',
                '😴 5 నిమిషాలు / SNOOZE',
                showsUserInterface: false,
                cancelNotification: false,
              ),
            ],
          ),
        ),
        payload: jsonEncode(alarmData),
      );
      
    } catch (e) {
      print('❌ Error in auto-trigger: $e');
    }
  }

  Future scheduleBurstAt({
    required int id,
    required tz.TZDateTime when,
    required String title,
    required String body,
    required Map payloadMap,
  }) async {
    final total = repeatTotalMinutes ~/ repeatEveryMinutes;
    print('🔔 Scheduling $total Telugu burst notifications starting at $when');
    
    for (int n = 1; n <= total; n++) {
      final t = when.add(Duration(minutes: repeatEveryMinutes * n));
      final burstId = _repeatId(id, n);
      
      await _plugin.zonedSchedule(
        burstId,
        title,
        body,
        t,
        _createNotificationDetails(title, body),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: jsonEncode({...payloadMap, 'burstId': burstId}),
      );
      
      print('🔔 Scheduled Telugu burst notification $burstId at $t');
    }
  }

  Future scheduleSnoozeAlarm({
    required int id,
    required String name,
    required tz.TZDateTime snoozeTime,
  }) async {
    final snoozeId = _snoozeId(id);
    final payload = jsonEncode({'id': id, 'name': name, 'type': 'snooze'});

    print('🔔 Scheduling Telugu snooze alarm ID: $snoozeId at $snoozeTime');

    await _plugin.zonedSchedule(
      snoozeId,
      'మందు వేసుకునే సమయం / Time for your medicine (Snoozed)',
      '$name (5 నిమిషాల తర్వాత)',
      snoozeTime,
      _createNotificationDetails('మందు వేసుకునే సమయం / Time for your medicine (Snoozed)', '$name (5 నిమిషాల తర్వాత)'),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );

    // ✅ Also set auto-trigger for snooze
    _scheduleAutoTrigger(snoozeId, name, snoozeTime);

    await scheduleBurstAt(
      id: snoozeId,
      when: snoozeTime,
      title: 'మందు వేసుకునే సమయం / Time for your medicine (Snoozed)',
      body: '$name (5 నిమిషాల తర్వాత)',
      payloadMap: {'id': id, 'name': name, 'type': 'snoozeBurst'},
    );
  }

  Future cancelBurstFor(int baseId) async {
    final total = repeatTotalMinutes ~/ repeatEveryMinutes;
    print('❌ Cancelling burst notifications for base ID: $baseId');
    
    for (int n = 1; n <= total; n++) {
      final burstId = _repeatId(baseId, n);
      await _plugin.cancel(burstId);
    }
    
    final snoozeId = _snoozeId(baseId);
    await _plugin.cancel(snoozeId);
    
    for (int n = 1; n <= total; n++) {
      final snoozeBurstId = _repeatId(snoozeId, n);
      await _plugin.cancel(snoozeBurstId);
    }

    // Cancel auto-trigger notification
    await _plugin.cancel(99999990 + baseId);
  }

  Future cancelAllFor(int baseId) async {
    print('❌ Cancelling ALL notifications and auto-trigger for base ID: $baseId');
    await _plugin.cancel(baseId);
    await cancelBurstFor(baseId);
    
    // Cancel auto-trigger timer
    _autoTriggerTimer?.cancel();
    
    print('✅ All notifications and auto-trigger cancelled for ID: $baseId');
  }

  Future testInSeconds(int seconds) async {
    final when = tz.TZDateTime.now(tz.local).add(Duration(seconds: seconds));
    print('🧪 Setting Telugu test alarm with AUTO-TRIGGER for: $when');
    
    await _plugin.zonedSchedule(
      999001,
      'మందు వేసుకునే సమయం / Time for your medicine',
      'Test alarm - టెస్ట్ అలార్మ్',
      when,
      _createNotificationDetails('మందు వేసుకునే సమయం / Time for your medicine', 'Test alarm - టెస్ట్ అలార్మ్'),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: jsonEncode({"test": true, "id": 999001, "name": "Test alarm", "type": "test"}),
    );

    // ✅ CRITICAL: Set auto-trigger for test alarm too
    _scheduleAutoTrigger(999001, 'Test alarm', when);
  }

  Future rescheduleAll(List<Medireminder> items) async {
    await _plugin.cancelAll();
    _autoTriggerTimer?.cancel(); // Cancel any existing auto-trigger
    
    final List<Medireminder> itemsCopy = List.from(items);
    for (final r in itemsCopy.where((e) => e.enabled)) {
      await scheduleDaily(r: r);
    }
  }

  // ✅ ENHANCED: Handle both notification taps AND auto-triggers
  Future _onTap(NotificationResponse r) async {
    final payload = r.payload;
    if (payload == null) return;
    
    print('🎯 NOTIFICATION TAPPED OR AUTO-TRIGGERED: ${r.actionId}');
    
    try {
      final data = jsonDecode(payload) as Map;
      final id = data['id'] as int? ?? 0;
      final name = data['name']?.toString() ?? '';
      final type = data['type']?.toString() ?? '';

      if (r.actionId == 'taken') {
        print('✅ TAKEN: Medicine taken');
        await AudioService.instance.stopAudio();
        await _plugin.cancelAll();
        await cancelAllFor(id);
        await _HistStore.add(MedHistory(id, name, DateTime.now()));
        return;
      }

      if (r.actionId == 'snooze') {
        print('😴 SNOOZE: Rescheduling for 5 minutes');
        await AudioService.instance.stopAudio();
        await _plugin.cancelAll();
        final snoozeTime = tz.TZDateTime.now(tz.local).add(const Duration(minutes: 5));
        await scheduleSnoozeAlarm(id: id, name: name, snoozeTime: snoozeTime);
        return;
      }

      // ✅ ALWAYS trigger alarm screen and audio for any notification tap
      print('🚨 TRIGGERING: Telugu audio + alarm screen for any notification interaction');
      
      // Start audio if not already playing
      if (!AudioService.instance.isPlaying) {
        await AudioService.instance.playTeluguReminderLoop();
      }
      
      // Trigger alarm screen
      AlarmTriggerService.instance.triggerAlarm(data);
      
    } catch (e) {
      print('❌ ERROR in notification handling: $e');
      // Fallback: always trigger alarm
      final fallbackData = {'id': 0, 'name': 'Medicine Reminder', 'type': 'fallback'};
      await AudioService.instance.playTeluguReminderLoop();
      AlarmTriggerService.instance.triggerAlarm(fallbackData);
    }
  }

  // ✅ NEW: Dispose method to clean up timers
  void dispose() {
    _autoTriggerTimer?.cancel();
  }
}

// ---------- Main App ----------

class MediremApp extends StatefulWidget {
  const MediremApp({super.key});
  @override
  State<MediremApp> createState() => _MediremAppState();
}

class _MediremAppState extends State<MediremApp> with WidgetsBindingObserver {
  bool _welcomeSeen = true;
  List<Medireminder> _items = [];
  List<MedHistory> _history = [];
  int index = 0;
  bool _loading = true;
  StreamSubscription<Map>? _alarmSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
    _setupAlarmStream();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alarmSubscription?.cancel();
    super.dispose();
  }

  void _setupAlarmStream() {
    _alarmSubscription = AlarmTriggerService.instance.alarmStream.listen((alarmData) {
      print('🔥 STREAM TRIGGER: Opening single alarm screen');
      _openAlarmScreen(alarmData);
    });
  }

  // ✅ SIMPLIFIED: Single alarm screen opening
  Future<void> _openAlarmScreen(Map alarmData) async {
    if (appNavigatorKey.currentState == null) {
      await Future.delayed(const Duration(milliseconds: 100));
      return _openAlarmScreen(alarmData);
    }

    try {
      final medicineId = alarmData['id'] as int? ?? 0;
      final medicine = _items.firstWhere(
        (m) => m.id == medicineId,
        orElse: () => Medireminder(
          id: medicineId,
          time: TimeOfDay.now(),
          name: alarmData['name']?.toString() ?? 'Medicine',
          enabled: true,
        ),
      );
      
      // ✅ Check if alarm screen is already open
      final currentRoute = ModalRoute.of(appNavigatorKey.currentContext!);
      if (currentRoute?.settings.name == '/alarm') {
        print('⚠️ Alarm screen already open, skipping duplicate');
        return;
      }
      
      // ✅ SINGLE ALARM SCREEN ONLY
      appNavigatorKey.currentState!.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => SingleActionAlarmScreen(
            payload: alarmData,
            medicine: medicine,
          ),
          settings: const RouteSettings(name: '/alarm'),
        ),
        (route) => route.settings.name != '/alarm', // Remove any existing alarm screens
      );
      print('🚨 Single alarm screen opened');
      
    } catch (e) {
      print('❌ ERROR opening alarm screen: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.resumed) {
      _checkPendingAlarms();
    }
  }

  Future<void> _checkPendingAlarms() async {
    final p = NotificationService.instance.takeLaunchPayload();
    if (p != null) {
      print('🚨 Found pending alarm');
      await AudioService.instance.playTeluguReminderLoop();
      AlarmTriggerService.instance.triggerAlarm(p);
    }
  }

  Future _boot() async {
    _welcomeSeen = await AppStore.welcomeSeen();
    _items = await AppStore.loadReminders();
    _history = await _HistStore.load();
    setState(() => _loading = false);
    await NotificationService.instance.requestPermissions();
    await NotificationService.instance.rescheduleAll(_items);

    final p = NotificationService.instance.takeLaunchPayload();
    if (p != null) {
      print('🚨 App launched from notification');
      await AudioService.instance.playTeluguReminderLoop();
      AlarmTriggerService.instance.triggerAlarm(p);
    }
  }

  void _save() async {
    await AppStore.saveReminders(_items);
    await NotificationService.instance.rescheduleAll(_items);
    setState(() {});
  }

  // ... rest of build method stays the same
  @override
  Widget build(BuildContext context) {
    final lightScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF4CAF50),
      brightness: Brightness.light,
      background: const Color(0xFFF8F9FA),
      surface: Colors.white,
      primary: const Color(0xFF4CAF50),
      secondary: const Color(0xFF2196F3),
    );

    return MaterialApp(
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: lightScheme,
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          color: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF8F9FA),
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Color(0xFF2C3E50),
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          iconTheme: IconThemeData(color: Color(0xFF2C3E50)),
        ),
      ),
      home: _welcomeSeen
          ? Scaffold(
              appBar: AppBar(
                title: const Text('Medicine Reminder'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.volume_up_outlined),
                    onPressed: () async {
                      print('🔊 Volume button pressed');
                      await AudioService.instance.playTeluguReminder();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('🔊 Testing Telugu audio...')),
                      );
                    }
                  ),
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined),
                    onPressed: () {
                      print('🔔 Test notification button pressed');
                      NotificationService.instance.testInSeconds(5);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('🔔 Test alarm in 5 seconds!')),
                      );
                    }
                  ),
                ],
              ),
              body: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : [
                      ModernHomeScreen(
                        items: _items,
                        onToggle: (r, v) {
                          final i = _items.indexOf(r);
                          _items[i] = r.copyWith(enabled: v);
                          _save();
                        },
                        onDelete: (r) {
                          _items.remove(r);
                          NotificationService.instance.cancelAllFor(r.id);
                          _save();
                        },
                        onEdit: (r) => _navigateToAddEdit(r),
                      ),
                      ModernAddPage(onSaved: (r) {
                        _items.add(r);
                        _save();
                        setState(() => index = 0);
                      }),
                      ModernHistoryPage(history: _history),
                    ][index],
              bottomNavigationBar: _buildBottomNav(),
            )
          : ModernWelcome(onStart: () async {
              await AppStore.setWelcomeSeen();
              setState(() => _welcomeSeen = true);
            }),
    );
  }

  void _navigateToAddEdit(Medireminder? medicine) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ModernAddPage(initial: medicine)),
    );
    
    if (result != null) {
      if (result is _DeleteRequest) {
        _items.removeWhere((e) => e.id == result.id);
        NotificationService.instance.cancelAllFor(result.id);
        _save();
      } else if (result is Medireminder) {
        final i = _items.indexWhere((e) => e.id == result.id);
        if (i >= 0) _items[i] = result;
        else _items.add(result);
        _save();
      }
    }
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            offset: Offset(0, -1),
            blurRadius: 10,
          ),
        ],
      ),
      child: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFF4CAF50).withOpacity(0.1),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle),
            label: 'Add Reminder',
          ),
          NavigationDestination(
            icon: Icon(Icons.history),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
        ],
      ),
    );
  }
}


// ✅ COMPLETELY NEW: Single-Action Alarm Screen
class SingleActionAlarmScreen extends StatefulWidget {
  final Map? payload;
  final Medireminder? medicine;

  const SingleActionAlarmScreen({super.key, this.payload, this.medicine});

  @override
  State<SingleActionAlarmScreen> createState() => _SingleActionAlarmScreenState();
}

class _SingleActionAlarmScreenState extends State<SingleActionAlarmScreen> 
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _actionExecuted = false; // ✅ CRITICAL: Prevent any double execution
  
  @override
  void initState() {
    super.initState();
    
    _pulseController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut)
    );

    print('🚨 SingleActionAlarmScreen initialized');
  }

  @override
  void dispose() {
    _pulseController.dispose();
    print('🚨 SingleActionAlarmScreen disposed');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.payload?['id'] as int? ?? 0;
    final name = widget.payload?['name']?.toString() ?? 'Medicine';
    final medicine = widget.medicine;

    return PopScope(
      canPop: false, // ✅ Prevent back button
      child: Scaffold(
        backgroundColor: const Color(0xFF1A1A1A),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Top row with time and close button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 40),
                    Text(
                      TimeOfDay.now().format(context),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    IconButton(
                      onPressed: _actionExecuted ? null : () {
                        _executeCloseAction();
                      },
                      icon: Icon(
                        Icons.close,
                        color: _actionExecuted ? Colors.grey : Colors.white70,
                      ),
                    ),
                  ],
                ),
                
                const Spacer(),
                
                // Main content
                Column(
                  children: [
                    // Pulsing pill image or icon
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _pulseAnimation.value,
                          child: Container(
                            width: 150,
                            height: 150,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF4CAF50).withOpacity(0.3),
                                  blurRadius: 30,
                                  spreadRadius: 10,
                                ),
                              ],
                            ),
                            child: medicine?.pillImagePath != null
                                ? _buildPillImage(medicine!.pillImagePath!)
                                : _buildDefaultPillIcon(),
                          ),
                        );
                      },
                    ),
                    
                    const SizedBox(height: 32),
                    
                    const Text(
                      'Take Your Medicine',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    
                    const SizedBox(height: 8),
                    
                    Text(
                      name,
                      style: const TextStyle(
                        color: Color(0xFF4CAF50),
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    
                    const SizedBox(height: 8),
                    
                    const Text(
                      'మందు వేసుకునే సమయం',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 18,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Status indicator
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: _actionExecuted
                            ? Colors.grey.withOpacity(0.2)
                            : const Color(0xFF4CAF50).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _actionExecuted ? Colors.grey : const Color(0xFF4CAF50),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _actionExecuted ? Icons.check : Icons.volume_up,
                            color: _actionExecuted ? Colors.grey : const Color(0xFF4CAF50),
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _actionExecuted
                                ? 'Action Completed'
                                : (AudioService.instance.isLooping 
                                    ? 'Telugu Voice Playing...'
                                    : 'Audio Ready'),
                            style: TextStyle(
                              color: _actionExecuted ? Colors.grey : const Color(0xFF4CAF50),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const Spacer(),
                
                // Action buttons
                Column(
                  children: [
                    // TAKEN button - SINGLE ACTION ONLY
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton(
                        onPressed: _actionExecuted ? null : () {
                          _executeTakenAction(id, name);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _actionExecuted ? Colors.grey : const Color(0xFF4CAF50),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: _actionExecuted
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check, size: 24),
                                SizedBox(width: 12),
                                Text(
                                  'Completed • పూర్తయింది',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ],
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_circle, size: 24),
                                SizedBox(width: 12),
                                Text(
                                  'Taken • తీసుకున్నాను',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // SNOOZE button - SINGLE ACTION ONLY
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: OutlinedButton(
                        onPressed: _actionExecuted ? null : () {
                          _executeSnoozeAction(id, name);
                        },
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: _actionExecuted ? Colors.grey : Colors.orange,
                            width: 2,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.snooze,
                              color: _actionExecuted ? Colors.grey : Colors.orange,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _actionExecuted
                                  ? 'Completed • పూర్తయింది'
                                  : 'Snooze 5m • 5 నిమిషాలు',
                              style: TextStyle(
                                color: _actionExecuted ? Colors.grey : Colors.orange,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ✅ SINGLE EXECUTION: TAKEN action
  void _executeTakenAction(int id, String name) {
    if (_actionExecuted) {
      print('⚠️ Action already executed, ignoring');
      return;
    }
    
    setState(() => _actionExecuted = true);
    print('✅ EXECUTING TAKEN ACTION - SINGLE TIME');
    
    // Execute action asynchronously to prevent blocking UI
    Future.microtask(() async {
      try {
        await AudioService.instance.stopAudio();
        
        final plugin = FlutterLocalNotificationsPlugin();
        await plugin.cancelAll();
        await NotificationService.instance.cancelAllFor(id);
        
        await _HistStore.add(MedHistory(id, name, DateTime.now()));
        
        print('✅ Medicine taken and logged - closing in 1 second');
        
        // Small delay to show completion state
        await Future.delayed(const Duration(seconds: 1));
        
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.settings.name != '/alarm');
        }
        
      } catch (e) {
        print('❌ Error in taken action: $e');
        if (mounted) {
          setState(() => _actionExecuted = false);
        }
      }
    });
  }

  // ✅ SINGLE EXECUTION: SNOOZE action
  void _executeSnoozeAction(int id, String name) {
    if (_actionExecuted) {
      print('⚠️ Action already executed, ignoring');
      return;
    }
    
    setState(() => _actionExecuted = true);
    print('😴 EXECUTING SNOOZE ACTION - SINGLE TIME');
    
    // Execute action asynchronously to prevent blocking UI
    Future.microtask(() async {
      try {
        await AudioService.instance.stopAudio();
        
        final plugin = FlutterLocalNotificationsPlugin();
        await plugin.cancelAll();
        
        final snoozeTime = tz.TZDateTime.now(tz.local).add(const Duration(minutes: 5));
        await NotificationService.instance.scheduleSnoozeAlarm(
          id: id,
          name: name,
          snoozeTime: snoozeTime,
        );
        
        print('😴 Snooze scheduled - closing in 1 second');
        
        // Small delay to show completion state
        await Future.delayed(const Duration(seconds: 1));
        
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.settings.name != '/alarm');
        }
        
      } catch (e) {
        print('❌ Error in snooze action: $e');
        if (mounted) {
          setState(() => _actionExecuted = false);
        }
      }
    });
  }

  // ✅ SINGLE EXECUTION: CLOSE action
  void _executeCloseAction() {
    if (_actionExecuted) return;
    
    setState(() => _actionExecuted = true);
    print('❌ EXECUTING CLOSE ACTION - SINGLE TIME');
    
    Future.microtask(() async {
      await AudioService.instance.stopAudio();
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.settings.name != '/alarm');
      }
    });
  }

  Widget _buildPillImage(String imagePath) {
    return Container(
      width: 150,
      height: 150,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: const Color(0xFF4CAF50), width: 4),
      ),
      child: ClipOval(
        child: Image.file(
          File(imagePath),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildDefaultPillIcon(),
        ),
      ),
    );
  }

  Widget _buildDefaultPillIcon() {
    return Container(
      width: 150,
      height: 150,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
      ),
      child: const Icon(
        Icons.medication_liquid,
        size: 80,
        color: Color(0xFF4CAF50),
      ),
    );
  }
}

class ModernWelcome extends StatelessWidget {
  final VoidCallback onStart;
  const ModernWelcome({super.key, required this.onStart});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Large pill icon
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.medication_liquid,
                    size: 60,
                    color: Color(0xFF4CAF50),
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Medicine Reminder',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2C3E50),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'మందు రిమైండర్',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF34495E),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Never forget your medicine again!\nమందు మర్చిపోవద్దు ఇకపై!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 48),
                // Feature highlights
                _buildFeatureItem(Icons.notifications_active, 'Smart Telugu Alerts', 'తెలుగు అలర్ట్‌లు'),
                const SizedBox(height: 16),
                _buildFeatureItem(Icons.camera_alt, 'Pill Photos', 'మందుల ఫోటోలు'),
                const SizedBox(height: 16),
                _buildFeatureItem(Icons.volume_up, 'Auto Voice Reminders', 'స్వయంచాలక వాయిస్ రిమైండర్‌లు'),
              ],
            ),
          ),
        ),
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.all(24),
          child: ElevatedButton(
            onPressed: onStart,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: const Text(
              'Get Started • ప్రారంభించండి',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      );

  Widget _buildFeatureItem(IconData icon, String title, String subtitle) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF4CAF50).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFF4CAF50), size: 24),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          ],
        ),
      ],
    );
  }
}

// ---------- ✅ MODERN Home Screen ----------

class ModernHomeScreen extends StatelessWidget {
  final List<Medireminder> items;
  final void Function(Medireminder, bool) onToggle;
  final void Function(Medireminder) onDelete;
  final void Function(Medireminder) onEdit;

  const ModernHomeScreen({
    super.key,
    required this.items,
    required this.onToggle,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header section
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Today\'s Medications',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C3E50),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'నేటి మందులు',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF7F8C8D),
                ),
              ),
              const SizedBox(height: 16),
              _buildStatusCard(items),
            ],
          ),
        ),
        
        // Medicine list
        Expanded(
          child: items.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final medicine = items[index];
                    return _buildMedicineCard(context, medicine);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildStatusCard(List<Medireminder> items) {
    final activeCount = items.where((m) => m.enabled).length;
    final totalCount = items.length;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4CAF50), Color(0xFF2E7D32)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.medical_services, color: Colors.white, size: 32),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$activeCount Active Reminders',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '$totalCount total • $activeCount active',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.medication_outlined,
              size: 50,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'No medication reminders yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2C3E50),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'ఇంకా మందుల రిమైండర్‌లు లేవు',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF7F8C8D),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Tap "Add Reminder" to get started',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF7F8C8D),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicineCard(BuildContext context, Medireminder medicine) {
    final hh = medicine.time.hour.toString().padLeft(2, '0');
    final mm = medicine.time.minute.toString().padLeft(2, '0');
    final timeString = '$hh:$mm';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => onEdit(medicine),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Pill image or icon
              PillPhotoService.instance.buildPillImage(
                medicine.pillImagePath,
                size: 60,
              ),
              const SizedBox(width: 16),
              
              // Medicine details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      MedicineTranslator.getBilingualName(medicine.name),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2C3E50),
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          timeString,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: medicine.enabled 
                                ? const Color(0xFF4CAF50).withOpacity(0.1)
                                : Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            medicine.enabled ? 'ACTIVE' : 'PAUSED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: medicine.enabled 
                                  ? const Color(0xFF4CAF50)
                                  : Colors.grey[600],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.volume_up,
                          size: 14,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Telugu Voice Alert',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Toggle switch and menu
              Column(
                children: [
                  Switch.adaptive(
                    value: medicine.enabled,
                    onChanged: (v) => onToggle(medicine, v),
                    activeColor: const Color(0xFF4CAF50),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'delete') {
                        _showDeleteDialog(context, medicine);
                      }
                    },
                    itemBuilder: (context) => [
                  
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                    child: Icon(Icons.more_vert, color: Colors.grey[400]),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, Medireminder medicine) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Reminder'),
        content: Text('Delete reminder for ${medicine.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onDelete(medicine);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ---------- ✅ MODERN Add/Edit Medicine Page ----------

class ModernAddPage extends StatefulWidget {
  final Medireminder? initial;
  final ValueChanged<Medireminder>? onSaved;

  const ModernAddPage({super.key, this.initial, this.onSaved});

  @override
  State<ModernAddPage> createState() => _ModernAddPageState();
}

class _ModernAddPageState extends State<ModernAddPage> {
  final _form = GlobalKey<FormState>();
  late TextEditingController nameCtrl;
  TimeOfDay _time = const TimeOfDay(hour: 8, minute: 0);
  bool _enabled = true;
  String? _pillImagePath;
  String _recurrence = 'Daily';

  @override
  void initState() {
    super.initState();
    nameCtrl = TextEditingController(text: widget.initial?.name ?? '');
    _time = widget.initial?.time ?? TimeOfDay.now();
    _enabled = widget.initial?.enabled ?? true;
    _pillImagePath = widget.initial?.pillImagePath;
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Reminder' : 'Set Reminder'),
        elevation: 0,
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Pill photo section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Medicine Photo',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2C3E50),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'మందు ఫోటో',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF7F8C8D),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        PillPhotoService.instance.buildPillImage(_pillImagePath, size: 80),
                        const SizedBox(width: 16),
                        Column(
                          children: [
                            ElevatedButton.icon(
                              onPressed: _takePillPhoto,
                              icon: const Icon(Icons.camera_alt, size: 18),
                              label: const Text('Take Photo'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4CAF50),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: _selectPillPhoto,
                              icon: const Icon(Icons.photo_library, size: 18),
                              label: const Text('Gallery'),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Medicine name
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Medication Name',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2C3E50),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'మందు పేరు',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF7F8C8D),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: nameCtrl,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter medicine name' : null,
                      decoration: InputDecoration(
                        hintText: 'e.g., Paracetamol, పారాసిటమాల్',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF4CAF50)),
                        ),
                        contentPadding: const EdgeInsets.all(16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Time selection
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Time',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2C3E50),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'సమయం',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF7F8C8D),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: _selectTime,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.access_time, color: Color(0xFF4CAF50)),
                            const SizedBox(width: 12),
                            Text(
                              _time.format(context),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Simple recurrence display (no complex functionality)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Recurrence',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2C3E50),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'పునరావృతం',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF7F8C8D),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _buildSimpleRecurrenceOption('Daily', 'ప్రతిరోజు', Icons.today, Colors.blue),
                        const SizedBox(width: 12),
                        _buildSimpleRecurrenceOption('Weekly', 'వారానికి', Icons.calendar_view_week, Colors.orange),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Enable/Disable
            Card(
              child: SwitchListTile(
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
                title: const Text(
                  'Enable Reminder',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('రిమైండర్ ఆన్ చేయండి'),
                activeColor: const Color(0xFF4CAF50),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Save button
            ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: Text(
                isEdit ? 'Update Reminder' : 'Set Reminder',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            
            if (isEdit) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => Navigator.of(context).pop(_DeleteRequest(widget.initial!.id)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  side: const BorderSide(color: Colors.red),
                ),
                label: const Text('Delete • తొలగించు', style: TextStyle(color: Colors.red)),
              ),
            ],
            
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSimpleRecurrenceOption(String value, String translation, IconData icon, Color color) {
    final isSelected = _recurrence == value;
    
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _recurrence = value),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.1) : Colors.grey[50],
            border: Border.all(
              color: isSelected ? color : Colors.grey[300]!,
              width: isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? color : Colors.grey[600],
                size: 24,
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isSelected ? color : Colors.grey[700],
                  fontSize: 12,
                ),
              ),
              Text(
                translation,
                style: TextStyle(
                  color: isSelected ? color : Colors.grey[500],
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _takePillPhoto() async {
    final imagePath = await PillPhotoService.instance.takePillPhoto();
    if (imagePath != null) {
      setState(() => _pillImagePath = imagePath);
    }
  }

  Future<void> _selectPillPhoto() async {
    final imagePath = await PillPhotoService.instance.selectPillPhoto();
    if (imagePath != null) {
      setState(() => _pillImagePath = imagePath);
    }
  }

  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _time,
    );
    if (picked != null) {
      setState(() => _time = picked);
    }
  }

  void _save() {
    if (!_form.currentState!.validate()) return;

    final r = (widget.initial ??
            Medireminder(
              id: DateTime.now().millisecondsSinceEpoch.remainder(100000000),
              time: _time,
              name: nameCtrl.text.trim(),
              enabled: _enabled,
            ))
        .copyWith(
          time: _time,
          name: nameCtrl.text.trim(),
          enabled: _enabled,
          pillImagePath: _pillImagePath,
        );

    if (widget.onSaved != null) {
      widget.onSaved!(r);
      nameCtrl.clear();
      _enabled = true;
      _pillImagePath = null;
      setState(() {});
    } else {
      Navigator.of(context).pop(r);
    }
  }
}

// ---------- ✅ MODERN History Page ----------

class ModernHistoryPage extends StatelessWidget {
  final List<MedHistory> history;

  const ModernHistoryPage({super.key, required this.history});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MedHistory>>(
      future: _HistStore.load(),
      builder: (context, snapshot) {
        final historyList = snapshot.data ?? [];
        
        return Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Medicine History',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2C3E50),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'మందుల చరిత్ర',
                    style: TextStyle(
                      fontSize: 16,
                      color: Color(0xFF7F8C8D),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildStatsCard(historyList),
                ],
              ),
            ),
            
            // History list
            Expanded(
              child: historyList.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: historyList.length,
                      itemBuilder: (context, index) {
                        final item = historyList[index];
                        return _buildHistoryCard(item, index == 0);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatsCard(List<MedHistory> historyList) {
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final todayCount = historyList.where((h) => h.takenAt.isAfter(todayStart)).length;
    final totalCount = historyList.length;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4CAF50), Color(0xFF2E7D32)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.history, color: Colors.white, size: 32),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$todayCount Taken Today',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '$totalCount total doses taken',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.history,
              size: 50,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'No history yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2C3E50),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'ఇంకా చరిత్ర లేదు',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF7F8C8D),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Medicine history will appear here\nafter you start taking medicines',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF7F8C8D),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(MedHistory item, bool isLatest) {
    final time = TimeOfDay.fromDateTime(item.takenAt);
    final dateStr = '${item.takenAt.day}/${item.takenAt.month}/${item.takenAt.year}';
    final timeStr = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: isLatest 
              ? Border.all(color: const Color(0xFF4CAF50), width: 2)
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Status icon
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: Color(0xFF4CAF50),
                  size: 24,
                ),
              ),
              
              const SizedBox(width: 16),
              
              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2C3E50),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$dateStr at $timeStr',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    if (isLatest) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'LATEST',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF4CAF50),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              
              // Time ago
              Text(
                _getTimeAgo(item.takenAt),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
}
