# ChillSkill(Mac)上架手册(App Store / Developer ID)

> 版本 0.3.0(build 3) · Team `A2SZ953D3V` · Bundle ID `io.primit.axblade`
> 本文只记录**这台机器上验证过**的事实:哪些已经自动化、哪些必须账号本人操作。

## 一、已经自动化(仓库里就绪,直接跑)

| 事项 | 位置 | 状态 |
|------|------|------|
| 自动签名 Team A2SZ953D3V | `project.yml` → `DEVELOPMENT_TEAM` / `CODE_SIGN_STYLE: Automatic` | ✅ Release 用 `Apple Development` 自动签名 |
| Hardened Runtime | `project.yml` → `ENABLE_HARDENED_RUNTIME: true` | ✅ `codesign -dv` 显示 `flags=0x10000(runtime)` |
| App Sandbox + 出网 | `Axblade/App/Axblade.entitlements`(Debug)/ `Axblade-Release.entitlements`(Release) | ✅ `app-sandbox` / `network.client` |
| Sign in with Apple(4.8 / 5.1.1) | Release 的 `com.apple.developer.applesignin = [Default]`,`project.yml` 按配置指定 `CODE_SIGN_ENTITLEMENTS` | ✅ archive 已带该 entitlement,capability 已自动登记到 App ID |
| 版本号 | `MARKETING_VERSION 0.3.0` / `CURRENT_PROJECT_VERSION 3` | ✅ 写进 Info.plist |
| 应用分类 | `LSApplicationCategoryType: public.app-category.finance` | ✅ |
| 加密豁免 | `ITSAppUsesNonExemptEncryption: false` | ✅(只用系统 HTTPS) |
| 账号注销入口(5.1.1(v)) | 设置 › 账户 › 删除账号 → `DELETE /v1/me` | ✅ app 内可发起;有密码的账号需重输密码 + 二次确认,纯社交账号只需二次确认 |
| archive | `./scripts/release.sh archive` | ✅ 本机跑通,产物 `build/Axblade.xcarchive` |
| Developer ID 导出 | `./scripts/release.sh export-devid` | ✅ 本机跑通,产物 `build/devid/ChillSkill.app` |
| App Store 导出/上传 | `./scripts/release.sh export-appstore` | ⛔ 缺 ASC 的 App 记录(见第二节) |
| 公证 | `./scripts/release.sh notarize <app-or-dmg>` | ⛔ 缺 `AC_NOTARY` 钥匙串凭据(见第二节) |

Debug 配置故意保持 ad-hoc 签名(`CODE_SIGN_IDENTITY: "-"`):xctest bundle 也是免签的,
宿主 App 一旦带 Team ID,两者 Team 不一致会导致测试 bundle `dlopen` 失败
(`different Team IDs`)。所以 `./scripts/test.sh` 在没有证书的机器上照样能跑。

### entitlements 为什么按配置分成两份

`com.apple.developer.applesignin` 需要描述文件背书;ad-hoc 签名的 app 带着它会被系统
**拒绝启动**。所以:

| 配置 | entitlements 文件 | 内容 | 后果 |
|------|------------------|------|------|
| Debug | `Axblade/App/Axblade.entitlements` | sandbox + network.client | 测试 / 本地跑照常;**「通过 Apple 登录」在 Debug 里点了会提示「需要正式签名的构建」**(客户端把 `ASAuthorizationError.unknown` 翻成了这句话),用 GitHub 或邮箱登录 |
| Release | `Axblade/App/Axblade-Release.entitlements` | 再加 `applesignin: [Default]` | archive / 分发包里 Apple 登录可用 |

改动位置:`project.yml` → `targets.Axblade.settings.configs.Debug/Release.CODE_SIGN_ENTITLEMENTS`
(原来的 XcodeGen `entitlements:` 块已删掉——它只能给全部配置指定同一份)。

### 常用命令

```bash
./scripts/test.sh                     # 全量单测,必须 ** TEST SUCCEEDED **
xcodebuild build -project Axblade.xcodeproj -scheme Axblade \
  -configuration Release -destination 'platform=macOS,arch=arm64'
./scripts/release.sh archive          # → build/Axblade.xcarchive
./scripts/release.sh export-devid     # → build/devid/ChillSkill.app(官网分发用)
./scripts/release.sh export-appstore  # → 直接上传 App Store Connect
./scripts/release.sh notarize build/devid/ChillSkill.app
codesign -dv --entitlements - build/devid/ChillSkill.app   # 复核签名与权限
```

本机验证过的签名结果:

```
# build/Axblade.xcarchive(开发签名,用于导出)
CodeDirectory ... flags=0x10000(runtime)
Authority=Apple Development: Wei Zhang (3D8X62UZ6G)
TeamIdentifier=A2SZ953D3V

# codesign -d --entitlements :- build/Axblade.xcarchive/Products/Applications/ChillSkill.app
com.apple.application-identifier   = A2SZ953D3V.io.primit.axblade
com.apple.developer.applesignin    = [Default]
com.apple.developer.team-identifier= A2SZ953D3V
com.apple.security.app-sandbox     = true
com.apple.security.network.client  = true

# 内嵌描述文件(说明 capability 已经登记到 App ID 上,-allowProvisioningUpdates 自动完成)
Contents/embedded.provisionprofile → "Mac Team Provisioning Profile: io.primit.axblade"
  Entitlements[com.apple.developer.applesignin] = [Default]

# build/devid/ChillSkill.app(导出后已换成分发签名 + 安全时间戳)
CodeDirectory ... flags=0x10000(runtime)
Authority=Developer ID Application: Wei Zhang (A2SZ953D3V)
Timestamp=Aug 18, 2026 at 11:55:11
TeamIdentifier=A2SZ953D3V
```

## 二、需要本人操作(账号 / 一次性)

### 1. App Store Connect 建 App 记录 —— **当前的拦路项**

`./scripts/release.sh export-appstore` 在本机的失败原文:

```
2026-08-18 11:55:23.463 xcodebuild[73107] [MT] IDEDistribution: Created bundle at path
  "/var/folders/.../Axblade_2026-08-18_11-55-23.462.xcdistributionlogs".
error: exportArchive Error Downloading App Information

** EXPORT FAILED **
```

分发日志(`IDEDistributionAppStoreConnect.log`)里查到的根因是:按 bundle id 查 App 记录返回空

```
filter[bundleId]=io.primit.axblade
AppsService: fetched 0 items, total 0 items
```

也就是说 **Xcode 的 Apple 账号会话是通的,只是 App Store Connect 里还没有这个 App**。
本人在 <https://appstoreconnect.apple.com> 新建一次即可:

- 平台:macOS
- 名称:`ChillSkill`
- 主要语言:简体中文(或英文)
- Bundle ID:`io.primit.axblade`
- SKU:`axblade-mac`

建完再跑 `./scripts/release.sh export-appstore`(首次会自动申请 Apple Distribution
证书与 Mac App Store 描述文件,需要保持 Xcode › Settings › Accounts 已登录
`zhangweiteakwondo@qq.com`;必要时先点一次 "Download Manual Profiles")。

### 2. 公证凭据(只有走官网 Developer ID 分发才需要)

```bash
xcrun notarytool store-credentials AC_NOTARY \
  --apple-id zhangweiteakwondo@qq.com --team-id A2SZ953D3V --password <App 专用密码>
```

App 专用密码在 <https://account.apple.com> › 登录与安全 › App 专用密码 生成。
存好之后 `./scripts/release.sh notarize build/devid/ChillSkill.app` 会提交并 staple。

### 3. 商店素材(必须人工准备)

- **App 隐私问卷(App Store Connect › App 隐私)**:本 app 会收集**电子邮件地址**,
  且**与用户身份关联**(账户 + 额度计量),用途选「App 功能」;不用于追踪、不做广告。
  除此之外不收集任何数据(无分析 SDK、无崩溃上报、无第三方 SDK)。
- **隐私清单 `PrivacyInfo.xcprivacy`:本次不需要**。已排查 Apple 的 required-reason API
  列表(`UserDefaults`、文件时间戳、可用磁盘空间、系统启动时间、活动键盘),
  本 app 一个都没用(设置走自己的 JSON 文件,凭据走钥匙串)。
  以后如果引入 `UserDefaults` 或第三方 SDK,要回来补这份清单。
- 截图:`1280×800`、`1440×900`、`2560×1600`、`2880×1800` 任一尺寸一组(建议深色 + 浅色各一张)
- 隐私政策 URL:`https://chillskill.xyz/en/privacy`
- 支持 URL:`https://chillskill.xyz`
- 分类:财务(已在 Info.plist 里写死 `public.app-category.finance`)
- 加密豁免:构建里已声明 `ITSAppUsesNonExemptEncryption=false`,ASC 不会再追问
- 审核时顺手确认:测试账号当天的额度没被跑光(审核员撞上 `429` 会当成 app 坏了),
  并在描述里写清本 app 与 Binance 无隶属关系(只是引用其公开行情接口)
- **审核备注必须给测试账号**:本版本未登录不能用 AI 对话与行情代理,
  审核员拿不到账号会直接判 "无法使用"。在 chillskill.xyz 注册一个测试邮箱 + 密码,
  写进 App 审核信息的「登录信息」,并注明「量化工具无需登录即可试用」。
  审核备注里再补三句(0.3.1 新增社交登录后必须写):
  1. 登录方式有三种:GitHub、Apple、邮箱 + 密码;给的测试账号走**邮箱**那条
     (在账户页展开「使用邮箱登录 / 注册」)。
  2. **Sign in with Apple 已提供**(Guideline 4.8:用了 GitHub 这类第三方登录就必须
     同时提供一个等价的隐私友好选项)——`com.apple.developer.applesignin` 在 Release
     构建里,审核员可直接试。
  3. 账号注销在 设置 › 账户 › 删除账号;GitHub / Apple 建的账号没有密码,
     删除只需二次确认。
- **App 隐私问卷补充**:GitHub 登录会拿到头像地址与用户名,Apple 登录可能拿到
  私密转发邮箱——两者都归到「电子邮件地址 / 用户 ID / 用户内容(头像)」,
  用途仍是「App 功能」,不用于追踪。


### 5. Developer ID 描述文件(官网分发 + Sign in with Apple)—— 需本人在后台建一次

`export-devid` 现在会报 `Cannot create a Developer ID provisioning profile for "io.primit.axblade"`:
带 `com.apple.developer.applesignin` 权限的 Developer ID 应用必须嵌入 **Developer ID 类型**的描述文件,
而这种描述文件 Xcode 不能自动申请。步骤:developer.apple.com → Certificates, Identifiers & Profiles →
Profiles → +,类型选 **Developer ID**(macOS App Development 下方),App ID 选 `io.primit.axblade`
(需已勾选 Sign in with Apple 能力),证书选 `Developer ID Application: Wei Zhang`,下载 `.provisionprofile`
双击导入 Xcode 后 `./scripts/release.sh export-devid` 即可;给 CI 用则 base64 后存为 secret(见 `release.yml`)。
在此之前,CI 与临时 DMG 都是 **不含 Apple 登录权限** 的 Developer ID 签名(GitHub / 邮箱登录正常,
点 Apple 登录会提示需要正式签名版)。

## 三、提交流程

1. `./scripts/test.sh` 全绿
2. 需要就改 `project.yml` 的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`(每次上传 build 号必须递增)
3. `./scripts/release.sh archive`
4. App Store:`./scripts/release.sh export-appstore`(`destination=upload`,直接进 ASC)
   官网分发:`./scripts/release.sh export-devid` → `./scripts/release.sh notarize build/devid/ChillSkill.app`
5. ASC 里给新 build 填「新增内容」,提交审核

### 4. 旧版内置令牌(legacy)的轮换 —— 排期项,不阻塞本次提交

0.2.x 客户端里内置过一个静态访问令牌,后端按设计仍然接受(spec §1.3 / §五 的兼容策略)。
它已经从工作区删除,但**仍留在本仓库的 git 历史与已分发的旧二进制里**,而且没有有效期。
仓库是私有的,不构成正在发生的泄露;正确处理是**等 0.2.x 用户基本迁移到 0.3.0 之后,
在后端把这枚 legacy 令牌下线并轮换**(后端侧 `AXBLADE_ACCESS_TOKENS` 改一行即可)。
建议节奏:0.3.0 上架后观察一个版本周期,确认旧版调用量归零再下线。

## 四、常见报错

| 报错 | 原因 | 处理 |
|------|------|------|
| `error: exportArchive Error Downloading App Information` | ASC 里没有该 bundle id 的 App 记录 | 见第二节第 1 条 |
| `No profiles for 'io.primit.axblade' were found` | 本机没有对应描述文件 | 加 `-allowProvisioningUpdates`(`release.sh` 已带),或 Xcode › Settings › Accounts 重新登录 |
| `not valid for use in process: ... different Team IDs` | 宿主 App 带 Team 而 xctest 免签 | Debug 保持 ad-hoc,别给 Debug 配置加 `DEVELOPMENT_TEAM` |
| `invalid or unsupported format for signature` | DerivedData 里残留 ad-hoc 签名的旧产物 | `xcodebuild clean` 后重建 |
| 上传后 ASC 提示缺 `com.apple.security.app-sandbox` | entitlements 丢了 | 确认 `project.yml` 的两个配置都指了 `CODE_SIGN_ENTITLEMENTS` |
| Debug 构建点「通过 Apple 登录」提示「需要正式签名的构建」 | Debug 是 ad-hoc 签名,故意不带 `applesignin` | 预期行为,用 GitHub / 邮箱登录;要试 Apple 就跑 `./scripts/release.sh archive` |
| archive 报 `Provisioning profile ... doesn't support the Sign in with Apple capability` | App ID 上还没开这个 capability | `release.sh archive` 带了 `-allowProvisioningUpdates`,通常会自动登记;不行就去 developer.apple.com › Identifiers › `io.primit.axblade` 勾上 Sign in with Apple 再重跑 |
| 公证 `Invalid credentials` | `AC_NOTARY` 没存或密码过期 | 重新跑 `notarytool store-credentials` |
