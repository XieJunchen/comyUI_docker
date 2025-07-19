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
RUN pip install --retries 3 --timeout 180 typing-extensions decord
# 安装 PyTorch 及相关包
RUN pip install --retries 10 --timeout 600 --prefer-binary torch torchvision torchaudio -i https://download.pytorch.org/whl/cu128 --no-cache-dir

# 拉取 ComfyUI 代码
RUN git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git /app

# 安装 ComfyUI 主依赖
RUN pip install --retries 3 --timeout 180 -r /app/requirements.txt

# 批量拉取 custom_nodes 并安装依赖（失败自动跳过）
RUN set -e; \
    for repo in \
        "AIGODLIKE/AIGODLIKE-ComfyUI-Translation" \
        "ltdrdata/ComfyUI-Manager" \
        "cubiq/ComfyUI_IPAdapter_plus" \
        "Kosinkadink/ComfyUI-AnimateDiff-Evolved" \
        "Fannovel16/comfyui_controlnet_aux" \
        "pythongosssss/ComfyUI-Custom-Scripts" \
        "kijai/ComfyUI-HunyuanVideoWrapper" \
        "ltdrdata/ComfyUI-Impact-Pack" \
        "AIGODLIKE/AIGODLIKE-ComfyUI-Translation" \
        "aigc-apps/EasyAnimate" \
        "city96/ComfyUI-GGUF" \
        "kijai/ComfyUI-SUPIR" \
        "rgthree/rgthree-comfy" \
        "Lightricks/ComfyUI-LTXVideo" \
        "cubiq/ComfyUI_InstantID" \
        "yolain/ComfyUI-Easy-Use" \
        "XLabs-AI/x-flux-comfyui" \
        "WASasquatch/was-node-suite-comfyui" \
        "kijai/ComfyUI-CogVideoXWrapper" \
        "kijai/ComfyUI-KJNodes" \
        "logtd/ComfyUI-Fluxtapoz" \
        "jags111/efficiency-nodes-comfyui" \
        "kijai/ComfyUI-Florence2" \
        "AlekPet/ComfyUI_Custom_Nodes_AlekPet" \
        "crystian/ComfyUI-Crystools" \
        "ssitu/ComfyUI_UltimateSDUpscale" \
        "Kosinkadink/ComfyUI-VideoHelperSuite" \
        "Acly/comfyui-inpaint-nodes" \
        "Suzie1/ComfyUI_Comfyroll_CustomNodes" \
        "nullquant/ComfyUI-BrushNet" \
        "cubiq/PuLID_ComfyUI" \
        "cubiq/ComfyUI_essentials" \
        "welltop-cn/ComfyUI-TeaCache" \
        "chrisgoringe/cg-use-everywhere" \
        "Fannovel16/ComfyUI-Frame-Interpolation" \
        "lquesada/ComfyUI-Inpaint-CropAndStitch" \
        "TTPlanetPig/Comfyui_TTP_Toolset" \
        "melMass/comfy_mtb" \
        "john-mnz/ComfyUI-Inspyrenet-Rembg" \
        "EvilBT/ComfyUI_SLK_joy_caption_two" \
        "kijai/ComfyUI-DepthAnythingV2" \
        "chflame163/ComfyUI_LayerStyle_Advance" \
        "logtd/ComfyUI-MochiEdit" \
        "facok/ComfyUI-HunyuanVideoMultiLora" \
        "MinusZoneAI/ComfyUI-CogVideoX-MZ" \
        "facok/ComfyUI-TeaCacheHunyuanVideo" \
        "XieJunchen/comfyUI_LLM" \
        "chflame163/ComfyUI_LayerStyle" \
        "cubiq/ComfyUI_FaceAnalysis" \
        "nicofdga/DZ-FaceDetailer" \
        ; do \
        git clone --depth=1 https://github.com/$repo.git /app/custom_nodes/$(basename $repo) || true; \
        if [ -f /app/custom_nodes/$(basename $repo)/requirements.txt ]; then \
            sed -i '/diffusers/d;/peft/d;/accelerate/d' /app/custom_nodes/$(basename $repo)/requirements.txt; \
            pip install --retries 3 --timeout 180 -r /app/custom_nodes/$(basename $repo)/requirements.txt || true; \
        fi; \
        if [ -f /app/custom_nodes/$(basename $repo)/install.py ]; then \
            python /app/custom_nodes/$(basename $repo)/install.py || true; \
        fi; \
    done

# 安装新版本 diffusers、peft、accelerate、huggingface_hub
RUN pip install --force-reinstall --no-cache-dir diffusers==0.31.0 peft==0.10.0 accelerate==0.27.2 huggingface_hub==0.23.2

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