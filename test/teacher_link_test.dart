import 'package:better_stundenplan/utils/teacher_photo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('links to the teacher anchor and marks only the name', () {
    expect(
      teacherPageUrl('GlWT', 'Erika Müller'),
      'https://start.bbs-papenburg.de/kollegium.php'
      '#kuerzel-GLWT:~:text=Erika%20M%C3%BCller',
    );
  });

  test('keeps hyphens encoded so the browser still marks the name', () {
    expect(
      teacherPageUrl('ITXY', 'Karl-Heinz Muster'),
      contains(':~:text=Karl%2DHeinz%20Muster'),
    );
  });
}
