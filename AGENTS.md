# FundVal-Live (Fundval) — Project Memory

> 项目级 AGENTS.md,会话 workdir = `~/projects/fundval-live` 时自动注入。
> 跨项目记忆(沟通风格/工具偏好) → `~/.hermes/memories/MEMORY.md` (auto-injected)。
> 调试会话根因 → `docs/2026-06-06-debugging-session.md`。
> 部署踩坑 → `docs/deployment-pitfalls.md`。

---

## 1. 是什么

**FundVal-Live** (Ye-Yu-Mo/Fundval) — Django 6 + DRF + Celery + Vue 3 SPA 基金估值与资产管理系统。
- **AGPL-3.0** (严格 copyleft)
- 4/4 全中"基金 bot" 4 条件(开源 + CLI + 虚拟持仓 + 真实数据)
- 4 大数据源: EastMoney (无登录) / Sina (股票) / 养基宝 (扫码) / 小倍养基 (手机号)
- 后端 stack: Django 6 / Celery 5 / PostgreSQL 16 / Redis 7
- 前端 stack: Vue 3 + Vite + Ant Design Vue

**版本**: 2.5.2 (后端 + 前端)

**本项目位置**: `~/projects/fundval-live/`

---

## 2. 部署状态 (2026-06-06)

| 项 | 状态 |
|---|---|
| 本机 WSL podman 跑 | ✅ 6 容器都健康 |
| 6 容器: db/backend/redis/celery-worker/celery-beat/frontend | ✅ |
| 访问 | `http://localhost:21345` (admin / admin123!) |
| 26963 只基金已同步列表 | ✅ (entrypoint 跑 `sync_funds --if-empty`) |
| 全量历史净值同步 | ⏳ 后台跑中 (5.2h, 剩 ~3h) |
| LLM 配置 | ✅ MiniMax-M3 via minimax-cn (A2 已验证) |
| Aliyun ECS 部署 | ❌ 未做 (等本地无问题再上) |

---

## 3. 关键修复记录 (2026-06-06)

| Bug | 修复 | 文件 |
|---|---|---|
| #1 celery.py 覆盖 beat_schedule | 删 celery.py 的 beat 块 | `backend/fundval/celery.py` |
| #2 update_nav 不算 returns/metrics | 加 sync_nav_history 触发 | `backend/api/tasks.py` (新 `sync_nav_history_full`) |
| #3 entrypoint 没触发首次同步 | 加 dispatch NAV sync 段 | `backend/entrypoint.sh` |
| #4 worker 容器代码修改丢失 | 改 host + rebuild 镜像 | (流程改进) |
| #5 frontend 写死 IP 漂移 | 临时:`/etc/hosts` 加新 IP; 根本: 改容器名 | `docker-compose.yml` (待改) |

详细根因: `docs/2026-06-06-debugging-session.md`

---

## 4. 架构速查

```
┌─────────────┐  HTTP 21345
│  Browser    ├──────────┐
└─────────────┘          ▼
                ┌────────────────┐
                │ frontend (nginx)│ port 80 → 21345
                │  Vue 3 SPA      │
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
| `POST /api/auth/login` | 登录拿 token |
| `GET /api/funds/?search=XXX` | 搜基金 (按代码/名称) |
| `GET /api/funds/compare/?codes=A,B,C` | 多基金对比 (returns/metrics) |
| `GET /api/funds/{code}/` | 单只基金详情 |
| `GET /api/positions/` | 持仓列表 |
| `GET /api/accounts/` | 账户列表 |
| `GET /api/watchlists/` | 自选列表 |
| `GET /api/nav-history/?fund=XXX` | 历史净值 |
| `POST /api/ai/analyze/` | AI 分析(LLM 调用) |
| `GET /api/admin/bootstrap/verify` | bootstrap 状态 |
| `GET /api/admin/stats/` | 管理员统计 |
| `GET /api/notification-channels/` | 通知渠道 |
| `GET /api/notification-rules/` | 通知规则 |

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
python manage.py sync_nav_history --fund-code XXX --start-date 2024-01-01 --end-date 2026-06-06
python manage.py sync_nav_history --start-date 2024-01-01 --end-date 2026-06-06  # 全量

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
| 批量行情 | `http://push2.eastmoney.com/api/qt/ulist.np/get` | — |

---

## 8. LLM 接入 (已配)

| 项 | 值 |
|---|---|
| Provider | minimax-cn (OpenAI 兼容) |
| base_url | `https://api.minimaxi.com/v1` |
| Model | `MiniMax-M3` |
| API key 长度 | 125 (token_urlsafe) |
| 配置位置 | Django `AIConfig` 表 (admin user) |
| 验证 | `/api/ai/analyze/` 真实 LLM 响应 ✅ |

---

## 9. 已知问题 (待修)

| # | 问题 | 影响 | 优先级 |
|---|---|---|---|
| 1 | 行情中心 4 tab (涨幅/人气/准度/搜索) 暂无数据 | UI 不完整 | 中(等全量 sync 完可能自动恢复) |
| 2 | 准度榜端点路径错(404) | UI 入口断 | 低 |
| 3 | `/api/ai/prompt-templates/` 404 | AI 用不了默认模板 | 中(用户自建模板可绕过) |
| 4 | frontend `/etc/hosts` 写死 IP 漂移 | 重启后 502 | **高**(生产环境必修) |
| 5 | "未登录养基宝" warning 日志噪音 | 日志难读 | 低(verbose 等级) |
| 6 | "系统状态: 未初始化" UI flag vs `check_bootstrap` 命令矛盾 | UX | 低 |
| 7 | 5 个 bug 修复未持久化(rebuild 镜像) | 容器重建会丢 | **高**(必须明早做) |

---

## 10. 待办 (按优先级)

### 高 (明早做)
- [ ] 改 `docker-compose.yml` 用容器名代替 IP (`extra_hosts` 删除或改用 init.sh)
- [ ] Rebuild 镜像:`podman-compose build && podman-compose up -d`
- [ ] 验证全量历史净值 sync 跑完 (`fund_nav_history` 表行数,目标 ~16M)

### 中
- [ ] 修"系统未初始化" UI flag
- [ ] 修 `/api/ai/prompt-templates/` 路径
- [ ] 行情中心 4 tab 排查(可能是 query 参数不对)

### 低
- [ ] "未登录养基宝" warning 静音
- [ ] 写 `docs/ai-feature-guide.md` (AI 分析最佳实践)

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
2. **不要**只 `podman cp`,这是临时手段
3. `podman-compose build <service>` 重 build
4. `podman-compose up -d` 重启
5. 验证 (`curl /api/health/` + UI)

**临时调试**(不持久化):
```bash
podman cp backend/api/tasks.py fundval-live_celery-worker_1:/app/api/tasks.py
podman restart fundval-live_celery-worker_1
# 测 OK 后,记得 step 3-4
```

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

**容器 IP 应急**:
```bash
NEW_IP=$(podman inspect fundval-live_backend_1 --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
podman exec fundval-live_frontend_1 sh -c "echo '$NEW_IP backend' >> /etc/hosts"
podman exec fundval-live_frontend_1 sh -c "nginx -s reload"
```

---

## 13. Last Updated

2026-06-06 (调试日,5 bug 修完,全量 sync 进行中)
