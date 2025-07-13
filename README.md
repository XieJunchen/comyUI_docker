# ComfyUI Docker 部署详细文档

## 1. Dockerfile 版本说明

项目提供了三个 Dockerfile 版本：

### 1.1 生产版本 (Dockerfile)
- **特点**：多阶段构建，安全性高，镜像体积小
- **适用**：生产环境部署，网络环境良好
- **优势**：非 root 用户运行，健康检查，完整的依赖管理

### 1.2 优化版本 (Dockerfile.optimized) 
- **特点**：针对国内网络环境优化，使用国内 PyPI 源
- **适用**：网络环境不稳定，但能访问 Docker Hub
- **优势**：使用清华大学 PyPI 镜像源，加速 Python 包下载

### 1.3 国内专用版本 (Dockerfile.china) ⭐ 推荐
- **特点**：完全使用国内镜像源，包括 Docker 基础镜像
- **适用**：国内网络环境，Docker Hub 访问困难
- **优势**：使用 DaoCloud 容器镜像服务，彻底解决网络连接问题

### 1.4 简化版本（快速测试用）

如需快速测试，可使用以下简化 Dockerfile：

```dockerfile
FROM python:3.12-slim

# 写入阿里云Debian源，适配slim镜像无sources.list情况
RUN echo "deb https://mirrors.aliyun.com/debian bookworm main contrib non-free non-free-firmware\ndeb https://mirrors.aliyun.com/debian-security bookworm-security main contrib non-free non-free-firmware\ndeb https://mirrors.aliyun.com/debian bookworm-updates main contrib non-free non-free-firmware\ndeb https://mirrors.aliyun.com/debian bookworm-backports main contrib non-free non-free-firmware" > /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        git \
        ffmpeg \
        libgl1 \
        libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY . /app

RUN pip install --upgrade pip
RUN pip install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu128
RUN pip install --no-cache-dir -r requirements.txt --extra-index-url https://download.pytorch.org/whl/cu128

EXPOSE 8188
CMD ["python", "main.py"]
```

## 2. 镜像打包（构建）

### 2.1 使用生产版本构建
```bash
docker build -t comfyui:latest .
```

### 2.2 使用优化版本构建
```bash
docker build -f Dockerfile.optimized -t comfyui:latest .
```

### 2.3 使用国内专用版本构建（强烈推荐国内用户）
```bash
docker build -f Dockerfile.china -t comfyui:latest .
```

### 2.4 构建问题排查

**网络连接超时问题：**
- **错误示例**：`dial tcp 31.13.76.65:443: i/o timeout`
- **原因**：国内网络访问 Docker Hub 不稳定
- **解决方案**：
  1. 首选：使用 `Dockerfile.china` 版本（使用 DaoCloud 镜像）
  2. 备选：使用 `Dockerfile.optimized` 版本
  3. 最后：配置 Docker 镜像加速器

**语法警告问题：**
- **警告示例**：`FromAsCasing: 'as' and 'FROM' keywords' casing do not match`
- **解决方案**：已在所有优化版本中修复

**Docker 镜像加速器配置（可选）：**
```json
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://mirror.ccs.tencentyun.com",
    "https://registry.cn-hangzhou.aliyuncs.com"
  ]
}
```

## 3. 镜像导出与离线部署（可选）

如需在无外网服务器部署：
```bash
docker save -o comfyui.tar comfyui:latest
# 拷贝 comfyui.tar 到目标服务器
# 目标服务器导入：
docker load -i comfyui.tar
```

有镜像仓库的，可直接推送镜像：
```shell
# 登录 Docker 镜像仓库
docker login myregistry.com
# tag 镜像
docker tag comfyui:latest myregistry.com/comfyui:latest
# 推送镜像
docker push myregistry.com/comfyui:latest
```

## 4. 启动容器（含文件挂载）

假设本地有如下目录：
- /data/comfyui/models      （模型文件）
- /data/comfyui/input       （输入图片等）
- /data/comfyui/output      （输出图片等）

启动命令如下（含GPU支持）：
```bash
docker run --gpus all -d -p 8188:8188 \
  -v /data/comfyui/models:/app/models \
  -v /data/comfyui/input:/app/input \
  -v /data/comfyui/output:/app/output \
  --name comfyui comfyui:latest
```

如需挂载更多目录（如 custom_nodes、配置文件等），可继续添加 -v 参数。

## 5. 访问服务

浏览器访问：http://localhost:8188

## 6. 常用运维命令

- 查看日志：
  ```bash
  docker logs -f comfyui
  ```
- 停止容器：
  ```bash
  docker stop comfyui
  ```
- 删除容器：
  ```bash
  docker rm comfyui
  ```
- 删除镜像：
  ```bash
  docker rmi comfyui:latest
  ```

## 7. 使用 docker-compose 部署（推荐Linux环境）

在项目根目录新建 `docker-compose.yml`，内容如下：

```yaml
version: '3.8'
services:
  comfyui:
    image: comfyui:latest
    container_name: comfyui
    restart: unless-stopped
    ports:
      - "8188:8188"
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    volumes:
      - /data/comfyui/models:/app/models
      - /data/comfyui/input:/app/input
      - /data/comfyui/output:/app/output
      # 如有需要可继续挂载 custom_nodes、配置文件等
```

启动服务：
```bash
docker compose up -d
```

如需关闭服务：
```bash
docker compose down
```

如需重启服务：
```bash
docker compose restart
```

---
如需自定义端口、环境变量或其他挂载，请在 volumes/ports 部分自行调整。
如需 CPU 版本或其他特殊需求，请补充说明。
