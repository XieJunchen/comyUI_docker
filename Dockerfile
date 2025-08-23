# ========================
# 构建阶段（builder）
# ========================
FROM python:3.10.11-slim AS builder

# 设置Python相关环境变量，优化输出和pip行为
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_DEFAULT_TIMEOUT=100

# 安装系统依赖（编译工具、git等）
RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc g++ python3-dev libffi-dev libssl-dev build-essential git wget ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 升级pip及常用构建工具
RUN pip install --upgrade pip setuptools wheel --no-cache-dir

# 创建虚拟环境，后续所有包都装到这里
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# 先安装typing-extensions等，避免PyTorch依赖冲突
RUN pip install --no-cache-dir --retries 4 --timeout 180 typing-extensions decord func_timeout gradio

# 安装PyTorch、torchvision、torchaudio（严格版本对应，官方whl源，禁用缓存）
RUN pip install --no-cache-dir --retries 10 --timeout 600 torch==2.1.2 torchvision==0.16.2 torchaudio==2.1.2 -f https://download.pytorch.org/whl/cu118/torch_stable.html

# 拉取ComfyUI主程序代码
RUN git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git /app

# 安装ComfyUI主依赖
RUN pip install --no-cache-dir --retries 3 --timeout 180 -r /app/requirements.txt

# 拉取custom_nodes并安装其依赖（失败自动跳过）
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
            pip install --no-cache-dir --retries 3 --timeout 180 -r /app/custom_nodes/$(basename $repo)/requirements.txt || true; \
        fi; \
        if [ -f /app/custom_nodes/$(basename $repo)/install.py ]; then \
            python /app/custom_nodes/$(basename $repo)/install.py || true; \
        fi; \
    done

# 安装新版本diffusers、peft、accelerate、huggingface_hub，兼容transformers
RUN pip install --no-cache-dir --retries 4 --timeout 180 diffusers==0.32.0 peft==0.10.0 accelerate==0.27.2 huggingface_hub==0.34.0

# 额外补充依赖，解决部分custom_nodes启动自动下载问题
RUN pip install --no-cache-dir --retries 4 --timeout 600 xformers deep-translator googletrans-py stanza==1.1.1 ctranslate2==4.6.0 sacremoses==0.0.53


# ========================
# 生产阶段（production）
# ========================
FROM python:3.10.11-slim AS production

# 设置环境变量
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/opt/venv/bin:$PATH" \
    COMFYUI_PORT=8188 \
    COMFYUI_HOST=0.0.0.0 \
    INSTALL_COMFYUI_MANAGER=false

# 安装运行时依赖
RUN echo "deb https://mirrors.aliyun.com/debian bookworm main contrib non-free non-free-firmware" > /etc/apt/sources.list \
    && echo "deb https://mirrors.aliyun.com/debian-security bookworm-security main contrib non-free non-free-firmware" >> /etc/apt/sources.list \
    && echo "deb https://mirrors.aliyun.com/debian bookworm-updates main contrib non-free non-free-firmware" >> /etc/apt/sources.list \
    && echo "deb https://mirrors.aliyun.com/debian bookworm-backports main contrib non-free non-free-firmware" >> /etc/apt/sources.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg libgl1 libglib2.0-0 libgomp1 libgcc-s1 curl ca-certificates git gcc g++ \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# 复制虚拟环境和主程序代码
COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /app /app

# 创建非root用户，提升安全性
RUN groupadd -r comfyui && useradd -r -g comfyui -d /app -s /bin/bash comfyui \
    && chown -R comfyui:comfyui /opt/venv /app

# 设置工作目录
WORKDIR /app

# 切换到非root用户
USER comfyui

# 暴露端口
EXPOSE $COMFYUI_PORT

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 CMD curl -f http://localhost:$COMFYUI_PORT/ || exit 1

# 启动命令
CMD ["sh", "-c", "python main.py --listen $COMFYUI_HOST --port $COMFYUI_PORT"]
