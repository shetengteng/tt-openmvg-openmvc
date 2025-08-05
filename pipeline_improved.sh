#!/bin/bash

# OpenMVG + OpenMVS 三维重建流水线脚本 (改进版)
# 使用方法: pipeline_improved.sh <images_directory> <output_directory> [options]
# 选项: --method [incremental|global] (默认: incremental)

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "命令 $1 未找到，请检查安装"
        exit 1
    fi
}

# 检查文件是否存在
check_file_exists() {
    if [ ! -f "$1" ]; then
        log_error "文件不存在: $1"
        return 1
    fi
    return 0
}

# 检查目录是否存在
check_dir_exists() {
    if [ ! -d "$1" ]; then
        log_error "目录不存在: $1"
        return 1
    fi
    return 0
}

# 计算图像数量
count_images() {
    local dir=$1
    local count=$(find "$dir" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.tiff" -o -iname "*.tif" \) | wc -l)
    echo $count
}

# 执行命令并检查结果
execute_step() {
    local step_name="$1"
    shift
    local cmd="$@"
    
    log_info "开始: $step_name"
    if eval "$cmd"; then
        log_success "完成: $step_name"
        return 0
    else
        log_error "失败: $step_name"
        log_error "命令: $cmd"
        exit 1
    fi
}

# 显示使用帮助
show_help() {
    echo "使用方法: $0 <images_directory> <output_directory> [选项]"
    echo ""
    echo "选项:"
    echo "  --method [incremental|global]  选择SfM方法 (默认: incremental)"
    echo "  --features [SIFT|AKAZE]        选择特征提取器 (默认: SIFT)"
    echo "  --help                         显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 /workspace/images /workspace/output"
    echo "  $0 /workspace/images /workspace/output --method global --features AKAZE"
}

# 解析参数
IMAGES_DIR=""
OUTPUT_DIR=""
SFM_METHOD="incremental"
FEATURE_METHOD="SIFT"

while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            show_help
            exit 0
            ;;
        --method)
            SFM_METHOD="$2"
            shift 2
            ;;
        --features)
            FEATURE_METHOD="$2"
            shift 2
            ;;
        -*)
            log_error "未知选项: $1"
            show_help
            exit 1
            ;;
        *)
            if [ -z "$IMAGES_DIR" ]; then
                IMAGES_DIR="$1"
            elif [ -z "$OUTPUT_DIR" ]; then
                OUTPUT_DIR="$1"
            else
                log_error "太多参数"
                show_help
                exit 1
            fi
            shift
            ;;
    esac
done

# 检查必需参数
if [ -z "$IMAGES_DIR" ] || [ -z "$OUTPUT_DIR" ]; then
    log_error "缺少必需参数"
    show_help
    exit 1
fi

# 验证SfM方法
if [ "$SFM_METHOD" != "incremental" ] && [ "$SFM_METHOD" != "global" ]; then
    log_error "无效的SfM方法: $SFM_METHOD (应为 incremental 或 global)"
    exit 1
fi

# 验证特征方法
if [ "$FEATURE_METHOD" != "SIFT" ] && [ "$FEATURE_METHOD" != "AKAZE" ]; then
    log_error "无效的特征方法: $FEATURE_METHOD (应为 SIFT 或 AKAZE)"
    exit 1
fi

echo "========================================="
echo "OpenMVG + OpenMVS 三维重建流水线 (改进版)"
echo "图像目录: $IMAGES_DIR"
echo "输出目录: $OUTPUT_DIR"
echo "SfM方法: $SFM_METHOD"
echo "特征方法: $FEATURE_METHOD"
echo "========================================="

# 预检查
log_info "执行预检查..."

# 检查输入目录
check_dir_exists "$IMAGES_DIR"

# 检查图像数量
IMAGE_COUNT=$(count_images "$IMAGES_DIR")
log_info "找到 $IMAGE_COUNT 张图像"

if [ $IMAGE_COUNT -lt 3 ]; then
    log_error "图像数量太少 ($IMAGE_COUNT)，至少需要3张图像"
    exit 1
elif [ $IMAGE_COUNT -lt 10 ]; then
    log_warning "图像数量较少 ($IMAGE_COUNT)，建议至少10张图像以获得更好效果"
fi

# 检查必需的命令
log_info "检查必需命令..."
check_command "openMVG_main_SfMInit_ImageListing"
check_command "openMVG_main_ComputeFeatures"
check_command "openMVG_main_ComputeMatches"
check_command "openMVG_main_IncrementalSfM"
check_command "openMVG_main_GlobalSfM"
check_command "openMVG_main_openMVG2openMVS"
check_command "DensifyPointCloud"
check_command "ReconstructMesh"
check_command "RefineMesh"
check_command "TextureMesh"

# 创建输出目录
mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

# 寻找sensor数据库
SENSOR_DB=""
for path in "/usr/local/share/openMVG/sensor_width_camera_database.txt" \
            "/opt/share/openMVG/sensor_width_camera_database.txt" \
            "/usr/share/openMVG/sensor_width_camera_database.txt"; do
    if [ -f "$path" ]; then
        SENSOR_DB="$path"
        break
    fi
done

if [ -z "$SENSOR_DB" ]; then
    log_warning "未找到sensor数据库，将跳过相机数据库参数"
    SENSOR_PARAM=""
else
    log_info "使用sensor数据库: $SENSOR_DB"
    SENSOR_PARAM="-d $SENSOR_DB"
fi

# 步骤 1: 初始化图像数据库
execute_step "初始化图像数据库" \
    "openMVG_main_SfMInit_ImageListing -i '$IMAGES_DIR' -o . $SENSOR_PARAM"

# 检查输出
if ! check_file_exists "sfm_data.json"; then
    log_error "步骤1失败：未生成 sfm_data.json"
    exit 1
fi

# 步骤 2: 计算特征点
execute_step "计算特征点 ($FEATURE_METHOD)" \
    "openMVG_main_ComputeFeatures -i sfm_data.json -o . -m $FEATURE_METHOD"

# 步骤 3: 计算特征匹配
execute_step "计算特征匹配" \
    "openMVG_main_ComputeMatches -i sfm_data.json -o . -g e"

# 步骤 4: SfM重建 (根据选择的方法)
if [ "$SFM_METHOD" = "incremental" ]; then
    execute_step "增量式SfM重建" \
        "openMVG_main_IncrementalSfM -i sfm_data.json -m . -o ."
else
    execute_step "全局SfM重建" \
        "openMVG_main_GlobalSfM -i sfm_data.json -m . -o ."
fi

# 检查SfM结果
if ! check_file_exists "sfm_data.bin"; then
    log_error "SfM重建失败：未生成 sfm_data.bin"
    exit 1
fi

# 步骤 5: 导出为OpenMVS格式
execute_step "导出为OpenMVS格式" \
    "openMVG_main_openMVG2openMVS -i sfm_data.bin -o scene.mvs -d ."

# 检查导出结果
if ! check_file_exists "scene.mvs"; then
    log_error "导出失败：未生成 scene.mvs"
    exit 1
fi

# 步骤 6: 密集重建
execute_step "密集重建" \
    "DensifyPointCloud scene.mvs"

# 步骤 7: 网格重建
if check_file_exists "scene_dense.mvs"; then
    execute_step "网格重建" \
        "ReconstructMesh scene_dense.mvs"
else
    log_warning "跳过网格重建：scene_dense.mvs 不存在"
fi

# 步骤 8: 网格细化
if check_file_exists "scene_dense_mesh.mvs"; then
    execute_step "网格细化" \
        "RefineMesh scene_dense_mesh.mvs"
else
    log_warning "跳过网格细化：scene_dense_mesh.mvs 不存在"
fi

# 步骤 9: 纹理映射
if check_file_exists "scene_dense_mesh_refine.mvs"; then
    execute_step "纹理映射" \
        "TextureMesh scene_dense_mesh_refine.mvs"
else
    log_warning "跳过纹理映射：scene_dense_mesh_refine.mvs 不存在"
fi

echo "========================================="
log_success "重建完成！"
echo "主要输出文件:"

# 检查并列出实际生成的文件
if check_file_exists "sfm_data.bin"; then
    echo "✓ 稀疏点云: sfm_data.bin"
fi
if check_file_exists "scene_dense.ply"; then
    echo "✓ 密集点云: scene_dense.ply"
fi
if check_file_exists "scene_dense_mesh_refine.ply"; then
    echo "✓ 网格模型: scene_dense_mesh_refine.ply"
fi
if check_file_exists "scene_dense_mesh_refine.obj"; then
    echo "✓ 带纹理模型: scene_dense_mesh_refine.obj"
fi

# 显示目录大小
OUTPUT_SIZE=$(du -sh . | cut -f1)
log_info "输出目录大小: $OUTPUT_SIZE"

echo "=========================================" 