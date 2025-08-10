#!/bin/bash
# 完整的3D重建流水线 - OpenMVG + OpenMVS
# 使用方法：./run_all.sh <工作目录路径>

set -euo pipefail  # 严格模式：遇到错误立即退出

# 参数检查
if [ $# -eq 0 ]; then
    echo "❌ 错误：必须提供工作目录路径"
    echo
    echo "📖 使用方法："
    echo "  $0 <工作目录路径>"
    echo
    echo "📝 示例："
    echo "  $0 /path/to/your/workspace"
    echo
    echo "💡 工作目录应包含 images/ 子目录，里面放置要重建的图像文件"
    exit 1
fi

# 获取工作目录路径
WORKSPACE_PATH="$1"
IMAGE_DIR="$WORKSPACE_PATH/images"

# 检查工作目录是否存在
if [ ! -d "$WORKSPACE_PATH" ]; then
    echo "❌ 错误：工作目录不存在: $WORKSPACE_PATH"
    exit 1
fi

# 检查图片目录是否存在
if [ ! -d "$IMAGE_DIR" ]; then
    echo "❌ 错误：图片目录不存在: $IMAGE_DIR"
    echo "💡 请在工作目录下创建images子目录并放入图片文件"
    exit 1
fi

# 检查图片目录是否包含图片文件
IMAGE_COUNT=$(find "$IMAGE_DIR" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.tiff" -o -iname "*.bmp" \) | wc -l)
if [ "$IMAGE_COUNT" -eq 0 ]; then
    echo "⚠️  警告：在目录中未找到图片文件: $IMAGE_DIR"
    echo "支持的格式: .jpg, .jpeg, .png, .tiff, .bmp"
    read -p "是否继续处理？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "已取消处理"
        exit 1
    fi
fi

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 设置中文显示
export LANG=C.UTF-8

echo "🚀 =================================================="
echo "🎯 完整3D重建流水线开始"
echo "📂 工作目录: $WORKSPACE_PATH"
echo "📂 图片目录: $IMAGE_DIR"
echo "📊 图片数量: $IMAGE_COUNT 张"
echo "⏰ 开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=================================================="
echo

# 记录开始时间
START_TIME=$(date +%s)

# ========================
# 第1步：OpenMVG 特征提取和匹配
# ========================
echo "🔍 === 第1步：OpenMVG 特征提取和匹配 ==="
echo "⏱️  $(date '+%H:%M:%S') - 开始 OpenMVG 处理..."
echo

MVG_START_TIME=$(date +%s)

if [ -f "$SCRIPT_DIR/run_openmvg_optimized.sh" ]; then
    echo "使用优化版本的 OpenMVG 脚本..."
    bash "$SCRIPT_DIR/run_openmvg_optimized.sh" "$WORKSPACE_PATH"
else
    echo "使用标准版本的 OpenMVG 脚本..."
    bash "$SCRIPT_DIR/run_openmvg.sh" "$WORKSPACE_PATH"
fi

MVG_END_TIME=$(date +%s)
MVG_DURATION=$((MVG_END_TIME - MVG_START_TIME))

echo
echo "✅ OpenMVG 完成！耗时: ${MVG_DURATION}秒"
echo

# 检查OpenMVG输出文件是否存在
MVS_INPUT_FILE="$WORKSPACE_PATH/output/mvs/scene.mvs"
if [ ! -f "$MVS_INPUT_FILE" ]; then
    echo "❌ 错误：OpenMVG 未生成预期的输出文件: $MVS_INPUT_FILE"
    echo "OpenMVG 处理可能失败，请检查上述日志"
    exit 1
fi

echo "🔍 OpenMVG 输出文件验证通过: scene.mvs ($(du -h "$MVS_INPUT_FILE" | cut -f1))"
echo

# ========================
# 第2步：OpenMVS 稠密重建
# ========================
echo "🏗️  === 第2步：OpenMVS 稠密重建 ==="
echo "⏱️  $(date '+%H:%M:%S') - 开始 OpenMVS 处理..."
echo

MVS_START_TIME=$(date +%s)

bash "$SCRIPT_DIR/run_openmvs.sh" "$WORKSPACE_PATH"

MVS_END_TIME=$(date +%s)
MVS_DURATION=$((MVS_END_TIME - MVS_START_TIME))

echo
echo "✅ OpenMVS 完成！耗时: ${MVS_DURATION}秒"
echo

# ========================
# 完成总结
# ========================
END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))

echo "🎉 =================================================="
echo "🏆 完整3D重建流水线已完成！"
echo "=================================================="
echo "📊 处理统计："
echo "  🔍 OpenMVG 耗时: ${MVG_DURATION}秒 ($(date -u -d @${MVG_DURATION} +%H:%M:%S))"
echo "  🏗️  OpenMVS 耗时: ${MVS_DURATION}秒 ($(date -u -d @${MVS_DURATION} +%H:%M:%S))"
echo "  ⏱️  总计耗时: ${TOTAL_DURATION}秒 ($(date -u -d @${TOTAL_DURATION} +%H:%M:%S))"
echo "  ⏰ 完成时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo

# 显示最终结果文件
echo "📁 最终结果文件位于: $WORKSPACE_PATH/output/"
echo
echo "📄 生成的文件："
echo "  🔹 稀疏重建: reconstruction/sfm_data.bin"
echo "  🔹 特征匹配: matches/matches.bin"
echo "  🔹 稠密点云: mvs/dense/scene_dense.ply ($(du -h "$WORKSPACE_PATH/output/mvs/dense/scene_dense.ply" 2>/dev/null | cut -f1 || echo "未知大小"))"
echo "  🔹 原始网格: mvs/mesh/scene_mesh.ply ($(du -h "$WORKSPACE_PATH/output/mvs/mesh/scene_mesh.ply" 2>/dev/null | cut -f1 || echo "未知大小"))"
echo "  🔹 细化网格: mvs/mesh/scene_mesh_refined.ply ($(du -h "$WORKSPACE_PATH/output/mvs/mesh/scene_mesh_refined.ply" 2>/dev/null | cut -f1 || echo "未知大小"))"
echo "  🔹 纹理模型: mvs/texture/scene_textured.ply ($(du -h "$WORKSPACE_PATH/output/mvs/texture/scene_textured.ply" 2>/dev/null | cut -f1 || echo "未知大小"))"
echo "  🔹 纹理图片: mvs/texture/scene_textured0.png ($(du -h "$WORKSPACE_PATH/output/mvs/texture/scene_textured0.png" 2>/dev/null | cut -f1 || echo "未知大小"))"
echo
echo "💡 可以使用以下软件查看结果："
echo "  • CloudCompare (推荐) - 查看点云和网格"
echo "  • MeshLab - 查看和编辑网格"
echo "  • Blender - 导入PLY文件进行进一步编辑"
