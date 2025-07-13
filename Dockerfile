# 基础镜像
FROM python:3.10.11-slim AS builder

# 环境变量
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_DEFAULT_TIMEOUT=100

# pip国内源
RUN pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple \
    && pip config set global.trusted-host pypi.tuna.tsinghua.edu.cn

# 构建依赖（阿里云源）
RUN echo "deb https://mirrors.aliyun.com/debian bookworm main contrib non-free non-free-firmware" > /etc/apt/sources.list \
    && echo "deb https://mirrors.aliyun.com/debian-security bookworm-security main contrib non-free non-free-firmware" >> /etc/apt/sources.list \
    && echo "deb https://mirrors.aliyun.com/debian bookworm-updates main contrib non-free non-free-firmware" >> /etc/apt/sources.list \
    && echo "deb https://mirrors.aliyun.com/debian bookworm-backports main contrib non-free non-free-firmware" >> /etc/apt/sources.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gcc g++ python3-dev libffi-dev libssl-dev build-essential git wget ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 升级pip
RUN pip install --upgrade pip setuptools wheel

# 虚拟环境
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# 先安装 typing-extensions，避免 PyTorch 依赖冲突
RUN pip install --retries 3 --timeout 180 typing-extensions
# 安装 PyTorch 及相关包
RUN pip install --retries 10 --timeout 600 --prefer-binary torch torchvision torchaudio -i https://download.pytorch.org/whl/cu128 --no-cache-dir

# 拉取 ComfyUI 代码
RUN git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git /app

# 安装 ComfyUI 主依赖
RUN pip install --retries 3 --timeout 180 -r /app/requirements.txt

# 拉取 ComfyUI-Manager 和 AIGODLIKE-ComfyUI-Translation 代码，并安装依赖
RUN git clone --depth=1 https://github.com/ltdrdata/ComfyUI-Manager.git /app/custom_nodes/ComfyUI-Manager \
    && git clone --depth=1 https://github.com/AIGODLIKE/AIGODLIKE-ComfyUI-Translation.git /app/custom_nodes/AIGODLIKE-ComfyUI-Translation \
    && pip install --retries 3 --timeout 180 -r /app/custom_nodes/ComfyUI-Manager/requirements.txt \
    && if [ -f /app/custom_nodes/AIGODLIKE-ComfyUI-Translation/requirements.txt ]; then pip install --retries 3 --timeout 180 -r /app/custom_nodes/AIGODLIKE-ComfyUI-Translation/requirements.txt; fi

# 生产镜像
FROM python:3.10.11-slim AS production

# 环境变量
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/opt/venv/bin:$PATH" \
    COMFYUI_PORT=8188 \
    COMFYUI_HOST=0.0.0.0 \
    INSTALL_COMFYUI_MANAGER=false

# 运行依赖（阿里云源，增加 git）
RUN echo "deb https://mirrors.aliyun.com/debian bookworm main contrib non-free non-free-firmware" > /etc/apt/sources.list \
    && echo "deb https://mirrors.aliyun.com/debian-security bookworm-security main contrib non-free non-free-firmware" >> /etc/apt/sources.list \
    && echo "deb https://mirrors.aliyun.com/debian bookworm-updates main contrib non-free non-free-firmware" >> /etc/apt/sources.list \
    && echo "deb https://mirrors.aliyun.com/debian bookworm-backports main contrib non-free non-free-firmware" >> /etc/apt/sources.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg libgl1 libglib2.0-0 libgomp1 libgcc-s1 curl ca-certificates git gcc g++ \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# 复制虚拟环境和代码
COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /app /app

# 创建非root用户
RUN groupadd -r comfyui && useradd -r -g comfyui -d /app -s /bin/bash comfyui \
    && chown -R comfyui:comfyui /opt/venv /app

# 设置工作目录
WORKDIR /app

USER comfyui
EXPOSE $COMFYUI_PORT
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 CMD curl -f http://localhost:$COMFYUI_PORT/ || exit 1
CMD ["sh", "-c", "python main.py --listen $COMFYUI_HOST --port $COMFYUI_PORT"]