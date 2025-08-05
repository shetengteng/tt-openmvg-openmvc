# 🚀 OpenMVG+OpenMVS+COLMAP Docker 快速上手指南

> **更新时间**: 2025年1月
> **适用版本**: Ubuntu 22.04 官方配置版本

## 📋 快速概览

本项目提供了两个Docker配置：
- **Dockerfile** (原版): 基础配置，可能存在兼容性问题
- **Dockerfile.official** (推荐): 基于OpenMVS作者官方配置，稳定可靠

## 🛠️ 系统要求

- **Docker**: 版本20.10+
- **内存**: 推荐8GB+
- **存储空间**: 预留15GB用于镜像构建
- **网络**: 良好的网络连接（需下载大量依赖）

## ⚡ 快速开始

### 1️⃣ 构建镜像
```bash
# 推荐：使用官方配置
git clone <your-repo>
cd tt-openmvg-openmvs
docker build -f Dockerfile.official -t 3d-reconstruction .

# 构建时间：20-40分钟
```

### 2️⃣ 准备照片
```bash
# 创建工作目录
mkdir ~/my-3d-project
cd ~/my-3d-project
mkdir images output

# 将照片复制到images文件夹
# 要求：10-30张照片，JPG/PNG格式，清晰无模糊
```

### 3️⃣ 一键重建
```bash
# 方法1：OpenMVG+OpenMVS流水线（推荐）
docker run --rm \
    -v $(pwd)/images:/workspace/images \
    -v $(pwd)/output:/workspace/output \
    3d-reconstruction \
    pipeline.sh /workspace/images /workspace/output

# 方法2：使用Python自动化脚本
docker run --rm \
    -v $(pwd)/images:/workspace/images \
    -v $(pwd)/output:/workspace/output \
    3d-reconstruction \
    python3 /opt/bin/MvgMvsPipeline.py /workspace/images /workspace/output

# 方法3：COLMAP自动重建
docker run --rm \
    -v $(pwd)/images:/workspace/images \
    -v $(pwd)/output:/workspace/output \
    3d-reconstruction \
    colmap automatic_reconstructor \
    --image_path /workspace/images \
    --workspace_path /workspace/output
```

## 🎯 三种重建方案对比

| 方案 | 适用场景 | 优势 | 缺点 |
|------|----------|------|------|
| **OpenMVG+OpenMVS** | 高质量重建 | 精度高、可控制性强 | 参数复杂 |
| **Python自动化** | 批量处理 | 简单易用、自动化 | 缺少定制化 |
| **COLMAP** | 通用场景 | 稳定性好、容错性强 | 速度较慢 |

## 📁 输出文件说明

### 🎨 最终3D模型
- `scene_dense.ply` - 密集点云（可用CloudCompare查看）
- `scene_dense_mesh_refine.ply` - 优化网格模型
- `scene_dense_mesh_refine.obj` - 带纹理模型（可导入Blender）

### 🔧 中间文件
- `sfm_data.json` - 相机参数和稀疏点云
- `*.feat` - 特征点文件
- `matches.*.bin` - 特征匹配结果

## 📸 拍摄技巧

### ✅ 正确拍摄
```
🎯 物体拍摄：
- 围绕物体360度拍摄
- 每张照片重叠60-80%
- 保持焦距一致
- 15-30张照片

🏠 场景拍摄：
- 从不同高度和角度
- 包含足够的重叠区域
- 避免纯色墙面
- 20-50张照片
```

### ❌ 避免问题
- 模糊照片
- 强烈反光
- 纯色表面
- 透明物体
- 快速移动

## 🔧 高级使用

### 🐛 调试模式
```bash
# 进入容器调试
docker run --rm -it \
    -v $(pwd)/images:/workspace/images \
    -v $(pwd)/output:/workspace/output \
    3d-reconstruction /bin/bash

# 查看可用工具
ls /opt/bin/

# 手动执行步骤
cd /workspace/output
openMVG_main_SfMInit_ImageListing -i /workspace/images -o .
```

### ⚙️ 自定义参数
```bash
# OpenMVG特征提取（使用AKAZE替代SIFT）
docker run --rm \
    -v $(pwd):/workspace \
    3d-reconstruction \
    openMVG_main_ComputeFeatures -i /workspace/sfm_data.json -o /workspace -m AKAZE

# OpenMVS密集重建（调整分辨率）
docker run --rm \
    -v $(pwd):/workspace \
    3d-reconstruction \
    DensifyPointCloud /workspace/scene.mvs --resolution-level 2
```

### 📊 性能优化
```bash
# 限制CPU使用（避免系统卡顿）
docker run --rm --cpus="4" \
    -v $(pwd)/images:/workspace/images \
    -v $(pwd)/output:/workspace/output \
    3d-reconstruction \
    pipeline.sh /workspace/images /workspace/output

# 限制内存使用
docker run --rm -m 6g \
    -v $(pwd)/images:/workspace/images \
    -v $(pwd)/output:/workspace/output \
    3d-reconstruction \
    pipeline.sh /workspace/images /workspace/output
```

## 🚨 故障排除

### 构建失败
```bash
# 检查磁盘空间
df -h

# 检查Docker内存设置
docker system info | grep Memory

# 清理Docker缓存
docker system prune -a
```

### 重建失败
```bash
# 检查照片格式
file images/*

# 验证照片数量
ls images/ | wc -l

# 查看详细错误
docker run --rm -it \
    -v $(pwd):/workspace \
    3d-reconstruction \
    pipeline.sh /workspace/images /workspace/output 2>&1 | tee reconstruction.log
```

### 常见问题

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| 构建超时 | 网络或资源不足 | 增加内存/更换网络 |
| 特征点不足 | 照片质量差 | 重新拍摄/增加照片 |
| 内存不足 | Docker限制 | 增加Docker内存配置 |
| 权限错误 | 文件权限 | `sudo chown -R $USER output/` |

## 🎨 结果查看

### 推荐软件
- **点云查看**: CloudCompare, MeshLab
- **3D模型**: Blender, 3ds Max
- **在线查看**: Three.js viewers

### 快速预览
```bash
# 在线3D查看器
python3 -m http.server 8000
# 然后访问 http://localhost:8000 上传PLY文件
```

## 📚 进一步学习

- [OpenMVG官方文档](https://openmvg.readthedocs.io/)
- [OpenMVS官方文档](https://cdcseacave.github.io/openMVS/)
- [COLMAP官方文档](https://colmap.github.io/)
- [计算机视觉基础](https://github.com/szeliski/Computer-Vision-Algorithms-and-Applications)

---

💡 **提示**: 首次使用建议先用5-10张测试照片熟悉流程，再进行大规模重建。 