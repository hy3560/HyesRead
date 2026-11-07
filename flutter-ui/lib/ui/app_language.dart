import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Interface strings belong to the application, not to books.
/// Interface strings are separate from book metadata and content.
enum HyesLanguage {
  chinese('zh', '简体中文'),
  english('en', 'English');

  const HyesLanguage(this.code, this.label);
  final String code;
  final String label;

  static HyesLanguage parse(String? code) =>
      code == 'en' ? english : chinese;
}

class HyesLanguagePreference {
  const HyesLanguagePreference._();
  static const key = 'hyes.ui.language';

  static HyesLanguage read(SharedPreferences preferences) =>
      HyesLanguage.parse(preferences.getString(key));

  static Future<bool> save(
      SharedPreferences preferences, HyesLanguage value) =>
      preferences.setString(key, value.code);
}

class HyesLanguageScope extends InheritedWidget {
  const HyesLanguageScope({
    super.key, required this.language, required super.child,
  });

  final HyesLanguage language;

  static HyesLanguage of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HyesLanguageScope>()
          ?.language ?? HyesLanguage.chinese;

  @override
  bool updateShouldNotify(HyesLanguageScope oldWidget) =>
      language != oldWidget.language;
}

class HyesCopy {
  const HyesCopy(this.language);
  final HyesLanguage language;

  bool get isEnglish => language == HyesLanguage.english;

  String tr(String original) => isEnglish
      ? (_english[original] ?? original) : original;

  String chapter(int number, {int? total}) => isEnglish
      ? 'Chapter $number${total == null ? '' : ' of $total'}'
      : '第 $number 章${total == null ? '' : ' · 共 $total 章'}';

  String bookCount(int number) => isEnglish
      ? '$number ${number == 1 ? 'book' : 'books'}'
      : '$number 本';

  String progress(double fraction) {
    final percent = (fraction.clamp(0.0, 1.0) * 100).round();
    return isEnglish ? '$percent% read' : '已读 $percent%';
  }

  static const _english = <String, String>{
    '续读': 'Continue',
    '书架': 'Library',
    '记录': 'History',
    '设置': 'Settings',
    '继续阅读': 'Continue reading',
    '我的书架': 'My library',
    '阅读记录': 'Reading history',
    '暂无阅读记录': 'No reading history',
    '我的阅读': 'My reading',
    '书房': 'Library',
    '正在阅读': 'Now reading',
    '上次阅读': 'Last read',
    '上次读到': 'Last reached',
    '浏览书架': 'Browse library',
    '浏览完整书架': 'Browse all books',
    '导入书籍': 'Import books',
    '导入': 'Import',
    '添加文件': 'Add a book',
    '添一本新书': 'Add a new book',
    '去书架': 'Open library',
    '全部': 'All',
    '正在读': 'Reading',
    '未开始': 'Not started',
    '收藏': 'Favorites',
    '我的收藏': 'Favorites',
    '最近打开': 'Recently opened',
    '最近阅读': 'Recently read',
    '最近加入': 'Recently added',
    '按书名': 'By title',
    '搜索书名': 'Search books',
    '搜索书名或格式': 'Search title or format',
    '书籍排序': 'Sort books',
    '切换列表': 'List view',
    '切换网格': 'Grid view',
    '显示更多书籍': 'Show more books',
    '外观': 'Appearance',
    '语言': 'Language',
    '界面语言': 'Interface language',
    '界面动效': 'Interface animations',
    '简体中文': 'Simplified Chinese',
    '自动': 'System',
    '浅色': 'Light',
    '深色': 'Dark',
    '已隐藏的书籍': 'Hidden books',
    '已隐藏，可在设置中恢复': 'Hidden · Restore in Settings',
    '恢复': 'Restore',
    '还未开始': 'Not started',
    '未开始阅读': 'Not started',
    '从书架隐藏': 'Hide from library',
    '书籍操作': 'Book actions',
    '加入收藏': 'Add to favorites',
    '取消收藏': 'Remove favorite',
    '从书架隐藏这本书？': 'Hide this book from your library?',
    '隐藏书籍': 'Hide book',
    '取消': 'Cancel',
    '了解': 'OK',
    '还没有书籍': 'No books yet',
    '没有匹配的书籍': 'No matching books',
    '清除筛选': 'Clear filters',
    '书脊墙': 'Book spines',
    '阅读排版': 'Reading layout',
    '保存并返回书架': 'Save & return to library',
    '章节目录': 'Table of contents',
    '跳转阅读位置': 'Go to reading position',
    '查看书签列表': 'View bookmarks',
    '书签列表': 'Bookmarks',
    '标记当前位置': 'Bookmark this page',
    '取消当前书签': 'Remove bookmark',
    '改为滚动阅读': 'Switch to scrolling',
    '开启双页翻页阅读': 'Enable facing pages',
    '开启翻页阅读': 'Enable page turns',
    '开启自动双页阅读': 'Enable automatic facing pages',
    '切换为滚动阅读': 'Switch to scrolling',
    '当前翻页模式，切换为滚动': 'Page mode; switch to scrolling',
    '当前滚动模式，开启双页': 'Scrolling; enable facing pages',
    '翻页': 'Pages',
    '双页': 'Facing',
    '滚动': 'Scroll',
    '更多阅读操作': 'More reading actions',
    '专注阅读': 'Focus mode',
    '进入专注阅读': 'Enter focus mode',
    '显示阅读工具栏': 'Show reader controls',
    '滚动阅读': 'Scroll reading',
    '覆盖翻页': 'Page turns',
    '上一对书页': 'Previous spread',
    '下一对书页': 'Next spread',
    '上一章': 'Previous chapter',
    '下一章': 'Next chapter',
    '阅读位置': 'Reading position',
    '从一本好书开始': 'Begin with a book',
    '今天想读哪一本？': 'What will you read today?',
    '已从收藏移除': 'Removed from favorites',
    '已加入收藏': 'Added to favorites',
    '此处可恢复': 'Restore here',
    '无书': 'No books',
    '收起搜索': 'Close search',
    '阅读进度': 'Reading progress',
    '暂未支持此格式阅读': 'Format not yet supported',
    '无标题': 'Untitled',
    '未命名': 'Untitled',
    '单本陈列': 'Featured book',
    '书架藏书': 'Books in your library',
    '已经开始': 'Started',
    '书签': 'Bookmarks',
    '最近': 'Recent',
    '继续探索': 'Continue exploring',
    '从上一页接着读': 'Pick up where you left off',
    '所有书籍': 'All books',
    '上架了。': 'Added to library',
    '部分书籍导入失败': 'Some books could not be imported',
    '无法打开系统文件选择器：': 'Cannot open file picker: ',
    '书籍副本不存在，请重新导入': 'Book copy missing · Import again',
    '无法保存打开时间：': 'Cannot save last opened time: ',
    '无法更新书架：': 'Cannot update library: ',
    '无法更新收藏：': 'Cannot update favorites: ',
    '无法恢复：': 'Cannot restore book: ',
    '我的书签': 'My bookmarks',
    '还没有书签': 'No bookmarks yet',
    '已添加书签': 'Bookmark added',
    '已取消书签': 'Bookmark removed',
    '无法保存阅读排版偏好': 'Could not save reading layout',
    '保存排版偏好失败：': 'Could not save layout: ',
    '阅读位置还未就绪': 'Reading position not ready',
    '无法保存书签：': 'Could not save bookmark: ',
    '跳转到此处': 'Go to position',
    '返回上次位置': 'Previous position',
    '目标段落预览': 'Paragraph',
    '已跳转到新位置': 'Position updated',
    '返回原处': 'Undo',
    '字体': 'Font',
    '宋体': 'Serif',
    '楷体': 'Kai',
    '黑体': 'Sans',
    '系统': 'System',
    '只调整这本书': 'This book only',
    '无法保存单书排版设置': 'Could not save book layout',
    '快速选择': 'Presets',
    '紧凑': 'Compact',
    '舒适': 'Comfortable',
    '宽松': 'Spacious',
    '字号': 'Font size',
    '行距': 'Line height',
    '正文宽度': 'Page width',
    '窄页': 'Narrow',
    '标准': 'Standard',
    '宽页': 'Wide',
    '段落排版': 'Paragraph layout',
    '段距': 'Paragraph spacing',
    '自然左对齐': 'Left align',
    '两端对齐': 'Justify',
    '纸张主题': 'Paper theme',
    '暖色': 'Warmth',
    '翻页方式': 'Page mode',
    '纸': 'Paper',
    '护眼': 'Eye care',
    '灰': 'Gray',
    '夜': 'Night',
    '白': 'White',
    '关闭阅读排版': 'Close reading layout',
    '上一页': 'Previous page',
    '下一页': 'Next page',
    '阅读模式保存失败：': 'Could not save reading mode: ',
    '位置保存失败：': 'Could not save position: ',
    '排版偏好保存失败：': 'Could not save layout: ',
    '无法保存阅读位置：': 'Could not save reading position: ',
  };
}
