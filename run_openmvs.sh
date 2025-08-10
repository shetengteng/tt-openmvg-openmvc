#!/bin/bash
# OpenMVS处理脚本 - 支持外部传入路径

set -euo pipefail  # 严格模式：遇到错误立即退出

# 参数检查 - 必须提供工作目录路径
if [ $# -eq 0 ]; then
    echo "❌ 错误：必须提供工作目录路径"
    echo
    echo "📖 使用方法："
    echo "  $0 <工作目录路径>"
    echo
    echo "📝 示例："
    echo "  $0 /path/to/your/workspace"
    echo
    echo "💡 工作目录应包含 output/mvs/scene.mvs 文件（由 OpenMVG 生成）"
    exit 1
fi

# 基本路径配置
WORKSPACE_PATH="$1"
DOCKER_IMAGE="openmvs:v2.3.0"
OUTPUT_DIR="output/mvs"

# OpenMVS 工具路径常量
OPENMVS_BIN_PATH="/opt/bin/OpenMVS"

# 设置中文显示
export LANG=C.UTF-8

# 验证工作目录是否存在
if [ ! -d "$WORKSPACE_PATH" ]; then
    echo "❌ 错误：工作目录不存在: $WORKSPACE_PATH"
    echo "请确保目录存在"
    exit 1
fi

echo '=== OpenMVS 处理开始 ==='
echo "📂 工作目录: $WORKSPACE_PATH"

# 定义输入路径
INPUT_MVS_FILE="$WORKSPACE_PATH/$OUTPUT_DIR/scene.mvs"

# 确保输入文件存在
if [ ! -f "$INPUT_MVS_FILE" ]; then
    echo "错误: 输入文件 $INPUT_MVS_FILE 不存在"
    echo "请先运行run_openmvg.sh生成OpenMVS格式文件"
    exit 1
fi

# 创建输出目录（如果不存在）
mkdir -p "$WORKSPACE_PATH/$OUTPUT_DIR/dense" "$WORKSPACE_PATH/$OUTPUT_DIR/mesh" "$WORKSPACE_PATH/$OUTPUT_DIR/texture"


# 运行OpenMVS容器

docker run --rm --platform linux/amd64 \
    -v "$WORKSPACE_PATH:/workspace" \
    $DOCKER_IMAGE \
    bash -c "
    cd /workspace
    
    echo '=== 1. 稠密点云重建 ==='
    echo '命令: DensifyPointCloud'
    echo '  输入: $OUTPUT_DIR/scene.mvs'
    echo '  输出: $OUTPUT_DIR/dense/scene_dense.mvs'
    $OPENMVS_BIN_PATH/DensifyPointCloud \
        -i \"$OUTPUT_DIR/scene.mvs\" \
        -o \"$OUTPUT_DIR/dense/scene_dense.mvs\"
    
    echo
    echo '=== 2. 网格重建 ==='
    echo '命令: ReconstructMesh'
    echo '  输入: $OUTPUT_DIR/dense/scene_dense.mvs'
    echo '  输出: $OUTPUT_DIR/mesh/scene_mesh.ply'
    $OPENMVS_BIN_PATH/ReconstructMesh \
        -i \"$OUTPUT_DIR/dense/scene_dense.mvs\" \
        -o \"$OUTPUT_DIR/mesh/scene_mesh.ply\"
    
    echo
    echo '=== 3. 网格细化 ==='
    echo '命令: RefineMesh'
    echo '  输入MVS: $OUTPUT_DIR/dense/scene_dense.mvs'
    echo '  输入网格: $OUTPUT_DIR/mesh/scene_mesh.ply'
    echo '  输出: $OUTPUT_DIR/mesh/scene_mesh_refined.ply'
    $OPENMVS_BIN_PATH/RefineMesh \
        -i \"$OUTPUT_DIR/dense/scene_dense.mvs\" \
        -m \"$OUTPUT_DIR/mesh/scene_mesh.ply\" \
        -o \"$OUTPUT_DIR/mesh/scene_mesh_refined.ply\"
    
    echo
    echo '=== 4. 纹理映射 ==='
    echo '命令: TextureMesh'
    echo '  输入MVS: $OUTPUT_DIR/dense/scene_dense.mvs'
    echo '  输入网格: $OUTPUT_DIR/mesh/scene_mesh_refined.ply'
    echo '  输出: $OUTPUT_DIR/texture/scene_textured.ply'
    $OPENMVS_BIN_PATH/TextureMesh \
        -i \"$OUTPUT_DIR/dense/scene_dense.mvs\" \
        -m \"$OUTPUT_DIR/mesh/scene_mesh_refined.ply\" \
        -o \"$OUTPUT_DIR/texture/scene_textured.ply\"
    
    echo
    echo '=== OpenMVS 处理完成 ==='
    echo
    echo '📁 输出文件结构:'
    
    echo '📂 '$OUTPUT_DIR'/'
    ls -lah \"$OUTPUT_DIR/\" | grep -E '^(total|d|-)' | head -10
    
    echo
    echo '📂 '$OUTPUT_DIR'/dense/ (稠密点云)'
    ls -lah \"$OUTPUT_DIR/dense/\" | grep -E '^(total|-)'
    
    echo
    echo '📂 '$OUTPUT_DIR'/mesh/ (网格模型)'
    ls -lah \"$OUTPUT_DIR/mesh/\" | grep -E '^(total|-)'
    
    echo
    echo '📂 '$OUTPUT_DIR'/texture/ (纹理模型)'
    ls -lah \"$OUTPUT_DIR/texture/\" | grep -E '^(total|-)'
    
    echo
    echo '✅ 所有文件生成完毕！'
    "

echo
echo '🎉 === OpenMVS 处理脚本已完成 ==='
echo
echo "📋 最终结果文件位于: $WORKSPACE_PATH/$OUTPUT_DIR"
echo
echo "📄 生成的文件："
echo "  🔹 稠密点云: dense/scene_dense.mvs + scene_dense.ply"
echo "  🔹 原始网格: mesh/scene_mesh.ply"  
echo "  🔹 细化网格: mesh/scene_mesh_refined.ply"
echo "  🔹 纹理模型: texture/scene_textured.ply"
echo "  🔹 纹理图片: texture/scene_textured0.png"
echo
echo "💡 可以使用 CloudCompare、MeshLab 或其他3D软件查看这些文件"