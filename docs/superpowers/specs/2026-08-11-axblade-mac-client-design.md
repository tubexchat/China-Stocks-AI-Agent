# Axblade for Mac — 原生 AI 客户端设计规格

日期:2026-08-11
仓库:`Primit-io/Axblade-Mac-Cli`
状态:已定稿(自主执行模式下由 Claude 决策;可随时修订)

## 1. 目标

用原生语言(Swift + SwiftUI)构建一个运行在 Apple Silicon(M 系列芯片,arm64)上的
macOS AI 聊天客户端。界面参考 Claude、Gemini、Kimi 等成熟产品的交互范式,
视觉沿用 Axblade 品牌(深色 + 青色霓虹,与营销站一致)。

**非目标(v1 不做)**:多模态(图片/文件上传)、联网搜索、Agent 工具调用、
多窗口标签、iCloud 同步、英文以外的多语言完整 i18n。

## 2. 技术选型

| 方案 | 结论 |
|------|------|
| Swift + SwiftUI + XcodeGen | ✅ 采用。纯原生、arm64 原生、开发效率高、`project.yml` 声明式入库 |
| Swift + AppKit | 控制力强但代码量数倍,MVP 不划算 |
| Electron / Tauri | 非原生语言,违背需求,排除 |

- 部署目标:**macOS 14.0+**,`ARCHS = arm64`(M 系列原生)。
- Swift 6.x,严格并发;UI 层 `@MainActor`。
- 无第三方依赖:网络用 URLSession,Markdown 用 AttributedString + 自研代码块分段。

## 3. 架构(MVVM)

```
AxbladeApp (App entry)
├── Models/          Conversation, ChatMessage, ProviderConfig, ProviderKind
├── Services/
│   ├── ChatService        协议: stream(messages, config) -> AsyncThrowingStream<String>
│   ├── OpenAIChatService  OpenAI 兼容 /chat/completions SSE(覆盖 OpenAI/Kimi/DeepSeek/Ollama/LM Studio)
│   ├── AnthropicChatService  Anthropic /v1/messages SSE(Claude)
│   ├── SSEParser          行缓冲 SSE 解析器(纯函数,可单测)
│   ├── ConversationStore  JSON 持久化 → ~/Library/Application Support/Axblade/
│   └── KeychainStore      API Key 存系统钥匙串
├── ViewModels/      AppViewModel(会话列表、当前会话、发送/停止/重命名/删除)
└── Views/           SidebarView, ChatView, MessageRow, ComposerView,
                     EmptyStateView, SettingsView, MarkdownText, Theme
```

各单元职责单一:SSEParser 不知道 HTTP;ChatService 不知道 UI;
Store 只管序列化;ViewModel 串接一切并持有取消用的 Task。

## 4. 数据模型

- `ChatMessage { id, role(user/assistant/system), content, createdAt, isError }`
- `Conversation { id, title, messages, createdAt, updatedAt, modelOverride? }`
- `ProviderConfig { id, kind(openaiCompatible/anthropic), name, baseURL, model, 其余存 Keychain 的 apiKey }`
- 持久化:`conversations.json` + `settings.json`,原子写入;API Key 只进 Keychain。

## 5. 流式请求

- `URLSession.bytes(for:)` + 逐行 SSE 解析,`AsyncThrowingStream` 向上游发文本增量。
- OpenAI 兼容:`choices[0].delta.content`;`data: [DONE]` 结束。
- Anthropic:`content_block_delta` 的 `delta.text`;`message_stop` 结束。
- 发送后立即插入空 assistant 消息,增量追加;Task 取消即"停止生成"。
- 错误(网络/4xx/密钥缺失)以红色错误样式消息呈现在会话内,不弹阻断式对话框。

## 6. UI 设计(参考成熟产品)

- **布局**:`NavigationSplitView`。侧栏 = 会话列表(按更新时间倒序)+「新对话」按钮
  (Claude/Kimi 范式);右侧 = 聊天区。
- **空状态**:居中 Axblade 标志 + 问候语 + 4 个建议 chips,点击即发送(Gemini 范式)。
- **消息**:用户消息右对齐圆角气泡(surface 色);AI 消息带品牌标志、全宽无气泡
  (Claude 范式);流式中尾部显示光标块。
- **Markdown**:段落/粗斜体/行内代码走 AttributedString;``` 代码块单独分段渲染
  (等宽字体、深色卡片、复制按钮)。
- **输入区**:底部圆角大输入框,自动增高(1–8 行),Enter 发送、Shift+Enter 换行;
  流式中变为「停止」按钮;左下角模型选择器(Claude/Kimi 范式)。
- **设置**:标准 macOS Settings 场景。Provider 管理(增删、类型、Base URL、
  API Key、模型名)+ 默认 provider 选择。
- **主题**:强制深色。`bg #0b0d10 / surface #12151a / border #232830 /
  text #e8ecf1 / muted #98a2ad / accent #22d3ee`(与营销站 globals.css 一致)。
- 文案:中文优先(v1 不做完整 i18n)。

## 7. 构建与工程

- XcodeGen `project.yml` 生成 `Axblade.xcodeproj`;生成物不入库,`project.yml` 入库。
- Target:`Axblade`(app,SwiftUI 生命周期)+ `AxbladeTests`(unit)。
- 签名:本地开发用 ad-hoc / automatic;无沙盒外网络权限问题
  (App Sandbox 开启 + `com.apple.security.network.client`)。

## 8. 测试与验收

- 单测:SSEParser(OpenAI/Anthropic 两种流、分块边界、[DONE]、异常行)、
  ConversationStore(往返序列化、原子写)、Markdown 分段器。
- 构建验收:`xcodebuild build test` 通过,产物为 arm64。
- UI 验收:启动 app,截图核对侧栏/空状态/消息流/设置四个界面。
