# CloudKit 探针（T01 / T02）

一次性验证用的最小 iOS App：确认「账号 → 签名 → 安装到真机 → CloudKit 私有库读写」这条链通不通。
真实 iOS target 建好后可以直接删掉这个目录。

## 跑法

```bash
cd Spikes/cloudkit-probe
xcodegen generate

# 换成你的真机 UDID
DEV=00008140-000E74313612801C
xcodebuild -project JingliProbe.xcodeproj -scheme JingliProbe \
  -configuration Debug -destination "platform=iOS,id=$DEV" \
  -derivedDataPath /tmp/JingliProbe/dd \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=W695YL8UYY build

xcrun devicectl device install app --device $DEV \
  /tmp/JingliProbe/dd/Build/Products/Debug-iphoneos/JingliProbe.app
xcrun devicectl device process launch --device $DEV com.freedom-shen.jingli.probe
```

## 2026-11-17 实测结果

| 步骤 | 结果 |
|---|---|
| 真机识别 | ✅ iPhone 16 Pro Max（iPhone17,2）· iOS 26.5 |
| Team 签名 | ✅ `W695YL8UYY`；其它 Team ID 未登录 Xcode（`No Account for Team`） |
| 安装 + 启动 | ✅ 无 entitlement 的版本已装到真机并成功启动 |
| iCloud 能力 | ❌ 被开发者协议拦住 |

加 `com.apple.developer.icloud-*` 后的报错：

```
error: Unable to process request - PLA Update available: You currently don't have
access to this membership resource. To resolve this issue, agree to the latest
Program License Agreement in your developer account.
error: Provisioning profile "iOS Team Provisioning Profile: *" doesn't include
the com.apple.developer.icloud-container-identifiers and
com.apple.developer.icloud-services entitlements.
```

处理：登录 https://developer.apple.com/account ，接受最新的 Program License Agreement，
然后重跑上面的 build（`-allowProvisioningUpdates` 会自动创建 App ID、iCloud container 和 profile）。

## 依赖的前提

- container 名固定为 `iCloud.com.freedom-shen.jingli`，必须属于同一个 Team；
- 真机第一次跑需要在「设置 → 通用 → VPN与设备管理」里信任开发者证书；
- 免费个人 Team 不支持 iCloud 能力。
