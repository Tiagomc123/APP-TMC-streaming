import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'core/device/tv_detector.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/library_repository.dart';
import 'data/repositories/tmdb_repository.dart';
import 'services/stream/video_resolver_service.dart';
import 'ui/screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  MediaKit.ensureInitialized(); // libmpv
  await TvDetector.warmUp(); // define UA de TV quando aplicavel
  await LibraryRepository.instance.load();

  runApp(const TmcApp());
}

class TmcApp extends StatefulWidget {
  const TmcApp({super.key});

  @override
  State<TmcApp> createState() => _TmcAppState();
}

class _TmcAppState extends State<TmcApp> {
  late final VideoResolverService _resolver = VideoResolverService();
  late final TmdbRepository _repository = TmdbRepository();

  @override
  void dispose() {
    _resolver.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TMC',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: HomeScreen(resolver: _resolver, repository: _repository),
    );
  }
}
