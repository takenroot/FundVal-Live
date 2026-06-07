FROM docker.m.daocloud.io/library/python:3.13-slim

# 换 debian 源到阿里云（容器内访问 deb.debian.org 慢，apt-get 卡 5+ min）
RUN sed -i 's|http://deb.debian.org|https://mirrors.aliyun.com|g' /etc/apt/sources.list.d/debian.sources 2>/dev/null \
 || sed -i 's|http://deb.debian.org|https://mirrors.aliyun.com|g' /etc/apt/sources.list 2>/dev/null

# 配 pip 走清华源（容器内 pypi.org 慢，django 8MB 卡 1min+）
RUN pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple \
 && pip config set global.trusted-host pypi.tuna.tsinghua.edu.cn

WORKDIR /app

# 安装系统依赖
RUN apt-get update && apt-get install -y \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# 复制依赖文件
COPY requirements.txt .

# 安装 Python 依赖
RUN pip install --no-cache-dir -r requirements.txt

# 复制项目文件
COPY . .

# 复制并设置 entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 创建配置目录（用于挂载 volume）
RUN mkdir -p /app/config

# 暴露端口
EXPOSE 8000

# 入口脚本
ENTRYPOINT ["/entrypoint.sh"]

# 默认启动命令
CMD ["gunicorn", "fundval.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "4", "--access-logfile", "-", "--error-logfile", "-"]
