import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Limpeza automatica do cache de rede gerado pelo player.
/// Essencial em Android TV Box com armazenamento pequeno.
class CacheService {
  CacheService._();

  /// Pastas que nunca devem ser apagadas.
  static const List<String> _protected = <String>['tmc_backup', 'perf', 'flutter_assets'];

  /// Remove arquivos antigos e, se ainda assim o diretorio passar de [maxMb],
  /// apaga os mais antigos ate caber. Devolve os bytes liberados.
  static Future<int> sweep({
    int maxMb = 320,
    Duration maxAge = const Duration(days: 7),
  }) async {
    if (kIsWeb) return 0;

    int freed = 0;
    try {
      final Directory root = await getTemporaryDirectory();
      if (!root.existsSync()) return 0;

      final DateTime limit = DateTime.now().subtract(maxAge);
      final List<File> survivors = <File>[];

      for (final FileSystemEntity entity in root.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final String path = entity.path.toLowerCase();
        if (_protected.any(path.contains)) continue;

        try {
          final FileStat stat = entity.statSync();
          if (stat.modified.isBefore(limit)) {
            freed += stat.size;
            entity.deleteSync();
          } else {
            survivors.add(entity);
          }
        } catch (_) {}
      }

      int total = 0;
      for (final File f in survivors) {
        total += _size(f);
      }

      final int cap = maxMb * 1024 * 1024;
      if (total > cap) {
        survivors.sort((File a, File b) => _modified(a).compareTo(_modified(b)));
        for (final File f in survivors) {
          if (total <= cap) break;
          final int size = _size(f);
          try {
            f.deleteSync();
          } catch (_) {}
          total -= size;
          freed += size;
        }
      }
    } catch (_) {}
    return freed;
  }

  static int _size(File f) {
    try {
      return f.statSync().size;
    } catch (_) {
      return 0;
    }
  }

  static DateTime _modified(File f) {
    try {
      return f.statSync().modified;
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }
}