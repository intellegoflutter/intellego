import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid || Platform.isIOS) {
    // Lets passive listening continue with the screen off, with controls in
    // the notification.
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.intellego.intellego.audio',
      androidNotificationChannelName: 'Audiobook playback',
      androidNotificationOngoing: true,
    );
  }
  runApp(const ProviderScope(child: IntellegoApp()));
}
