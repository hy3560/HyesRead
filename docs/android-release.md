# Android 发布

GitHub Release 同时上传通过签名验证的 Android ARM64 APK 与 AAB。APK 用于直接安装和站外分发，AAB 用于 Google Play。Android 构建本身不需要密钥；发布工作流需要以下仓库 Actions Secrets：

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEY_BASE64` | `.jks` keystore 的 Base64 文本 |
| `ANDROID_KEY_ALIAS` | keystore 中的 alias |
| `ANDROID_KEY_PASSWORD` | 私钥密码 |
| `ANDROID_STORE_PASSWORD` | keystore 密码 |

使用本项目脚本生成新密钥时，keystore 会保存在 `%LOCALAPPDATA%\HyesRead\android-release\`，并按当前 Windows 用户限制目录权限；Secrets 清单使用 Windows DPAPI 加密保存。运行：

```powershell
./scripts/create-android-release-keystore.ps1
```

然后依次从 GitHub 仓库 **Settings → Secrets and variables → Actions** 添加四个 Secrets。对每一项，在 PowerShell 运行下面命令（替换 Secret 名称）；脚本会复制该值到剪贴板，不会打印值。粘贴到 GitHub 的同名 Secret 后，再复制下一项：

```powershell
./scripts/copy-android-release-secret.ps1 -Name ANDROID_KEY_BASE64
```

将命令中的名称依次替换为 `ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`、`ANDROID_STORE_PASSWORD`。不要把 keystore 或密码放进项目目录、Issue、Pull Request 或聊天。配置完成后，推送对应 `v*` 标签会构建 Android 包；工作流分别验证 APK 与 AAB 签名后才上传。任一 Secrets 缺失、任一签名检查失败或任一平台构建失败时，整个 Release 都不会进入发布步骤，避免出现只有 Windows 或只有 Android 的半成品版本。

请把 `hyesread-release.jks` 及恢复所需密码另行备份到你控制的密码管理器或加密备份。DPAPI Secrets 文件只能由创建它的 Windows 用户账户解密；设备或账户损坏时，单靠该文件不能恢复。Android 用户只能安装由同一签名密钥签署的更新；密钥丢失会使现有安装无法通过后续 APK 原位升级。详情见 [Tauri Android 签名说明](https://v2.tauri.app/distribute/sign/android/) 和 [Android 应用签名说明](https://developer.android.com/studio/publish/app-signing)。
