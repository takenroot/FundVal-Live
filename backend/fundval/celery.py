"""
Celery 配置

定时任务系统，用于自动更新基金净值等后台任务
注意：定时任务调度在 settings.py 的 CELERY_BEAT_SCHEDULE 中统一定义。
      本文件只做应用初始化，不再覆盖 beat_schedule（之前会覆盖 settings 的 9 个任务为 3 个）。
"""

import os
from celery import Celery

# 设置 Django 配置模块
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "fundval.settings")

# 创建 Celery 应用
app = Celery("fundval")

# 从 Django settings 加载配置（使用 CELERY_ 前缀）
app.config_from_object("django.conf:settings", namespace="CELERY")

# 自动发现所有已安装应用中的 tasks.py
app.autodiscover_tasks()


@app.task(bind=True, ignore_result=True)
def debug_task(self):
    """调试任务"""
    print(f"Request: {self.request!r}")
