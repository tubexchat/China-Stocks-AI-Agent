# ChillSkill for Mac

> 运维手册(部署 / 发布 / 密钥 / 排障 / 人工清单):[https://github.com/Primit-io/Axblade-API-AI/blob/main/docs/ops-runbook.md](https://github.com/Primit-io/Axblade-API-AI/blob/main/docs/ops-runbook.md)

> 产品名 **ChillSkill**;仓库/工程/模块名沿用内部代号 `Axblade`(bundle id `io.primit.axblade` 不变)。

原生 macOS **金融数据分析 AI 客户端**。Swift + SwiftUI,**只支持 Apple Silicon(arm64)**,零第三方依赖。

- **零配置接入官方后端**(`api.chillskill.xyz`):模型固定为 DeepSeek / Kimi 二选一,
  客户端不涉及任何 APIKEY——模型密钥只存在于服务端
- 流式输出,随时停止;Markdown 渲染(标题 / 列表 / 表格 / 引用 / 代码块),每条回答与代码块都带复制按钮
- **7 个金融数据源**:Binance / OKX / 抹茶 MEXC / 美股 / 韩股 / 港股 / A股,
  输入卡 “+” 一键附加实时行情给 AI 分析
- **Tools 量化工作区**(侧栏顶部 Home|Tools 切换):原生梯度提升树预测、
  风控指标(VaR/回撤/波动/夏普)、双均线回测,结果一键交给 AI 解读
- **官方后端账户**:**GitHub / Apple 一键登录为主**,邮箱 + 密码为次要入口
  (都可在 [chillskill.xyz](https://chillskill.xyz) 或 app 内直接注册);
  登录后能看到套餐、每日额度与数据权限;未登录时 AI 对话与 Binance 行情代理会被拦下,
  本地量化工具照常可用
- 会话本地 JSON 持久化 + 侧栏搜索,访问令牌只进系统钥匙串(客户端不内置任何令牌)
- **Binance 风格界面**(与官网同一套设计 token),跟随系统浅色/深色;
  **中英文双语**(设置 → 通用 切换,即时生效)

## 环境要求

| 项 | 版本 |
|----|------|
| macOS | 14.0+ |
| 芯片 | Apple Silicon(M 系列),`ARCHS = arm64` |
| Xcode | 15+(开发用 26.5 验证) |
| XcodeGen | `brew install xcodegen` |

## 构建与运行

```bash
xcodegen generate                       # 由 project.yml 生成 Axblade.xcodeproj
open Axblade.xcodeproj                  # 或者用命令行:
xcodebuild build -project Axblade.xcodeproj -scheme Axblade \
  -configuration Release -destination 'platform=macOS,arch=arm64'
```

`.xcodeproj` 不入库,改工程配置请改 `project.yml` 后重新 `xcodegen generate`。

签名分两档,都写在 `project.yml` 里:

- **Debug**:ad-hoc(`CODE_SIGN_IDENTITY: "-"`)。xctest bundle 也是免签的,
  宿主一旦带 Team ID 两边不一致会 `dlopen` 失败,所以测试链路保持免签,
  没有开发者证书的机器也能跑 `./scripts/test.sh`。
- **Release**:自动签名,Team `A2SZ953D3V`,开 Hardened Runtime,
  版本 `MARKETING_VERSION 0.3.0` / `CURRENT_PROJECT_VERSION 3`。

## 自动打包与下载(CI)

每次推 `main`,`.github/workflows/release.yml` 在 macOS runner 上:跑测试 → Release 构建 →
`scripts/package-dmg.sh` 打 `ChillSkill-<版本>-<构建号>.dmg`(附 `ChillSkill-latest.dmg` 与 `latest.json`)→
用 GitHub Actions 自带的 **OIDC 令牌**直接分块上传到 `api.chillskill.xyz`(后端校验签名与仓库/分支,**不需要任何 secret**)→
网站「Download for Mac」按钮读取 `GET https://api.chillskill.xyz/v1/releases/latest` 直链下载。

- **签名 / 公证按 secrets 自动启用**:配置 `MAC_SIGNING_P12_BASE64` + `MAC_SIGNING_P12_PASSWORD`
  (Developer ID Application 证书 .p12)则正式签名;再配 `NOTARY_KEY_P8_BASE64` + `NOTARY_KEY_ID` +
  `NOTARY_ISSUER_ID`(App Store Connect API Key)则公证并 staple。没有 secrets 时是 **ad-hoc 签名**
  的测试版:可运行,但首次需 **右键 → 打开** 绕过 Gatekeeper(`latest.json` 里 `signed:false`)。
- 上传走 `scripts/upload-release.py`(标准库,分块 ≤ 900 KB);服务端只接受 `Primit-io/Axblade-Mac-Cli` 的 `main` 分支令牌。
- 本地打包:`scripts/package-dmg.sh --build 1 [--identity "Developer ID Application: …"]`,产物在 `build/dmg/`。
- CI 失败时日志会推到 `ci-logs` 分支(`git fetch origin ci-logs`),不需要 Actions 权限也能排障。

## 测试

```bash
./scripts/test.sh
```

等价于:

```bash
xcodebuild test -project Axblade.xcodeproj -scheme Axblade \
  -destination 'platform=macOS,arch=arm64' -quiet
```

`SnapshotTests` 会把十几张界面图(含账户仪表盘、未登录横幅)渲染到测试宿主的容器 tmp 里,路径在输出中以
`AXBLADE_SNAPSHOT_OUTPUT=…` 打印,通常是
`~/Library/Containers/io.primit.axblade/Data/tmp/AxbladeSnapshots/`。

## 发布与上架

```bash
./scripts/release.sh archive          # → build/Axblade.xcarchive
./scripts/release.sh export-devid     # → build/devid/ChillSkill.app(官网分发,Developer ID 签名)
./scripts/release.sh export-appstore  # → 直接上传 App Store Connect
./scripts/release.sh notarize build/devid/ChillSkill.app
```

导出参数在 `ExportOptions/AppStore.plist`(`app-store-connect` + `destination=upload`)
与 `ExportOptions/DeveloperID.plist`(`developer-id` + `destination=export`)。
`build/` 与 `*.xcarchive` 都不入库。

哪些已经自动化、哪些必须账号本人操作(ASC 建 App 记录、公证凭据、截图、审核测试账号),
见 **[docs/app-store-submission.md](docs/app-store-submission.md)**。

## 模型服务

**无需配置任何密钥,登录即用。** 所有 AI 请求固定经由官方后端
[Axblade API](https://github.com/Primit-io/Axblade-API-AI)(`https://api.chillskill.xyz`)转发:

- 模型只有两个选项(界面显示完整模型名):**DeepSeek-V4-Flash-0731**(别名 `deepseek`,默认)
  和 **Kimi-K2.7-Code**(别名 `kimi`)。按 `⌘,` 打开设置 → 模型服务 单选,
  或点输入卡右下角的模型标签切换。实际可用的模型以账户权限为准(账户页「可用模型」)。
- **客户端不涉及任何 APIKEY,也不内置访问令牌**:万擎模型密钥只存在于服务端;
  客户端用的是你登录后后端签发的令牌,存系统钥匙串,可随时在服务端吊销。
- 不支持自定义 Provider / Base URL / 自带 Key 直连第三方。

## 附加行情数据

点输入卡左下角 **“+”** → 选数据源 → 输入代码 → 查询 → 附加。行情以可见数据块
(现价、24h 涨跌、高低、量、近 30 日收盘)并入你的消息发给 AI;可只附数据不写字直接发送。

| 数据源 | 代码示例 | 说明 |
|--------|---------|------|
| Binance | `BTCUSDT`、`btc`(自动补 USDT) | **经官方后端代理**(Binance 封锁中美 IP,代理保证可达) |
| 抹茶 MEXC | 同上 | 公共 REST,无需 Key |
| OKX | `BTC-USDT`、`btcusdt`(自动转横线格式) | 同上 |
| 美股 | `AAPL`、`TSLA` | Yahoo Finance |
| 韩股 | `005930`(自动补 `.KS`) | Yahoo Finance |
| 港股 | `700` → `0700.HK`(自动补零) | Yahoo Finance |
| A股 | `600519` → `.SS`,`000001`/`300750` → `.SZ` | Yahoo Finance |

设置 → 数据源 可逐个启用/禁用。注:Yahoo 为非官方接口;Binance 行情已改经
官方后端(AWS 东京)只读代理转发,中国/美国网络下无需任何代理工具即可加载。

## Tools 量化工作区

侧栏顶部 **Home | Tools** 切换。三个工具全部本地原生计算(零第三方依赖),
选数据源 + 代码 + 历史长度(90/180/365 天)即可运行,结果可一键「让 AI 解读」
(自动开新会话把数据发给模型)。仅供研究参考,不构成投资建议。

| 工具 | 输出 |
|------|------|
| 梯度提升树模型 | 纯 Swift GBDT(树数/深度可调,确定性训练):次日方向、预测收益、时间序 80/20 验证集命中率、特征重要性(滞后收益 r1–r5、ma5/ma20、动量、波动) |
| 风控模型 | 单日 VaR(95/99)、最大回撤、年化波动率(√252)、夏普比率 |
| 因子挖掘 | 9 个价格类因子(反转/动量×3/乖离×2/波动/RSI14/价格位置)对次日收益的 Spearman 秩相关 IC + 最高/最低 30% 多空分层收益差,按 \|IC\| 排序 |
| 历史回测 | 双均线交叉(快/慢可调,信号 T+1 生效,未计手续费)vs 买入持有:收益/年化/回撤/交易次数/胜率 + 双净值曲线 |

## 账户登录

登录方式:**GitHub / Apple 为主,邮箱为次要入口**。三种方式都签发同一套后端令牌
(存系统钥匙串),同一个已验证邮箱会自动关联到同一个账号。按 `⌘,` → 账户:

| 方式 | 怎么走 | 备注 |
|------|--------|------|
| **使用 GitHub 登录** | 点按钮 → app 显示一串大写用户码并自动打开 <https://github.com/login/device> → 在浏览器里输入该码授权 → app 自动完成登录 | 设备码流程由后端代理(`POST /v1/auth/github/device` + `/poll`),客户端不持有任何 GitHub secret;可随时点「取消」中止轮询 |
| **通过 Apple 登录** | 点按钮 → 系统 Sign in with Apple 面板 → 授权 | **Debug 构建不可用**:ad-hoc 签名的 app 不能带 `com.apple.developer.applesignin`,点了会提示「需要正式签名的构建」。Release / archive 出来的包正常 |
| 邮箱登录 / 注册 | 展开「使用邮箱登录 / 注册」折叠区,填邮箱、显示名、密码(至少 8 位) | 与 0.3.0 完全一致 |

纯社交账户(没设过密码)有两处不同:账户页的「修改密码」变成「**设置密码**」
(不需要填当前密码),「删除账号」也不要求输密码,只走二次确认。
设过密码之后就能用邮箱 + 密码登录同一个账号。
这两个操作后端都要求**刚登录过的会话**(15 分钟内);过期了会回 403 `reauth_required`,
账户页原样显示后端提示并给一个「重新登录」按钮(只清本地登录态,回到登录页)。

Apple 登录带**防重放 nonce**:客户端生成 32 字节随机数,把它的 sha256 十六进制设进
`ASAuthorizationAppleIDRequest.nonce`(Apple 会写进 id_token 的 `nonce` 声明),
明文随 `POST /v1/auth/apple` 发出去,后端比对二者。截获的旧 id_token 因此换不到令牌。

另外两种后端拒绝的处理:409 `email_registered_with_password`(这个邮箱已经用密码注册过,
第三方登录不能自动认领)会**自动展开邮箱表单**并显示后端原话;
400 `invalid_device_code`(设备码后端不认了)会自动换一枚码重来一次,再不行才报错。

登录状态影响什么:

| 功能 | 未登录 | 已登录 |
|------|--------|--------|
| AI 对话(`/v1/chat/completions`) | 拦下,输入卡上方提示「去登录」 | 按套餐额度使用 |
| Binance 行情(经 `/v1/market/binance/*` 代理) | 拦下并提示登录(不发请求) | 按权限与额度使用 |
| OKX / MEXC / 美股 / 韩股 / 港股 / A股 | 照常(公共接口,直连) | 照常 |
| Tools 量化工具 | 计算全在本地;**数据源选 Binance 时需要登录**,换成 OKX/MEXC/股票源即可离线跑 | 照常 |

**额度与权限在哪看**:设置(`⌘,`)→ 账户。已登录时这一页是仪表盘——

- 顶部:头像(GitHub / Apple 的 `avatar_url`,没有就显示首字母圈)+ 邮箱 +
  套餐徽章 + 登录方式徽章(GitHub / Apple / 邮箱)
- 额度:「AI 对话(今日)」与「行情代理(今日)」两条进度条,显示 `已用 / 上限`
  与重置时间;套餐不限量时上限显示「不限」
- 权限:「可用模型」「可用行情源」两组芯片(行情源还会列出放行的路径)
- 已登录设备:客户端类型 / 登录时间 / 当前设备标记,可逐个吊销
- 底部:修改密码 / 设置密码(折叠)、**删除账号**(折叠,红框:有密码时需重输密码 + 二次确认,
  对应后端 `DELETE /v1/me`,App Store 5.1.1(v) 要求 app 内可注销)、
  刷新、退出登录、退出全部设备

侧栏底部常驻显示头像(有 `avatar_url` 就拉远程图,否则首字母圈)+ 邮箱 + 套餐徽章;
未登录显示「未登录」。

可选模型跟着账户权限走:登录后模型选择器(设置 › 模型服务 与输入卡右下角)
只列 `/v1/me` 返回的 `permissions.models`,套餐降级后已选模型会自动收敛。

数据接口对应后端 `/v1/auth/*` 与 `/v1/me`、`/v1/me/usage`、`/v1/me/sessions`、`DELETE /v1/me`,
错误文案一律以后端 `error.message` 为准。令牌只在系统钥匙串
(service `io.primit.axblade`,account `auth.backend`),`account.json` 只存
「邮箱 / 显示名 / 套餐」这份不含凭据的摘要,供离线启动时展示。

## 界面主题

Binance Dark/Light,**与官网共用同一份设计 token**:唯一来源是
`ChillSkill-Website/design-tokens.json`,Mac 端在 `Axblade/Views/Theme.swift`
的 `Theme.tokens` 里逐值镜像,`ThemeTokenTests` 会断言每个 hex,两边漂移当场红。

| token | dark | light | 用途 |
|-------|------|-------|------|
| background | `#0B0E11` | `#FFFFFF` | 页面 / 主区底 |
| surface | `#181A20` | `#FAFAFA` | 侧栏、卡片 |
| surface2 | `#1E2329` | `#F5F5F5` | 输入卡、悬停、代码块 |
| elevated / border | `#2B3139` | `#EAECEF` | 选中、边框 |
| text | `#EAECEF` | `#1E2329` | 正文 |
| muted | `#848E9C` | `#707A8A` | 次要文字 |
| disabled | `#5E6673` | `#B7BDC6` | 禁用 |
| accent / accentStrong | `#FCD535` / `#F0B90B` | 同左 | 币安黄、悬停强调 |
| onAccent | `#181A20` | 同左 | 黄底上的字 |
| accentSoft | 黄 12% | 黄 16% | 底纹、横幅、芯片 |
| up / down | `#0ECB81` / `#F6465D` | 同左 | 涨跌、成功/错误 |

圆角统一 4–8px(不用 pill),数字一律 `.monospacedDigit()`。

## 数据存放

沙盒 app,数据都在容器里:

```
~/Library/Containers/io.primit.axblade/Data/Library/Application Support/Axblade/
├── conversations.json
├── settings.json          # 模型/语言选择与数据源开关,不含任何密钥
└── account.json           # 邮箱/显示名/套餐的本地摘要,不含令牌
```

访问令牌在钥匙串,service = `io.primit.axblade`、account = `auth.backend`;
退出登录会直接删掉它。

## 快捷键

| 键 | 作用 |
|----|------|
| `Enter` | 发送 |
| `Option+Enter` | 换行 |
| `⌘N` | 新对话 |
| `⌘,` | 设置 |

## 架构

```
Axblade/
├── App/          AxbladeApp(WindowGroup + Settings 场景)
├── Models/       Conversation / ChatMessage / AppSettings / MarketModels
├── Services/
│   ├── Backend             官方后端地址、固定模型表、TokenStore(钥匙串令牌)
│   ├── AccountService      后端账户接口:注册/登录/登出/改密/me/usage/sessions
│   │                       + 社交登录(GitHub 设备码 / Apple identity token)
│   ├── AuthProviders       Sign in with Apple 的 async 包装与错误翻译
│   ├── Localization        AppLanguage + 中英文文案表(切换即时生效)
│   ├── SSEParser           逐行 SSE 解析(不知道 HTTP)
│   ├── ChatService         协议 + OpenAI 兼容实现(固定打官方后端)+ 流循环
│   ├── ConversationStore   JSON 持久化(原子写)
│   ├── JSONCoding          毫秒级 ISO8601 编解码
│   ├── MarkdownSegmenter   按 ``` 围栏切段
│   ├── MarkdownBlockParser 标题 / 列表 / 引用 / 分割线 / 表格 / 段落(行内语法交给 AttributedString)
│   └── KeychainStore       访问令牌(service io.primit.axblade)
├── ViewModels/   AppViewModel(会话编排 + 账户状态,@MainActor)
└── Views/        Sidebar / Chat / MessageRow / Composer / EmptyState /
                  AccountSettings(GitHub/Apple/邮箱登录 + 设备码提示 + 额度权限仪表盘)/ Settings /
                  MarkdownText / BrandMark / Theme(镜像 design-tokens.json)
```

设计与实现记录见 `docs/superpowers/`。

## 已知边界(v1 不做)

自定义模型服务(只走官方后端)、多模态、联网搜索、工具调用、多窗口标签、iCloud 同步、中英文之外的语言(量化报告正文暂为中文)。
