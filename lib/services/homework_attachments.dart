import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class HomeworkAttachments {
  HomeworkAttachments._();

  static Future<Directory> _directory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/homework_images');
    await directory.create(recursive: true);
    return directory;
  }

  static Future<List<String>> copyPicked(Iterable<XFile> picked) async {
    final images = picked.toList();
    if (images.isEmpty) return [];
    final directory = await _directory();
    final saved = <String>[];
    var index = 0;
    for (final image in images) {
      final originalName = image.name.split('/').last.split(r'\\').last;
      final safeName = originalName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final name = safeName.isEmpty ? 'photo.jpg' : safeName;
      final target = File(
        '${directory.path}/${DateTime.now().microsecondsSinceEpoch}_'
        '${index++}_$name',
      );
      await File(image.path).copy(target.path);
      saved.add(target.path);
    }
    return saved;
  }

  static Future<void> deleteOwned(Iterable<String> paths) async {
    final directory = await _directory();
    final root = directory.absolute.path;
    for (final path in paths) {
      final file = File(path).absolute;
      if (!file.path.startsWith('$root${Platform.pathSeparator}')) continue;
      if (await file.exists()) await file.delete();
    }
  }
}
