# HyesRead 纸墨动效：参考、许可与性能边界

状态：2026-11-05，独立 Android Debug 预览。没有复制 Wonderous、Vignettes 或第三方商业阅读器的界面素材。

| 参考 / 依赖 | 项目中的实际应用 | 许可 / 边界 |
| --- | --- | --- |
| [Rive Flutter](https://pub.dev/packages/rive) `0.14.11` | `rive_ink_waves.dart`：导入印章旁的一次性状态机墨迹波纹，资源为 Rive MIT runtime 附带 `runtime_nested_inputs.riv` 示例的 947B 编码；Android 上可选，不能影响导入或阅读 | MIT；原版示例需遵守 MIT 署名。Runtime 原生库增加 APK 体积，不为正文常驻创建动画 |
| [Flutter Custom Carousel](https://github.com/gskinnerTeam/flutter_custom_carousel) `0.1.0+1` | `resume_carousel.dart`：3 本及以上时启用物理滚动、选中项景深与透视；小样本/减少动效时回退 `PageView` | BSD-3-Clause；没有复制 Demo 卡片素材 |
| [Flutter Animate](https://github.com/gskinner/flutter_animate) `4.5.2` | `app_shell.dart`：网格封面错峰淡入/缩放/位移的声明式动效 | BSD-3-Clause；仅首次与筛选变化，不无限重播 |
| [Wonderous](https://github.com/gskinnerTeam/flutter-wonderous-app) | 借鉴页面层级、标题留白、视觉叙事；未依赖或复制其资源 | MIT；借鉴设计原则不等于安装框架 |
| [Flutter Vignettes](https://github.com/gskinnerTeam/flutter_vignettes) | 借鉴画布插画、光线分层、卡片景深；本工程以 `CustomPainter` 自绘、`Path.combine` 换肤 | MIT；没有直接复制源码 |

全局时长、缓动、弹性和触感见 `lib/design/motion.dart`。减少动效按 `MediaQuery.disableAnimations` 回退 120ms 的淡入淡出；不应产生持续位移/旋转。空书架绘图用一个 ticker，非 Android 的 widget 测试使用静态画面。Android 高刷新率通过 `flutter_displaymode` 尽力请求，系统可以拒绝。

**尚未达到的验收**：Flutter DevTools Profile 真机 Raster/UI 帧预算测试、连续长文翻页 60/120fps、iOS Runner 与 120Hz Info.plist、准确中文 ICU 避头尾分析、10MB 以上 TXT 分章懒加载、真正按屏幕排版的手势覆盖翻页。不得把已有的上下滚动/按段落定位称为这些功能已经实现。

Debug 演示书架的十二本书及进度都是明确标识的虚构数据，只在内存中渲染。当前没有打包两份真实 EPUB 封面作为演示资源；正常导入的 EPUB 若书籍自身包含声明的封面，封面系统将使用它。不能把生成的文字封面称为真实 EPUB 图片。
