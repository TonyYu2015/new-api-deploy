# 工作日志

本文件是仓库唯一的日常工作记录和次日计划入口。

记录边界：

- `WORKLOG.md`：按日期记录当天实际完成内容、验证结果、遗留问题和次日计划。
- `TODO.md`：只维护跨日期的任务状态和完成标准，不追加每日流水。
- `config/validation/`：只保存验收环境、测试数据和可复核证据。
- `config/production-rollout.md`：只维护 staging/production 基线、待发布项和回滚信息。
- `.local-run/`：保存被 Git 忽略的脱敏自动化报告，不作为人工工作日志。

记录中不得写入密码、验证码、API Key、Token、私钥、完整 webhook 签名或支付请求体。
历史验收过程仍保留在对应验收文档中；从 2026-07-29 起不再向其他文件追加每日工作记录。

## 历史索引

- 2026-07-15–2026-07-23 的核心流程演进和详细证据：
  [`config/validation/2026-07-23-ccai8-core-flow.md`](config/validation/2026-07-23-ccai8-core-flow.md)
- 2026-07-02 的生产发布记录：[`config/releases/`](config/releases/)
- 当前跨日期任务状态：[`TODO.md`](TODO.md)

## 2026-07-29

### 今日完成

1. 检查仓库中的 TODO、验收记录、发布登记、脱敏运行报告和最近 Git 记录，确认最后一次
   功能验收发生在 2026-07-23。
2. 以最新实测结果修正验收记录：
   - 将文件重命名为
     `config/validation/2026-07-23-ccai8-core-flow.md`。
   - 将顶部版本更新为本地和 staging 的 `ccai/new-api:rc15-ccai.8`。
   - 明确 P0 核心流程已经通过：邮箱注册、登录、API Key 鉴权、7/7 模型严格计费、
     Pancake staging 沙箱支付和 Wallet 回跳均有通过记录。
   - 保留早期失败记录，但标记为历史状态；新增当前遗留事项。
3. 更新 `TODO.md`：
   - 将目标调整为 P1 组合回归、全面 UI 验收、webhook 日志整改和仓库收尾。
   - 补充 2026-07-23 的 `ccai.8` Pancake 完整支付结果。
   - 将旧的“仍需部署 ccai.8”说明标记为已被最新结果取代。
4. 更新 `config/production-rollout.md`：
   - staging 基线更新为 `ccai.8` 及其已验证镜像 ID。
   - 生产环境保留最新已记录的 `ccai.4`，并明确 2026-07-23 未重新查询生产运行状态。
   - 新增待生产发布的 `PAYMENT-007`，记录支付前额度基线修复已在 staging 通过。
   - 更新 staging 验证和回滚信息。
5. 建立本文件作为统一工作日志，并在项目文档中统一日志入口和文档职责。

### 检查结果

- 旧验收文件路径和“仍需部署 `ccai.8`”等当前状态冲突已清除。
- `git diff --check` 通过。
- 本轮更新文档未发现尾随空白、私钥块、Bearer Token 或 `sk-` 格式密钥。
- 今日未部署环境、未调用上游模型、未发起支付，也未修改 MySQL 或 Redis 数据。
- 当前改动尚未提交 Git。

### 当前遗留

- P1 邮箱注册、登录、充值信息、API Key 创建与鉴权、模型列表和聊天接口的组合回归。
- 桌面端和移动端 Wallet、API Key、模型选择等页面的全面 UI 验收。
- Pancake webhook 接收日志可能记录完整签名和请求体，需要整改和回归。
- 工作区文件分类、全量验证和 Git 提交尚未完成。
- 生产运行版本需要在任何生产发布决策前重新只读确认。

## 2026-07-30 工作计划

目标：优先完成 webhook 日志隐私整改和 P1 组合回归；在核心回归通过后推进 UI 与仓库收尾。

### 阶段 1：建立当日基线

- 只读检查本地与 staging 服务状态、`/api/status`、运行镜像和数据库健康状态。
- 检查 Git 工作区，确认本轮代码、配置、文档和本地运行文件的边界。
- 确认测试凭据和 `.local-run/` 仍被 Git 忽略。

### 阶段 2：整改 webhook 日志

- 定位 Pancake webhook 输出完整签名和请求体的日志位置。
- 调整日志策略，仅保留排障所需的事件类型、模式、订单标识和脱敏错误摘要。
- 增加或执行针对成功、验签失败和异常请求的测试，确认日志不再包含签名或支付用户信息。
- 不改变 webhook 验签、订单幂等和额度入账逻辑。

### 阶段 3：P1 组合回归

- 回归邮箱验证码注册、邮箱落库、登录和 `GET /api/user/self`。
- 回归充值信息、API Key 创建与鉴权、模型列表和聊天接口。
- 对真实计费模型调用继续使用最小请求，并在调用前保留人工确认点。
- 仅在确有必要时重复 Pancake staging 沙箱支付；创建订单前保留沙箱和 `/test`
  webhook 的人工确认点。
- 汇总检查 panic、fatal、HTTP 500 和其他未解释异常。

### 阶段 4：UI 验收

- 在桌面端检查 Wallet、Pancake 回跳与到账、API Key 和模型选择。
- 在移动端重复关键路径，记录视觉、交互和文案结果。
- 将发现的问题记录到 `TODO.md`，每日执行结果只写入本文件。

### 阶段 5：收尾

- 执行脚本语法、配置、测试、敏感信息和 Git 差异检查。
- 更新验收证据、TODO 状态和生产发布登记，但不在这些文件中追加工作流水。
- 确认最终验收结论和待提交范围后再整理 Git 提交；不进行生产部署。

完成标准：webhook 日志不再暴露敏感请求信息，P1 组合回归有明确结论，UI 问题和剩余
阻塞均已记录，工作区达到可审查状态。

## 2026-10-12

### 今日完成

1. 排查并修复「模型价格」在同步上游价格后看不到价格数字的问题。
   - 数据核查（本地 dev 库）：`billing_setting.billing_mode` 中 `MiniMax-M3`、
     `qwen3.7-plus`、`deepseek-flash`、`deepseek-v4-pro` 为 `tiered_expr`，价格写在
     `billing_setting.billing_expr` 表达式中；`ModelPrice` 为空，`ModelRatio` 保留
     （表达式生效时仅作为回退值，不参与展示）。
   - 根因：管理端「系统设置 → 计费 → 模型价格」的价格摘要列对表达式计费模型只渲染
     「阶梯计费 · N 档 / 表达式计费」，不解析表达式里的价格数字，导致同步后看起来
     “看不到已设置的价格”。公开定价页不受影响（动态价格逻辑本就显示数字）。
   - 修复：新增补丁 `custom-new-api/tiered-price-summary.patch`，价格摘要解析表达式
     首档并在其后追加「输入 $… · 输出 $…」；`custom-new-api/Dockerfile` 应用该补丁，
     版本提升为 `1.0.0-rc.15-ccai.9`；`scripts/build-staging-image.sh` 默认镜像同步更新。
2. 构建本地/预发镜像 `ccai/new-api:rc15-ccai.9`（镜像 ID `sha256:e460186f…`）。
3. 部署到本地 dev：`.env.dev.local` 指向 `ccai/new-api:rc15-ccai.9`，仅重建 `new-api`
   服务；MySQL/Redis/Caddy 未重建，数据不变。

### 验证结果

- 四个补丁在固定上游提交上 `git apply --check` 全部通过；镜像构建中两套前端与 Go 编译
  均成功，构建日志确认新补丁已在镜像内应用。
- dev 站点（`http://localhost:3101`）入口包由 `index.8c35891842.js` 更新为
  `index.2032c431d9.js`；新包中的价格摘要已包含表达式首档价格解析（旧包无），
  `/api/status` 正常。
- 预期界面效果：表达式计费模型显示「阶梯计费 · 2 档 · 输入 $0.446 · 输出 $1.784」等；
  倍率计费模型的摘要不变。因未持有管理员凭据，未在管理端页面内逐项点验。

### 遗留

- staging / production 未重新部署，仍为 `ccai.8`；如需发布，按既有流程更新
  `.env.staging` 后重建，staging 验证通过后再更新 `config/production-rollout.md` 基线。
- 浏览器需强刷（Ctrl+F5）以加载新前端包。
- 本轮涉及文件：`custom-new-api/tiered-price-summary.patch`（新增）、
  `custom-new-api/Dockerfile`、`scripts/build-staging-image.sh`；`.env.dev.local` 为被忽略的
  本地覆盖文件，不入库。当日全部本地改动已一并提交到本地 `main`（未推送）。

### 上游大版本升级（rc.15 → rc.43，dev 先行）

上游 rc.15 之后累计 28 个版本：前端将 `web/default` + `web/classic` 合并为单一 `web/`
并改用 rsbuild 构建，Go 侧引入 `relaykit` / `tokenkit` 本地子模块。经确认采用 dev
先行方案：重基 4 个补丁、改造 Dockerfile、升级前备份 dev 数据库、构建并部署 dev 验证；
staging / production 暂不动。

#### 执行内容

1. 升级前备份 dev 数据库：`.local-run/dev-mysql-backup-2026-10-12-pre-rc43.sql.gz`
   （107969 字节，30 张表，sha256 `7ac148ad…`，gzip 完整性已验证）。rc.43 的数据库
   迁移为向前迁移，回滚镜像需先用该备份恢复。
2. 补丁重基（上游固定提交 `c6741c36…`，rc.43）：
   - `ccai.patch`（1526 行 / 12 文件）：3 个 Go 文件不变；9 个前端文件按 rc.43 新路径
     （`web/src/…`）重基——profile 页改单列、通知设置仅保留邮件渠道、充值表单去除预设
     金额并修正 0 值占位显示、Wallet 适配 rc.43 的 `dispatchSelectedPayment` 分发结构、
     首页 / 导航沿用 CCAI 自定义。
   - `waffo-pancake-min-topup.patch`：仅路径 `web/default` → `web` 重命名。
   - `pancake-balance-baseline.patch`（103 行 / 5 hunks）：支付前额度基线改用
     sessionStorage，兼容新的支付分发结构。
   - `tiered-price-summary.patch`（48 行）：适配新 import 路径
     `@/features/pricing/lib/billing-expr`。
   - 干净 rc.43 检出上按顺序 `git apply --check` / `apply` 全部通过
     （18 文件，+244 / −838）。
3. `custom-new-api/Dockerfile` 改造：单前端 rsbuild 构建（`oven/bun:1.4.0`）、
   Go 1.26.1 + `GOWORK=off` + PGO、版本后缀 `-ccai.1`，`UPSTREAM_COMMIT` /
   `UPSTREAM_VERSION` 指向 rc.43。首次构建在 `go mod download` 阶段因
   proxy.golang.org 在本构建网络不可达而失败，已在 builder 阶段加入
   `GOPROXY=https://goproxy.cn,direct`（Qiniu 镜像 + direct 回退）后构建成功。
4. 构建 `ccai/new-api:rc43-ccai.1`（镜像 ID `sha256:df8e8a89…`），二进制内确认版本串、
   `CCAI Service`、pancake 基线存储键、充值文案等自定义标记均已嵌入。
5. dev 部署：`.env.dev.local` 指向新镜像，仅重建 `new-api` 服务
   （MySQL / Redis / Caddy 未重建，数据卷不变）；启动日志显示数据库迁移完成、
   版本 `v1.0.0-rc.43-ccai.1`，无错误。

#### 升级验证结果

- `/api/status` 返回版本 `v1.0.0-rc.43-ccai.1`、`setup: true`；数据库表数 30 → 39。
- 前端入口包 `index.2032c431d9.js` → `index.e0700110a5.js`；构建产物与 dev 实际服务的
   该文件字节一致（sha256 前缀 `c8bdf197…`）；编译产物中确认价格摘要补丁代码
   （`?.inputPrice` / `?.outputPrice` 与 `Input $…`、`Output $…` 拼接）及
   `<title>CCAI Service</title>`。
- `/pricing` 路由 200；`/api/pricing` 返回 `pricing is disabled`：经查该消息由
   `middleware/header_nav.go` 的 `HeaderNavModuleAuth` 按 `options.HeaderNavModules`
   配置返回（`GET /api/pricing` 注册于 `router/api-router.go`），代码与前端默认均为
   启用；dev 库 `pricing.enabled=false` 且升级前备份中的值相同（备份内审计日志显示
   当日 10:38 管理端两次 `option.update`），系升级前已存在的配置，未被本次升级改动；
   恢复入口为管理端「系统设置 → 顶部导航」。
- `POST /api/user/waffo-pancake/amount` → 401（路由已注册、要求鉴权）；
   pancake webhook 与订阅路由均已注册。
- 未持有管理员凭据，未在管理端页面内逐项点验；浏览器需强刷（Ctrl+F5）加载新前端包。

#### 已知差异与注意事项

- rc.43 已移除 `profile-security-card.tsx`（安全设置改为 features/security 的命名
   访问令牌卡片），旧补丁对该文件的改动不再适用；现保留 rc.43 原生形态，
   AccessTokensCard 正常可见。
- legacy access token 退役机制：rc.43 首次启动记录 `LegacyAccessTokenRetireAt`
   （首次启动 + 30 天，dev 为 2026-11-11）。到期前
   `scripts/test-pancake-topup.sh`、`scripts/run-production-creem-test.sh` 使用的
   `users.access_token` 仍有效（该列仍存在）；到期后需改用命名访问令牌。
- 启动日志出现 `TRUSTED_PROXIES` 未设置警告（上游默认信任回环 / 内网代理）与
   `SESSION_COOKIE_SECURE` 未开启警告（本地 HTTP 环境属预期）；
   生产部署时应设置 `SESSION_COOKIE_SECURE=true`。
- 回滚提示：rc.43 迁移为向前迁移，仅回退镜像会与升级后的表结构不兼容；
   如需回滚，先用升级前备份恢复数据库。

#### staging 部署（2026-10-12）

- 本地提交 `c55752c`（rc.43 升级）并推送到 `origin/main`；staging 服务器代码更新
   到同一提交。
- 升级前备份 staging 数据库：
   `/opt/new-api-deploy/backups/staging-rc15-db-20261012-134549.sql.gz`
   （752 KB，gzip 校验通过，29 张表）。
- 服务器构建 `ccai/new-api:rc43-ccai.1`
   （`sha256:c4d4b130c5d70d1eb298a8393d306956a61d7aa96571165ea97e44910301bb33`）；
   首次构建在 `go mod download` 阶段因 `goproxy.cn` 返回 `GOAWAY` 失败，重试成功。
- 部署后内网 3002 与公开 `test.ccaiservice.com` 的 `/api/status` 均为
   `v1.0.0-rc.43-ccai.1`，首页 HTTP 200，日志无 `fatal`/`panic`/error；迁移后
   users=12、channels=5、tokens=1、top_ups=19、options=72。
- 故障与修复：`new-api` 重建换了 IP 后，html-filter 的 nginx 仍缓存旧地址导致
   502；已在 `deploy-staging.sh` / `deploy-oracle.sh` 中加入部署后强制重建
   `html-filter` 与 `nginx`。
- `config/production-rollout.md` 的 staging 基线已更新为 `rc43-ccai.1`。

#### 补丁冲突修正与 ccai.2 部署（2026-10-13）

- 对 4 个补丁与上游 rc.43 做冲突审查，恢复两处被补丁覆盖的上游能力：
  `home/index.tsx` 的 **Custom Home Page** 分支，以及 `public-header.tsx` 的
  上游实现（管理端动态导航优先）；其余移除保持为文档化的有意精简。提交
  `d7b10ff`，并把补丁功能写入 `custom-new-api/README.md`。
- 版本升级到 `rc43-ccai.2` 并重建（提交 `7f9fbb0`）：dev 先行部署验证，
  构建产物已包含恢复的 Custom Home Page 分支。
- staging 部署：先备份数据库
  `/opt/new-api-deploy/backups/staging-ccai1-db-20261013-030946.sql.gz`
  （765 KB，gzip 校验通过），再在服务器构建 `ccai/new-api:rc43-ccai.2`
  （`sha256:586d942b5e5d2e90a3990efc260302c909c06d5887c5fcce921bab42c2d02ca2`）。
- 部署后内网 3002 与公开 `test.ccaiservice.com` 的 `/api/status` 均为
  `v1.0.0-rc.43-ccai.2`，首页 HTTP 200，日志无 `fatal`/`panic`/error；
  users=13、channels=5、tokens=1、top_ups=20、options=75。
- 代理层 `html-filter`/`nginx` 由部署脚本按预期强制重建，未再出现 502。
- `config/production-rollout.md` 的 staging 基线更新为 `rc43-ccai.2`。

#### 生产部署（2026-10-13）

- 对 `rc15-ccai.4` 从 dev 到 staging 的验证已通过，按 `config/production-rollout.md`
   流程把 production 升级到 `rc43-ccai.2`。
- 升级前备份 production 数据库：
   `/opt/new-api-deploy/backups/prod-rc15-db-20261013-032305.sql.gz`
   （821,761 字节，gzip 校验通过，29 张表）；同时备份 `nginx/conf.d/default.conf`
   （`prod-html-filter-20261013-032305.conf`）。
- 服务器代码同步到 `a06985c`，设置 `.env.production` 的 `NEW_API_IMAGE` 为
   `ccai/new-api:rc43-ccai.2`，由 `deploy-oracle.sh` 在服务器上构建镜像并重建
   `new-api`；MySQL / Redis 沿用原数据卷，仅重建容器，代理层 `html-filter` /
   `nginx` 按脚本强制重建以清除缓存的上游地址。
- 部署后内网 80 与公开 `www.ccaiservice.com` 的 `/api/status` 均为
   `v1.0.0-rc.43-ccai.2`，首页 HTTP 200；启动日志显示数据库迁移完成、
   `New API v1.0.0-rc.43-ccai.2 started`，无 `fatal`/`panic`/error。
- 数据核对：users=54、channels=5、tokens=27、top_ups=9、logs=12383、options=71；
   `abilities` 路由表 10 个模型；注册、邮箱验证、密码登录开关与升级前一致。
- 前端入口包 `index.ca78e05c31.js`，产物内确认包含恢复的 Custom Home Page 分支。
- `config/production-rollout.md` 的 production 基线与发布登记已更新为
   `rc43-ccai.2`，并记录回滚镜像与备份路径。
- 支付方式文案修正（PAYMENT-008）：用户反馈生产 `/wallet` 的 Payment Method 只显示
   「Credit Card (Minimum USD 10)」而看不到 Waffo Pancake。核查确认接口
   `/api/user/topup/info` 一直返回一个 `waffo_pancake` 条目，只是生产 `PayMethods`
   将该条目的 `name` 覆盖成了生产专用文案（PAYMENT-003），而后端只在 `PayMethods`
   没有 `waffo_pancake` 条目时才补默认的「Waffo Pancake」；staging/dev 的 `PayMethods`
   为空，因此显示默认名。已把生产 `PayMethods` 改回
   `[{"name":"Waffo Pancake","type":"waffo_pancake","color":"#F97316","min_topup":"10"}]`，
   改后接口内联生效，最低金额仍为 10；旧值备份在
   `/opt/new-api-deploy/backups/prod-paymethods-20261013.txt`，未改动任何支付凭据、webhook
   或下单逻辑。

#### 升级遗留

- production 已升级到 `rc43-ccai.2`；rc.43 迁移为向前迁移，回滚需先用
   `prod-rc15-db-20261013-032305.sql.gz` 恢复数据库后再使用 `rc15-ccai.4` 镜像。
- 完整桌面/移动端 UI 回归、模型转发与 Pancake 支付需在 `rc43-ccai.2` 上重新验收，
   production 尚未重跑真实模型调用与支付。
- 建议在浏览器中用管理员账号人工复验管理端「模型价格」页与 Wallet / pancake 回跳。
