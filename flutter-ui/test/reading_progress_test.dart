import 'dart:io';

import 'package:archive/archive.dart';
import 'package:epub_rtl/epub_rtl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyesread_flutter/data/reading_progress.dart';

void main() {
  test('TXT progress follows exact stable text offsets, not paragraph count',
      () {
    final index = TextReadingProgress([
      '开场', '短', '长' * 96, '尾声',
    ]);
    // Being in the last paragraph is not automatically 75% read.
    expect(index.at(1, 0), closeTo(2 / 101, .00001));
    expect(index.at(2, 48), closeTo(51 / 101, .00001));
    expect(index.at(3, 0), closeTo(99 / 101, .00001));
    expect(index.at(3, 2), 1.0);
    expect(index.at(-90, -20), 0.0);
    expect(index.at(999, 999), 1.0);
    expect(TextReadingProgress(['', '']).at(1, 0), 0.0);
  });

  test('TXT reading percent keeps UTF-16 emoji anchor positions', () {
    final index = TextReadingProgress(['日🌙月', '书']);
    expect(index.at(0, 3), closeTo(3 / 5, .00001));
    expect(index.at(1, 0), closeTo(4 / 5, .00001));
  });

  test('EPUB reading percent uses blocks across chapters', () {
    const counts = [10, 30, 60];
    expect(epubProgressFromBlocks(
      const EpubLocation(spineIndex: 1, elementIndex: 15),
      counts,
    ), closeTo(.25, .00001));
    expect(epubProgressFromBlocks(
      const EpubLocation(spineIndex: 2, elementIndex: 60), counts), 1);
    expect(epubProgressFromBlocks(
      const EpubLocation(spineIndex: 0, elementIndex: 0), counts), 0);
    expect(epubProgressFromBlocks(
      const EpubLocation(spineIndex: 99, elementIndex: 999), counts), 1);
  });

  test('saved EPUB anchor recovers its percent from a real EPUB file',
      () async {
    final directory = Directory.systemTemp.createTempSync('hyes-progress-');
    final file = File('${directory.path}/book.epub');
    try {
      final archive = Archive();
      archive.addFile(ArchiveFile.string(
          'mimetype', 'application/epub+zip'));
      archive.addFile(ArchiveFile.string('META-INF/container.xml',
        '<?xml version="1.0"?><container version="1.0" '
        'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
        '<rootfiles><rootfile full-path="OEBPS/content.opf" '
        'media-type="application/oebps-package+xml"/></rootfiles>'
        '</container>'));
      archive.addFile(ArchiveFile.string('OEBPS/content.opf',
        '<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" '
        'version="3.0" unique-identifier="id"><metadata '
        'xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:identifier id="id">book-1</dc:identifier>'
        '<dc:title>进度测试</dc:title><dc:language>zh-CN</dc:language>'
        '</metadata><manifest>'
        '<item id="c0" href="c0.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>'
        '</manifest><spine><itemref idref="c0"/>'
        '<itemref idref="c1"/></spine></package>'));
      for (var i = 0; i < 2; i++) {
        archive.addFile(ArchiveFile.string('OEBPS/c$i.xhtml',
          '<?xml version="1.0"?><html '
          'xmlns="http://www.w3.org/1999/xhtml">'
          '<head><title>章节</title></head><body>'
          '<h1>第 ${i + 1} 章</h1>'
          '<p>第一段</p><p>第二段</p>'
          '</body></html>'));
      }
      await file.writeAsBytes(ZipEncoder().encode(archive));
      final weights = await epubBlockCountsFromFile(file.path);
      expect(weights, hasLength(2));
      expect(weights.every((weight) => weight >= 2), isTrue);
      final encoded = const EpubLocation(
          spineIndex: 1, elementIndex: 1, fraction: .5).encode();
      final restored = await epubProgressFromFile(file.path, encoded);
      expect(restored, isNotNull);
      expect(restored!, greaterThan(.5));
      expect(restored, lessThan(1));
      expect(await epubProgressFromFile(file.path, 'invalid'), isNull);
    } finally {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    }
  });
}
