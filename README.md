# 今日事

日常工作与生活习惯的每日提醒，安卓手机 + Windows 电脑，通过坚果云自动同步。

## 下载安装

打开仓库右侧 **Releases**，下载最新一次构建：

- 手机：`jinrishi-android-x.y.z.apk`，在小米手机上直接安装（允许“安装未知应用”）
- 电脑：`jinrishi-setup-x.y.z.exe` 安装程序；或免安装的 `jinrishi-windows-portable-x.y.z.zip`

每次往 `main` 分支推送代码，GitHub Actions 会自动重新打包并发布新版本。

## 功能

- 事项：一次性待办、每天 / 工作日 / 每周几 / 每月几号重复
- 中国法定节假日感知：“工作日”自动跳过放假、包含调休上班；其他重复规则可选“节假日跳过”
- 分类、优先级、备注；逾期待办自动出现在今天
- 到点弹窗：电脑端窗口置顶弹出，手机端悬浮/锁屏全屏通知，可直接点“完成”或“10 分钟后”
- 每天早上 8:00（可改）推送今日清单
- 手机桌面小组件；电脑端托盘常驻、开机自启、小窗置顶
- 坚果云 WebDAV 同步（数据在坚果云的 `jinrishi/data.json`）

## 第一次使用

1. **坚果云**：网页版 → 账户信息 → 安全选项 → 第三方应用管理 → 添加应用，得到应用密码。在手机和电脑的“设置 → 坚果云同步”里填同一个账号和应用密码。
2. **小米手机**：首次打开会弹出引导，依次授予通知/闹钟/全屏通知权限，打开“自启动”，省电策略设为“无限制”，并在通知管理里为“到点提醒”打开悬浮通知和锁屏通知。
3. **小组件**：长按桌面 → 小部件 → 今日事。

## 说明

- 手机端会提前排好未来 14 天的提醒，每次打开应用、修改或同步后自动重排。两周都不打开应用的话，请打开一次。
- 次年节假日安排一般 11 月公布，应用联网后会自动下载（数据来自 NateScarlet/holiday-cn）。
- 安卓签名密钥放在 `platform/android/release.jks`，保证每次新版本都能覆盖安装。请保持仓库为私有。

## 开发

本仓库只保存 `lib/` 等跨平台代码，`android/`、`windows/` 由 CI 用 `flutter create` 生成，再由 `tool/patch_platforms.py` 写入权限、小组件、托盘等原生配置。本地开发：

```bash
flutter create --org com.shen --project-name jinrishi --platforms android,windows .
python tool/patch_platforms.py android
python tool/patch_platforms.py windows
flutter run
```
