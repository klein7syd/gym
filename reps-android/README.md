# REPS — 健身记录（Android 原生版 v0.1）

组间计时 / 训练记录 / 渐进超负荷分析 / 黑胶播放器。
安卓原生（Kotlin + View），前台服务保活，**息屏后计时不停、音乐不断**。

## 怎么装

1. 把 `apk/REPS-v0.1.apk` 传到手机（微信文件传输助手 / 数据线 / 网盘都行）
2. 手机上点开这个文件
3. 系统提示「未知来源」→ 允许安装（自签名，不是商店应用）
4. 桌面出现黑底荧光黄唱片图标 = REPS

首次打开会问通知权限，**要点允许**（否则组间休息到点没有通知）。

## 功能

| 模块 | 行为 |
|---|---|
| 组间休息 | 点「完成一组」自动开始倒计时（60/90/120/180 可切），前台服务跑，**息屏/切后台不断**；到点响铃 + 震动 + 通知栏显示「GO · 上组」 |
| 训练记录 | 重量/次数步进器，每组单独存，实时算估算 1RM；26 个动作按部位分组，可切换 |
| 渐进超负荷 | 每次训练算每个动作的 e1RM 趋势；按规则给建议：3 组全到 12 次 → +2.5kg；到 10 次 → 再挤 1-2 次；组数不够 → 先补组数；另有本周总容量 |
| 音乐 | 从手机选音频文件（可多选），后台播放，**熄屏继续、锁屏可控**（上一首/暂停/下一首），黑胶转盘旋转 |
| 数据 | 存本机 SharedPreferences，卸载会清 |

## 已知边界（不藏着）

- **没有在真机上跑过**：构建环境是无 KVM 的 Linux 容器，跑不了安卓模拟器。静态检查（Android Lint）0 error / 70 warning，编译通过。第一次装如果崩，把现象告我，我按日志修。
- 音乐走系统文件选择器（SAF），选过的文件已申请持久权限，重启后能续播最后一首；换手机/删文件会失效。
- 只做了手机竖屏。
- 导入导出还没做（下一步加，JSON 备份到手机存储）。

## 自己构建

```bash
export ANDROID_HOME=/opt/android-sdk
cd /workspace/reps-android
./gradlew assembleDebug        # 产物 app/build/outputs/apk/debug/app-debug.apk
```

工具链：Gradle 8.13 / AGP 8.13.2 / Kotlin 2.0.21 / compileSdk 34 / minSdk 26。

## 代码结构

```
app/src/main/java/com/reps/app/
  MainActivity.kt    三个页面 + 交互
  Store.kt           数据层（JSON 存 SharedPreferences）
  RestService.kt     组间计时前台服务（WakeLock + 通知 + 响铃）
  MusicService.kt    音乐前台服务（MediaSession + 锁屏控制）
  TimerView.kt       计时环
  VinylView.kt       黑胶转盘
app/src/main/res/
  layout/activity_main.xml   全部界面
  drawable/                  卡片/按钮/胶囊底
```
