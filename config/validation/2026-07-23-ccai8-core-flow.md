# ccai.8 核心流程验收记录

- 最新验收时间：2026-07-23 18:39 CST
- 文档状态更新时间：2026-07-29
- 验收环境：本地 Docker Compose（`http://127.0.0.1:3101`）和 staging
  （`https://test.ccaiservice.com`）
- 本地运行镜像：`ccai/new-api:rc15-ccai.8`
  （`sha256:cac23b7fae53acb1e0e9595f190dfa24141d86106d3e9453d222e63193e59f6a`）
- staging 运行镜像：`ccai/new-api:rc15-ccai.8`
  （`sha256:877cf60757072a3f69f04b1d7941c8aa38c15eb9d2dc143e9e3efa0b946cc8f1`）
- 接口报告版本：`v1.0.0-rc.15-ccai.8`
- 验收范围：邮箱注册、登录、API Key、模型调用与计费、Pancake staging
  沙箱支付闭环，以及 Wallet 支付回跳的定向 UI 验证。
- 数据处理：保留现有 MySQL 和 Redis 数据；执行了最小真实模型调用和一笔
  Pancake staging 沙箱支付，未使用生产支付凭据。

本文档按时间保留早期失败和续作计划；若历史段落与本页结论冲突，以日期更新、
版本更高的实测结果为准。

## 最新结论

核心 P0 流程已经跑通。早期记录中的 SMTP、Pancake 配置和模型渠道阻塞均已解除；
邮箱注册于 2026-07-21 通过，模型严格计费和 `ccai.8` staging 支付闭环于
2026-07-23 通过。

| 流程步骤 | 最新结果 | 验收依据 |
|---|---|---|
| 邮箱验证码注册 | 通过 | 2026-07-21 使用独立测试邮箱完成验证码发送、注册和邮箱落库；测试用户 ID 7 创建成功。 |
| 用户名和密码登录 | 通过 | 测试用户 ID 7 登录成功，`GET /api/user/self` 与数据库用户信息一致。 |
| API Key 创建和鉴权 | 通过 | 早期创建接口和鉴权已通过；2026-07-23 又使用普通测试用户 ID 2 自有的有效 Token ID 1 完成严格模型调用验收。 |
| 获取 API 模型列表 | 通过 | `GET /v1/models` 返回 7 个已配置模型，覆盖 5 个启用渠道。 |
| 模型调用和计费 | 通过 | 7/7 模型返回有效响应；7 条 `type=2` 消费日志按请求 ID 精确匹配，Token、用户和钱包的 828 quota 变化一致。 |
| Pancake 金额和结账 | 通过 | staging 最低金额 10，成功创建订单并确认初始状态为 `pending`，支付回跳域名为 `test.ccaiservice.com`。 |
| Pancake webhook 和入账 | 通过 | `/test` webhook 验签成功，订单 ID 19 更新为 `success`，用户额度增加 5,000,000。 |
| Wallet 支付回跳 | 通过 | 同一 staging 用户的 Wallet 显示到账后余额 `$150`，`payment_return` 标记和支付前额度基线均已清理。 |
| 严重错误检查 | 通过 | 邮箱注册、模型严格验收和 Pancake 完整支付对应日志均未发现 panic、fatal 或可识别的 HTTP 500。 |

## 最新测试数据

- 邮箱注册测试：用户 ID 7；邮箱地址和验证码未写入本文档。
- 模型严格验收：用户 ID 2、Token ID 1、7 个模型、5 个渠道、643 tokens、
  828 quota。
- Pancake staging 沙箱支付：用户 ID 2、订单 ID 19、金额 10、额度增加
  5,000,000，最终 Wallet 余额 `$150`。
- 敏感值未写入本文档；脱敏运行报告保存在被 Git 忽略的 `.local-run/`。

## 当前遗留事项

1. 执行 P1 组合回归，重新覆盖邮箱注册、登录、充值信息、API Key 创建与鉴权、
   模型列表和聊天接口，并统一检查异常日志。
2. 完成桌面端和移动端 Wallet、API Key、模型选择等页面的全面 UI 验收；当前只完成了
   Pancake 支付回跳和到账显示的定向验证。
3. 整改 Pancake webhook 原始日志策略，避免记录完整签名和可能包含支付用户信息的
   请求体。
4. 完成文档、脚本、配置差异检查并整理 Git 提交。

## 历史记录说明

以下各日期段落记录当时的环境和结果，用于追溯问题演进，不代表当前状态。
自 2026-07-29 起，每日工作记录和次日计划只维护在
[`WORKLOG.md`](../../WORKLOG.md)，本文件不再追加工作流水，只更新可复核的验收结论和证据。

## 2026-07-15 工作记录

今日已完成以下工作：

1. 启动并确认原本的本地 Compose 服务可用。
2. 将 `admin` 用户密码按要求完成两次重置，最终值未写入本记录。
3. 检查原本运行的上游 `calciumion/new-api:latest`，确认其报告版本为
   `v1.0.0-rc.11`，不适合作为本次 Pancake 自定义改动的验收对象。
4. 使用 `custom-new-api/Dockerfile` 构建
   `ccai/new-api:rc15-ccai.7`。首次构建因直连 `proxy.golang.org` 超时失败，
   随后通过宿主网络和本机代理重试成功。
5. 将本地 `.env.development` 的 `NEW_API_IMAGE` 切换为
   `ccai/new-api:rc15-ccai.7`，仅重建 `new-api` 应用容器，没有重启或清空
   MySQL、Redis。
6. 确认自定义版本启动成功、数据库迁移完成，并报告版本
   `v1.0.0-rc.15-ccai.7`。
7. 按 API 流程验证注册、登录、Pancake 金额计算和创建结账、API Key 创建、
   模型列表及聊天接口，结果详见上方表格。
8. 按要求停止 UI 自动化验收，后续 UI 由人工验证。

截至 2026-07-15 22:19 CST，本地 `new-api`、MySQL 和 Redis 均保持运行；
MySQL 与 Redis 状态健康。本地开发环境继续使用自定义镜像
`ccai/new-api:rc15-ccai.7`。

## 2026-07-16 续作清单（历史）

明日从以下顺序继续：

1. 准备本地测试用 SMTP 配置，开启邮箱验证，重新创建独立测试用户，确认验证码、
   邮箱落库和登录完整通过。
2. 准备 Pancake 沙箱商户配置，包括商户 ID、私钥、回跳地址、Store ID 和
   Product ID；仅使用测试环境配置，不复制生产密钥到本地记录或代码仓库。
3. 保存 Pancake 配置后，确认 `/api/user/topup/info` 返回
   `enable_waffo_pancake_topup: true`，并关闭旧的 Creem 充值入口。
4. 创建一笔 Pancake 沙箱订单，完成测试支付，核对 `top_ups` 状态、webhook
   验签结果和用户额度变化。
5. 填写 `.env.development` 中的 `UPSTREAM_*` 测试渠道配置，执行
   `scripts/sync-model-channel.sh .env.development`，确认 `/v1/models` 返回模型。
6. 使用测试用户生成的 API Key 调用 `/v1/chat/completions`，以收到有效模型回复
   作为核心流程最终通过标准。
7. 更新本记录中的阻塞项和最终结论；UI 验收结果由人工确认后另行补充。

明日恢复工作时可先执行：

```bash
cd /root/new-api-deploy
docker compose --env-file .env.development ps
curl --noproxy '*' -sS http://127.0.0.1:3101/api/status
```

## 2026-07-17 配置同步记录

已从测试环境向本地开发环境同步以下配置：

1. SMTP 配置和邮箱验证开关；敏感 Token 未写入本文档或代码仓库。
2. Waffo Pancake 沙箱商户、Store、Product、回跳地址、最低充值金额和私钥；
   私钥未写入本文档或代码仓库。
3. 全部模型相关配置以测试环境为唯一基准，覆盖同步 `channels`、`abilities`、
   `models` 和 `vendors` 表，以及模型比例、阶梯计费、限流、重试和价格选项。
4. 开发环境与测试环境的四张模型表校验和一致，17 项模型选项摘要一致。
5. 本地 `GET /v1/models` 已成功返回以下 7 个模型：
   `MiniMax-M3`、`deepseek-v4-flash`、`deepseek-v4-pro`、`glm-5.2`、
   `kimi-k2.5`、`qwen3.7-max`、`qwen3.7-plus`。

配置保存在本地开发 MySQL 数据卷中；`.env.development` 的单渠道
`UPSTREAM_*` 模板继续留空，以数据库内的多渠道配置为准。本次未发起计费模型调用。

## 2026-07-18 工作记录

今日仅进行了现状核对，未开始下列功能验收任务，也没有进行新的配置同步、部署、
沙箱支付或计费模型调用。7 月 17 日遗留事项均未完成，顺延至 7 月 19 日继续。

只读核对结果如下：

- 本地 `new-api`、Caddy、HTML Filter、MySQL 和 Redis 容器均保持运行，MySQL 与
  Redis 状态健康。
- 应用仍运行 `ccai/new-api:rc15-ccai.7`，接口报告版本为
  `v1.0.0-rc.15-ccai.7`。
- 数据库中现有 5 个渠道且全部启用，共有 16 条模型记录和 7 条能力记录。
- 最近 8 小时应用日志中未发现 panic、fatal 或 HTTP 500；本次未执行功能请求回归。

## 2026-07-19 续作计划（历史）

明日按以下顺序继续：

1. 使用新的独立测试邮箱完成注册和验证码流程，确认邮箱正确落库，并验证登录和
   `GET /api/user/self`。
2. 登录测试用户后确认 `/api/user/topup/info` 返回
   `enable_waffo_pancake_topup: true`，且旧的 Creem 充值入口符合预期状态。
3. 创建一笔最低金额的 Pancake 沙箱订单，核对结账跳转、回跳地址和初始
   `top_ups` pending 记录；不使用生产支付凭据。
4. 完成沙箱支付并检查 webhook 验签、订单从 pending 更新为 success、用户额度
   增加，以及前端等待到账流程正常结束。
5. 使用开发环境已有测试 API Key 调用 `/v1/chat/completions`，优先验证
   `qwen3.7-max`，再对其余渠道做最小化连通性测试；记录响应结果和异常，不在日志中
   保存 API Key。
6. 对注册、登录、充值、模型列表和聊天接口执行一次完整回归，确认应用日志中没有
   panic、fatal 或 HTTP 500。
7. UI 继续由人工验收，重点检查 Wallet、Pancake 支付回跳、到账提示、API Key
   页面和模型选择；记录桌面端及移动端结果。
8. 根据实测结果更新本文档顶部结论，将已解除的 SMTP、Pancake 和模型转发阻塞项
   改为通过，并单独记录仍存在的问题。

明日开始前先执行：

```bash
cd /root/new-api-deploy
docker compose --env-file .env.development ps
curl --noproxy '*' -sS http://127.0.0.1:3101/api/status
```

## 2026-07-21 邮箱注册链路验收

使用 `scripts/test-email-registration.sh` 完成独立测试邮箱的交互式验收：

- 注册和 SMTP 前置检查通过，运行版本为 `v1.0.0-rc.15-ccai.7`。
- 验证邮件发送、验证码注册和数据库邮箱字段核对均通过。
- 测试用户创建为用户 ID 7，用户名和密码登录成功。
- `GET /api/user/self` 与数据库用户信息一致。
- 对应应用日志未发现 panic、fatal 或 HTTP 500。
- 邮箱地址、验证码和密码均未写入本文档或脱敏报告。

阶段结论：2026-07-15 的邮箱注册配置阻塞已经解除，邮箱注册链路通过。

## 2026-07-22 模型调用脚本审查与加固记录

今日审查并重构了 `scripts/test-model-calling.sh`。本轮工作只涉及脚本、文档和离线模拟，
没有调用真实上游模型，没有产生模型费用，没有部署任何环境，也没有修改 MySQL、Redis
或远程服务数据。

### 审查发现

原脚本能够完成模型连通性测试，但存在以下会导致验收结论失真的问题：

1. 消费日志使用 `type=0` 查询；当前 New API 的消费日志类型实际为 `type=2`。
2. Token 额度、消费日志或渠道关联为 0 时仍无条件记录 `PASS`。2026-07-21 的最终报告
   实际显示消费日志和渠道关联均为 0。
3. 本地 E2E 用户没有可用 API Key 时，脚本会回退到数据库中其他用户的第一条无限额度
   Key，导致用户、Token 和日志无法正确对应。
4. staging 流程将网页管理接口使用的 `E2E_ACCESS_TOKEN` 当作 `/v1` API Key，并另外
   选择该用户第一条 Token 记录作为计费对象，两者不保证一致。
5. 全模型模式只检查 HTTP 2xx 和 `error.message`；空对象或缺少 `choices` 的响应可能被
   误判为成功，部分模型失败后脚本仍可能以退出码 0 结束。
6. API Key 被拼入 curl Header 命令参数，可能通过进程参数暴露，不符合现有敏感信息
   处理约束。

因此，2026-07-21 的记录仍可证明 7 个模型曾实际返回、`qwen3.7-max` 返回 189 tokens，
且 Token `used_quota` 增加 694；但原报告不能证明消费日志及渠道关联已被严格验证。

### 已完成修改

加固后的脚本执行以下检查：

1. 预检服务、启用渠道、`quota_per_unit` 和 `LogConsumeEnabled`，并提供不产生模型费用的
   `--preflight-only` 模式。
2. 交互确认普通测试用户，只允许选择该用户自己名下状态、有效期和额度均可用的 API
   Key；不再回退使用其他用户的 Key。
3. 从数据库读取所选 Key 后写入权限受限的临时 Header 文件；Key 不输出、不写入报告、
   不导出，也不出现在 curl 进程参数中。网页 `E2E_ACCESS_TOKEN` 不再用于 `/v1`。
4. 获取并校验 `/v1/models`，确认主测模型存在；在付费调用前显示环境、用户、Token
   记录、模型列表、调用次数和最大输出 Token，并等待显式确认。
5. 每个模型均检查 JSON、`choices`、有效内容或推理内容、模型标识和正数 Token 用量；
   任一模型失败均记为 `FAIL`，最终返回非零退出码。
6. 从响应头读取 `X-Oneapi-Request-Id`，按请求 ID 精确轮询对应的 `type=2` 消费日志，
   核对用户、Token、模型、渠道、请求 ID、输入输出 Token、计费额度及钱包或订阅来源。
7. 汇总核对消费日志额度、Token `used_quota`、用户 `used_quota` 和钱包剩余额度，并为
   批量异步更新预留轮询时间；并发使用同一测试 Key 导致的额度差异会使验收失败。
8. 扩充 panic、fatal 和 HTTP 500 日志匹配格式；Markdown 报告记录步骤耗时、实际使用
   渠道及脱敏错误摘要，不保存模型回复正文或原始应用日志。

### 离线验证结果

- `bash -n scripts/test-model-calling.sh` 通过。
- `--help` 及缺失参数处理通过。
- 使用完全离线的模拟服务执行 `--yes --all-models`：2/2 模型通过，两个请求均按请求
  ID 找到消费日志，日志额度合计 300，Token、用户累计用量及钱包额度变化一致。
- 失败用例将第二个模型响应替换为空对象：脚本识别 `response has no choices`，同时发现
  Token 额度与已匹配日志额度不一致，并以退出码 1 结束。
- `--preflight-only` 模式通过，确认不会进入用户、Token 和付费调用步骤。
- 扫描模拟 curl 参数和 Markdown 报告，未发现测试 API Key、Bearer Header 或 `sk-`
  密钥内容。

### 后续真实验收

本轮没有重新执行真实模型调用，因此严格计费验收仍待完成。恢复本地服务后按以下顺序
执行：

```bash
./scripts/test-model-calling.sh --preflight-only
./scripts/test-model-calling.sh --all-models
```

staging 使用 `--target staging --all-models`，从 `ui-tests/.env.e2e` 读取专用测试用户 ID，
通过 SSH 查询该用户自己的 API Key；执行前仍会显示计费计划并等待人工确认。仅在明确
配置了零价格模型时使用 `--allow-zero-cost`。

## 2026-07-23 执行基线

本阶段仅执行只读核对、工作区分类和敏感信息扫描；没有发起模型调用、部署、支付，
也没有修改本地或远程数据库数据。

### 运行环境

- 本地 Compose 的 `new-api`、Caddy、HTML Filter、MySQL 和 Redis 均处于运行状态，
  MySQL 与 Redis 健康检查通过。
- 本地应用容器运行 `ccai/new-api:rc15-ccai.8`，镜像 ID 为
  `sha256:cac23b7fae53acb1e0e9595f190dfa24141d86106d3e9453d222e63193e59f6a`；
  `/api/status` 报告版本为 `v1.0.0-rc.15-ccai.8`。
- staging 的 `https://test.ccaiservice.com/api/status` 可正常访问，报告版本仍为
  `v1.0.0-rc.15-ccai.7`。公开配置中的服务地址、Passkey 域名均指向
  `test.ccaiservice.com`，邮箱验证、注册、隐私政策和用户协议均已启用。
- 本阶段未部署 staging；`ccai.8` 的 staging 支付回跳修复仍待后续阶段验证。

### 工作区分类

- 当前分支为 `main`，相对 `origin/main` 超前 3 个提交。
- 已跟踪修改共 7 个文件，主要为环境模板、README、TODO、Caddy、Compose 和 Oracle
  部署脚本。
- 未跟踪文件共 25 个，分为 staging 部署配置、站点及法律文档、发布与验收记录、
  配置同步脚本和模型调用验收脚本；最终提交前仍需按功能边界复核。
- `.env`、`.env.development`、`ui-tests/.env.e2e` 和 `.local-run/` 均继续被 Git 忽略，
  不属于提交候选文件。
- `git diff --check` 通过，当前已跟踪差异未发现空白错误。

### 敏感信息检查

- 对全部已修改及未跟踪文件扫描了私钥块、Bearer Header、`sk-` 密钥以及常见
  API Key、Token、Secret 和密码赋值模式。
- 仅环境示例中的占位密码触发匹配；开发和生产模板中的敏感值为占位符或空值，
  staging 模板中的敏感值为空。
- 未发现实际私钥、Bearer Token、API Key 或其他明显密钥内容。

阶段结论：执行基线通过。下一步先运行模型调用脚本的 `--preflight-only` 无费用预检，
再根据预检结果确认真实计费调用范围。

### 模型调用无费用预检

2026-07-23 09:18 CST 运行 `scripts/test-model-calling.sh --preflight-only` 通过：本地版本为
`v1.0.0-rc.15-ccai.8`，共有 5 个启用渠道，`quota_per_unit` 为 500000，消费日志已启用，
批量更新关闭。本次预检没有选择用户或 API Key，没有调用上游模型，也没有产生模型费用。
脱敏运行报告保存在被 Git 忽略的
`.local-run/model-calling-local-20260723-091838.md`。

### 模型调用严格计费验收

2026-07-23 12:49 CST 首次按默认测试用户 ID 7 执行时，脚本发现 Token ID 33 已于
2026-07-21 被软删除，在模型请求前安全停止，因此该次没有产生费用。没有恢复旧 Token，
也没有直接修改数据库绕过校验。

随后使用现有普通测试用户 `e2e_flow_0715`（ID 2）及其有效 API Key 记录（Token ID 1）
重新执行 `scripts/test-model-calling.sh --yes --all-models --user-id 2`。结果如下：

| 模型 | Tokens | 计费 quota | 渠道 | 计费来源 |
|---|---:|---:|---:|---|
| `qwen3.7-max` | 134 | 474 | 4 | wallet |
| `deepseek-v4-flash` | 25 | 4 | 1 | wallet |
| `deepseek-v4-pro` | 25 | 52 | 1 | wallet |
| `glm-5.2` | 33 | 62 | 3 | wallet |
| `kimi-k2.5` | 28 | 41 | 2 | wallet |
| `MiniMax-M3` | 197 | 34 | 5 | wallet |
| `qwen3.7-plus` | 201 | 161 | 4 | wallet |

严格验收结论：

- 7/7 模型均返回有效响应，共使用 643 tokens，覆盖 5 个启用渠道。
- 7 个请求均按 `X-Oneapi-Request-Id` 精确匹配到对应的 `type=2` 消费日志。
- 消费日志合计、Token `used_quota` 增量、用户 `used_quota` 增量和钱包额度减少均为
  828 quota，四项一致。
- 验收后用户 ID 2 的钱包额度为 4,997,035，用户及 Token 累计 `used_quota` 均为 2,965。
- 本轮应用日志中未发现 panic、fatal 或可识别的 HTTP 500。
- 脱敏报告保存在被 Git 忽略的
  `.local-run/model-calling-local-20260723-125027.md`。

阶段结论：模型连通性和严格计费验收均通过，2026-07-21 旧脚本的误判风险已由本次
加固脚本实测闭环。下一步进入 Pancake staging 部署和支付回跳验收。

### Pancake staging 部署前检查

2026-07-23 12:52 CST 运行 staging `--preflight-only` 通过：公开 API、数据库配置和
测试用户认证正常，Pancake 已启用，旧 Creem 已关闭，最低充值金额为 10，支付回跳域名
为 `test.ccaiservice.com`。本次预检没有创建结账或支付订单。

staging 当前仍运行 `v1.0.0-rc.15-ccai.7`。远端仓库 HEAD 为旧提交 `f670496`，且远端
`custom-new-api` 构建输入与本地 `ccai.8` 不一致：缺少
`pancake-balance-baseline.patch`，Dockerfile 和其余补丁校验和也不同。因此不能直接使用
远端现有源码重新构建；部署前必须先同步本地已验证的 Dockerfile 和三个补丁，并将
`.env.staging` 的镜像标签从 `ccai.7` 更新为 `ccai.8`。旧 `ccai.7` 镜像继续保留用于
必要时回滚。

### `ccai.8` staging 部署

2026-07-23 18:33 CST 已完成 staging 部署：

- 部署前将远端 `.env.staging`、旧 Dockerfile 和旧补丁备份到
  `/opt/new-api-deploy/backups/ccai8-deploy-20260723-stage3`。
- 同步本地已验证的 Dockerfile、`ccai.patch`、`waffo-pancake-min-topup.patch` 和
  `pancake-balance-baseline.patch`；远端四个文件的 SHA-256 与本地一致。
- 将 staging 镜像标签更新为 `ccai/new-api:rc15-ccai.8`，远端构建成功，镜像 ID 为
  `sha256:877cf60757072a3f69f04b1d7941c8aa38c15eb9d2dc143e9e3efa0b946cc8f1`。
- Compose 更新期间 MySQL 容器因基础镜像拉取被重建，但继续使用原数据卷；重建后健康
  检查通过，原有 2 个用户、18 条充值记录和 5 个启用渠道仍存在。Redis 保持健康。
- staging `/api/status` 报告 `v1.0.0-rc.15-ccai.8`，应用启动和数据库迁移正常。
- 部署后再次运行 Pancake `--preflight-only` 通过：测试用户 ID 2 认证成功，Pancake
  已启用，旧 Creem 已关闭，最低金额为 10，回跳域名为 `test.ccaiservice.com`。
- 旧 `ccai.7` 镜像
  `sha256:910e1bfc2107e8a727aeddf1b0db7f525cf25ace5dac198f661bd1273996d681`
  继续保留，可结合部署备份回滚。

本阶段尚未创建新的 Pancake 订单。下一步需人工确认沙箱商户和 `/test` webhook 路由，
然后创建最低金额结账并完成沙箱支付。

### `ccai.8` Pancake staging 完整支付验收

2026-07-23 18:35–18:39 CST 使用 staging 普通测试用户 ID 2 完成最低金额沙箱支付：

- 操作者确认 Pancake 商户处于沙箱模式，`/test` webhook 路由到 staging。
- 以金额 10 创建订单 `WAFFO_PANCAKE-2-1784803018863-ouaGlF`，初始状态为 `pending`。
- 沙箱支付完成后，`/api/waffo-pancake/webhook/test` 收到 `mode=test` 的成功事件，
  webhook 验签和订单入账日志均通过。
- 数据库订单 ID 为 19，最终状态为 `success`，支付方式和提供方均为
  `waffo_pancake`；创建时间为 18:36:58，完成时间为 18:38:27。
- 用户额度增加 5,000,000，接口与数据库值一致；最终用户额度为 75,000,000。
- Playwright 使用同一 staging 用户验证 Wallet 回跳通过，页面显示余额 `$150`，
  `payment_return` 标记已清理。
- 应用严重错误检查通过，未发现 panic、fatal 或可识别的 HTTP 500。
- 脱敏报告保存在被 Git 忽略的
  `.local-run/pancake-topup-staging-20260723-183546.md`。

功能结论：`ccai.8` 在 staging 的创建订单、沙箱支付、`/test` webhook、订单更新、
额度到账和 Wallet 回跳刷新已形成完整闭环，Pancake 阶段通过。

安全遗留：核对原始应用日志时发现 webhook 接收日志会记录完整签名和请求体，其中可能
包含支付用户信息。本文档和脱敏报告未保存这些值；后续完整回归需确认并整改该日志策略。
