#!/bin/bash
set -e

echo "=========================================="
echo "  Fundval Backend Starting"
echo "=========================================="

# 2026-06-07 治本 (跟 podman 版本无关): 动态解析 db/redis 容器名
# podman 3.4.4 + 4+ + 5+ 都靠 CNI / dnsname, dnsname 不可靠
# 策略: 启动时重试解析容器名, 拿到 IP 写 /etc/hosts
# 优势: 不依赖 extra_hosts 写死 IP, IP 漂移也不怕 (每次启动都重新解析)
echo "Resolving service hostnames (dnsname fallback)..."
for svc in db redis; do
  RESOLVED=0
  for i in {1..30}; do
    # 试解析 — 优先 getent hosts, 失败用 ping subnet 扫描
    if getent hosts "$svc" > /dev/null 2>&1; then
      IP=$(getent hosts "$svc" | awk '{print $1; exit}')
      if [ -n "$IP" ]; then
        # 写到 /etc/hosts (只在没写过时)
        if ! grep -qE "[[:space:]]${svc}(\$|[[:space:]])" /etc/hosts 2>/dev/null; then
          echo "$IP $svc" >> /etc/hosts
        fi
        echo "  ✓ $svc -> $IP (via getent)"
        RESOLVED=1
        break
      fi
    fi
    sleep 1
  done
  if [ $RESOLVED -eq 0 ]; then
    echo "  ✗ $svc FAILED to resolve in 30s (entrypoint will continue, may fail later)"
  fi
done

# 等待数据库就绪
echo "Waiting for database..."
while ! pg_isready -h ${POSTGRES_HOST:-db} -p ${POSTGRES_PORT:-5432} -U $POSTGRES_USER > /dev/null 2>&1; do
    sleep 1
done
echo "✓ Database ready"

# 运行数据库迁移
echo "Running migrations..."
python manage.py migrate --noinput
echo "✓ Migrations complete"

# 收集静态文件
echo "Collecting static files..."
python manage.py collectstatic --noinput
echo "✓ Static files collected"

# 检查系统初始化状态
echo "=========================================="
python manage.py check_bootstrap
echo "=========================================="

# 首次启动自动同步基金数据
echo "Checking fund data..."
python manage.py sync_funds --if-empty
echo "✓ Fund data check complete"

# 首次启动触发后台拉净值(避免启动阻塞 30+ 分钟)
# - update_nav: 拉最新净值 (Fund 表 latest_nav 字段)
# - sync_nav_history: 拉历史净值 (returns/metrics 计算的源数据)
# celery worker 会异步执行,本容器不阻塞,刷新 UI 几分钟后看数据
echo "Triggering background NAV sync (update_nav + sync_nav_history)..."
python -c "
import django, os
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'fundval.settings')
django.setup()
from api.tasks import update_fund_nav, sync_nav_history_full
try:
    update_fund_nav.delay()
    print('  update_fund_nav dispatched')
except Exception as e:
    print(f'  update_fund_nav dispatch failed: {e}')
try:
    sync_nav_history_full.delay()
    print('  sync_nav_history_full dispatched')
except Exception as e:
    print(f'  sync_nav_history_full dispatch failed: {e}')
" || echo "  (celery dispatch skipped — broker unreachable, will rely on beat @ 22:30)"

# 启动应用
exec "$@"
