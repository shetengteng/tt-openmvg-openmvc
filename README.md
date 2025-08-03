# tt-openmvg-openmvc
docker file for openmvg and open mvc

# OpenMVG + OpenMVS Docker 镜像详细解释

## 什么是 OpenMVG 和 OpenMVS？

- **OpenMVG** (Open Multiple View Geometry): 用于从多张照片中提取特征点、计算相机位置，生成稀疏的 3D 点云
- **OpenMVS** (Open Multi-View Stereo): 基于 OpenMVG 的结果，生成密集的 3D 点云和 3D 网格模型

简单说：**拍一堆照片 → OpenMVG 分析照片 → OpenMVS 生成 3D 模型**

## Dockerfile 详细解释

### 第一部分：基础环境设置
```dockerfile
FROM ubuntu:20.04
```
**作用**: 告诉 Docker 以 Ubuntu 20.04 作为基础系统（就像给电脑装了 Ubuntu 系统）

```dockerfile
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai
```
**作用**: 设置环境变量，避免安装软件时弹出询问窗口，设置时区为上海

### 第二部分：安装必要软件
```dockerfile
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    wget \
    unzip \
    pkg-config \
    libjpeg-dev \
    libpng-dev \
    ...
```
**作用**: 安装编译 OpenMVG 和 OpenMVS 需要的所有依赖库，相当于：
- `build-essential`: 编译工具（像 Visual Studio）
- `cmake`: 构建工具
- `git`: 版本控制工具
- `libjpeg-dev`, `libpng-dev`: 图像处理库
- `libopencv-dev`: OpenCV 计算机视觉库
- 等等...

### 第三部分：编译安装 OpenMVG
```dockerfile
RUN git clone --recursive https://github.com/openMVG/openMVG.git && \
    cd openMVG && \
    mkdir build && \
    cd build && \
    cmake -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_INSTALL_PREFIX=/usr/local \
          ...
          .. && \
    make -j$(nproc) && \
    make install
```
**作用**: 
1. 从 GitHub 下载 OpenMVG 源代码
2. 创建 build 目录（编译专用文件夹）
3. 用 cmake 配置编译选项
4. 用 make 编译（-j$(nproc) 表示用所有 CPU 核心并行编译）
5. 安装到系统中

### 第四部分：编译安装 OpenMVS
```dockerfile
RUN git clone https://github.com/cdcseacave/openMVS.git && \
    cd openMVS && \
    mkdir build && \
    cd build && \
    cmake -DCMAKE_BUILD_TYPE=Release \
          ...
    make -j$(nproc) && \
    make install
```
**作用**: 和 OpenMVG 类似，下载、编译、安装 OpenMVS

### 第五部分：环境配置
```dockerfile
RUN ldconfig
ENV PATH="/usr/local/bin:${PATH}"
ENV LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH}"
```
**作用**: 
- `ldconfig`: 更新系统动态库缓存
- 设置环境变量，让系统能找到新安装的程序

## pipeline.sh 脚本详细解释

这是一个自动化脚本，执行完整的 3D 重建流程：

### 输入检查
```bash
if [ "$#" -ne 2 ]; then
    echo "使用方法: $0 <images_directory> <output_directory>"
    exit 1
fi
```
**作用**: 检查用户是否提供了两个参数（图像目录和输出目录）

### 步骤1：初始化图像数据库
```bash
openMVG_main_SfMInit_ImageListing \
    -i $IMAGES_DIR \
    -o . \
    -d /usr/local/share/openMVG/sensor_width_camera_database.txt
```
**作用**: 扫描图像文件夹，读取每张照片的信息（分辨率、相机型号等），创建一个图像数据库

### 步骤2：计算特征点
```bash
openMVG_main_ComputeFeatures \
    -i sfm_data.json \
    -o . \
    -m SIFT
```
**作用**: 在每张照片中找到特征点（像照片中的角点、边缘等独特位置），使用 SIFT 算法

### 步骤3：计算特征匹配
```bash
openMVG_main_ComputeMatches \
    -i sfm_data.json \
    -o . \
    -g e
```
**作用**: 找出不同照片之间的相同特征点，建立照片间的对应关系

### 步骤4-5：3D重建
```bash
openMVG_main_IncrementalSfM ...
openMVG_main_GlobalSfM ...
```
**作用**: 根据特征点匹配，计算出每张照片的拍摄位置和角度，生成稀疏的 3D 点云

### 步骤6：格式转换
```bash
openMVG_main_openMVG2openMVS \
    -i sfm_data.bin \
    -o scene.mvs
```
**作用**: 将 OpenMVG 的结果转换为 OpenMVS 能读取的格式

### 步骤7-10：密集重建和网格化
```bash
DensifyPointCloud scene.mvs      # 生成密集点云
ReconstructMesh scene_dense.mvs  # 生成网格
RefineMesh scene_dense_mesh.mvs  # 优化网格
TextureMesh scene_dense_mesh_refine.mvs  # 添加纹理
```
**作用**: 
- 生成更密集的 3D 点云
- 将点云连接成网格（像游戏中的 3D 模型）
- 优化网格质量
- 给网格添加真实的照片纹理

## 如何使用这个镜像？

### 第一步：准备文件
1. 创建一个文件夹，比如 `mvg-mvs-docker`
2. 在里面创建两个文件：
   - `Dockerfile`（复制第一个代码框的内容）
   - `pipeline.sh`（复制第二个代码框的内容）

### 第二步：构建镜像
```bash
cd mvg-mvs-docker
docker build -t my-3d-reconstruction .
```
**解释**: 
- `docker build`: 告诉 Docker 构建镜像
- `-t my-3d-reconstruction`: 给镜像起名字
- `.`: 在当前目录寻找 Dockerfile

### 第三步：准备照片
```bash
mkdir ~/my-3d-project
mkdir ~/my-3d-project/images
mkdir ~/my-3d-project/output
```
然后把你要重建 3D 模型的照片放到 `images` 文件夹中。

### 第四步：运行重建
```bash
docker run --rm \
    -v ~/my-3d-project/images:/workspace/images \
    -v ~/my-3d-project/output:/workspace/output \
    my-3d-reconstruction \
    pipeline.sh /workspace/images /workspace/output
```
**解释**:
- `docker run`: 运行容器
- `--rm`: 运行完后自动删除容器
- `-v ~/my-3d-project/images:/workspace/images`: 把你电脑上的 images 文件夹"挂载"到容器里的 /workspace/images
- `-v ~/my-3d-project/output:/workspace/output`: 把输出文件夹也挂载进去
- `my-3d-reconstruction`: 使用刚才构建的镜像
- `pipeline.sh ...`: 运行重建脚本

## 输出结果说明

运行完成后，在 `output` 文件夹中会有：

### 中间文件
- `sfm_data.json`: 图像信息数据库
- `*.feat`: 特征点文件
- `*.bin`: 匹配结果文件

### 最终结果
- `scene_dense.ply`: 密集点云文件（可以用 MeshLab 打开）
- `scene_dense_mesh_refine.ply`: 网格模型
- `scene_dense_mesh_refine.obj`: 带纹理的最终 3D 模型（可以导入 Blender）

## 照片要求

为了获得好的重建效果：
1. **拍摄要求**:
   - 至少 10-20 张照片
   - 相邻照片要有 60-80% 的重叠
   - 围绕物体从不同角度拍摄
   - 保持焦距一致，避免变焦

2. **照片质量**:
   - 清晰，不模糊
   - 光照均匀
   - 避免强烈阴影和反光

## 简单示例流程

```bash
# 1. 准备
mkdir my-reconstruction
cd my-reconstruction

# 2. 创建 Dockerfile 和 pipeline.sh（复制前面的代码）

# 3. 构建镜像
docker build -t my-3d .

# 4. 准备照片
mkdir images output
# 把照片放到 images 文件夹

# 5. 运行重建
docker run --rm \
    -v $(pwd)/images:/workspace/images \
    -v $(pwd)/output:/workspace/output \
    my-3d \
    pipeline.sh /workspace/images /workspace/output

# 6. 查看结果
ls output/  # 查看生成的文件
```
