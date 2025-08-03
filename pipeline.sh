#!/bin/bash

# OpenMVG + OpenMVS 三维重建流水线脚本
# 使用方法: pipeline.sh <images_directory> <output_directory>

set -e

if [ "$#" -ne 2 ]; then
    echo "使用方法: $0 <images_directory> <output_directory>"
    echo "示例: $0 /workspace/images /workspace/output"
    exit 1
fi

IMAGES_DIR=$1
OUTPUT_DIR=$2

echo "========================================="
echo "OpenMVG + OpenMVS 三维重建流水线"
echo "图像目录: $IMAGES_DIR"
echo "输出目录: $OUTPUT_DIR"
echo "========================================="

# 创建输出目录
mkdir -p $OUTPUT_DIR
cd $OUTPUT_DIR

echo "步骤 1: 初始化图像数据库..."
openMVG_main_SfMInit_ImageListing \
    -i $IMAGES_DIR \
    -o . \
    -d /usr/local/share/openMVG/sensor_width_camera_database.txt

echo "步骤 2: 计算特征点..."
openMVG_main_ComputeFeatures \
    -i sfm_data.json \
    -o . \
    -m SIFT

echo "步骤 3: 计算特征匹配..."
openMVG_main_ComputeMatches \
    -i sfm_data.json \
    -o . \
    -g e

echo "步骤 4: 增量式SfM重建..."
openMVG_main_IncrementalSfM \
    -i sfm_data.json \
    -m . \
    -o .

echo "步骤 5: 全局BA优化..."
openMVG_main_GlobalSfM \
    -i sfm_data.json \
    -m . \
    -o .

echo "步骤 6: 导出为OpenMVS格式..."
openMVG_main_openMVG2openMVS \
    -i sfm_data.bin \
    -o scene.mvs \
    -d .

echo "步骤 7: 密集重建..."
DensifyPointCloud scene.mvs

echo "步骤 8: 网格重建..."
ReconstructMesh scene_dense.mvs

echo "步骤 9: 网格细化..."
RefineMesh scene_dense_mesh.mvs

echo "步骤 10: 纹理映射..."
TextureMesh scene_dense_mesh_refine.mvs

echo "========================================="
echo "重建完成！"
echo "主要输出文件:"
echo "- 稀疏点云: sfm_data.bin"
echo "- 密集点云: scene_dense.mvs, scene_dense.ply"
echo "- 网格模型: scene_dense_mesh_refine.ply"
echo "- 带纹理模型: scene_dense_mesh_refine.obj"
echo "========================================="