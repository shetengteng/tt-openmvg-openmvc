#!/bin/bash
# OpenMVG处理脚本 - 优化版本
# 用途: 自动化OpenMVG 3D重建流程，包含错误处理和进度跟踪

set -euo pipefail  # 严格模式：遇到错误立即退出

# =============================================================================
# 配置参数 - 可根据需要修改
# =============================================================================

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
    echo "💡 工作目录应包含 images/ 子目录，里面放置要重建的图像文件"
    echo "   使用 -h 或 --help 查看详细帮助"
    exit 1
fi

# 基本路径配置
WORKSPACE_PATH="$1"
DOCKER_IMAGE="openmvg:v2.1"
IMAGES_DIR="images"
OUTPUT_DIR="output"

# 相机参数配置 (RICOH THETA S)
FOCAL_LENGTH=1050
CAMERA_MODEL=3
GROUP_CAMERA_MODEL=1
# 传感器数据库路径（可选，如果不存在会被跳过）
SENSOR_DB_PATH="/opt/openMVG_Build/install/bin/sensor_width_camera_database.txt"

# 特征匹配参数
FEATURE_TYPE="SIFT"
MATCH_RATIO=0.7

# SfM参数
TRIANGULATION_METHOD=3
RESECTION_METHOD=3
REFINE_INTRINSIC="ADJUST_FOCAL_LENGTH"

# 初始图像对（如果为空则自动选择）
INITIAL_PAIR_A=""
INITIAL_PAIR_B=""

# 全局SfM参数
ROTATION_AVERAGING=2
TRANSLATION_AVERAGING=3

# =============================================================================
# 工具函数
# =============================================================================

# 彩色日志输出
log_info() {
    echo -e "\033[1;34m[INFO $(date '+%H:%M:%S')]\033[0m $1"
}

log_success() {
    echo -e "\033[1;32m[SUCCESS $(date '+%H:%M:%S')]\033[0m $1"
}

log_error() {
    echo -e "\033[1;31m[ERROR $(date '+%H:%M:%S')]\033[0m $1" >&2
}

log_warn() {
    echo -e "\033[1;33m[WARN $(date '+%H:%M:%S')]\033[0m $1"
}

# 检查必要文件和目录
check_prerequisites() {
    log_info "检查运行前提条件..."

    # 检查工作目录
    if [ ! -d "$WORKSPACE_PATH" ]; then
        log_error "工作目录不存在: $WORKSPACE_PATH"
        exit 1
    fi

    # 检查镜像目录
    if [ ! -d "$WORKSPACE_PATH/$IMAGES_DIR" ]; then
        log_error "图像目录不存在: $WORKSPACE_PATH/$IMAGES_DIR"
        exit 1
    fi

    # 检查图像文件数量
    local image_count=$(find "$WORKSPACE_PATH/$IMAGES_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) | wc -l)
    if [ "$image_count" -lt 2 ]; then
        log_error "图像数量不足 (发现 $image_count 张，至少需要2张)"
        exit 1
    fi

    log_success "前提条件检查通过 (发现 $image_count 张图像)"
}

# 验证步骤输出
verify_output() {
    local step_name="$1"
    local expected_file="$2"
    local file_path="$WORKSPACE_PATH/$expected_file"

    if [ -f "$file_path" ]; then
        local file_size=$(stat -f%z "$file_path" 2>/dev/null || echo "0")
        if [ "$file_size" -gt 0 ]; then
            log_success "$step_name 完成 - 输出文件: $expected_file (${file_size} bytes)"
            return 0
        else
            log_error "$step_name 失败 - 输出文件为空: $expected_file"
            return 1
        fi
    else
        log_error "$step_name 失败 - 缺少输出文件: $expected_file"
        return 1
    fi
}

# 显示处理统计信息
show_statistics() {
    log_info "处理统计信息:"

    # 特征统计
    if [ -f "$WORKSPACE_PATH/output/matches/sfm_data.json" ]; then
        local view_count=$(grep -o '"views":\[' "$WORKSPACE_PATH/output/matches/sfm_data.json" | wc -l)
        log_info "  - 检测到的视图数量: $view_count"
    fi

    # 重建统计
    if [ -f "$WORKSPACE_PATH/output/reconstruction/sfm_data.bin" ]; then
        log_info "  - 增量重建: ✓ 完成"
    fi

    if [ -f "$WORKSPACE_PATH/output/reconstruction/robust.bin" ]; then
        log_info "  - 结构优化: ✓ 完成"
    fi

    if [ -f "$WORKSPACE_PATH/output/mvs/scene.mvs" ]; then
        log_info "  - OpenMVS导出: ✓ 完成"
    fi
}

# =============================================================================
# 主处理流程
# =============================================================================

show_usage() {
    echo "用法: $0 [工作目录路径]"
    echo ""
    echo "参数说明:"
    echo "  工作目录路径    包含images/文件夹的工作目录（可选）"
    echo ""
    echo "示例:"
    echo "  $0 /path/to/my/workspace     # 使用指定路径"
    echo "  $0 /Users/TerrellShe/Documents/personal/tt-projects/ImageDataset_SceauxCastle/"
    echo ""
    echo "注意: 工作目录下必须包含 images/ 子目录，里面放置要重建的图像文件"
}

main() {
    # 检查帮助参数（只检查第一个参数）
    if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
        show_usage
        exit 0
    fi

    # 验证工作目录是否存在（此时已经从命令行参数获取了路径）
    if [ ! -d "$WORKSPACE_PATH" ]; then
        log_error "工作目录不存在: $WORKSPACE_PATH"
        log_error "请确保目录存在"
        exit 1
    fi

    local start_time=$(date +%s)
    log_info "开始OpenMVG处理流程..."
    log_info "工作目录: $WORKSPACE_PATH"
    log_info "Docker镜像: $DOCKER_IMAGE"

    # 运行前检查
    check_prerequisites

    # 执行Docker容器中的处理流程
    log_info "启动Docker容器并执行处理流程..."

    docker run --rm \
        -v "$WORKSPACE_PATH:/workspace" \
        "$DOCKER_IMAGE" \
        bash -c "
        set -euo pipefail
        cd /workspace

        # 创建输出目录
        mkdir -p $OUTPUT_DIR/{matches,reconstruction,mvs}

        echo '[$(date '+%H:%M:%S')] === 0. 清空旧的输出文件 ==='
        echo '步骤0详细信息:'
        echo '  - 清理matches目录: $OUTPUT_DIR/matches/'
        echo '  - 清理reconstruction目录: $OUTPUT_DIR/reconstruction/'
        echo '  - 清理mvs目录: $OUTPUT_DIR/mvs/'

        rm -rf $OUTPUT_DIR/matches/*
        rm -rf $OUTPUT_DIR/reconstruction/*
        rm -rf $OUTPUT_DIR/mvs/*

        echo '步骤0完成: 旧输出文件已清理'

        echo '[$(date '+%H:%M:%S')] === 1. 图像列表和内参估计 ==='
        echo '步骤1详细信息:'
        echo '  - 输入图像目录: $IMAGES_DIR/'
        echo '  - 输出目录: $OUTPUT_DIR/matches/'
        echo '  - 焦距: $FOCAL_LENGTH'
        echo '  - 相机模型: $CAMERA_MODEL'
        echo '  - 相机分组模型: $GROUP_CAMERA_MODEL'

        # 检查传感器数据库是否存在
        if [ -f \"$SENSOR_DB_PATH\" ]; then
            echo '  - 传感器数据库: $SENSOR_DB_PATH'
            echo '执行命令（使用传感器数据库）...'
            openMVG_main_SfMInit_ImageListing \
              -i $IMAGES_DIR/ \
              -o $OUTPUT_DIR/matches/ \
              -d $SENSOR_DB_PATH \
              --focal $FOCAL_LENGTH \
              --camera_model $CAMERA_MODEL \
              --group_camera_model $GROUP_CAMERA_MODEL || exit 1
        else
            echo '  - 传感器数据库: 未找到，跳过'
            echo '执行命令（不使用传感器数据库）...'
            openMVG_main_SfMInit_ImageListing \
              -i $IMAGES_DIR/ \
              -o $OUTPUT_DIR/matches/ \
              --focal $FOCAL_LENGTH \
              --camera_model $CAMERA_MODEL \
              --group_camera_model $GROUP_CAMERA_MODEL || exit 1
        fi

        echo '步骤1结果:'
        ls -la $OUTPUT_DIR/matches/
        if [ -f '$OUTPUT_DIR/matches/sfm_data.json' ]; then
            echo '  - sfm_data.json 文件大小:' $(stat -f%z '$OUTPUT_DIR/matches/sfm_data.json') 'bytes'
            echo '  - 检测到的图像数量:' $(grep -o '\"filename\":' '$OUTPUT_DIR/matches/sfm_data.json' | wc -l)
        fi

        echo '[$(date '+%H:%M:%S')] === 2. 特征提取 ==='
        echo '步骤2详细信息:'
        echo '  - 输入文件: $OUTPUT_DIR/matches/sfm_data.json'
        echo '  - 输出目录: $OUTPUT_DIR/matches/'
        echo '  - 特征类型: $FEATURE_TYPE'
        echo '执行命令...'

        openMVG_main_ComputeFeatures \
          -i $OUTPUT_DIR/matches/sfm_data.json \
          -o $OUTPUT_DIR/matches/ \
          -m $FEATURE_TYPE || exit 1

        echo '步骤2结果:'
        echo '  - 生成的特征文件数量:' $(find $OUTPUT_DIR/matches/ -name '*.feat' | wc -l)
        echo '  - 生成的描述符文件数量:' $(find $OUTPUT_DIR/matches/ -name '*.desc' | wc -l)
        if [ $(find $OUTPUT_DIR/matches/ -name '*.feat' | wc -l) -gt 0 ]; then
            echo '  - 特征文件示例大小:' $(stat -f%z $(find $OUTPUT_DIR/matches/ -name '*.feat' | head -1)) 'bytes'
        fi

        echo '[$(date '+%H:%M:%S')] === 3. 特征匹配 ==='
        echo '步骤3详细信息:'
        echo '  - 输入文件: $OUTPUT_DIR/matches/sfm_data.json'
        echo '  - 输出文件: $OUTPUT_DIR/matches/matches.bin'
        echo '  - 匹配比率阈值: $MATCH_RATIO'
        echo '执行命令...'

        openMVG_main_ComputeMatches \
          -i $OUTPUT_DIR/matches/sfm_data.json \
          -o $OUTPUT_DIR/matches/matches.bin \
          --ratio $MATCH_RATIO || exit 1

        echo '步骤3结果:'
        if [ -f '$OUTPUT_DIR/matches/matches.bin' ]; then
            echo '  - matches.bin 文件大小:' $(stat -f%z '$OUTPUT_DIR/matches/matches.bin') 'bytes'
        fi
        if [ -f '$OUTPUT_DIR/matches/putative_matches' ]; then
            echo '  - 候选匹配文件大小:' $(stat -f%z '$OUTPUT_DIR/matches/putative_matches') 'bytes'
        fi
        echo '  - matches目录内容:'
        ls -la $OUTPUT_DIR/matches/

        echo '[$(date '+%H:%M:%S')] === 4. 增量SfM重建 ==='
        echo '步骤4详细信息:'
        echo '  - SfM引擎: INCREMENTAL'
        echo '  - 输入文件: $OUTPUT_DIR/matches/sfm_data.json'
        echo '  - 匹配目录: $OUTPUT_DIR/matches/'
        echo '  - 匹配文件: matches.bin'
        echo '  - 输出目录: $OUTPUT_DIR/reconstruction/'
        echo '  - 三角化方法: $TRIANGULATION_METHOD'
        echo '  - 后方交会方法: $RESECTION_METHOD'
        echo '  - 内参优化配置: $REFINE_INTRINSIC'

        if [ -n '$INITIAL_PAIR_A' ] && [ -n '$INITIAL_PAIR_B' ]; then
            echo '  - 初始图像对: $INITIAL_PAIR_A, $INITIAL_PAIR_B'
            echo '执行命令（使用指定初始图像对）...'
            openMVG_main_SfM \
              --sfm_engine INCREMENTAL \
              --input_file $OUTPUT_DIR/matches/sfm_data.json \
              --match_dir $OUTPUT_DIR/matches/ \
              --match_file matches.bin \
              --output_dir $OUTPUT_DIR/reconstruction/ \
              --triangulation_method $TRIANGULATION_METHOD \
              --resection_method $RESECTION_METHOD \
              --refine_intrinsic_config $REFINE_INTRINSIC \
              --initial_pair_a $INITIAL_PAIR_A \
              --initial_pair_b $INITIAL_PAIR_B || exit 1
        else
            echo '  - 初始图像对: 自动选择'
            echo '执行命令（自动选择初始图像对）...'
            openMVG_main_SfM \
              --sfm_engine INCREMENTAL \
              --input_file $OUTPUT_DIR/matches/sfm_data.json \
              --match_dir $OUTPUT_DIR/matches/ \
              --match_file matches.bin \
              --output_dir $OUTPUT_DIR/reconstruction/ \
              --triangulation_method $TRIANGULATION_METHOD \
              --resection_method $RESECTION_METHOD \
              --refine_intrinsic_config $REFINE_INTRINSIC || exit 1
        fi

        echo '步骤4结果:'
        if [ -f '$OUTPUT_DIR/reconstruction/sfm_data.bin' ]; then
            echo '  - sfm_data.bin 文件大小:' $(stat -f%z '$OUTPUT_DIR/reconstruction/sfm_data.bin') 'bytes'
        fi
        echo '  - reconstruction目录内容:'
        ls -la $OUTPUT_DIR/reconstruction/

        echo '[$(date '+%H:%M:%S')] === 5. 全局SfM优化 ==='
        if [ -f '$OUTPUT_DIR/reconstruction/sfm_data.bin' ]; then
            echo '步骤5详细信息:'
            echo '  - SfM引擎: GLOBAL'
            echo '  - 输入文件: $OUTPUT_DIR/reconstruction/sfm_data.bin'
            echo '  - 匹配目录: $OUTPUT_DIR/matches/'
            echo '  - 匹配文件: matches.bin'
            echo '  - 输出目录: $OUTPUT_DIR/reconstruction/'
            echo '  - 旋转平均方法: $ROTATION_AVERAGING'
            echo '  - 平移平均方法: $TRANSLATION_AVERAGING'
            echo '执行命令...'

            openMVG_main_SfM \
              --sfm_engine GLOBAL \
              --input_file $OUTPUT_DIR/reconstruction/sfm_data.bin \
              --match_dir $OUTPUT_DIR/matches/ \
              --match_file matches.bin \
              --output_dir $OUTPUT_DIR/reconstruction/ \
              --rotationAveraging $ROTATION_AVERAGING \
              --translationAveraging $TRANSLATION_AVERAGING || echo 'Warning: 全局SfM失败，继续使用增量结果'

            echo '步骤5结果:'
            echo '  - reconstruction目录内容（全局优化后）:'
            ls -la $OUTPUT_DIR/reconstruction/
        else
            echo '步骤5跳过: 未找到增量重建结果文件'
        fi

        echo '[$(date '+%H:%M:%S')] === 6. 结构优化 ==='
        echo '步骤6详细信息:'
        echo '  - 输入文件: $OUTPUT_DIR/reconstruction/sfm_data.bin'
        echo '  - 匹配目录: $OUTPUT_DIR/matches/'
        echo '  - 输出文件: $OUTPUT_DIR/reconstruction/robust.bin'
        echo '执行命令...'

        openMVG_main_ComputeStructureFromKnownPoses \
          -i $OUTPUT_DIR/reconstruction/sfm_data.bin \
          -m $OUTPUT_DIR/matches/ \
          -o $OUTPUT_DIR/reconstruction/robust.bin || exit 1

        echo '步骤6结果:'
        if [ -f '$OUTPUT_DIR/reconstruction/robust.bin' ]; then
            echo '  - robust.bin 文件大小:' $(stat -f%z '$OUTPUT_DIR/reconstruction/robust.bin') 'bytes'
        fi
        echo '  - reconstruction目录内容（结构优化后）:'
        ls -la $OUTPUT_DIR/reconstruction/

        echo '[$(date '+%H:%M:%S')] === 7. 导出为OpenMVS格式 ==='
        echo '步骤7详细信息:'
        echo '  - 输入文件: $OUTPUT_DIR/reconstruction/robust.bin'
        echo '  - 输出文件: $OUTPUT_DIR/mvs/scene.mvs'
        echo '  - 图像输出目录: $OUTPUT_DIR/mvs/images/'
        echo '执行命令...'

        mkdir -p $OUTPUT_DIR/mvs/images/
        openMVG_main_openMVG2openMVS \
          -i $OUTPUT_DIR/reconstruction/robust.bin \
          -o $OUTPUT_DIR/mvs/scene.mvs \
          -d $OUTPUT_DIR/mvs/images/ || exit 1

        echo '步骤7结果:'
        if [ -f '$OUTPUT_DIR/mvs/scene.mvs' ]; then
            echo '  - scene.mvs 文件大小:' $(stat -f%z '$OUTPUT_DIR/mvs/scene.mvs') 'bytes'
        fi
        echo '  - 导出的图像数量:' $(find $OUTPUT_DIR/mvs/images/ -type f | wc -l)
        echo '  - mvs目录内容:'
        ls -la $OUTPUT_DIR/mvs/

        echo '[$(date '+%H:%M:%S')] === 处理完成，生成输出文件列表 ==='
        echo '输出目录结构:'
        find $OUTPUT_DIR -type f -name '*.json' -o -name '*.bin' -o -name '*.mvs' | head -20
        "
    
    # 验证关键输出文件
    log_info "验证处理结果..."
    verify_output "图像列表" "output/matches/sfm_data.json"
    verify_output "特征匹配" "output/matches/matches.bin" 
    verify_output "SfM重建" "output/reconstruction/sfm_data.bin"
    verify_output "结构优化" "output/reconstruction/robust.bin"
    verify_output "OpenMVS导出" "output/mvs/scene.mvs"
    
    # 显示统计信息
    show_statistics
    
    # 计算总用时
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))
    
    log_success "OpenMVG处理流程全部完成!"
    log_info "总用时: ${minutes}分${seconds}秒"
    log_info "输出目录: $WORKSPACE_PATH/$OUTPUT_DIR"
    log_info "下一步可以运行 run_openmvs.sh 进行密集重建"
}

# =============================================================================
# 脚本入口
# =============================================================================

# 捕获中断信号，确保清理
trap 'log_error "处理被中断"; exit 130' INT TERM

# 执行主函数
main "$@"