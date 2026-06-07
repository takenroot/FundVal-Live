#!/bin/sh
# frontend/entrypoint.sh — 启动时解析 backend 容器名, 写 /etc/hosts
# 2026-06-07 治本 — 跟 podman 版本无关, IP 漂移也不怕
# 用 /bin/sh (alpine 默认 ash, 没有 bash)
set -e

echo "=========================================="
echo "  Fundval Frontend Starting"
echo "=========================================="

# 解析 backend 容器名, 写 /etc/hosts
# 策略: 1) getent (dnsname)  2) 扫 subnet 试 8000 端口
#       (dnsname 在 podman 3.4.4 不可靠, 但 subnet 扫描稳)
echo "Resolving backend hostname..."
RESOLVED=0

# 1. 试 getent
IP=$(getent hosts backend 2>/dev/null | awk '{print $1; exit}')
if [ -n "$IP" ]; then
  echo "$IP backend" >> /etc/hosts
  echo "  ✓ backend -> $IP (via getent)"
  RESOLVED=1
fi

# 2. 扫 subnet 试 8000 端口 (fallback, 30 次重试)
if [ $RESOLVED -eq 0 ]; then
  echo "  getent failed, scanning subnet 10.88.0.0/24 for :8000..."
  for i in 1 2 3 4 5 6 7 8 9 10; do
    for last in 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
      ip="10.88.0.$last"
      # 试 8000 端口 (busybox nc -z)
      if nc -z -w 1 "$ip" 8000 2>/dev/null; then
        echo "$ip backend" >> /etc/hosts
        echo "  ✓ backend -> $ip (via subnet scan :8000)"
        RESOLVED=1
        break 2
      fi
    done
    sleep 1
  done
fi

if [ $RESOLVED -eq 0 ]; then
  echo "  ✗ backend FAILED to resolve in 30s — nginx will likely fail to start"
fi

# 启动 nginx (daemon mode)
exec nginx -g "daemon off;"
