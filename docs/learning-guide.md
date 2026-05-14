# New API 项目学习指南

> 本文档面向希望深入理解 New API 项目的开发者。涵盖项目架构、核心流程、开发指南和最佳实践。

---

## 目录

1. [项目概述](#1-项目概述)
2. [快速开始](#2-快速开始)
3. [系统架构](#3-系统架构)
4. [目录结构详解](#4-目录结构详解)
5. [启动流程](#5-启动流程)
6. [请求处理流程](#6-请求处理流程)
7. [Provider 适配器体系](#7-provider-适配器体系)
8. [计费系统](#8-计费系统)
9. [数据库模型](#9-数据库模型)
10. [渠道分发机制](#10-渠道分发机制)
11. [中间件体系](#11-中间件体系)
12. [配置系统](#12-配置系统)
13. [前端开发](#13-前端开发)
14. [如何添加新的 AI 提供商](#14-如何添加新的-ai-提供商)
15. [部署与运维](#15-部署与运维)

---

## 1. 项目概述

New API 是一个 **AI API 网关 / 代理系统**，统一聚合 40+ 上游 AI 提供商（OpenAI、Claude、Gemini、Azure、AWS Bedrock 等）到单一 API 接口，并提供用户管理、计费、速率限制和管理面板。

### 核心能力

- **统一接入**：所有提供商通过 OpenAI 兼容接口访问，支持 `/v1/chat/completions`、`/v1/messages`、`/v1/embeddings`、`/v1/images`、`/v1/audio` 等
- **多协议支持**：OpenAI 格式、Claude 格式、Gemini 格式自动识别和转换
- **流式支持**：SSE 流式响应，包含 usage 信息
- **计费系统**：支持按量计费、阶梯计费、表达式计费、缓存计费
- **渠道管理**：多渠道负载均衡、自动测试、故障转移、渠道亲和性
- **用户系统**：注册登录、Token 管理、2FA、Passkey、OAuth
- **订阅系统**：订阅计划、自动续费、额度重置
- **管理面板**：两大前端主题（default/classic）嵌入 Go 二进制
- **异步任务**：视频生成（Sora、Kling、Jimeng）、音乐生成（Suno）的任务轮询和计费

### 技术栈

| 层次 | 技术 |
|------|------|
| 后端语言 | Go 1.22+ |
| Web 框架 | Gin v1.9.1 |
| ORM | GORM v2 |
| 数据库 | SQLite / MySQL 5.7.8+ / PostgreSQL 9.6+ |
| 缓存 | Redis (go-redis) + 内存缓存 |
| 前端 | React 19 + TypeScript + Rsbuild（default 主题） |
| 前端包管理 | Bun |
| 认证 | JWT、WebAuthn/Passkey、OAuth（GitHub/Discord/OIDC） |
| 支付 | Stripe、Creem、Epay、Waffo |

---

## 2. 快速开始

### 环境要求

- Go 1.22+
- Node.js 18+（前端开发）
- Bun（推荐的前端包管理器）
- SQLite（开发默认）/ MySQL / PostgreSQL
- Redis（可选，推荐生产使用）

### 开发环境搭建

```bash
# 1. 克隆仓库
git clone https://github.com/QuantumNous/new-api.git
cd new-api

# 2. 复制环境变量文件
cp .env.example .env
# 编辑 .env 配置数据库等参数

# 3. 启动后端（开发模式）
go run main.go

# 4. 前端开发（另一个终端）
cd web/default
bun install
bun run dev
```

### 环境变量

关键环境变量（详见 `.env.example`）：

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `PORT` | HTTP 监听端口 | `3000` |
| `SQL_DSN` | 数据库 DSN | `new_api.db`（SQLite） |
| `REDIS_CONN_STRING` | Redis 连接 | 空（禁用） |
| `SESSION_SECRET` | 会话密钥 | `random` |
| `SYNC_FREQUENCY` | 缓存同步频率（秒） | `120` |
| `BATCH_UPDATE_ENABLED` | 批量更新 | `false` |
| `LOG_DSN` | 独立日志数据库 | 空（与主库共用） |
| `GIN_MODE` | Gin 运行模式 | `release` |

---

## 3. 系统架构

### 分层架构

```
Router → Middleware → Controller → Service → Model
  ↑                        ↓
  └── Relay (Provider Adapters)
```

### 架构全景图

```
┌─────────────┐     ┌─────────────────────────────────────────────┐
│  客户端      │     │              New API 网关                    │
│ (OpenAI SDK) │────▶│  ┌─────────┐ ┌──────────┐ ┌─────────────┐  │
└─────────────┘     │  │ Router  │ │Middleware│ │ Controller  │  │
                    │  └─────────┘ └──────────┘ └──────┬───────┘  │
                    │                                  │          │
                    │  ┌───────────────────────────────▼────────┐ │
                    │  │              Relay Layer               │ │
                    │  │  ┌────────┐ ┌────────┐ ┌───────────┐  │ │
                    │  │  │OpenAI  │ │Claude  │ │Gemini     │  │ │
                    │  │  │Adaptor │ │Adaptor │ │Adaptor    │  │ │
                    │  │  └───┬────┘ └───┬────┘ └─────┬─────┘  │ │
                    │  │      └───────┬──┴──────┬──────┘        │ │
                    │  │              ▼         ▼               │ │
                    │  │      HTTP Requests to Providers        │ │
                    │  └────────────────────────────────────────┘ │
                    │                                              │
                    │  ┌─────────┐ ┌────────┐ ┌───────────────┐  │
                    │  │ Service │ │ Model  │ │ Setting/Config│  │
                    │  └─────────┘ └────────┘ └───────────────┘  │
                    └──────────────────────────────────────────────┘
```

### 设计模式

1. **适配器模式（Adaptor）** — 每个 AI 提供商实现 `Adaptor` 接口，统一在 relay 层调用
2. **注册模式（Registry）** — Setting 模块、OAuth 提供商等使用注册模式动态加载
3. **中间件链（Middleware Chain）** — Gin 中间件链处理认证、分发、限流
4. **数据访问对象（DAO）** — Model 层封装 GORM 操作
5. **快照模式（Snapshot）** — 计费系统使用 `BillingSnapshot` 冻结状态，确保结算一致性

---

## 4. 目录结构详解

```
new-api/
├── main.go                  # 应用入口：初始化资源、启动 HTTP 服务
├── common/                  # 通用工具和全局变量
│   ├── constants.go         # 全局变量（端口、缓存、限流等）
│   ├── json.go              # JSON 序列化封装（所有 JSON 操作必须通过此文件）
│   ├── redis.go             # Redis 客户端
│   ├── env.go               # 环境变量解析
│   └── ...
├── constant/                # 常量定义
│   ├── channel.go           # 渠道类型枚举（1=OpenAI, 14=Anthropic, ...）
│   ├── context.go           # Gin Context Key 常量
│   └── ...
├── controller/              # HTTP 请求处理器（Controller 层）
│   ├── relay.go             # 核心 Relay 控制器
│   ├── channel.go           # 渠道 CRUD
│   ├── user.go              # 用户管理
│   ├── token.go             # Token 管理
│   ├── log.go               # 日志查询
│   ├── option.go            # 系统选项
│   ├── oauth.go             # OAuth 登录
│   ├── twofa.go             # 2FA 管理
│   ├── subscription.go      # 订阅管理
│   ├── topup_*.go           # 充值（Stripe/Creem/Waffo）
│   └── ...
├── service/                 # 业务逻辑层
│   ├── channel.go           # 渠道选择
│   ├── channel_affinity.go  # 渠道亲和性
│   ├── quota.go             # 配额计算
│   ├── text_quota.go        # 文本模型配额
│   ├── tiered_settle.go     # 阶梯计费结算
│   ├── billing.go           # 计费会话
│   ├── convert.go           # 请求格式转换
│   ├── token_counter.go     # Token 计数
│   └── ...
├── model/                   # 数据访问层（GORM）
│   ├── main.go              # 数据库初始化、迁移
│   ├── channel.go           # Channel 模型
│   ├── user.go              # User 模型
│   ├── token.go             # Token 模型
│   ├── log.go               # Log 模型
│   ├── option.go            # Option 模型
│   └── ...
├── middleware/              # Gin 中间件
│   ├── auth.go              # 认证（Token 认证/会话认证/管理员认证）
│   ├── distributor.go       # 渠道分发
│   ├── rate-limit.go        # 速率限制
│   ├── cors.go              # CORS
│   └── ...
├── relay/                   # AI 提供商中继层（核心）
│   ├── relay_task.go        # 中继任务编排
│   ├── websocket.go         # WebSocket 处理（realtime API）
│   ├── channel/             # 各提供商的适配器实现
│   │   ├── adapter.go       # Adaptor / TaskAdaptor 接口定义
│   │   ├── openai/          # OpenAI（也作为 Azure/Custom 等的基础）
│   │   ├── claude/          # Anthropic Claude
│   │   ├── gemini/          # Google Gemini
│   │   ├── azure/           # Azure OpenAI（直接在 openai/ 中处理）
│   │   ├── aws/             # AWS Bedrock
│   │   ├── vertex/          # Google Vertex AI
│   │   ├── ollama/          # Ollama
│   │   ├── deepseek/        # DeepSeek
│   │   ├── ...
│   │   └── task/            # 异步任务适配器
│   │       ├── suno/        # Suno 音乐生成
│   │       ├── kling/       # Kling 视频生成
│   │       ├── sora/        # OpenAI Sora 视频
│   │       └── ...
│   ├── common/              # 中继通用类型
│   │   ├── relay_info.go    # RelayInfo 结构体（传递请求上下文）
│   │   └── override.go      # 请求参数覆盖系统
│   ├── helper/              # 辅助函数
│   │   ├── price.go         # 价格计算
│   │   ├── stream_scanner.go # SSE 流扫描
│   │   └── ...
│   └── constant/            # 中继模式常量
├── router/                  # 路由注册
│   ├── main.go              # SetRouter() 入口
│   ├── api-router.go        # /api/* 路由
│   ├── relay-router.go      # /v1/*, /mj/*, /suno/* 路由
│   ├── video-router.go      # 视频生成路由
│   ├── dashboard-router.go  # OpenAI 兼容的计费端点
│   └── web-router.go        # 前端 SPA 静态文件服务
├── setting/                 # 配置管理
│   ├── config/              # 配置注册框架
│   ├── system_setting/      # 系统设置
│   ├── operation_setting/   # 运营设置
│   ├── billing_setting/     # 计费设置（阶梯计费表达式）
│   ├── ratio_setting/       # 模型配额比例设置
│   └── ...
├── dto/                     # 数据传输对象
│   ├── dto.go               # GeneralOpenAIRequest / GeneralOpenAIResponse
│   ├── claude.go            # Claude 格式
│   ├── gemini.go            # Gemini 格式
│   └── ...
├── types/                   # 类型定义
│   ├── relay_format.go      # 中继格式枚举
│   ├── errors.go            # 自定义错误
│   └── ...
├── i18n/                    # 国际化
│   ├── i18n.go              # 翻译函数
│   └── locales/             # 翻译文件（en, zh-CN, zh-TW）
├── oauth/                   # OAuth 提供商框架
│   ├── provider.go          # Provider 接口
│   ├── registry.go          # 注册中心
│   ├── github.go            # GitHub OAuth
│   ├── discord.go           # Discord OAuth
│   ├── oidc.go              # OIDC 通用
│   └── generic.go           # 通用 OAuth（可从数据库加载）
├── pkg/                     # 内部包
│   ├── billingexpr/         # 计费表达式引擎
│   ├── cachex/              # 混合缓存
│   └── perf_metrics/        # 性能指标
├── logger/                  # 日志系统
├── web/                     # 前端代码
│   ├── default/             # 默认主题（React + Rsbuild）
│   └── classic/             # 经典主题（React + Vite）
├── docs/                    # 文档
├── electron/                # Electron 桌面应用
└── Dockerfile               # 多阶段 Docker 构建
```

---

## 5. 启动流程

`main.go` 的 `main()` 函数执行以下步骤：

### 阶段一：资源初始化（`InitResources()`）

```
1. godotenv.Load(".env")         ← 加载 .env 文件
2. common.InitEnv()              ← 解析环境变量到全局配置
3. logger.SetupLogger()          ← 初始化日志系统（文件轮转）
4. ratio_setting.InitRatioSettings() ← 加载模型配额比例
5. service.InitHttpClient()      ← 配置共享 HTTP 客户端
6. service.InitTokenEncoders()   ← 初始化 Token 编码器（tiktoken）
7. model.InitDB()                ← 连接数据库，运行 GORM 自动迁移
8. model.CheckSetup()            ← 检查系统初始化状态，创建 root 用户
9. model.InitOptionMap()         ← 从数据库加载 options 到内存
10. common.CleanupOldCacheFiles() ← 清理过期磁盘缓存
11. model.GetPricing()           ← 加载价格数据
12. model.InitLogDB()            ← 可选：连接独立日志数据库
13. common.InitRedisClient()     ← 可选：连接 Redis
14. perfmetrics.Init()           ← 启动性能指标采集
15. common.StartSystemMonitor()  ← 启动 CPU/内存监控
16. i18n.Init()                  ← 加载翻译文件
17. oauth.LoadCustomProviders()  ← 从数据库加载自定义 OAuth 提供商
```

### 阶段二：缓存与后台任务

```
1. model.InitChannelCache()      ← 初始化渠道缓存
2. go model.SyncChannelCache()   ← 后台同步渠道缓存
3. go model.SyncOptions()        ← 热更新配置选项
4. go model.UpdateQuotaData()    ← 数据看板聚合
5. go controller.AutomaticallyUpdateChannels()  ← 定时更新渠道
6. go controller.AutomaticallyTestChannels()    ← 定时测试渠道
7. service.StartCodexCredentialAutoRefreshTask() ← Codex OAuth 刷新
8. service.StartSubscriptionQuotaResetTask()     ← 订阅额度重置
9. controller.StartChannelUpstreamModelUpdateTask() ← 上游模型更新
10. go controller.UpdateMidjourneyTaskBulk()     ← MJ 任务轮询
11. go controller.UpdateTaskBulk()               ← 视频/音乐任务轮询
```

### 阶段三：HTTP 服务器启动

```
1. gin.New() + CustomRecovery    ← 创建 Gin 引擎
2. server.Use(middleware...)
   └─ RequestId, PoweredBy, I18n, Logger, Sessions (cookie store)
3. InjectUmamiAnalytics()        ← 注入 Umami 统计脚本
4. InjectGoogleAnalytics()       ← 注入 Google Analytics 脚本
5. router.SetRouter()            ← 注册所有路由
6. server.Run(":3000")           ← 启动 HTTP 监听
```

---

## 6. 请求处理流程

### 6.1 API 请求流程

以 `/api/user/login` 为例：

```
客户端 HTTP 请求
    │
    ▼
Gin Router ─── 匹配路由组和中间件
    │
    ▼
Middleware Chain:
  ┌─ RequestId      ── 分配唯一请求 ID
  ├─ PoweredBy      ── 设置 X-Powered-By 头
  ├─ I18n           ── 检测语言（Accept-Language → 用户设置 → 默认）
  ├─ Logger         ── 记录请求日志
  └─ Sessions       ── 加载会话
    │
    ▼
Controller (user.go) ── 处理请求逻辑
    │
    ▼
Service (可选)     ── 调用业务逻辑
    │
    ▼
Model              ── 数据库操作 (GORM)
    │
    ▼
JSON Response
```

### 6.2 AI 请求流程（Relay 核心流程）

以 `POST /v1/chat/completions` 为例：

```
客户端请求
  Authorization: Bearer sk-xxx
  POST /v1/chat/completions
    │
    ▼
Router (relay-router.go)
    │
    ▼
Middleware Chain:
  ├─ RequestId
  ├─ TokenAuth()          ── 验证 API Token
  │   ├─ 从 Header 提取 Authorization: Bearer sk-xxx
  │   ├─ 查找 Token（缓存/数据库）
  │   └─ 验证 Token 状态、额度、IP 限制
  │
  ├─ Distribute()         ── 渠道分发（核心步骤）
  │   ├─ 从 Token 获取用户组 (group)
  │   ├─ 从请求中解析模型名 (model)
  │   ├─ 查找匹配的渠道（group + model）
  │   ├─ 应用渠道亲和性（优先使用最近成功的渠道）
  │   ├─ 渠道密钥轮换（多 key 渠道）
  │   └─ 设置渠道信息到 Context
  │       ├─ ChannelId, ChannelType, ChannelKey
  │       ├─ BaseURL, ModelMapping
  │       └─ 其他渠道设置
  │
  ├─ ModelRequestRateLimit() ── 模型级别限流
  │
  └─ 其他中间件...
    │
    ▼
Controller (relay.go → relayTask())
    │
    ▼
1. 确定 RelayFormat (OpenAI / Claude / Gemini)
2. 确定 RelayMode (ChatCompletions / Embeddings / ...)
3. 确定 Adaptor（根据 ChannelType）
    │
    ▼
4. Adaptor.ConvertOpenAIRequest()  ← 转换请求格式
   └─ 如果是 Claude/Gemini 请求格式，先转为 OpenAI 格式
    │
    ▼
5. Pre-consume Quota（预扣费）
   ├─ 计算预估 Token 消耗
   ├─ 调用 Price 计算预估费用
   ├─ 扣除用户配额（预扣）
   └─ 创建 BillingSnapshot（计费快照）
    │
    ▼
6. Adaptor.DoRequest()     ← 发送请求到上游提供商
   ├─ 构建上游 URL（GetRequestURL）
   ├─ 设置请求头（SetupRequestHeader）
   └─ 发送 HTTP 请求
    │
    ▼
7. Adaptor.DoResponse()    ← 处理上游响应
   ├─ 流式响应：逐块转换并写入客户端响应
   ├─ 非流式响应：一次转换
   └─ 提取 Token 用量
    │
    ▼
8. Post-consume Quota（结算）
   ├─ 从响应中提取实际 Token 用量
   ├─ 计算实际费用
   ├─ 结算预扣与实际的差额（多退少补）
   └─ 记录日志
    │
    ▼
9. 返回响应给客户端
```

### 6.3 适配器选择逻辑

```go
// relay/relay_task.go
func GetAdaptor(channelType int) Adaptor {
    switch channelType {
    case constant.ChannelTypeOpenAI:
        return &openai.Adaptor{ChannelType: channelType}
    case constant.ChannelTypeAnthropic:
        return &claude.Adaptor{}
    case constant.ChannelTypeGemini:
        return &gemini.Adaptor{}
    // ... 40+ providers
    }
}
```

---

## 7. Provider 适配器体系

### Adaptor 接口

每个 AI 提供商必须实现 `channel.Adaptor` 接口（`relay/channel/adapter.go`）：

```go
type Adaptor interface {
    Init(info *RelayInfo)
    GetRequestURL(info *RelayInfo) (string, error)
    SetupRequestHeader(c *gin.Context, req *http.Header, info *RelayInfo) error
    ConvertOpenAIRequest(c *gin.Context, info *RelayInfo, request *dto.GeneralOpenAIRequest) (any, error)
    ConvertRerankRequest(c *gin.Context, relayMode int, request dto.RerankRequest) (any, error)
    ConvertEmbeddingRequest(c *gin.Context, info *RelayInfo, request dto.EmbeddingRequest) (any, error)
    ConvertAudioRequest(c *gin.Context, info *RelayInfo, request dto.AudioRequest) (io.Reader, error)
    ConvertImageRequest(c *gin.Context, info *RelayInfo, request dto.ImageRequest) (any, error)
    DoRequest(c *gin.Context, info *RelayInfo, requestBody io.Reader) (any, error)
    DoResponse(c *gin.Context, resp *http.Response, info *RelayInfo) (usage any, err *types.NewAPIError)
    GetModelList() []string
    GetChannelName() string
    ConvertClaudeRequest(c *gin.Context, info *RelayInfo, request *dto.ClaudeRequest) (any, error)
    ConvertGeminiRequest(c *gin.Context, info *RelayInfo, request *dto.GeminiChatRequest) (any, error)
}
```

### 异步任务适配器（TaskAdaptor）

用于视频生成、音乐生成等异步操作：

```go
type TaskAdaptor interface {
    Init(info *RelayInfo)
    ValidateRequestAndSetAction(c *gin.Context, info *RelayInfo) *dto.TaskError
    EstimateBilling(c *gin.Context, info *RelayInfo) map[string]float64
    AdjustBillingOnSubmit(info *RelayInfo, taskData []byte) map[string]float64
    AdjustBillingOnComplete(task *model.Task, taskResult *TaskInfo) int
    BuildRequestURL(info *RelayInfo) (string, error)
    BuildRequestHeader(c *gin.Context, req *http.Request, info *RelayInfo) error
    BuildRequestBody(c *gin.Context, info *RelayInfo) (io.Reader, error)
    DoRequest(c *gin.Context, info *RelayInfo, requestBody io.Reader) (*http.Response, error)
    DoResponse(c *gin.Context, resp *http.Response, info *RelayInfo) (taskID string, taskData []byte, err *dto.TaskError)
    GetModelList() []string
    GetChannelName() string
    FetchTask(baseUrl, key string, body map[string]any, proxy string) (*http.Response, error)
    ParseTaskResult(respBody []byte) (*TaskInfo, error)
}
```

### RelayInfo 结构体

`relay/common/relay_info.go` 是贯穿整个中继请求的核心上下文，携带所有关键信息：

| 字段 | 类型 | 说明 |
|------|------|------|
| ChannelType | int | 渠道类型（对应 constant.ChannelTypeXxx） |
| ChannelId | int | 渠道 ID |
| ChannelKey | string | 渠道 API Key |
| ChannelBaseUrl | string | 渠道基础 URL |
| ChannelSetting | *dto.ChannelSetting | 渠道详细设置 |
| OriginModelName | string | 客户端请求的原始模型名 |
| UpstreamModelName | string | 映射后的上游模型名 |
| UserId | int | 用户 ID |
| TokenId | int | Token ID |
| TokenName | string | Token 名称 |
| Group | string | 用户组 |
| IsStream | bool | 是否为流式请求 |
| RelayMode | int | 中继模式（ChatCompletions, Embeddings 等） |
| RelayFormat | int | 请求格式（OpenAI/Claude/Gemini） |
| OriginModelPrice | float64 | 原始模型价格 |
| Ratio | float64 | 配额比例 |
| Quota | float64 | 预估配额 |
| PreConsumedQuota | int64 | 已预扣配额 |
| BillingSnapshot | *BillingSnapshot | 计费快照（冻结状态） |
| HeadersOverride | map[string]string | 请求头覆盖 |
| Override | dto.OverrideConfig | URL/模型/参数覆盖 |
| ... | | |

### 请求格式转换流

```
客户端请求格式 → 内部 OpenAI 格式 → 上游提供商格式 → 上游提供商响应 → OpenAI 格式响应
```

支持三种请求格式的自动识别和转换：

| 路径 | 请求格式 | 目标格式库 |
|------|----------|------------|
| `/v1/chat/completions` | OpenAI | `dto.GeneralOpenAIRequest` |
| `/v1/messages` | Claude | `dto.ClaudeRequest` → 转为 OpenAI |
| `/v1beta/models/` | Gemini | `dto.GeminiChatRequest` → 转为 OpenAI |

转换函数位于 `service/convert.go`：
- `ClaudeToOpenAIRequest()` — Claude 到 OpenAI 格式转换
- `GeminiToOpenAIRequest()` — Gemini 到 OpenAI 格式转换

### 覆盖系统（Override）

`relay/common/override.go` 实现了一个强大的请求参数覆盖系统：

- **模型映射**：将请求模型名映射为上游模型名
- **URL 重写**：修改请求 URL 路径
- **Header 覆盖/注入**：添加或覆盖 HTTP 请求头
- **Body 参数覆盖/注入**：修改请求体参数
- **状态码映射**：将上游 HTTP 状态码映射为自定义状态码
- **表达式引擎**：支持 Go 模板和 `expr-lang` 表达式实现动态覆盖

---

## 8. 计费系统

### 计费模式

系统支持多种计费模式：

1. **固定比例计费**：模型固定配额比例
2. **阶梯计费（Tiered Billing）**：基于上下文长度分档定价
3. **表达式计费（Billing Expression）**：灵活的表达式定价（推荐方式）

### 计费流程

```
请求到达 → 预扣费 → 渠道请求 → 响应返回 → 结算
                │                    │
                ▼                    ▼
        根据请求估算 Token      根据实际响应 Token
        计算预估配额            计算实际配额
        冻结计费快照            结算差额（多退少补）
```

### 表达式计费系统

详见 `pkg/billingexpr/expr.md`，核心要点：

表达式格式示例：
```
# 简单固定定价
tier("base", p * 2.5 + c * 15 + cr * 0.25)

# 多档阶梯定价
len <= 200000
  ? tier("standard", p * 3 + c * 15)
  : tier("long_context", p * 6 + c * 22.5)
```

**变量说明**：

| 变量 | 含义 |
|------|------|
| `p` | 输入 token（计价用，自动排除单独定价的子类别） |
| `len` | 输入总长度（条件用，不受排除影响） |
| `cr` | 缓存命中（读取）token |
| `cc` | 缓存创建 token（5 分钟 TTL） |
| `cc1h` | 缓存创建 token（1 小时 TTL） |
| `img` | 图片输入 token |
| `ai` | 音频输入 token |
| `c` | 输出 token |
| `img_o` | 图片输出 token |
| `ao` | 音频输出 token |

**请求规则**（通过 `|||` 分隔）：
```
tier("base", p * 5 + c * 25)|||when(header("anthropic-beta") has "fast-mode") * 6
```

### Token 标准化（AST 内省）

系统通过解析表达式的 AST（抽象语法树）自动判断哪些变量被引用，从而从 `p` 和 `c` 中减去已单独计价的子类别：
- 如果表达式使用了 `cr`，缓存读取 token 从 `p` 中减去
- 如果没使用 `img`，图片 token 留在 `p` 中按基础价格计费

### 文件映射

| 层次 | 文件 |
|------|------|
| 表达式引擎 | `pkg/billingexpr/compile.go`, `run.go`, `settle.go` |
| 表达式存储 | `setting/billing_setting/tiered_billing.go` |
| 预扣费 | `relay/helper/price.go` → `modelPriceHelperTiered()` |
| 结算 | `service/tiered_settle.go`, `service/quota.go` |
| 日志注入 | `service/log_info_generate.go` |
| 前端编辑器 | `web/default/src/pages/Setting/Ratio/components/TieredPricingEditor.jsx` |

---

## 9. 数据库模型

### 核心模型

| 模型 | 表名 | 说明 |
|------|------|------|
| `Channel` | `channels` | AI 提供商渠道配置 |
| `Token` | `tokens` | 用户 API Token |
| `User` | `users` | 用户账户 |
| `Option` | `options` | 系统配置键值对 |
| `Log` | `logs` | 请求日志 |
| `Ability` | `abilities` | 渠道模型权限映射 |
| `Redemption` | `redemptions` | 兑换码 |
| `Midjourney` | `midjourneys` | Midjourney 任务 |
| `TopUp` | `top_ups` | 充值记录 |
| `Task` | `tasks` | 异步任务（视频/音乐等） |
| `Pricing` | `pricing` | 模型定价 |
| `SubscriptionOrder` | `subscription_orders` | 订阅订单 |
| `SubscriptionPlan` | `subscription_plans` | 订阅计划 |
| `UserSubscription` | `user_subscriptions` | 用户订阅 |
| `CustomOAuthProvider` | `custom_oauth_providers` | 自定义 OAuth 提供商 |

### 数据库初始化

`model/main.go` 中 `InitDB()`：
1. 支持 SQLite、MySQL、PostgreSQL
2. GORM `AutoMigrate` 自动创建/更新表结构
3. 可分离主 DB 和日志 DB（`InitLogDB()`）
4. 连接池配置（空闲/最大/生命周期）

### 跨数据库兼容

| 注意事项 | 处理方式 |
|----------|----------|
| 列引用 | PostgreSQL 用 `"column"`，MySQL/SQLite 用 `` `column` `` |
| 布尔值 | PostgreSQL 用 `true/false`，MySQL/SQLite 用 `1/0` |
| JSON 存储 | 统一用 TEXT 字段 |
| 保留字列名 | 使用 `commonGroupCol`, `commonKeyCol` 变量 |
| 数据库检测 | `common.UsingPostgreSQL`, `common.UsingSQLite`, `common.UsingMySQL` |

### 缓存体系

- **渠道缓存**：`model/channel_cache.go` — 内存 + Redis 双层缓存
- **Token 缓存**：`model/token_cache.go` — 缓存 Token 查询结果
- **用户缓存**：`model/user_cache.go` — 缓存用户信息
- **批量更新**：`model/batch_update.go` — 定期批量写入数据库
- **配置热更新**：`model/SyncOptions()` — 定时从数据库刷新 Option 配置

---

## 10. 渠道分发机制

### 分发流程（`middleware/distributor.go`）

```
1. 从请求中解析模型名（model）
2. 从 Token 中获取用户组（group）
3. 在 Ability 表中查找匹配的渠道
   └─ 条件：渠道启用 + 模型匹配 + 组匹配 + 配额充足
4. 应用渠道亲和性规则
   └─ 优先使用亲和性最高的渠道
5. 渠道密钥轮换（多 Key 渠道）
   └─ 轮询使用渠道下的多个 API Key
6. 设置渠道信息到请求上下文
```

### 渠道亲和性（`service/channel_affinity.go`）

- 记录每次请求的成功/失败状态
- 亲和性越高，优先级越高
- 失败后降低亲和性，实现自动故障转移

### 渠道选择（`service/channel_select.go`）

- 支持多种选择策略
- 模型级别 Token 限制检查
- 自动跳过配额不足的渠道

### 数据库表（Ability）

`abilities` 表存储渠道的模型权限：

| 字段 | 说明 |
|------|------|
| `group` | 用户组 |
| `model` | 模型名 |
| `channel_id` | 渠道 ID |
| `enabled` | 是否启用 |

---

## 11. 中间件体系

| 中间件 | 文件 | 功能 |
|--------|------|------|
| `RequestId` | `request-id.go` | 为每个请求分配唯一 ID |
| `PoweredBy` | `powered-by.go` | 设置 `X-Powered-By` 响应头 |
| `I18n` | `i18n.go` | 根据 `Accept-Language` 设置语言 |
| `SetUpLogger` | `logger.go` | Gin 请求日志记录 |
| `Sessions` | — | Cookie 会话存储 |
| `TokenAuth` | `auth.go` | 验证 Bearer Token |
| `TokenAuthReadOnly` | `auth.go` | 只读 Token 验证 |
| `TokenOrUserAuth` | `auth.go` | Token 或会话认证 |
| `AdminAuth` | `auth.go` | 管理员权限验证 |
| `RootAuth` | `auth.go` | Root 超级管理员验证 |
| `Distribute` | `distributor.go` | 渠道分发（分配上游提供商） |
| `GlobalAPIRateLimit` | `rate-limit.go` | 全局 API 速率限制（Redis/内存） |
| `ModelRequestRateLimit` | `model-rate-limit.go` | 模型级别速率限制 |
| `CriticalRateLimit` | `rate-limit.go` | 关键操作（登录/注册）限流 |
| `SearchRateLimit` | `rate-limit.go` | 搜索接口限流 |
| `EmailVerificationRateLimit` | `email-verification-rate-limit.go` | 邮箱验证限流 |
| `CORS` | `cors.go` | 跨域配置 |
| `TurnstileCheck` | `turnstile-check.go` | Cloudflare Turnstile 验证码 |
| `Cache` | `cache.go` | 静态资源浏览器缓存 |
| `BodyStorageCleanup` | `body_cleanup.go` | 请求体清理 |
| `DisableCache` | `disable-cache.go` | 禁用缓存头 |
| `SecureVerificationRequired` | `secure_verification.go` | 安全验证要求 |
| `SystemPerformanceCheck` | `performance.go` | 系统负载检查 |
| `JimengRequestConvert` | `jimeng_adapter.go` | Jimeng 请求格式转换 |
| `KlingRequestConvert` | `kling_adapter.go` | Kling 请求格式转换 |

---

## 12. 配置系统

### 配置来源（优先级从高到低）

```
环境变量 > 数据库选项表 > 默认值
```

### 配置注册框架（`setting/config/config.go`）

每个配置模块通过 `init()` 函数注册自身：

```go
// 例如 setting/operation_setting/token_setting.go
func init() {
    config.Register(config.Setting{
        KeyPrefix: "token_",
        Title:     "Token Settings",
    })
}
```

### 配置分类

| 目录 | 功能 |
|------|------|
| `system_setting/` | 系统级：Discord/OIDC 配置、法律页面、Passkey、主题 |
| `operation_setting/` | 运营级：渠道配置、签到、监控、支付、配额、Token |
| `billing_setting/` | 计费级：阶梯计费表达式 |
| `model_setting/` | 模型级：Claude/Gemini/Grok/Qwen 默认参数 |
| `ratio_setting/` | 比例级：模型配额比例、分组比例、缓存比例 |
| `performance_setting/` | 性能级：性能采集配置 |

---

## 13. 前端开发

### 前端架构

```
web/
├── default/           # 默认主题（React + TypeScript + Rsbuild）
│   ├── src/
│   │   ├── components/    # 通用组件
│   │   ├── pages/         # 页面组件
│   │   ├── i18n/          # 前端国际化
│   │   ├── helpers/       # 工具函数
│   │   └── hooks/         # 自定义 Hooks
│   ├── rsbuild.config.ts  # Rsbuild 配置
│   └── package.json       # Bun 包管理
│
└── classic/           # 经典主题（React + JavaScript + Vite）
    ├── src/
    ├── vite.config.js
    └── package.json
```

### 开发命令

```bash
cd web/default

bun install           # 安装依赖
bun run dev           # 启动开发服务器（热重载）
bun run build         # 生产构建
bun run i18n:sync     # 同步翻译文件
```

### 前端国际化

- 使用 `i18next` + `react-i18next` + `i18next-browser-languagedetector`
- 翻译文件：`web/default/src/i18n/locales/{lang}.json`
- 支持语言：en（基础）、zh（回退）、fr、ru、ja、vi
- Key 为英文字符串，通过 `t('key')` 使用

### 构建与集成

前端构建后的 `dist/` 目录通过 Go `//go:embed` 嵌入到二进制文件中：

```go
//go:embed web/default/dist
var buildFS embed.FS

//go:embed web/default/dist/index.html
var indexPage []byte
```

### 主题切换

通过 `common.SetTheme("default" | "classic")` 切换主题，同时 `ThemeAwarePath()` 函数将经典主题的 `/console/*` 路径映射到默认主题的对应路径。

---

## 14. 如何添加新的 AI 提供商

### 步骤一：添加渠道类型常量

在 `constant/channel.go` 中添加新的渠道类型：

```go
const (
    // ... 现有类型
    ChannelTypeMyProvider = 58  // 在 Dummy 之前
    ChannelTypeDummy      // 保持最后一个
)
```

### 步骤二：实现 Adaptor 接口

创建 `relay/channel/myprovider/adaptor.go`：

```go
package myprovider

import (
    "github.com/QuantumNous/new-api/relay/channel"
    relaycommon "github.com/QuantumNous/new-api/relay/common"
    // ... 其他依赖
)

type Adaptor struct {}

func (a *Adaptor) Init(info *relaycommon.RelayInfo) {
    // 初始化逻辑
}

func (a *Adaptor) GetRequestURL(info *relaycommon.RelayInfo) (string, error) {
    // 返回上游 API URL
    return relaycommon.GetFullRequestURL(info.ChannelBaseUrl, info.RequestURLPath, info.ChannelType), nil
}

func (a *Adaptor) SetupRequestHeader(c *gin.Context, req *http.Header, info *relaycommon.RelayInfo) error {
    channel.SetupApiRequestHeader(info, c, req)
    req.Set("Authorization", "Bearer "+info.ApiKey)
    return nil
}

func (a *Adaptor) ConvertOpenAIRequest(c *gin.Context, info *relaycommon.RelayInfo, request *dto.GeneralOpenAIRequest) (any, error) {
    // 将 OpenAI 格式请求转换为提供商格式
    // 直接返回 request 如果提供商也是 OpenAI 兼容格式
    return request, nil
}

func (a *Adaptor) DoRequest(c *gin.Context, info *relaycommon.RelayInfo, requestBody io.Reader) (any, error) {
    return channel.DoApiRequest(a, c, info, requestBody)
}

func (a *Adaptor) DoResponse(c *gin.Context, resp *http.Response, info *relaycommon.RelayInfo) (usage any, err *types.NewAPIError) {
    if info.IsStream {
        return openai.OaiStreamHandler(c, info, resp)
    }
    return openai.OpenaiHandler(c, info, resp)
}

func (a *Adaptor) GetModelList() []string {
    return []string{}  // 或返回默认模型列表
}

func (a *Adaptor) GetChannelName() string {
    return "my provider"
}

// 其他方法（ConvertClaudeRequest、ConvertGeminiRequest 等）
// 如果不支持相应模式，返回 nil
```

### 步骤三：注册适配器

在 `relay/relay_task.go` 的 `GetAdaptor()` 函数中添加：

```go
case constant.ChannelTypeMyProvider:
    return &myprovider.Adaptor{}
```

### 步骤四：注册到渠道路由

在 `router/api-router.go` 中确保渠道 CRUD 路由支持新类型。

### 步骤五：注册模型列表（可选）

在 `controller/channel.go` 的模型列表中注册新提供商的模型。

### 步骤六：前端配置

### 对于异步任务提供商

如果提供商需要异步任务支持（如视频生成），还需要实现 `TaskAdaptor` 接口并注册到 `relay/relay_task.go` 的 `GetTaskAdaptor()`：

```go
func GetTaskAdaptor(platform constant.TaskPlatform) channel.TaskAdaptor {
    switch platform {
    case constant.TaskPlatformMyProvider:
        return &myprovider.TaskAdaptor{}
    // ...
    }
}
```

---

## 15. 部署与运维

### Docker 部署

```bash
docker build -t new-api .
docker run -d -p 3000:3000 -v ./data:/data new-api
```

多阶段 Dockerfile：
1. 构建 default 前端（Bun）
2. 构建 classic 前端（Bun）
3. 构建 Go 二进制（CGO_ENABLED=0）
4. 运行在 debian:bookworm-slim

### Docker Compose

```yaml
version: '3'
services:
  new-api:
    build: .
    ports:
      - "3000:3000"
    volumes:
      - ./data:/data
      - ./.env:/root/.env
    environment:
      - SQL_DSN=new_api.db
      - REDIS_CONN_STRING=redis://redis:6379
  redis:
    image: redis:alpine
```

### 性能优化

- **Redis 缓存**：启用 Redis 减少数据库查询
- **内存缓存**：`MemoryCacheEnabled=true`（Redis 启用时自动开启）
- **批量更新**：`BATCH_UPDATE_ENABLED=true` 减少数据库写入
- **独立日志数据库**：`LOG_DSN` 将日志分离到独立数据库
- **渠道缓存同步**：`SYNC_FREQUENCY` 控制缓存刷新间隔

### 监控

- **pprof**：`ENABLE_PPROF=true` 在 8005 端口开启性能分析
- **Pyroscope**：`PYROSCOPE_*` 环境变量配置持续性能分析
- **系统监控**：`common.StartSystemMonitor()` 自动监控 CPU/内存
- **Umami/Google Analytics**：前端统计注入

### Electron 桌面应用

`electron/` 目录包含 Electron 桌面打包配置：
- `electron-builder` 打包
- 系统托盘图标
- 跨平台支持（Windows/Mac/Linux）

---

## 附录

### 关键文件索引

| 文件 | 内容 |
|------|------|
| `main.go` | 应用入口和启动流程 |
| `common/constants.go` | 全局变量配置 |
| `constant/channel.go` | 渠道类型枚举 |
| `constant/context.go` | 上下文 Key 常量 |
| `model/main.go` | 数据库初始化和迁移 |
| `router/main.go` | 路由总入口 |
| `router/api-router.go` | API 路由定义 |
| `router/relay-router.go` | 中继路由定义 |
| `middleware/auth.go` | 认证中间件 |
| `middleware/distributor.go` | 渠道分发中间件 |
| `relay/relay_task.go` | 中继任务主流程 |
| `relay/channel/adapter.go` | Adaptor 接口定义 |
| `relay/common/relay_info.go` | 中继上下文结构 |
| `relay/common/override.go` | 请求覆盖系统 |
| `relay/helper/price.go` | 价格计算 |
| `service/quota.go` | 配额结算 |
| `service/tiered_settle.go` | 阶梯计费结算 |
| `pkg/billingexpr/expr.md` | 计费表达式系统文档 |
| `i18n/i18n.go` | 国际化配置 |
| `oauth/provider.go` | OAuth 提供商接口 |
| `model/channel_cache.go` | 渠道缓存实现 |

### 学习路线建议

1. 从 `main.go` 入手，理解启动流程
2. 阅读 `constant/` 了解系统常量
3. 阅读 `model/` 了解数据库结构
4. 阅读 `router/` 了解 API 路由设计
5. 阅读 `middleware/` 了解请求处理管道
6. 阅读 `relay/channel/adapter.go` + `relay/relay_task.go` 理解核心中继流程
7. 选择一个简单提供商（如 `relay/channel/deepseek/`）完整阅读其适配器实现
8. 阅读 `service/quota.go` + `service/tiered_settle.go` 理解计费系统
9. 阅读 `pkg/billingexpr/expr.md` 深入理解计费表达式
10. 阅读前端 `web/default/src/` 了解管理面板
