#!/bin/bash
# 完整的3D重建流水线 - OpenMVG + OpenMVS
# 使用方法：./run_all.sh <工作目录路径>

set -euo pipefail

# 参数检查
if [ $# -eq 0 ]; then
    echo "错误：必须提供工作目录路径"
    echo "使用方法: $0 <工作目录路径>"
    exit 1
fi

WORKSPACE_PATH="$1"

# 基本检查
if [ ! -d "$WORKSPACE_PATH" ]; then
    echo "错误：工作目录不存在: $WORKSPACE_PATH"
    exit 1
fi

if [ ! -d "$WORKSPACE_PATH/images" ]; then
    echo "错误：图片目录不存在: $WORKSPACE_PATH/images"
    exit 1
fi

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "开始3D重建流水线: $WORKSPACE_PATH"

# 步骤1: 运行OpenMVG
echo "步骤1: OpenMVG处理..."
bash "$SCRIPT_DIR/run_openmvg.sh" "$WORKSPACE_PATH"

# 检查OpenMVG输出
if [ ! -f "$WORKSPACE_PATH/output/mvs/scene.mvs" ]; then
    echo "错误：OpenMVG处理失败"
    exit 1
fi

# 步骤2: 运行OpenMVS  
echo "步骤2: OpenMVS处理..."
bash "$SCRIPT_DIR/run_openmvs.sh" "$WORKSPACE_PATH"

echo "3D重建流水线完成！结果文件位于: $WORKSPACE_PATH/output/"
