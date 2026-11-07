import 'package:flutter_test/flutter_test.dart';
import 'package:hyesread_flutter/data/text_blocks.dart';

void main() {
  test('stable paragraph indexes do not depend on typography', () {
    expect(splitTextIntoStableBlocks('第一段\n\n第二段'), ['第一段', '第二段']);
    expect(splitTextIntoStableBlocks('第一段\r\n\r\n第二段'), ['第一段', '第二段']);
  });

  test('very long paragraphs preserve surrogate pairs', () {
    final source = List.filled(1399, '甲').join() + '😀乙' +
        List.filled(200, '丙').join();
    final blocks = splitTextIntoStableBlocks(source);
    expect(blocks.join(), source);
    expect(blocks.length, greaterThan(1));
    for (final block in blocks) {
      expect(block.length, lessThanOrEqualTo(1400));
      expect(block, isNotEmpty);
      final last = block.codeUnitAt(block.length - 1);
      expect(last >= 0xD800 && last <= 0xDBFF, isFalse);
    }
  });

  test('whitespace-only content creates no paragraphs', () {
    expect(splitTextIntoStableBlocks('  \n\n  \r\n '), isEmpty);
  });
}
