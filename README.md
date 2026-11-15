# hide-shortcut-overlay

> **下载**：到右侧 [Releases](https://github.com/Crusheart-7/hide-shortcut-overlay/releases/latest) 下载 `hide-shortcut-overlay.zip`，完整解压后运行 `Install.cmd`。

# Windows 11 快捷方式箭头与 UAC 盾牌隐藏工具

本包使用独立资源 DLL 中的近乎透明图标，设置 Windows Explorer 的 `Shell Icons` 值 `29` 和 `77`。DLL 的第 197 号**序号**（从 0 开始）可被 Windows 提取；它包含 16、24、32、48、64、256 像素的 32 位 BGRA 图像。每个像素的 Alpha 都是 `1/255`，不是 0。

## 安装

1. 将 ZIP **完整解压**到本地文件夹，不要直接在压缩包预览中运行。
2. 用有管理员权限的 Windows 11 账户登录。右键以管理员身份运行 `Install.cmd`，等待窗口显示结果；直接双击也会请求提权，原窗口会显示退出代码。
3. Explorer 会短暂关闭并重新启动。若图标仍显示旧缓存，先注销再登录，必要时重启。

脚本会先校验 DLL 的 SHA-256、198 个图标组和第 197 号图标的提取结果，再修改系统。它将 DLL 放到 `C:\Windows\Resources\ShortcutOverlay\blank-resource.dll`，把 HKLM 与当前账户 HKCU 下的 `SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons` 中 `29`、`77` 四个字符串值设为 `C:\Windows\Resources\ShortcutOverlay\blank-resource.dll,197`。

## 卸载及恢复

双击解压目录里的 `Uninstall.cmd`；安装后也可以运行 `C:\ProgramData\ShortcutOverlayInstaller\Uninstall.cmd`。安装时的注册表原值及类型、两个注册表键的 `.reg` 导出，以及原位置已有的同名 DLL，都保存在 `C:\ProgramData\ShortcutOverlayInstaller\backup-...`。卸载只恢复本工具仍在使用的四个值；若某项后来被其他程序或用户修改，它会跳过该项并报告冲突，避免覆盖新配置。原 DLL 也只在当前文件仍与本工具的 DLL 匹配时恢复。备份不会自动删除。

退出代码：`0` 为完成，`1` 为失败，`2` 为卸载时发现已被改动的项目并保留备份。

## 边界与风险

- 安装**会替换**这四个值；已有值会先备份。其他注册表值与其他目录不动。若同名目标 DLL 已存在，也会先备份，确认备份哈希后才替换。
- HKLM 是计算机级设置，可能影响这台电脑上的其他用户；HKCU 只对应运行脚本的账户。卸载恢复本次安装前的 HKLM 与该账户 HKCU 值。
- 脚本只清理**当前账户**的 `iconcache*.db` 和旧版 `IconCache.db`，不清理缩略图缓存，不影响其他账户的缓存。若缓存文件被占用，会提示注销或重启。
- Explorer 重启会关闭当前打开的文件管理器窗口。先保存正在进行的文件操作。
- 这种 `Shell Icons` 覆盖方式并非 Windows 11 的正式外观设置；系统版本、图标缓存重建或后续更新可能改变显示效果，特别是 `77` 的 UAC 盾牌效果。DLL 未进行代码签名，某些安全策略可能拦截。
- 不替换 `imageres.dll`，不改系统文件所有权或权限，也不触碰其他用户的 HKCU。若 UAC 使用了**另一位管理员**的凭据，脚本会拒绝继续，以免写错账户。
- 安装失败会尝试自动回滚。若回滚也失败，请查看窗口提示及备份目录；不要反复安装，先用备份的 `.reg` 文件和原 DLL 手动核对恢复。

## 校验与源代码

随包 DLL 的 SHA-256：`6F4225F21E5A1B567FE3436A7A97CADA5AEA0011C1B415D32EB60B7259D779BC`。源代码在 `Source` 文件夹，供审阅或自行构建。安装脚本将上面的哈希固定在 `Common.ps1` 中；重新构建 DLL 后需要同步更新该值，方可安装。
