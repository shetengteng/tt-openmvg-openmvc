#!/bin/bash

# 构建所有 Docker 镜像的脚本
set -e

echo "🚀 开始构建 OpenMVG, COLMAP, 和 OpenMVS 镜像..."

# 构建 OpenMVG 镜像
echo "📦 构建 OpenMVG v2.1 镜像..."
docker build --platform linux/amd64 -f Dockerfile.openmvg -t openmvg:v2.1 .

# 构建 OpenMVS 镜像
echo "📦 构建 OpenMVS v2.3.0 镜像..."
docker build  --platform linux/amd64 -f Dockerfile.openmvs -t openmvs:v2.3.0 .

# 构建 COLMAP 镜像
echo "📦 构建 COLMAP 镜像..."
docker build --platform linux/amd64  -f Dockerfile.colmap -t colmap:latest .

# 构建完整组合镜像
echo "📦 构建完整组合镜像..."
docker build  --platform linux/amd64 -f Dockerfile.combined -t photogrammetry:complete .

echo "✅ 所有镜像构建完成！"

echo "📋 构建的镜像："
echo "  - openmvg:v2.1"
echo "  - colmap:latest" 
echo "  - openmvs:v2.3.0"
echo "  - photogrammetry:complete"

echo "🔧 使用方法："
echo "  docker run -it --rm -v \$(pwd):/workspace openmvg:v2.1"
echo "  docker run -it --rm -v \$(pwd):/workspace colmap:latest"
echo "  docker run -it --rm -v \$(pwd):/workspace openmvs:v2.3.0"
echo "  docker run -it --rm -v \$(pwd):/workspace photogrammetry:complete" 