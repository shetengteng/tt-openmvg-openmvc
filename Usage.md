# Docker三维重建完整使用指南

## 1. 构建Docker镜像

首先，将您的两个Dockerfile分别保存为不同的文件，然后构建镜像：

```bash
# 构建OpenMVG镜像
docker build -f Dockerfile.openmvg -t openmvg:v2.1 .

# 构建OpenMVS镜像  
docker build -f Dockerfile.openmvs -t openmvs:v2.3.0 .
```

## 2. 准备数据

创建一个本地工作目录来存放您的图像和输出结果：

```bash
mkdir -p ~/3d_reconstruction/{images,output}
```

将您要进行三维重建的图像放入 `~/3d_reconstruction/images/` 目录中。

## 3. 使用OpenMVG进行特征提取和匹配

### 3.1 启动OpenMVG容器

```bash
docker run -it --rm \
    -v ~/3d_reconstruction:/workspace \
    openmvg:v2.1 /bin/bash
```

### 3.2 在容器内执行OpenMVG流程

```bash
# 进入工作目录
cd /workspace

# 创建输出目录结构
mkdir -p output/{matches,reconstruction,mvs}

# 1. 图像列表和内参估计
openMVG_main_SfMInit_ImageListing \
  -i images/ \
  -o output/matches/ \
  -d /opt/openMVG_Build/install/bin/sensor_width_camera_database.txt

# 2. 特征提取
openMVG_main_ComputeFeatures \
  -i output/matches/sfm_data.json \
  -o output/matches/ \
  -m SIFT

# 3. 特征匹配 
#openMVG_main_ComputeMatches \ 
#  -i output/matches/sfm_data.json \
#  -o output/matches/ \
#  -g e
# 有报错
  
openMVG_main_ComputeMatches \
  -i output/matches/sfm_data.json \
  -o output/matches/matches.bin

# 4. 运动恢复结构 (SfM)
#openMVG_main_IncrementalSfM \
#  -i output/matches/sfm_data.json \
#  -m output/matches/ \
#  -o output/reconstruction/
  
openMVG_main_SfM \
  --sfm_engine INCREMENTAL \
  --input_file output/matches/sfm_data.json \
  --match_dir output/matches/ \
  --match_file matches.bin \
  --output_dir output/reconstruction/
  
# 全局 SfM（自动估算）
openMVG_main_SfM \
  --sfm_engine GLOBAL \
  --input_file output/matches/sfm_data.json \
  --output_dir output/reconstruction/

# 5. 结构优化
openMVG_main_ComputeStructureFromKnownPoses \
  -i output/reconstruction/sfm_data.bin \
  -m output/matches/ \
  -o output/reconstruction/robust.bin

# 6. 导出为OpenMVS格式
openMVG_main_openMVG2openMVS \
  -i output/reconstruction/robust.bin \
  -o output/mvs/scene.mvs \
  -d output/mvs/images/
```

完成后退出容器：`exit`

## 4. 使用OpenMVS进行密集重建

### 4.1 启动OpenMVS容器

```bash
docker run -it --rm \
    -v ~/3d_reconstruction:/workspace \
    openmvs:v2.3.0 /bin/bash
```

### 4.2 在容器内执行OpenMVS流程

```bash
cd /workspace/output/mvs

# 1. 密集化点云
DensifyPointCloud scene.mvs

# 2. 重建网格
ReconstructMesh scene_dense.mvs

# 3. 细化网格
RefineMesh scene_dense_mesh.mvs

# 4. 纹理映射
TextureMesh scene_dense_mesh_refine.mvs
```

## 5. 一键式脚本运行

您也可以创建脚本来自动化整个流程：

### 5.1 创建OpenMVG处理脚本

```bash
# 创建 run_openmvg.sh
cat > run_openmvg.sh << 'EOF'
#!/bin/bash
docker run --rm \
    -v $(pwd):/workspace \
    openmvg:v2.1 \
    bash -c "
    cd /workspace
    mkdir -p output/{matches,reconstruction,mvs}
    
    echo '=== 1. 图像列表和内参估计 ==='
    openMVG_main_SfMInit_ImageListing \
      -i images/ \
      -o output/matches/ \
      -d /opt/openMVG_Build/install/bin/sensor_width_camera_database.txt
    
    echo '=== 2. 特征提取 ==='
    openMVG_main_ComputeFeatures \
      -i output/matches/sfm_data.json \
      -o output/matches/ \
      -m SIFT
    
    echo '=== 3. 特征匹配 ==='
    openMVG_main_ComputeMatches \
      -i output/matches/sfm_data.json \
      -o output/matches/ \
      -g e
    
    echo '=== 4. 运动恢复结构 ==='
    openMVG_main_IncrementalSfM \
      -i output/matches/sfm_data.json \
      -m output/matches/ \
      -o output/reconstruction/
    
    echo '=== 5. 结构优化 ==='
    openMVG_main_ComputeStructureFromKnownPoses \
      -i output/reconstruction/sfm_data.bin \
      -m output/matches/ \
      -o output/reconstruction/robust.bin
    
    echo '=== 6. 导出为OpenMVS格式 ==='
    openMVG_main_openMVG2openMVS \
      -i output/reconstruction/robust.bin \
      -o output/mvs/scene.mvs \
      -d output/mvs/images/
    
    echo '=== OpenMVG 处理完成 ==='
    "
EOF

chmod +x run_openmvg.sh
```

### 5.2 创建OpenMVS处理脚本

```bash
# 创建 run_openmvs.sh
cat > run_openmvs.sh << 'EOF'
#!/bin/bash
docker run --rm \
    -v $(pwd):/workspace \
    openmvs:v2.3.0 \
    bash -c "
    cd /workspace/output/mvs
    
    echo '=== 1. 密集化点云 ==='
    DensifyPointCloud scene.mvs
    
    echo '=== 2. 重建网格 ==='
    ReconstructMesh scene_dense.mvs
    
    echo '=== 3. 细化网格 ==='
    RefineMesh scene_dense_mesh.mvs
    
    echo '=== 4. 纹理映射 ==='
    TextureMesh scene_dense_mesh_refine.mvs
    
    echo '=== OpenMVS 处理完成 ==='
    echo '最终结果文件：'
    ls -la *.ply *.obj
    "
EOF

chmod +x run_openmvs.sh
```

### 5.3 运行完整流程

```bash
# 在包含images文件夹的目录中执行
./run_openmvg.sh
./run_openmvs.sh
```

## 6. 输出文件说明

处理完成后，您将在 `output/mvs/` 目录中得到以下主要文件：

- `scene_dense.ply` - 密集点云
- `scene_dense_mesh.ply` - 重建的三维网格
- `scene_dense_mesh_refine.ply` - 细化后的网格
- `scene_dense_mesh_refine_texture.obj` - 带纹理的最终模型
- `scene_dense_mesh_refine_texture.mtl` - 材质文件
- `scene_dense_mesh_refine_texture_*.jpg` - 纹理贴图

## 7. 常见问题处理

### 镜像构建失败
如果构建过程中网络连接有问题，可以：
```bash
# 使用国内镜像源
docker build --build-arg HTTP_PROXY=http://代理地址:端口 -t openmvg:v2.1 .
```

### 内存不足
如果处理大量图像时内存不足：
```bash
# 限制并行线程数（将 -j2 改为 -j1）
# 或者增加Docker的内存限制
```

### 权限问题
如果输出文件权限有问题：
```bash
# 在容器中设置用户ID
docker run --rm -u $(id -u):$(id -g) -v $(pwd):/workspace openmvg:v2.1
```

## 8. 性能优化建议

1. **图像预处理**：确保输入图像质量良好，分辨率适中（建议1-4MP）
2. **重叠度**：相邻图像间应有60-80%的重叠
3. **拍摄角度**：多角度拍摄，避免纯平移
4. **光照条件**：尽量保持一致的光照条件
5. **硬件资源**：给予Docker足够的CPU和内存资源

这样您就可以完整使用这两个Docker镜像进行端到端的三维重建了！