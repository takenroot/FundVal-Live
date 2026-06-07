# FundVal-Live 部署踩坑清单

> 本地 podman 部署 + aliyun ECS 部署时**已踩过**的坑,以及**下次部署必看**的注意事项。

---

## 1. podman 3.4.4 限制(WSL 环境)

| 限制 | 影响 | 解法 |
|---|---|---|
| 无 `compose` 子命令 | 必须装 `podman-compose` 1.6.0+ | `pip install podman-compose` |
| 不支持 `condition: service_healthy` | compose 健康检查条件不工作 | 手动 `extra_hosts` + 等 5 秒 |
| compose 不写 DNS 解析 | 容器间不能用名字访问 | `extra_hosts: "db:10.88.0.2"` 写死 IP |
| **容器 restart 后 IP 漂移** | `extra_hosts` 写死的 IP 失效,出现 502 | 见下文 §2 |

---

## 2. 容器 IP 漂移 — 头号踩坑

**症状**: podman-compose up 一段时间后,前端 nginx 502,backend 实际在跑。

**根因**: podman 容器每次 restart 会从 10.88.0.X 池里**随机分配新 IP**,我之前写死的 `extra_hosts` 失效。

**短期应急**:
```bash
# 1. 拿新 IP
NEW_IP=$(podman inspect fundval-live_backend_1 --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
# 2. 写进 frontend /etc/hosts
podman exec fundval-live_frontend_1 sh -c "echo '$NEW_IP backend' >> /etc/hosts"
# 3. 重载 nginx
podman exec fundval-live_frontend_1 sh -c "nginx -s reload"
```

**根治方案 (明天做)**:
1. **改用容器名**而非 IP — 修 `docker-compose.yml`:
   ```yaml
   # 之前 (坏):
   extra_hosts:
     - "backend:10.88.0.4"
   # 之后 (好):
   # 删掉 extra_hosts,容器间靠 podman 网络 + DNS 解析
   ```
   但 podman 3.4.4 内部 DNS 解析可能不稳,**需要测试**。
2. **init.sh 动态写 hosts** — 在 backend/celery/beat 启动时通过 podman 注入脚本:
   ```bash
   #!/bin/bash
   # init.sh
   for svc in backend db redis celery-worker celery-beat; do
     IP=$(podman inspect fundval-live_${svc}_1 --format '{{.NetworkSettings.Networks.fundval.IPAddress}}')
     echo "$IP $svc" >> /etc/hosts
   done
   ```
3. **改用 `podman network create` 显式子网** — 固定 IP 池。

---

## 3. 镜像源配置 (国内)

**当前配置** (`~/.config/containers/registries.conf`):
```
[[registry.mirror]]
location = "docker.1ms.run"
```

**白名单覆盖**:
- `docker.1ms.run` — 部分 Docker Hub 镜像 (postgres/redis/python/nginx/node ✅)
- `docker.m.daocloud.io` — 完整 docker.io 镜像 (上面全 5 个 ✅)
- `jasamine/fundval-*` 预制镜像 — **daocloud 白名单外** ❌,必须本地 build

**结论**: aliyun ECS 部署时,如果 registry mirror 没配好,会卡 5+ 分钟(docker.io GFW 阻断)。

**aliyun 推荐配置**:
1. 用 `docker.m.daocloud.io` (白名单覆盖全)
2. 基础镜像用 daocloud,自定义镜像本地 build
3. aliyun 自身有 `registry.cn-hangzhou.aliyuncs.com` 加速,但 fundval-live 镜像没 push 到那

---

## 4. 容器内 apt/pip 源 (debian 镜像)

**踩坑**: 容器内 `apt-get install` 卡 5+ 分钟(docker.io 网络慢),`pip install django 8MB` 卡 1+ 分钟。

**修法** (`backend/Dockerfile`):
```dockerfile
# 换 debian 源到阿里云
RUN sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list.d/debian.sources
# 换 pip 源到清华
RUN pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
```

`frontend/Dockerfile` 同样改 FROM 到 `docker.m.daocloud.io/library/node:20-alpine` + `nginx:alpine`。

---

## 5. AGPL-3.0 法律风险

FundVal-Live 是 AGPL-3.0 严格 copyleft。

**风险矩阵**:
| 部署方式 | 风险 |
|---|---|
| 本机自用,不发布 | 0 |
| 公司内私有 GitLab | 低 |
| 公网 GitHub + AGPL 标记 | 合规 |
| 公网 GitHub + 闭源 | **违法** |

**自用场景无忧**。如果将来要二次开发分发,**必须**:
- 隔离:把自定义代码放独立进程,通过 REST API 调用
- 不直接 fork FundVal-Live 源码改

---

## 6. AGPL/AGPL 触发条件

| 行为 | 是否触发 AGPL 义务 |
|---|---|
| 用 FundVal-Live 自用 | 不触发 |
| 修改 FundVal-Live 源码自用 | 不触发(只用不发布) |
| 把 FundVal-Live 部署到服务器,服务公开访问 | 触发 — 必须开源你的修改 |
| Fork 改后发布 | 触发 — 整个 work 必须 AGPL |

**aliyun ECS 部署**:
- 如果**只自己用**(VPN 访问),不触发
- 如果**给团队/朋友用**,触发 — 需开源所有 derivative work
- 如果**对外公开服务**,触发

---

## 7. celery 定时任务的两套配置

**易踩坑**: celery.py 和 settings.py 都可能有 `beat_schedule`,
**只有一个会生效**(后者覆盖前者)。

**统一规则**:
- **全部** beat schedule 写 `settings.py::CELERY_BEAT_SCHEDULE`(完整、详细)
- `celery.py` **不**覆盖 `beat_schedule`(只做 app 初始化)
- 加新 task 时:同时改 `tasks.py` + `settings.py`,**别忘了 `app.autodiscover_tasks()`**

**alerts 模式**: `app.conf.beat_schedule = {...}` 直接赋值是**覆盖**,
应该用 `app.conf.beat_schedule.update({...})` 增量加(更安全)。

---

## 8. Celery 容器代码修改

**踩坑**: `podman cp` 改 worker 容器内代码,**重启就丢**(从镜像恢复)。

**修法**:
- 改 host 源码 → `podman-compose build` → `podman-compose up -d`
- **不要**只 `podman cp`,这是临时调试手段,不是持久方案

**调试时**:
```bash
# 1. 改 host 源码
vim backend/api/tasks.py
# 2. cp 到容器测
podman cp backend/api/tasks.py fundval-live_celery-worker_1:/app/api/tasks.py
# 3. 重启 worker
podman restart fundval-live_celery-worker_1
# 4. 测 OK 后,记得 rebuild 镜像(否则下次 up 丢)
podman-compose build celery-worker
```

---

## 9. 数据库连接稳定性

**WSL podman 3.4.4 + 容器间通信偶发断**:
- 现象: gunicorn 报 `connection refused` 或 `host unreachable`
- 临时: `podman restart backend frontend`
- 根治: aliyun ECS 用真实 docker 网络,不依赖 podman 3.4.4

**PostgreSQL 容器**:
- 配置密码不能含特殊字符(`$`,`!`,`#`)
- 端口映射到 host **不安全**(仅调试用)
- 生产环境:用云 RDS (aliyun RDS-PG)

---

## 10. 全量同步的工程考虑

**单次 sync 5.2 小时**:
- 不能在交易时段(影响 gunicorn 4 workers)
- 周末跑不影响生产
- 大表 (15M 行) 不影响查询性能,但备份变慢

**优化方向**:
1. **分批**: 跑白名单 6 只优先(< 1 分钟),后跑全量
2. **并发**: worker ForkPool 调大 max_tasks_per_child
3. **增量**: 用 `updated_at` 跳过 7 天内已同步的
4. **数据压缩**: 历史净值表用 `numeric(10,4)` 而非 `text`

---

## 11. aliyun ECS 部署 checklist

- [ ] podman 3.4.4 → ECS 装 docker 24+ (用 docker compose)
- [ ] 镜像 registry mirror 配 daocloud
- [ ] 容器 IP 漂移问题用 `docker network create fundval --subnet 10.88.0.0/24` 固定子网
- [ ] PostgreSQL 用 aliyun RDS(不跑容器)
- [ ] .env 里的 SECRET_KEY / POSTGRES_PASSWORD 改用 aliyun KMS
- [ ] 配置 nginx reverse proxy 域名 + HTTPS
- [ ] 配 aliyun CloudMonitor 报警(容器 down / DB down)
- [ ] 备份策略:每天 03:00 PG 逻辑备份到 OSS
- [ ] AGPL 风险评估:如果给团队用,需开源所有 derivative work

---

## 12. 资源参考

- 修复 5 个 bug 的根因: `docs/2026-06-06-debugging-session.md`
- podman 镜像加速: https://docker.m.daocloud.io
- AGPL 3.0 中文翻译: https://www.gnu.org/licenses/agpl-3.0.html
- Django + Celery beat 调度: https://docs.celeryq.dev/en/stable/userguide/periodic-tasks.html
