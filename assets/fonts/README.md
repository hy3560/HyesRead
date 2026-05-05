# 字体文件下载指南

本项目支持以下开源字体，但**字体文件为可选项**。如果未下载，应用将自动回退到系统默认字体。

---

## 1. 思源宋体 (Source Han Serif) - 推荐

**特点**：Adobe 与 Google 联合开发，优雅衬线字体，适合长文阅读

**下载地址**：
- GitHub: https://github.com/adobe-fonts/source-han-serif/releases
- 国内镜像: https://mirrors.tuna.tsinghua.edu.cn/adobe-fonts/source-han-serif/

**所需文件**：
- `SourceHanSerifSC-Regular.otf` (简体中文常规体)
- `SourceHanSerifSC-Bold.otf` (简体中文粗体)

**重命名规则**：
- `SourceHanSerifSC-Regular.otf → SourceHanSerif-Regular.otf
- `SourceHanSerifSC-Bold.otf → SourceHanSerif-Bold.otf

---

## 2. 霞鹜文楷 (LXGW WenKai) - 推荐

**特点**：温润手写风格，基于 Klee One 改造，护眼舒适

**下载地址**：
- GitHub: https://github.com/lxgw/LxgwWenKai/releases
- Gitee 镜像: https://gitee.com/lxgw/LxgwWenKai/releases

**所需文件**：
- `LXGWWenKai-Regular.ttf`
- `LXGWWenKai-Bold.ttf`

---

## 3. JetBrains Mono

**特点**：等宽字体，适合代码高亮和技术文档

**下载地址**：
- 官网: https://www.jetbrains.com/lp/mono/
- GitHub: https://github.com/JetBrains/JetBrainsMono/releases

**所需文件**：
- `JetBrainsMono-Regular.ttf`
- `JetBrainsMono-Bold.ttf`

---

## 4. Noto Sans SC

**特点**：Google 开发的现代无衬线字体，清晰易读

**下载地址**：
- Google Fonts: https://fonts.google.com/noto/specimen/Noto+Sans+SC
- GitHub: https://github.com/notofonts/noto-cjk/releases

**所需文件**：
- `NotoSansSC-Regular.ttf`
- `NotoSansSC-Bold.ttf`

---

## 安装步骤

1. 下载上述字体文件
2. 将所有 `.otf` 和 `.ttf` 文件放置到 `assets/fonts/` 目录
3. 运行 `flutter pub get` 重新加载资源
4. 重启应用即可在设置中选择字体

---

## 字体回退机制

如果字体文件缺失，应用将按以下顺序回退：

1. **阅读正文**：SourceHanSerif → 系统衬线字体
2. **UI 界面**：NotoSansSC → 系统无衬线字体
3. **代码高亮**：JetBrainsMono → 系统等宽字体

**无需担心编译错误**，Flutter 会自动处理字体缺失的情况。