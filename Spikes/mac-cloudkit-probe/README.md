# macOS CloudKit 可行性验证

目的：确认 **Mac 端能不能通过 CloudKit 读到 iPhone 写的数据**，以及需要付出什么代价。

## 怎么跑

```bash
cd Spikes/mac-cloudkit-probe
xcodegen generate
xcodebuild -project MacProbe.xcodeproj -scheme MacProbe -configuration Debug \
  -derivedDataPath /tmp/macprobe-dd -allowProvisioningUpdates build
./.../MacProbe.app/Contents/MacOS/MacProbe
```

## 结论（2026-11-17）

```
[MAC] accountStatus=1
[MAC] userRecordID=_ccd3a
[MAC] zone failed: CKError 10/2007 "Permission Failure"
     server message = "Invalid bundle ID for container"
```

- **好消息**：macOS 上只要 `CODE_SIGN_STYLE=Automatic` + 同一 team + iCloud entitlement，
  账号与身份都正常（`accountStatus=1`、`userRecordID` 拿得到）。
- **坏消息**：容器只授权给了 iOS 的 App ID。换一个 bundle ID 访问同一个容器会被拒
  （`Invalid bundle ID for container`）。

## 所以 Mac 端接同步要三步

1. Mac App 的 bundle id 注册成 App ID，并勾选 iCloud(CloudKit)
2. 把同一个容器 `iCloud.com.freedom-shen.jingli` 分配给这个 App ID
3. Mac 工程从现在的 `CODE_SIGN_IDENTITY: "-"`（ad-hoc）改成自动签名 + team

第 3 步会改变分发方式：现在的 `scripts/package.sh` 是免签名的 zip 安装，
改成自动签名后需要描述文件、且换机器装包会有信任问题。**这一步必须用户拍板。**
