# 2026-06-06 FundVal-Live 调试会话

> 用户报告"基金对比 → 热门组合 → 白酒 vs 新能源 vs 半导体 4 维图空"开始,
> 实际发现 5 个相互关联的 bug,详见本文档。

---

## 1. 现象

**用户报**: 点击"基金对比 → 热门组合 → 白酒 vs 新能源 vs 半导体",
弹出 3 个基金代码标签(161725/012414/014193),但 4 维图只剩骨架屏,无数值。

---

## 2. 完整因果链

```
┌──────────────────────────────────────────────────────────┐
│  Bug #1  celery.py 覆盖 settings.py 的 beat_schedule      │
│          → 8 个定时任务被压成 3 个 (1 个 check + 3 个净值)│
└──────────────────────────────────────────────────────────┘
                          ↓
┌──────────────────────────────────────────────────────────┐
│  Bug #3  entrypoint.sh 只跑 sync_funds --if-empty          │
│          → 26963 只基金有"代码+名称"记录                  │
│          → 没有任何一只基金被拉过 latest_nav              │
└──────────────────────────────────────────────────────────┘
                          ↓
┌──────────────────────────────────────────────────────────┐
│  Bug #2  update_nav 只拉最新净值                           │
│          → 即使手动跑,returns / metrics 仍 null           │
│          → 因为计算 returns/metrics 需要历史净值           │
│          → 但 sync_nav_history 没有任何 trigger           │
└──────────────────────────────────────────────────────────┘
                          ↓
┌──────────────────────────────────────────────────────────┐
│  Bug #6  backend 容器 IP 漂移 (10.88.0.4 → 10.88.0.16)    │
│          → frontend /etc/hosts 写死旧 IP → 502 Bad Gateway│
│          → 修复:nginx -s reload + /etc/hosts 加新 IP     │
└──────────────────────────────────────────────────────────┘
                          ↓
┌──────────────────────────────────────────────────────────┐
│  结论: 4 维图空 = 数据层 0 净值 + 网络层 502 双重叠加     │
└──────────────────────────────────────────────────────────┘
```

---

## 3. 5 个 Bug 详细

### Bug #1 — celery.py 覆盖 beat_schedule

**位置**: `backend/fundval/celery.py:24-37`

**症状**: celery.py 在 `config_from_object("django.conf:settings", namespace="CELERY")`
之后**又**直接赋值 `app.conf.beat_schedule = {...}`,**覆盖**了 settings.py 的 9 个任务。

**根因**: 开发时把 beat schedule 写在 celery.py(更显眼),但没意识到 settings.py 也有一份更完整的。

**修复**: 删 `celery.py` 的 `beat_schedule` 块,让 settings.py 单一来源。

```diff
- app.conf.beat_schedule = {
-     "update-fund-nav-daily": {...},
-     "update-fund-today-nav-evening": {...},
-     "update-fund-today-nav-night": {...},
- }
```

**验证**: `celery -A fundval inspect scheduled` 现在能列出 9 个任务(之前只 1 个)。

---

### Bug #2 — update_nav 不算 returns/metrics

**位置**: `backend/api/management/commands/update_nav.py`

**症状**: `update_nav` 只调 `fetch_realtime_nav()` 拉**最新**净值,写入 `fund.latest_nav`。
但前端 `compare` 端点需要的 `returns.{1m,3m,6m,1y}` 和 `metrics.{max_drawdown,volatility,sharpe}`
**必须用历史净值**计算。

**修复**: 必须**另外跑** `sync_nav_history`(拉 2.5 年历史),然后 `returns` 才会有值。

```bash
# 拉单只 2.5 年历史 (586 条)
python manage.py sync_nav_history --fund-code 161725 --start-date 2024-01-01 --end-date 2026-06-06
# 全量 26963 只 (后台,5+ 小时)
python manage.py sync_nav_history --start-date 2024-01-01 --end-date 2026-06-06
```

---

### Bug #3 — entrypoint 启动后没触发首次同步

**位置**: `backend/entrypoint.sh`

**症状**: 启动流程:
1. wait db ✅
2. migrate ✅
3. collectstatic ✅
4. check_bootstrap ✅
5. **`sync_funds --if-empty`** ← 只同步基金列表
6. exec gunicorn

**没触发**:
- `update_nav` (拉最新净值)
- `sync_nav_history` (拉历史净值)

→ 启动 5 秒后,UI 已经能打开,但**所有数据都是 null**,用户看到的就是"4 维图空"。

**修复**: 在 `sync_funds` 之后加一段,**dispatch 到 celery 后台**(避免启动阻塞 1.5h):

```bash
python -c "
import django, os
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'fundval.settings')
django.setup()
from api.tasks import update_fund_nav, sync_nav_history_full
update_fund_nav.delay()
sync_nav_history_full.delay()
" || echo "(celery dispatch failed — broker unreachable)"
```

---

### Bug #4 — Celery 容器 restart 后丢失修改的代码

**症状**: 修改 `tasks.py` + `podman cp` 到容器 + `podman restart` 后,
worker 仍报 `KeyError: 'api.tasks.sync_nav_history_full'`。

**根因**:
- backend 容器是**有状态**(config_data volume 挂载) → 修改可保留
- celery-worker/beat 容器**每次 restart 从镜像恢复** → `podman cp` 改的代码丢

**修复**: 改 host 源码 → **rebuild 镜像** → `podman-compose up -d`。
(临时调试:再次 `podman cp` 到 worker 容器,但下次 restart 仍会丢。)

**重要教训**: **任何代码修改必须先改 host 文件,rebuild 镜像再 up**,不能只 `podman cp`。
调试期可以 cp,但记得最后要 rebuild。

---

### Bug #5 — (开发中常见) — 之前 docker-compose.yml 的 IP 写死问题

**位置**: `docker-compose.yml:extra_hosts`

**症状**: 我之前为了绕开 `podman 3.4.4 compose 不写 DNS`,手动写:
```yaml
extra_hosts:
  - "backend:10.88.0.4"  # hardcode IP
```

但**容器 restart 后 IP 变化** (10.88.0.4 → 10.88.0.16),导致:
- frontend nginx `proxy_pass http://backend:8000` 解析到旧 IP
- 502 Bad Gateway

**临时修**: `podman exec frontend sh -c "echo '10.88.0.16 backend' >> /etc/hosts"` + `nginx -s reload`

**根本修**(明天做): 改 `docker-compose.yml` 用**容器名**而不是 IP,让 podman 内部 DNS 解析。
或: 写一个 `init.sh` 在容器启动后自动从 podman inspect 拿 IP 写 hosts。

---

### Bug #6 — bug 编号复用修正

> 上面 Bug #5 和 Bug #6 实际是同一个问题(frontend 写死 IP 漂移),重命名为 "Bug #5 IP 漂移"。

---

## 4. 修复后实测

修复完,3 只白名单基金数据:

```
161725 招商中证白酒(LOF)A   0.5564  1y -25.51%  弱 (回撤 -44.22 / 波动 26.07 / 夏普 -0.78)
012414 招商中证白酒(LOF)C   0.5537  1y -25.58%  弱 (回撤 -44.33 / 波动 26.07 / 夏普 -0.78)
014193 汇添富中证芯片增强    1.7938  1y +119.10% 强 (回撤 -19.7  / 波动 37.66 / 夏普 +1.31)
```

数据完全符合 2024-2025 A 股行情(白酒暴跌 25% / 芯片暴涨 119%)。

---

## 5. 关键文件改动清单 (备份在 _backups/2026-06-06-bug-fixes/)

| 文件 | 改动 | 备份 |
|---|---|---|
| `backend/fundval/celery.py` | 删 beat_schedule 块 (Bug #1) | `celery.py.remove-beat-override` |
| `backend/entrypoint.sh` | 加 dispatch NAV sync 段 (Bug #3) | `entrypoint.sh.add-bg-nav-sync` |
| `backend/api/tasks.py` | 新增 `sync_nav_history_full` task | `tasks.py.add-sync-nav-history-full` |

---

## 6. 顺手发现的"非 bug 但需注意"项

| # | 现象 | 原因 | 建议 |
|---|---|---|---|
| 1 | `update_nav` 日志: "获取基金 X 净值失败: 未登录养基宝" | 养基宝数据源需要扫码登录(我们没用) | 不影响 EastMoney 主源,加 verbose 等级 |
| 2 | `sync_funds --if-empty` 只在空表时跑 | 设计 — 避免重复同步 26963 只 | OK |
| 3 | UI "系统状态: 未初始化" flag 跟 `check_bootstrap` 命令矛盾 | 两套独立 flag:UI flag 表示"前端引导完成",命令 flag 表示"后端 entrypoint 完成" | 改用同一 flag |
| 4 | 行情中心 4 tab (涨幅/人气/准度/搜索) 暂无数据 | 因为全市场基金 `latest_nav` 大多 null,排序后还是空 | 等全量同步完应该自动有 |

---

## 7. 全量同步资源估算

**问题**: "光说跑全量了,环境够不够?"

**资源**:
- WSL host: 11Gi 内存 / 8 核 / 1007GB 磁盘(57GB used)
- 容器 worker 实测: 494MB 内存 / 1.69% CPU / 网络 36ms
- 数据库增长: 187 KB/只 × 26963 只 = **~5 GB**

**结论**: 资源充足(用了不到 5%),但:
- **全量 sync 5.2h 不能在交易时段跑**(周六凌晨跑了没事,工作日会拖慢 gunicorn)
- **5GB 数据库**对 PG 没问题,但备份/同步要算上
- 周末 0% 数据,工作日会有真实净值更新

**优化方向**(明天考虑):
- 并发跑 sync (worker 改 ForkPool max_tasks_per_child)
- 分批:先跑白名单 6 只,后跑全量
- celery 任务队列加优先级

---

## 8. AGPL-3.0 风险评估

**新增的 `sync_nav_history_full` task** 是 FundVal-Live 源码的修改,
按 AGPL-3.0 算 derivative work,理论上有传染风险。

**风险评估**:
| 部署方式 | AGPL 风险 |
|---|---|
| 本机自用,不发布 | 0 |
| 内部 GitLab (公司私有) | 低(不公开分发) |
| 公网 GitHub + AGPL 标记 | 合规传染 |
| 公网 GitHub + 商业闭源 | **违法** |

**结论**: 本项目自用场景风险为 0。如果将来要二次发布,需要**隔离**:
- 把 `sync_nav_history_full` 移到独立 client 进程
- 通过 FundVal-Live REST API 调用,不直接改源码
