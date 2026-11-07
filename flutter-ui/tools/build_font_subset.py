"""Reproducibly prepare the licensed, static 600-weight app display font.

Binary output is a generated source asset. It comes from installed upstream
NotoSerifSC-VF.ttf (SIL Open Font License 1.1), not from an AI-created font.
Keeps GB2312 Chinese, all source-language glyphs, and common punctuation.
Remaining uncommon ideographs fall back to Android's installed serif.
Usage: py tools/build_font_subset.py
Requires: pip install fonttools
"""

from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools import subset

root = Path(__file__).resolve().parents[1]
source = Path('C:/Windows/Fonts/NotoSerifSC-VF.ttf')
output = root / 'assets/fonts/HyesSerifSC-SemiBold.ttf'
if not source.exists():
    raise SystemExit(f'Missing upstream licensed font: {source}')

chars = set('\n \t0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
            '，。！？；：、·《》「」『』（）【】—…～“”‘’￥%+-/\'".,:;()[]')
for lead in range(0xA1, 0xF8):
    for trail in range(0xA1, 0xFF):
        try:
            chars.add(bytes([lead, trail]).decode('gb2312'))
        except UnicodeError:
            pass

for code in (root / 'lib').rglob('*.dart'):
    chars.update(code.read_text(encoding='utf-8'))

font = TTFont(source)
font = instantiateVariableFont(font, {'wght': 600}, inplace=False)
settings = subset.Options()
settings.name_IDs = ['*']
settings.name_legacy = True
settings.layout_features = ['*']
subsetter = subset.Subsetter(options=settings)
subsetter.populate(unicodes={ord(ch) for ch in ''.join(chars)})
subsetter.subset(font)
output.parent.mkdir(parents=True, exist_ok=True)
font.save(output)
size = output.stat().st_size
if size > 15 * 1024 * 1024:
    raise SystemExit(f'Generated serif font is too large: {size} bytes')
print(f'Licensed NotoSerifSC 600 subset: {size} bytes, {len(chars)} requested glyphs')
