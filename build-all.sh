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