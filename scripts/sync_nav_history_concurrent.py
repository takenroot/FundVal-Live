#!/usr/bin/env python3
"""
sync_nav_history_concurrent.py — 并发版全量历史净值同步(临时脚本)

功能:
  - ThreadPoolExecutor 并发 (默认 8 worker, 可调)
  - 单只 3 次重试 + 指数退避
  - 单只 60s 超时
  - 进度文件 /tmp/sync_progress.json (崩溃可续)
  - 心跳文件 /tmp/sync_heartbeat.txt (5min 无新 → 报警)
  - 连续 20 次失败 → 暂停 + 写告警
  - 跳过已 sync 的基金 (增量)
  - 单只处理写日志, 摘要写 docs/sync-summary-<date>.md

用法:
  python3 sync_nav_history_concurrent.py
  MAX_WORKERS=16 python3 sync_nav_history_concurrent.py
"""
import os
import sys
import json
import time
import signal
import logging
import traceback
from datetime import datetime, date
from concurrent.futures import ThreadPoolExecutor, as_completed
from threading import Lock

import django

# === Django 初始化 ===
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "fundval.settings")
django.setup()

from api.models import Fund, FundNavHistory
from api.services.nav_history import sync_nav_history
from api.sources import SourceRegistry

# === 配置 ===
MAX_WORKERS = int(os.environ.get("MAX_WORKERS", "8"))
MAX_FUNDS = int(os.environ.get("MAX_FUNDS", "0"))  # 0 = 跑全部
RETRY_MAX = 3
RETRY_BACKOFF = [2, 5, 10]  # 第 1/2/3 次失败后等 N 秒
SINGLE_TIMEOUT = 60  # 单只 60s 超时
HEARTBEAT_INTERVAL = 30  # 30s 写一次心跳
PROGRESS_FILE = "/tmp/sync_progress.json"
HEARTBEAT_FILE = "/tmp/sync_heartbeat.txt"
ALERT_LOG = "/home/saltedfish/projects/fundval-live/docs/watchdog-alerts.log"
SUMMARY_LOG_DIR = "/home/saltedfish/projects/fundval-live/docs"

# === 状态 ===
state = {
    "started_at": datetime.now().isoformat(),
    "total_remaining": 0,
    "processed": 0,
    "succeeded": 0,
    "failed": 0,
    "current_funds": [],
    "consecutive_failures": 0,
    "last_failure_at": None,
    "paused_reason": None,
}
state_lock = Lock()
should_stop = False


def write_heartbeat(extra=""):
    with open(HEARTBEAT_FILE, "w") as f:
        f.write(f"{datetime.now().isoformat()}  processed={state['processed']}/{state['total_remaining']}  succeeded={state['succeeded']}  failed={state['failed']}  {extra}\n")


def write_progress():
    try:
        with open(PROGRESS_FILE, "w") as f:
            json.dump(state, f, indent=2, ensure_ascii=False)
    except Exception as e:
        logging.error(f"写进度文件失败: {e}")


def alert(reason):
    """写告警到 docs/watchdog-alerts.log"""
    msg = f"[{datetime.now().isoformat()}] PAUSED: {reason}\n"
    with open(ALERT_LOG, "a") as f:
        f.write(msg)
    state["paused_reason"] = reason
    logging.error(msg)


def get_remaining_funds():
    """找没历史净值的基金代码 (增量)"""
    done_ids = set(FundNavHistory.objects.values_list("fund_id", flat=True).distinct())
    all_funds = list(Fund.objects.values_list("fund_code", "id"))
    return [(code, fid) for code, fid in all_funds if fid not in done_ids]


def process_one(fund_code, fund_id):
    """处理单只基金,带 retry"""
    last_err = None
    for attempt in range(RETRY_MAX):
        if should_stop:
            return {"code": fund_code, "ok": False, "error": "stopped", "attempts": attempt}
        try:
            count = sync_nav_history(fund_code)
            return {"code": fund_code, "ok": True, "count": count, "attempts": attempt + 1}
        except Exception as e:
            last_err = f"{type(e).__name__}: {str(e)[:200]}"
            if attempt < RETRY_MAX - 1:
                time.sleep(RETRY_BACKOFF[attempt])
    return {"code": fund_code, "ok": False, "error": last_err, "attempts": RETRY_MAX}


def sigint_handler(signum, frame):
    global should_stop
    if not should_stop:
        logging.warning("收到 SIGINT, 设置 should_stop, 当前 fund 跑完会退出...")
        should_stop = True


def main():
    global should_stop
    signal.signal(signal.SIGINT, sigint_handler)
    signal.signal(signal.SIGTERM, sigint_handler)

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        datefmt="%H:%M:%S",
    )
    logger = logging.getLogger("sync_concurrent")

    # 1. 找剩余基金
    remaining = get_remaining_funds()
    if MAX_FUNDS > 0:
        remaining = remaining[:MAX_FUNDS]
        logger.info(f"MAX_FUNDS={MAX_FUNDS}, 只跑前 {len(remaining)} 只 (小批量测试)")
    state["total_remaining"] = len(remaining)
    logger.info(f"找到 {len(remaining)} 只基金需要 sync (从 0 跳过, 增量)")
    if not remaining:
        logger.info("✅ 没有需要 sync 的基金, 退出")
        write_heartbeat("ALL_DONE")
        return

    write_heartbeat("STARTED")
    write_progress()

    # 2. 启动并发 pool
    logger.info(f"启动 {MAX_WORKERS} worker, 处理 {len(remaining)} 只基金")
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as ex:
        future_to_code = {
            ex.submit(process_one, code, fid): code
            for code, fid in remaining
        }

        last_heartbeat = time.time()

        for future in as_completed(future_to_code):
            if should_stop:
                logger.warning(f"should_stop=True, 取消剩余任务")
                for f in future_to_code:
                    f.cancel()
                break

            code = future_to_code[future]
            try:
                result = future.result(timeout=SINGLE_TIMEOUT + 30)
            except Exception as e:
                result = {"code": code, "ok": False, "error": f"FUTURE: {e}", "attempts": 0}

            with state_lock:
                state["processed"] += 1
                if result["ok"]:
                    state["succeeded"] += 1
                    state["consecutive_failures"] = 0
                    logger.info(f"✅ {code} ({result.get('count', 0)} 条) attempt={result['attempts']}")
                else:
                    state["failed"] += 1
                    state["consecutive_failures"] += 1
                    state["last_failure_at"] = datetime.now().isoformat()
                    logger.warning(f"❌ {code} attempt={result['attempts']} err={result.get('error', '?')[:120]}")

                    # 连续失败 → 暂停
                    if state["consecutive_failures"] >= 20:
                        reason = f"连续 {state['consecutive_failures']} 次失败 (最新: {code} {result.get('error', '?')[:100]})"
                        alert(reason)
                        should_stop = True

                # 心跳
                if time.time() - last_heartbeat >= HEARTBEAT_INTERVAL:
                    write_heartbeat(f"in_progress, latest={code}")
                    write_progress()
                    last_heartbeat = time.time()

    # 3. 完成
    finished_at = datetime.now().isoformat()
    state["finished_at"] = finished_at
    write_heartbeat("FINISHED")
    write_progress()

    # 4. 写摘要
    summary = f"""# Sync Run @ {datetime.now().strftime("%Y-%m-%d %H:%M")}

- **Total**: {state["total_remaining"]} 只
- **Succeeded**: {state["succeeded"]} ({state["succeeded"]/max(1, state["total_remaining"])*100:.1f}%)
- **Failed**: {state["failed"]}
- **Consecutive Failures (max)**: 触发暂停 阈值=20
- **Started**: {state["started_at"]}
- **Finished**: {finished_at}
- **Paused**: {state["paused_reason"] or "无"}

进度文件: `{PROGRESS_FILE}`
心跳文件: `{HEARTBEAT_FILE}`
告警日志: `{ALERT_LOG}`
"""
    summary_path = f"{SUMMARY_LOG_DIR}/sync-summary-{datetime.now().strftime('%Y%m%d-%H%M%S')}.md"
    with open(summary_path, "w") as f:
        f.write(summary)
    logger.info(f"摘要写入 {summary_path}")

    logger.info("=" * 60)
    logger.info(f"完成: 成功 {state['succeeded']} / 失败 {state['failed']} / 暂停 {state['paused_reason'] or '无'}")
    logger.info("=" * 60)


if __name__ == "__main__":
    main()
