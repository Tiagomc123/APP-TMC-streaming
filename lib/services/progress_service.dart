import '../data/models/media_ref.dart';
import '../data/repositories/library_repository.dart';

class ProgressService {
  ProgressService._();

  static Duration startAt(MediaRef ref) => LibraryRepository.instance.positionOf(ref.key);

  static Future<void> save(MediaRef ref, Duration position, Duration duration) =>
      LibraryRepository.instance.saveProgress(ref, position, duration);

  static Future<void> complete(MediaRef ref) => LibraryRepository.instance.complete(ref);
}