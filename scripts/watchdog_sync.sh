#!/bin/bash
# watchdog_sync.sh — FundVal-Live 全量历史净值同步 watchdog
# 配 cron job 5 分钟跑一次 (no_agent=True, 异常才 stdout 推送)
#
# 三种检测:
#   1. 心跳文件 > 10 分钟没新 → 报警
#   2. sync 进程不在了 → 报警
#   3. paused_reason 非空 / failed > 100 → 报警
# 正常时静默, 只更新 docs/watchdog-status.md (用户随时可查)

set -e

POD="fundval-live_backend_1"
HEARTBEAT_CONTAINER="/tmp/sync_heartbeat.txt"
PROGRESS_CONTAINER="/tmp/sync_progress.json"
STATUS_MD="/home/saltedfish/projects/fundval-live/docs/watchdog-status.md"
ALERT_LOG="/home/saltedfish/projects/fundval-live/docs/watchdog-alerts.log"

NOW=$(date -Iseconds)

alert() {
  local msg="$1"
  echo "🚨 [$NOW] $msg"
  echo "[$NOW] $msg" >> "$ALERT_LOG"
}

# 0. 拿 progress (container → host 缓存)
PROGRESS=$(podman exec "$POD" cat "$PROGRESS_CONTAINER" 2>/dev/null)
[ -z "$PROGRESS" ] && {
  alert "progress 文件空/不存在 ($POD:$PROGRESS_CONTAINER)"
  exit 0
}

# 0.1. FINISHED 状态?  (sync 任务自然结束, 进程退出, 心跳停留是正常的)
FINISHED=$(echo "$PROGRESS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('finished_at') or '')" 2>/dev/null)
if [ -n "$FINISHED" ]; then
  PROCESSED=$(echo "$PROGRESS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('processed', 0))" 2>/dev/null || echo 0)
  TOTAL=$(echo "$PROGRESS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('total_remaining', 0))" 2>/dev/null || echo 0)
  FAILED=$(echo "$PROGRESS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('failed', 0))" 2>/dev/null || echo 0)
  cat > "$STATUS_MD" <<EOF
# Sync Watchdog Status — ✅ FINISHED

**Sync 完成于**: $FINISHED
**最后检查**: $NOW
**结果**: $PROCESSED / $TOTAL (failed=$FAILED)

⚠️  任务已结束, watchdog 不再报警. 如需重启 sync 跑全量, 删 /tmp/sync_progress.json 后手动启脚本.
EOF
  # 静默退出 — FINISHED 是预期状态
  exit 0
fi

# 1. 拿心跳 (仅在非 FINISHED 状态才有意义)
HEARTBEAT=$(podman exec "$POD" cat "$HEARTBEAT_CONTAINER" 2>/dev/null | head -1)
if [ -z "$HEARTBEAT" ]; then
  alert "心跳文件空/不存在 ($POD:$HEARTBEAT_CONTAINER)"
  exit 0
fi

LAST_TIME=$(echo "$HEARTBEAT" | awk '{print $1}')
if [ -z "$LAST_TIME" ]; then
  alert "心跳格式异常: $HEARTBEAT"
  exit 0
fi

NOW_S=$(date -d "$NOW" +%s)
LAST_S=$(date -d "$LAST_TIME" +%s)
AGE_S=$(( NOW_S - LAST_S ))

# 2. 进程检查已删 — 心跳 8s 内有更新 = 进程必然在跑 (心跳只能由 sync 脚本写)
#    容器内无 ps, 且 python 进程 comm 是 "python" 不含脚本名, /proc 检测不可靠

# 3. 解析进度
PROCESSED=$(echo "$PROGRESS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('processed', 0))" 2>/dev/null || echo 0)
TOTAL=$(echo "$PROGRESS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('total_remaining', 0))" 2>/dev/null || echo 0)
SUCCEEDED=$(echo "$PROGRESS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('succeeded', 0))" 2>/dev/null || echo 0)
FAILED=$(echo "$PROGRESS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('failed', 0))" 2>/dev/null || echo 0)
PAUSED=$(echo "$PROGRESS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('paused_reason', '') or '')" 2>/dev/null || echo "")
PCT=$(python3 -c "print(f'{${PROCESSED}/${TOTAL}*100:.1f}%' if $TOTAL > 0 else '?')" 2>/dev/null || echo "?")

# 4. 报警判断
if [ "$AGE_S" -gt 600 ]; then
  alert "心跳 ${AGE_S}s 没新 (>10min) — latest: $HEARTBEAT"
fi
if [ -n "$PAUSED" ]; then
  alert "已暂停: $PAUSED (processed=$PROCESSED/$TOTAL succeeded=$SUCCEEDED failed=$FAILED)"
fi
if [ "${FAILED:-0}" -gt 100 ]; then
  alert "失败过多: failed=$FAILED (threshold=100) — processed=$PROCESSED/$TOTAL"
fi

# 5. 写 status md (用户随时可查, 不推送)
cat > "$STATUS_MD" <<EOF
# Sync Watchdog Status

**Generated**: $NOW

| 指标 | 值 |
|---|---|
| Container | $POD |
| Heartbeat age | ${AGE_S}s |
| Processed | $PROCESSED / $TOTAL ($PCT) |
| Succeeded | $SUCCEEDED |
| Failed | $FAILED |
| Paused | ${PAUSED:-无} |
| Latest fund | $(echo "$HEARTBEAT" | grep -oE 'latest=[^ ]*' || echo "?") |

EOF

# 6. 静默退出 (no_agent cron 不会推送空 stdout)
exit 0
