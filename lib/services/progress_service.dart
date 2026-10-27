import '../data/models/media_ref.dart';
import '../data/repositories/library_repository.dart';

/// Fachada de progresso. Guarda o exato milissegundo em que o usuario parou.
class ProgressService {
  ProgressService._();

  static Duration startAt(MediaRef ref) =>
      LibraryRepository.instance.positionOf(ref.key);

  static Future<void> save(MediaRef ref, Duration position, Duration duration) =>
      LibraryRepository.instance.saveProgress(ref, position, duration);

  static Future<void> complete(MediaRef ref) =>
      LibraryRepository.instance.complete(ref);

  /// Registra a abertura do titulo no historico geral.
  static Future<void> touch(MediaRef ref) =>
      LibraryRepository.instance.addHistory(
        ref,
        LibraryRepository.instance.positionOf(ref.key),
        Duration.zero,
      );

  static String stamp(Duration d) {
    final int h = d.inHours;
    final String m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final String s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  static String resumeLabel(Duration d) => 'CONTINUAR DE ${stamp(d)}';
}