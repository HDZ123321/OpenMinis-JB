# 侧载安装

## 直接可用的产物

`Minis-unsigned.ipa` — 每次 push 到 `main` 后由 GitHub Actions 的 `Build iOS` 产出，挂在 Release 上。

Sideloadly / AltStore / ESign / TrollStore 直接拖进去签，免费 Apple ID 就行。

## 为什么能签

原始 `Minis.entitlements` 要 9 项能力：App Groups、iCloud(CloudKit + ubiquity)、HealthKit(含 health-records)、HomeKit、NFC、WeatherKit、aps-environment。免费 Personal Team 一项也给不了。请求它们签名校验就过不去；profile 悄悄剥掉它们又会让二进制在第一次查容器时崩。

所以这个 fork 在代码层把「没有这些能力」当成正常情况处理，而不是等签名去满足：

| 能力 | 缺失时的行为 |
| --- | --- |
| App Groups | `SharedContainerStore.sharedDirectory(_:)` 回落 Application Support。路径全部有效，只是 `shared/` `skills/` `memory/` 不再出现在「文件」App 里，分享扩展也收不到附件 |
| iCloud / CloudKit | 备份与同步不可用。干净安装默认关闭，不会尝试连接 |
| HealthKit | health offload 工具报不可用 |
| HomeKit | home offload 工具报不可用 |
| NFC | 读卡器不可用 |
| WeatherKit | 天气工具报不可用 |
| aps-environment | 无推送。代码里没有 `registerForRemoteNotifications`，不会有人发现 |

`src/ios/Personal.entitlements` 是空 dict，本地用免费账号直接构建时指过去：

```bash
xcodebuild -project src/ios/Minis.xcodeproj -scheme Minis \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  DEVELOPMENT_TEAM=<你的 team id> \
  CODE_SIGN_ENTITLEMENTS=src/ios/Personal.entitlements \
  build
```

CI 的产物不需要这个文件 —— 未签名的 `.app` 里根本没有 entitlements blob，签名工具在设备侧按自己 profile 允许的范围补。

## 两个曾经导致闪退的坑（已修）

**1. `ENABLE_DEBUG_DYLIB`**

Xcode 16 起默认 YES。Debug 产出的 `Minis.app/Minis` 只是 72 KB 的壳，真正的代码在 205 MB 的 `Minis.debug.dylib` 里，而且那个 dylib 未签名。侧载工具重签只签主二进制，dyld 在 `main()` 之前就把它拒了 —— 表现为点图标立刻退出，连崩溃日志都没有。

修法：app target 两个 config 都钉 `ENABLE_DEBUG_DYLIB = NO`，CI 用 `-configuration Release`。现在 `Minis.app/Minis` 是 153,574,696 字节的完整二进制，包里零个 `*.debug.dylib`。

**2. `containerURL(forSecurityApplicationGroupIdentifier:)!`**

4 处强制解包：`AIChatViewModel+RequestBudget.swift` 的 `minisAppGroupRoot` / `minisConfigRoot`、`FileProviderExtension.swift` 的 `providerRoot`、`MinisApp.swift` 的 `migrateSharedDirToAppGroup()`。签名缺 App Group 时全部返回 nil，第一处被调用就崩。

修法：新增 `SharedContainerStore.sharedDirectory(_:)`，4 处全部改走它。

## CI 门禁

`Verify the app is sideloadable` 步骤在主二进制小于 5 MB 或包里存在 `Minis.debug.dylib` 时直接 `exit 1`。这两个都是「装上就闪退且没有日志」的成因，宁可构建失败也不要发出这种产物。

## 已知限制

- 免费证书 7 天到期，到期后重签同一个 IPA 即可，数据保留（bundle id 不变）。
- 换成付费账号（$99/年）时，把 4 个 target 的 `PRODUCT_BUNDLE_IDENTIFIER` 和 entitlements 里的 `group.` / `iCloud.` 前缀改成自己的，就能拿回全部能力。
