# OpenMVG + OpenMVS 3D重建系统

## 📋 项目简介

本项目基于Docker构建了一个完整的3D重建流水线，集成了OpenMVG和OpenMVS两个开源库，可以从多张2D图像生成高质量的3D模型。

### 🔬 技术原理

**OpenMVG (Multiple View Geometry)**
- **用途**: 稀疏重建，从多视角图像计算相机姿态和稀疏3D点云
- **核心算法**: 
  - SIFT特征提取和匹配
  - 增量式SfM (Structure from Motion)
  - Bundle Adjustment优化
  - 相机标定和姿态估计

**OpenMVS (Multiple View Stereo)**
- **用途**: 密集重建，生成高质量网格模型和纹理
- **核心算法**:
  - 密集点云重建
  - 泊松表面重建
  - 网格细化和纹理映射

### 🎯 处理流程

```
原始图像 → 特征提取 → 特征匹配 → 稀疏重建 → 密集重建 → 网格生成 → 纹理映射 → 最终3D模型
   ↓           ↓         ↓         ↓         ↓         ↓         ↓         ↓
[images/]  [OpenMVG]  [OpenMVG]  [OpenMVG]  [OpenMVS] [OpenMVS] [OpenMVS]  [results]
```

## 🛠️ 环境要求

### 系统要求
- **操作系统**: macOS, Linux, Windows (WSL2)
- **Docker**: 版本 20.10+
- **内存**: 建议8GB以上
- **存储**: 根据图像数量，建议10GB以上可用空间

### Docker版本支持
- OpenMVG: v2.1 (基于Ubuntu 22.04)
- OpenMVS: v2.3.0 (基于Ubuntu 22.04)
- 支持平台: linux/amd64

## 🚀 快速开始

### 1. 构建Docker镜像

```bash
# 构建所有镜像 (首次运行需要30-60分钟)
chmod +x build-all.sh
./build-all.sh
```

### 2. 准备数据

```bash
# 创建工作目录
mkdir my_reconstruction
cd my_reconstruction

# 创建图像目录并放入图片
mkdir images
# 将你的图片复制到 images/ 目录下
cp /path/to/your/photos/*.jpg images/
```

### 3. 运行重建

#### 方法一: 一键运行完整流水线
```bash
# 运行完整的3D重建流水线
./run_all.sh /path/to/my_reconstruction
```

#### 方法二: 分步运行
```bash
# 步骤1: 运行OpenMVG稀疏重建
./run_openmvg.sh /path/to/my_reconstruction

# 步骤2: 运行OpenMVS密集重建
./run_openmvs.sh /path/to/my_reconstruction
```

## 📂 输出文件结构

```
my_reconstruction/
├── images/                          # 原始图像
├── output/
│   ├── matches/                     # OpenMVG特征匹配结果
│   │   ├── sfm_data.json           # 场景数据
│   │   ├── matches.bin             # 特征匹配数据
│   │   └── *.feat, *.desc          # 特征文件
│   ├── reconstruction/              # OpenMVG重建结果
│   │   ├── sfm_data.bin            # 稀疏重建数据
│   │   └── robust.bin              # 优化后的重建数据
│   └── mvs/                        # OpenMVS结果
│       ├── scene.mvs               # OpenMVS场景文件
│       ├── dense/                  # 密集点云
│       │   ├── scene_dense.mvs
│       │   └── scene_dense.ply
│       ├── mesh/                   # 网格模型
│       │   ├── scene_mesh.ply      # 原始网格
│       │   └── scene_mesh_refined.ply # 细化网格
│       └── texture/                # 纹理模型
│           ├── scene_textured.ply  # 带纹理的模型
│           └── scene_textured0.png # 纹理图像
```

## ⚙️ 高级配置

### OpenMVG参数调整

编辑 `run_openmvg.sh` 中的配置参数：

```bash
# 相机参数
FOCAL_LENGTH=-1              # -1为自动检测，或设置具体值
CAMERA_MODEL=1               # 1=PINHOLE_CAMERA
GROUP_CAMERA_MODEL=1

# 特征匹配参数
FEATURE_TYPE="SIFT"          # 特征类型：SIFT, AKAZE
MATCH_RATIO=0.6              # 匹配阈值 (0.6-0.8)

# SfM参数
TRIANGULATION_METHOD=2       # 三角化方法
RESECTION_METHOD=1           # 后方交会方法
REFINE_INTRINSIC="ADJUST_FOCAL_LENGTH"  # 内参优化
```

### 传感器数据库使用

```bash
# 使用传感器数据库进行更准确的相机标定
./run_openmvg.sh -s /path/to/sensor_database.txt /path/to/workspace

# 或者使用默认的传感器数据库
./run_openmvg.sh -s /opt/openMVG_Build/install/bin/sensor_width_camera_database.txt /path/to/workspace
```

## 📸 最佳拍摄实践

### 图像要求
- **数量**: 最少10张，推荐20-50张
- **格式**: JPEG, PNG
- **分辨率**: 建议1000x1000像素以上
- **重叠度**: 相邻图像重叠60-80%
- **EXIF信息**: 保留原始EXIF数据(包含焦距信息)

### 拍摄技巧
1. **围绕物体**拍摄，确保各个角度都有覆盖
2. **保持适当距离**，避免过近或过远
3. **稳定拍摄**，避免模糊
4. **光照均匀**，避免强烈阴影和反光
5. **背景简洁**，避免复杂背景干扰

### 避免的情况
- ❌ 反光表面（玻璃、金属）
- ❌ 透明或半透明材质
- ❌ 纯色无纹理表面
- ❌ 快速移动的物体
- ❌ 光照变化剧烈的场景

## 🔧 故障排除

### 常见问题

**1. Docker镜像构建失败**
```bash
# 检查Docker是否运行
docker --version
# 清理Docker缓存
docker system prune -a
# 重新构建
./build-all.sh
```

**2. 特征匹配失败**
- 检查图像质量和重叠度
- 降低 `MATCH_RATIO` 值 (如改为0.5)
- 尝试不同的特征类型 (`AKAZE` 代替 `SIFT`)

**3. 稀疏重建失败**
- 检查图像EXIF信息是否完整
- 手动设置焦距值代替自动检测
- 减少图像数量进行测试

**4. 内存不足**
```bash
# 检查Docker内存限制
docker stats
# 增加Docker内存分配 (Docker Desktop设置)
# 减少并行处理线程数
```

**5. OpenMVS处理缓慢**
- 这是正常现象，密集重建需要大量计算
- 可以在 `run_openmvs.sh` 中调整参数减少精度换取速度

### 调试模式

```bash
# 启用详细日志
docker run -it --rm -v "$(pwd):/workspace" openmvg:v2.1 bash
# 手动执行命令进行调试
```

## 📊 性能参考

### 处理时间估算 (基于M1 Mac Pro)
- **10张图像**: OpenMVG ~5分钟, OpenMVS ~10分钟
- **25张图像**: OpenMVG ~15分钟, OpenMVS ~30分钟  
- **50张图像**: OpenMVG ~45分钟, OpenMVS ~90分钟

### 硬件推荐
- **CPU**: 多核处理器，推荐8核以上
- **内存**: 16GB以上
- **存储**: SSD硬盘，提升IO性能

## 🌟 高级功能

### 批量处理
```bash
# 为多个数据集批量处理
for dataset in dataset1 dataset2 dataset3; do
    ./run_all.sh "/path/to/$dataset"
done
```

### 结果可视化
推荐的3D查看软件：
- **CloudCompare** (免费，支持点云和网格)
- **MeshLab** (免费，专业网格处理)
- **Blender** (免费，功能强大)
- **PLY查看器** (在线查看器)

## 🤝 贡献指南

1. Fork 项目
2. 创建功能分支
3. 提交更改
4. 发起 Pull Request

## 📄 许可证

本项目基于开源许可证，具体请查看各组件的许可证：
- OpenMVG: MPL2 License
- OpenMVS: AGPL License

## 🆘 获得帮助

- **Issues**: 在GitHub上提交问题
- **社区**: OpenMVG和OpenMVS官方社区
- **文档**: 查看官方文档获得更多技术细节

---

**最后更新**: 2025年8月
**版本**: v1.0
**作者**: TT
