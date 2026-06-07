# FundVal-Live (Fundval) — Project Memory

> 项目级 AGENTS.md,会话 workdir = `~/projects/fundval-live` 时自动注入。
> 跨项目记忆(沟通风格/工具偏好) → `~/.hermes/memories/MEMORY.md` (auto-injected)。
> 调试会话根因 → `docs/2026-06-06-debugging-session.md`。
> 部署踩坑 → `docs/deployment-pitfalls.md`。

---

## 1. 是什么

**FundVal-Live** (Ye-Yu-Mo/Fundval) — Django 6 + DRF + Celery + React SPA 基金估值与资产管理系统。
- **AGPL-3.0** (严格 copyleft)
- 4/4 全中"基金 bot" 4 条件(开源 + CLI + 虚拟持仓 + 真实数据)
- 4 大数据源: EastMoney (无登录) / Sina (股票) / 养基宝 (扫码) / 小倍养基 (手机号)
- 后端 stack: Django 6 / Celery 5 / PostgreSQL 16 / Redis 7
- 前端 stack: React 18 + Vite + React Router (`frontend/src/App.jsx` 是入口, 不是 .vue)

**版本**: 2.5.2 (后端 + 前端)

**本项目位置**: `~/projects/fundval-live/`

---

## 2. 部署状态 (2026-06-07)

| 项 | 状态 |
|---|---|
| 本机 WSL podman 跑 | ✅ 6 容器都健康 |
| 6 容器: db/backend/redis/celery-worker/celery-beat/frontend | ✅ |
| 访问 | `http://localhost:21345` (admin / admin123!) |
| 26963 只基金已同步列表 | ✅ (entrypoint 跑 `sync_funds --if-empty`) |
| 全量历史净值同步 | ✅ 06-07 04:30 跑完, **26.2M rows, 0 失败** |
| **fund_nav_history** 区间 | 2001-09-21 → **2026-06-05 (周五)** — 25 年全 |
| **fund.latest_nav** 覆盖 | 25,346/26,963 (94%) — 剩 1,617 没 (965 货币型 + 652 僵尸基金) |
| 行情中心指数 (market-indices) | ✅ 4 个指数实时 (今上证 -0.74% / 科创50 -4.01%) |
| 排行榜 3 榜 (gain/popular/accuracy) | ⚠ 周日全 0, 正常 (周一 21:30 校准后有数) |
| LLM 配置 | ✅ MiniMax-M3 via minimax-cn |
| Aliyun ECS (小小左) 部署 | ❌ 未做 — 仅后端 backend + db 计划中 |

---

## 3. 关键修复记录

### 2026-06-06 (5 bug 修)

| Bug | 修复 | 文件 |
|---|---|---|
| #1 celery.py 覆盖 beat_schedule | 删 celery.py 的 beat 块 | `backend/fundval/celery.py` |
| #2 update_nav 不算 returns/metrics | 加 sync_nav_history 触发 | `backend/api/tasks.py` (新 `sync_nav_history_full`) |
| #3 entrypoint 没触发首次同步 | 加 dispatch NAV sync 段 | `backend/entrypoint.sh` |
| #4 worker 容器代码修改丢失 | 改 host + rebuild 镜像 | (流程改进) |
| #5 frontend 写死 IP 漂移 | 临时:`/etc/hosts` 加新 IP; 根本: 改容器名 | `docker-compose.yml` (待改) |

详细根因: `docs/2026-06-06-debugging-session.md`

### 2026-06-07 (3 commit 推到 fork)

| Commit | 内容 |
|---|---|
| `d497ff9` | 治本 IP 漂移 — entrypoint 动态解析 + 扫 subnet |
| `c3549ea` | fixup: subnet 10.88→10.89 (治本漏 add) |
| `a553819` | **AI analyze 自动填占位符** (本次修, 见 §15) |
| `ee09986` | podman 3.4.4 适配 + 5 bug 修复 + 镜像源 + sync/watchdog 脚本 |
| `99a622b` | AGENTS.md 加 §14 Fork 维护 |

---

## 4. 架构速查

```
┌─────────────┐  HTTP 21345
│  Browser    ├──────────┐
└─────────────┘          ▼
                ┌────────────────┐
                │ frontend (nginx)│ port 80 → 21345
                │  React SPA      │
                └────┬───────────┘
                     │ /api/* proxy_pass http://backend:8000
                     ▼
                ┌────────────────┐
                │ backend (gunicorn) │ 4 workers, port 8000
                │  Django 6 + DRF  │
                └─┬──────────┬────┘
                  │          │
        ┌─────────▼──┐    ┌──▼─────────┐
        │ PostgreSQL  │    │   Redis     │
        │ 16-alpine   │    │  7-alpine   │
        │ port 5432   │    │  port 6379  │
        └─────────────┘    └────────────┘
                              ▲
                              │ broker + result
                ┌─────────────┴──────┐    ┌────────────────┐
                │ celery-worker      │    │ celery-beat     │
                │ (跑 tasks)         │    │ (调度)         │
                └────────────────────┘    └────────────────┘
```

---

## 5. URL 速查

| 端点 | 用途 |
|---|---|
| `GET /api/health/` | 健康检查 |
| `POST /api/auth/login` | 登录拿 **JWT** (用 `Authorization: Bearer XXX`, 不是 Token) — **路径无斜杠** |
| `GET /api/funds/?search=XXX` | 搜基金 (按代码/名称) |
| `GET /api/funds/compare/?codes=A,B,C` | 多基金对比 (returns/metrics) |
| `GET /api/funds/{code}/` | 单只基金详情 |
| `GET /api/funds/market-indices/` | 4 个指数实时行情 (上证/深证/创业板/科创50) |
| `GET /api/funds/rankings/?type=gain\|popular\|accuracy` | 排行榜 (3 榜) |
| `GET /api/positions/` | 持仓列表 |
| `GET /api/accounts/` | 账户列表 |
| `GET /api/watchlists/` | 自选列表 (空, 需手动加) |
| `GET /api/nav-history/?fund=XXX` | 历史净值 |
| `POST /api/ai/analyze/` | AI 分析 (需 `template_id=1`, 传 `fund_code` 自动填占位符) |
| `GET /api/ai/templates/` | **AI 模板列表** (id=1 基金趋势, id=2 持仓健康度) |
| `GET /api/admin/bootstrap/verify` | bootstrap 状态 |
| `GET /api/admin/stats/` | 管理员统计 |
| `GET /api/notification-channels/` | 通知渠道 (webhook/email 2 种, **无微信**) |
| `GET /api/notification-rules/` | 通知规则 (growth_up/growth_down 2 种, 只支持单只基金阈值) |

---

## 6. management commands 速查

```bash
# 基金列表
python manage.py sync_funds --if-empty       # 仅空表同步 (entrypoint 用)

# 净值
python manage.py update_nav --fund-code XXX  # 拉单只最新
python manage.py update_nav                  # 拉全量最新 (30+ 分钟)
python manage.py update_nav --today          # 拉今日确认 (晚 21:30+)

# 历史净值
python manage.py sync_nav_history --fund-code XXX --start-date 2024-01-01 --end-date 2026-06-07
python manage.py sync_nav_history --start-date 2024-01-01 --end-date 2026-06-07  # 全量

# 其他
python manage.py check_bootstrap
python manage.py calculate_accuracy
python manage.py recalculate_positions
```

**注意参数格式**:
- `update_nav` 用 `--fund_code` (下划线)
- `sync_nav_history` 用 `--fund-code` (连字符)

---

## 7. 已确认 4 个数据源 URL

| 数据 | URL | 备注 |
|---|---|---|
| 估算净值 | `http://fundgz.1234567.com.cn/js/{code}.js` | 实时 |
| 历史净值 | `http://fund.eastmoney.com/pingzhongdata/{code}.js` | 拉一次 1-2 年 |
| 基金列表 | `http://fund.eastmoney.com/js/fundcode_search.js` | 全量 26963 |
| 持仓成分股 | `https://fundmobapi.eastmoney.com/FundMNewApi/FundMNInverstPosition` | ✅ 还活着 (我之前 AGPL 标"弃用"是错的) |
| 批量行情 | `http://push2.eastmoney.com/api/qt/ulist.np/get` | — (aliyun GFW 阻断) |

---

## 8. LLM 接入 (已配)

| 项 | 值 |
|---|---|
| Provider | minimax-cn (OpenAI 兼容) |
| base_url | `https://api.minimaxi.com/v1` |
| Model | `MiniMax-M3` |
| API key 长度 | 125 (token_urlsafe) |
| 配置位置 | Django `AIConfig` 表 (admin user) |
| 验证 | `/api/ai/analyze/` 真 AI 响应 (3 只基金 2,500-3,200 字) ✅ |

---

## 9. 已知问题 (待修)

| # | 问题 | 影响 | 状态 |
|---|---|---|---|
| 1 | 行情中心 3 榜 (gain/popular/accuracy) 周末 0 | UI 不完整 | 周日+没人持仓+23:00 校准未跑=真空, 周一自然有数 |
| 2 | "未登录养基宝" warning 日志噪音 | 日志难读 | 低 (verbose 等级) |
| 3 | "系统状态: 未初始化" UI flag vs `check_bootstrap` 命令矛盾 | UX | 低 |
| 4 | 1,617 只基金没 latest_nav | 行业/排名扫略慢 | 已查: 965 货币型 (正常) + 652 僵尸 (EastMoney 内部已下架, 拉不到) — 接受现状, 周末再验 |
| 5 | **fundval-live 无"主动推荐"功能** | 想系统挑基金 = 不能 | 0 grep 命中, 9 候选 API 全 404 — 只能"自选 + AI 分析" 组合 |
| 6 | **AI 输出不接通知** | AI 不自动发 webhook/email | 手动发, 或 aliyun cron 写 shell 脚本调 AI + 提取 result + 发 webhook |
| 7 | 通知 channel 只 2 种 (webhook/email) | 没法直接发微信 | 微信要走 aliyun hermes-gateway + wechat skill (跨服务) |
| 8 | 通知 rule 只 2 种 (单只基金涨跌幅) | 没法 AI 报告推送 / 持仓变化 / 自定义 trigger | 低, 等用户自定义 |

---

## 10. 待办 (按优先级)

### 高
- [ ] aliyun ECS (小小左) 部署 — 仅 backend + db, 让小小左 cron 调 AI 给选购建议

### 中
- [ ] 修"系统未初始化" UI flag
- [ ] 写 `docs/ai-feature-guide.md` (AI 分析最佳实践 — aliyun cron 怎么调, 通知怎么接)
- [ ] aliyun 通知方案: webhook (Slack/企业微信) 还是 email (SMTP)

### 低
- [ ] "未登录养基宝" warning 静音
- [ ] 行情中心 3 榜 (周末空) — 加提示文案 "周一 21:30 自动有数据"

### 远期 (aliyun)
- [ ] aliyun ECS 部署 (按 `docs/deployment-pitfalls.md` checklist)
- [ ] aliyun RDS 替代容器 PG
- [ ] 配置 HTTPS + 域名

---

## 11. 关联项目

| 项目 | 关系 |
|---|---|
| `~/projects/fund-daily-report/` | 兄弟项目,本机的基金日报。考虑调 FundVal-Live API 当数据源 |
| `~/projects/ai-hedge-fund/` | 候选,4 条件 2/4(无虚拟持仓/无真数据),未装 |
| `~/projects/openbb-terminal/` | 候选,4 条件 0/4,clone 未装 |

---

## 12. 调试工作流 (踩坑后沉淀)

**修代码的推荐流程**:
1. 改 host 源码(`vim backend/...`)
2. `podman cp backend/api/views.py fundval-live_backend_1:/app/api/views.py` 临时调试
3. `podman restart fundval-live_backend_1`
4. 验证 (`curl /api/health/` + UI)
5. **必须** `git add` + `commit` + `push` — podman cp 不持久化, 容器重建会丢
6. **持久化必须** `podman-compose build backend && podman-compose up -d backend` (rebuild 镜像)

**登录忘了密码**:
```bash
podman exec fundval-live_backend_1 python manage.py shell -c "
from django.contrib.auth import get_user_model
U = get_user_model()
u = U.objects.get(username='admin')
u.set_password('new_password')
u.save()
print('RESET admin password → new_password')
"
```

**容器 IP 应急** (治本后极少用):
- 现在 `entrypoint.sh` 治本 (subnet 扫描找 backend), **不需要手动改 IP**
- 历史: 写死 IP → 改容器名 (失败) → 改 entrypoint 动态解析 ✅

---

## 13. Last Updated

2026-06-07 15:55
- AI analyze 占位符自动填修 (commit `a553819` 推 fork)
- 治本 fixup (commit `c3549ea` 推 fork)
- AGENTS.md 重写 7 处 (前端栈 Vue→React / JWT Bearer / ai 端点 / etc.)
- 加 §15 今日修
- 通知系统 verify 完 (webhook/email 2 种, AI 不接通知)

---

## 14. Fork 维护工作流 (2026-06-07 起)

**你 fork 的地址**: `git@github.com:takenroot/FundVal-Live.git`
**upstream**: `https://github.com/Ye-Yu-Mo/FundVal-Live.git` (HTTPS 也行, 22 端口 SSH 更稳)

### 14.1 推送本地到 fork (你日常改完代码)

```bash
cd ~/projects/fundval-live
git status            # 必须无未 commit 改动
git add -A
git commit -m "..."   # 详细 message, 参考 ee09986
git push              # -u 第一次, 之后直接 git push
```

### 14.2 拉 upstream 更新 (周期性: 每 release / 每周)

```bash
cd ~/projects/fundval-live
git fetch upstream

# 看 upstream 有什么新 commit
git log --oneline HEAD..upstream/main

# 简单 merge (推荐 — 你通常只几个 commit ahead, 简单不出错)
git merge upstream/main

# 解冲突 (如果未来有)
git status
# 手动改 → git add . → git commit

# 推 fork
git push
```

### 14.3 拉 upstream/new-main (upstream 切新主干时)

```bash
git fetch upstream
git checkout -b new-main upstream/new-main
git merge main        # 把本地 main 的修改带过来
git push -u origin new-main
```

### 14.4 ⚠ AGPL-3.0 风险

你的 fork **是 public, 没法改 private** (GitHub 2020 后限制, 必须 unlink 才能改).
推 5 bug 修复 + podman 适配 = **derivative work 公开**.
- **自用 OK**
- **不卖/不二次分发项目** OK
- **想卖/二次发布**: 需重构为"外部 client 调 API" 模式

### 14.5 ⚠ HTTPS 走不通, 必须 SSH

国内 443 端口慢/被墙. 已配置:
- SSH key: `~/.ssh/id_ed25519` (在 GitHub 注册过, 用户名 takenroot)
- origin 用 SSH: `git@github.com:takenroot/FundVal-Live.git`

测: `ssh -T git@github.com` 应返回 `Hi takenroot!`

### 14.6 推送前必查清单

```bash
git config --global --list | grep user.   # 确认 name + email 配了
git status                                  # 无未 commit 改动
git diff --stat HEAD~1 HEAD                 # 看这次改了什么 (确认无误)
git log --oneline HEAD..upstream/main       # 看 upstream 有没有新东西拉
```

### 14.7 不应该提交的东西 (已在 .gitignore)

- `_backups/` — 5 bug 修复的 patch 备份 (git 历史就是 backup)
- `*.md` 默认被忽略 — 但**长期文档**用 `git add -f` 强制:
  - `AGENTS.md` (项目记忆)
  - `docs/2026-06-06-debugging-session.md` (5 bug 根因)
  - `docs/deployment-pitfalls.md` (部署踩坑)
- `backend/config.json` — 个人 LLM 配置
- `.env` — 真实密钥 (用 .env.example 占位)

### 14.8 关键路径

| 路径 | 用途 |
|---|---|
| `~/projects/fundval-live/` | 项目根 |
| `~/projects/fundval-live/AGENTS.md` | 项目记忆 (会话 workdir=此目录时自动注入) |
| `~/projects/fundval-live/_backups/2026-06-06-bug-fixes/` | 5 bug 修复 patch 备份 (git 忽略) |
| `~/projects/fundval-live/scripts/sync_nav_history_concurrent.py` | 全量历史净值并发同步脚本 |
| `~/projects/fundval-live/scripts/watchdog_sync.sh` | sync watchdog (FINISHED 状态识别) |
| `~/.hermes/scripts/fundval_sync_watchdog.sh` | 同步副本 (cron 调用) |
| `~/.hermes/skills/fundval-push/SKILL.md` | 本 skill (推送 / 拉 upstream 流程) |

---

## 15. AI analyze 自动填占位符修复 (2026-06-07)

### 问题 (commit `a553819` 前的根因)

后端 `/api/ai/analyze/` 的 `ai_analyze` view 期望的 schema:
```json
{
  "template_id": 1,
  "context_data": { "fund_code": "X", "fund_name": "Y", ... }  ← 包装在 context_data 里
}
```

但实际前端/脚本都直接传:
```json
{ "template_id": 1, "fund_code": "X" }  ← 没用 context_data 包装
```

→ `context_data` 永远是空 `{}`, `_replace_placeholders` 不替换任何 `{{fund_code}}` 等占位符  
→ AI 收到带占位符的 prompt, 抱怨"请提供数据", **不返真分析**

### 修法 (兼容 + 智能化)

`backend/api/views.py:ai_analyze` 函数, `if not template_id` 之后加:

```python
if not context_data:
    fund_code = request.data.get("fund_code")
    if fund_code:
        # 自动从 Fund / FundNavHistory 查
        fund = Fund.objects.get(fund_code=fund_code)
        history = FundNavHistory.objects.filter(fund=fund).order_by("-nav_date")[:30]
        context_data = {
            "fund_code": fund.fund_code,
            "fund_name": fund.fund_name,
            "fund_type": fund.fund_type,
            "latest_nav": str(fund.latest_nav),
            "estimate_growth": f"{fund.estimate_growth:.2f}",
            "nav_history": "\n".join(f"{h.nav_date}: {h.unit_nav}" for h in history),
        }
```

### 调用方式 (简化后)

```bash
curl -X POST -H "Authorization: Bearer XXX" -H "Content-Type: application/json" \
  -d '{"template_id":1,"fund_code":"161725","question":"最近1个月表现如何？"}' \
  http://localhost:21345/api/ai/analyze/
```

### 验证 (3 只基金真 AI 响应)

| 基金 | 字数 | 关键洞察 |
|---|---|---|
| 161725 招商白酒 | 2,587 字 | 4/22 0.6247 → 6/5 0.5564 (-10.9% 跌) |
| 008888 半导体 | 3,095 字 | period high 2.2941 (5/25) / low 1.6140 (4/23) |
| 159995 半导体ETF | 3,238 字 | Phase 1/2 分段, peak 2.7202 (5/25) |

### aliyun cron 调 AI 模板 (推荐)

```bash
# aliyun 上: 每 5 分钟跑一次, 拿 AI 报告
AI_RESP=$(curl -s -X POST -H "Authorization: Bearer XXX" \
  -d '{"template_id":1,"fund_code":"161725","question":"今天适合加仓吗？"}' \
  http://localhost:21345/api/ai/analyze/)
MSG=$(echo "$AI_RESP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('result',''))")

# 发 webhook (Slack/企业微信)
curl -X POST "$SLACK_WEBHOOK" -d "{\"text\":\"$MSG\"}"

# 或发 email
echo "$MSG" | mail -s "AI 基金分析" user@example.com
```

**AI 不会自动发通知** — 必须 aliyun cron 写 shell 脚本手动提取 + 转发 (见 §9 已知问题 #6)
