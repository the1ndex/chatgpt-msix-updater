# ChatGPT Windows MSIX 一键更新脚本

适用于无法正常使用 Microsoft Store 的 Windows 电脑。脚本会根据 ChatGPT 的 Microsoft Store 商品链接解析最新安装包，自动选择主 `x64 .msix`，下载到当前用户的 `Downloads` 文件夹，完成校验后安装或更新。

> Microsoft Store 商品 ID：[`9PLM9XGG6VKS`](https://apps.microsoft.com/detail/9plm9xgg6vks?hl=zh-CN&gl=CN)

## 功能

- 通过 [store.rg-adguard.net](https://store.rg-adguard.net/) 获取 Microsoft Store 临时下载地址。
- 只选择主 `x64 .msix`，自动排除 `arm64`、BlockMap 和框架依赖包。
- 实际安装包只允许从微软的 `*.dl.delivery.mp.microsoft.com` 域名下载。
- 下载完成后校验页面提供的 SHA-1 和 MSIX 数字签名，验证失败时不会安装。
- 自动比较本机版本；已经是最新版时不会重复下载约 700 MB 的安装包。
- 支持断点续传、仅下载和仅解析测试。

## 使用方法

下载本仓库后，双击：

```text
Update-ChatGPT-Codex.bat
```

也可以在 PowerShell 中运行：

```powershell
# 正常检查、下载并安装
.\Update-ChatGPT-Codex.ps1

# 只解析最新版信息，不下载
.\Update-ChatGPT-Codex.ps1 -ResolveOnly

# 只下载，不安装
.\Update-ChatGPT-Codex.ps1 -DownloadOnly

# 已安装最新版时仍然下载安装包
.\Update-ChatGPT-Codex.ps1 -ForceDownload
```

默认下载目录是：

```text
%USERPROFILE%\Downloads
```

需要指定其它目录时：

```powershell
.\Update-ChatGPT-Codex.ps1 -DownloadDirectory 'D:\Downloads'
```

## 运行要求

- Windows 10 或 Windows 11 x64
- Windows PowerShell 5.1 或 PowerShell 7
- 系统可以运行 `curl.exe` 和 `Add-AppxPackage`
- 可以访问 rg-adguard 与微软下载服务器

脚本不要求管理员权限；安装更新时可能会自动关闭正在运行的 ChatGPT 窗口。

## 关于 Codex 包名

ChatGPT 桌面应用当前由 Microsoft Store 返回的 MSIX 内部包名是 `OpenAI.Codex`，但应用显示名称仍是 ChatGPT。脚本以 Microsoft Store 商品链接和商品 ID 为产品身份标准，不会把 `OpenAI.Codex` 写死为校验条件；内部包名会从每次的实时返回结果中提取，仅用于查询已安装版本。

## 常见问题

如果 rg-adguard 临时触发 Cloudflare 验证，脚本会自动重试三次。仍然失败时，先用浏览器打开 [store.rg-adguard.net](https://store.rg-adguard.net/) 完成人机验证，再重新运行脚本。临时下载链接具有时效性，脚本每次运行都会重新解析，不会保存旧链接。

## 免责声明

这是非官方社区脚本，与 OpenAI、Microsoft 和 rg-adguard 均无隶属关系。脚本不包含或再分发 ChatGPT 安装包，实际文件由微软下载服务器提供。
