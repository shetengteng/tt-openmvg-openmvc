#!/bin/bash
# OpenMVG处理脚本 - 优化版本
# 用途: 自动化OpenMVG 3D重建流程，包含错误处理和进度跟踪

set -euo pipefail  # 严格模式：遇到错误立即退出

# =============================================================================
# 配置参数 - 可根据需要修改
# =============================================================================

# 参数解析
WORKSPACE_PATH=""
SENSOR_DB_PATH=""

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--sensor-db)
            SENSOR_DB_PATH="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        -*)
            echo "❌ 未知选项: $1"
            show_usage
            exit 1
            ;;
        *)
            if [ -z "$WORKSPACE_PATH" ]; then
                WORKSPACE_PATH="$1"
            else
                echo "❌ 错误：只能指定一个工作目录"
                exit 1
            fi
            shift
            ;;
    esac
done

# 检查必需参数
if [ -z "$WORKSPACE_PATH" ]; then
    echo "❌ 错误：必须提供工作目录路径"
    echo
    show_usage
    exit 1
fi

# 基本路径配置
DOCKER_IMAGE="openmvg:v2.1"
IMAGES_DIR="images"
OUTPUT_DIR="output"

# 相机参数配置 - 优化版本
# 使用-1启用自动焦距检测，或设置具体数值
FOCAL_LENGTH=-1  # 自动检测，更鲁棒
CAMERA_MODEL=1   # PINHOLE_CAMERA模型，更稳定
GROUP_CAMERA_MODEL=1

# 特征匹配参数 - 更保守的设置
FEATURE_TYPE="SIFT"
MATCH_RATIO=0.6  # 更严格的匹配阈值

# SfM参数 - 增强鲁棒性
TRIANGULATION_METHOD=2  # 使用默认三角化方法
RESECTION_METHOD=1      # 使用DLT+EPnP，更稳定
REFINE_INTRINSIC="ADJUST_FOCAL_LENGTH"  # 优化焦距

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



# 智能焦距估计（基于图像尺寸的经验公式）
estimate_focal_length() {
    local image_dir="$WORKSPACE_PATH/$IMAGES_DIR"
    local sample_image=$(find "$image_dir" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) | head -1)

    if [ -n "$sample_image" ]; then
        # 尝试获取图像尺寸（需要Docker容器中的imagemagick或类似工具）
        local image_width=$(docker run --rm --platform linux/amd64 -v "$WORKSPACE_PATH:/workspace" "$DOCKER_IMAGE" bash -c "
            cd /workspace
            if command -v identify >/dev/null 2>&1; then
                identify -format '%w' \"$sample_image\" 2>/dev/null || echo '0'
            else
                echo '0'
            fi
        ")

        if [ "$image_width" -gt 0 ]; then
            # 基于图像宽度的焦距估计公式：f ≈ 1.2 * image_width
            local estimated_focal=$((image_width * 12 / 10))
            log_info "自动估计焦距: ${estimated_focal} (基于图像宽度: ${image_width}px)" >&2
            echo "$estimated_focal"
        else
            log_warn "无法获取图像尺寸，使用默认焦距估计值" >&2
            echo "800"  # 默认估计值
        fi
    else
        log_warn "未找到样本图像，使用默认焦距估计值" >&2
        echo "800"
    fi
}

# =============================================================================
# 主处理流程
# =============================================================================

show_usage() {
    echo "用法: $0 [选项] <工作目录路径>"
    echo ""
    echo "必需参数:"
    echo "  工作目录路径              包含images/文件夹的工作目录"
    echo ""
    echo "可选参数:"
    echo "  -s, --sensor-db PATH     传感器数据库文件路径"
    echo "  -h, --help               显示帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 /path/to/workspace"
    echo "  $0 -s /path/to/sensor_db.txt /path/to/workspace"
    echo "  $0 --sensor-db /opt/openMVG_Build/install/bin/sensor_width_camera_database.txt /path/to/workspace"
    echo ""
    echo "注意: 工作目录下必须包含 images/ 子目录，里面放置要重建的图像文件"
}

main() {
    # 验证工作目录是否存在
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

    # 智能焦距处理（在Docker外执行）
    ACTUAL_FOCAL_LENGTH="$FOCAL_LENGTH"
    if [ "$FOCAL_LENGTH" = "-1" ]; then
        log_info "正在进行智能焦距估计..."
        ACTUAL_FOCAL_LENGTH=$(estimate_focal_length)
        log_info "智能估计完成，将使用焦距: $ACTUAL_FOCAL_LENGTH"
    fi

    # 执行Docker容器中的处理流程
    log_info "启动Docker容器并执行处理流程..."

    docker run --rm \
        --platform linux/amd64 \
        -v "$WORKSPACE_PATH:/workspace" \
        -e ACTUAL_FOCAL_LENGTH="$ACTUAL_FOCAL_LENGTH" \
        -e SENSOR_DB_PATH="$SENSOR_DB_PATH" \
        "$DOCKER_IMAGE" \
        bash -c "
        set -euo pipefail
        cd /workspace

        # 创建输出目录
        mkdir -p $OUTPUT_DIR/{matches,reconstruction,mvs}

        echo ''
        echo '=========================================='
        echo '[$(date '+%H:%M:%S')] 步骤 0: 清空旧的输出文件'
        echo '=========================================='
        echo '  📁 清理目录:'
        echo '     • matches目录      : $OUTPUT_DIR/matches/'
        echo '     • reconstruction目录 : $OUTPUT_DIR/reconstruction/'
        echo '     • mvs目录          : $OUTPUT_DIR/mvs/'
        echo ''

        rm -rf $OUTPUT_DIR/matches/*
        rm -rf $OUTPUT_DIR/reconstruction/*
        rm -rf $OUTPUT_DIR/mvs/*

        echo '  ✅ 步骤0完成: 旧输出文件已清理'
        echo ''

        echo '=========================================='
        echo '[$(date '+%H:%M:%S')] 步骤 1: 图像列表和内参估计'
        echo '=========================================='
        echo '  📋 配置参数:'
        echo '     • 输入图像目录     : $IMAGES_DIR/'
        echo '     • 输出目录        : $OUTPUT_DIR/matches/'
        echo '     • 焦距           : $ACTUAL_FOCAL_LENGTH'
        echo '     • 相机模型        : $CAMERA_MODEL (PINHOLE)'
        echo '     • 相机分组模型     : $GROUP_CAMERA_MODEL'

        echo ''
        echo '  🔍 传感器数据库检查:'
        # 检查传感器数据库是否提供且存在
        if [ -n \"$SENSOR_DB_PATH\" ] && [ -f \"$SENSOR_DB_PATH\" ]; then
            echo '     • 状态: 使用传感器数据库'
            echo '     • 路径: $SENSOR_DB_PATH'
            echo ''
            echo '  🚀 执行图像列表初始化（使用传感器数据库）...'
            openMVG_main_SfMInit_ImageListing \
                -i $IMAGES_DIR/ \
                -o $OUTPUT_DIR/matches/ \
                -d $SENSOR_DB_PATH \
                --focal $ACTUAL_FOCAL_LENGTH \
                --camera_model $CAMERA_MODEL \
                --group_camera_model $GROUP_CAMERA_MODEL || exit 1
        else
            if [ -n \"$SENSOR_DB_PATH\" ]; then
                echo '     • 状态: 指定路径不存在，跳过传感器数据库'
            else
                echo '     • 状态: 未指定，跳过传感器数据库'
            fi
            echo ''
            echo '  🚀 执行图像列表初始化（不使用传感器数据库）...'
            openMVG_main_SfMInit_ImageListing \
                -i $IMAGES_DIR/ \
                -o $OUTPUT_DIR/matches/ \
                --focal $ACTUAL_FOCAL_LENGTH \
                --camera_model $CAMERA_MODEL \
                --group_camera_model $GROUP_CAMERA_MODEL || exit 1
        fi

        echo ''
        echo '  📊 步骤1结果:'
        ls -la $OUTPUT_DIR/matches/ | sed 's/^/     /'

        echo ''
        echo '=========================================='
        echo '[$(date '+%H:%M:%S')] 步骤 2: 特征提取'
        echo '=========================================='
        echo '  📋 配置参数:'
        echo '     • 输入文件        : $OUTPUT_DIR/matches/sfm_data.json'
        echo '     • 输出目录        : $OUTPUT_DIR/matches/'
        echo '     • 特征类型        : $FEATURE_TYPE'
        echo ''
        echo '  🚀 执行特征提取...'

        openMVG_main_ComputeFeatures \
            -i $OUTPUT_DIR/matches/sfm_data.json \
            -o $OUTPUT_DIR/matches/ \
            -m $FEATURE_TYPE || exit 1

        echo ''
        echo '  📊 步骤2结果:'
        echo '     • 特征文件数量     :' $(find $OUTPUT_DIR/matches/ -name '*.feat' 2>/dev/null | wc -l)
        echo '     • 描述符文件数量   :' $(find $OUTPUT_DIR/matches/ -name '*.desc' 2>/dev/null | wc -l)

        echo ''
        echo '=========================================='
        echo '[$(date '+%H:%M:%S')] 步骤 3: 特征匹配'
        echo '=========================================='
        echo '  📋 配置参数:'
        echo '     • 输入文件        : $OUTPUT_DIR/matches/sfm_data.json'
        echo '     • 输出文件        : $OUTPUT_DIR/matches/matches.bin'
        echo '     • 匹配比率阈值     : $MATCH_RATIO'
        echo '     • 最近邻匹配方法   : AUTO (自动选择)'
        echo ''
        echo '  🚀 执行特征匹配...'

        openMVG_main_ComputeMatches \
            -i $OUTPUT_DIR/matches/sfm_data.json \
            -o $OUTPUT_DIR/matches/matches.bin \
            --ratio $MATCH_RATIO || exit 1

        echo ''
        echo '  📊 步骤3结果:'
        ls -la $OUTPUT_DIR/matches/ | sed 's/^/     /'

        echo ''
        echo '=========================================='
        echo '[$(date '+%H:%M:%S')] 步骤 4: 增量SfM重建'
        echo '=========================================='
        echo '  📋 配置参数:'
        echo '     • SfM引擎         : INCREMENTAL'
        echo '     • 输入文件        : $OUTPUT_DIR/matches/sfm_data.json'
        echo '     • 匹配目录        : $OUTPUT_DIR/matches/'
        echo '     • 匹配文件        : matches.bin'
        echo '     • 输出目录        : $OUTPUT_DIR/reconstruction/'
        echo '     • 三角化方法      : $TRIANGULATION_METHOD'
        echo '     • 后方交会方法     : $RESECTION_METHOD'
        echo '     • 内参优化配置     : $REFINE_INTRINSIC'
        echo ''
        echo '  🔍 初始图像对检查:'
        if [ -n '$INITIAL_PAIR_A' ] && [ -n '$INITIAL_PAIR_B' ]; then
            echo '     • 模式: 使用指定初始图像对'
            echo '     • 图像A: $INITIAL_PAIR_A'
            echo '     • 图像B: $INITIAL_PAIR_B'
            echo ''
            echo '  🚀 执行增量SfM重建（指定初始对）...'
            openMVG_main_SfM \
                --sfm_engine INCREMENTAL \
                --input_file $OUTPUT_DIR/matches/sfm_data.json \
                --match_dir $OUTPUT_DIR/matches/ \
                --match_file matches.bin \
                --output_dir $OUTPUT_DIR/reconstruction/ \
                --triangulation_method $TRIANGULATION_METHOD \
                --resection_method $RESECTION_METHOD \
                --refine_intrinsic_config "$REFINE_INTRINSIC" \
                --initial_pair_a $INITIAL_PAIR_A \
                --initial_pair_b $INITIAL_PAIR_B || exit 1
        else
            echo '     • 模式: 自动选择最佳初始图像对'
            echo ''
            echo '  🚀 执行增量SfM重建（自动选择）...'
            openMVG_main_SfM \
                --sfm_engine INCREMENTAL \
                --input_file $OUTPUT_DIR/matches/sfm_data.json \
                --match_dir $OUTPUT_DIR/matches/ \
                --match_file matches.bin \
                --output_dir $OUTPUT_DIR/reconstruction/ \
                --triangulation_method $TRIANGULATION_METHOD \
                --resection_method $RESECTION_METHOD \
                --refine_intrinsic_config "$REFINE_INTRINSIC" || exit 1
        fi

        echo ''
        echo '  📊 步骤4结果:'
        ls -la $OUTPUT_DIR/reconstruction/ | sed 's/^/     /'

        echo ''
        echo '=========================================='
        echo '[$(date '+%H:%M:%S')] 步骤 5: 全局SfM优化'
        echo '=========================================='
        if [ -f \"$OUTPUT_DIR/reconstruction/sfm_data.bin\" ]; then
            echo '  📋 配置参数:'
            echo '     • SfM引擎         : GLOBAL'
            echo '     • 输入文件        : $OUTPUT_DIR/reconstruction/sfm_data.bin'
            echo '     • 匹配目录        : $OUTPUT_DIR/matches/'
            echo '     • 匹配文件        : matches.bin'
            echo '     • 输出目录        : $OUTPUT_DIR/reconstruction/'
            echo '     • 旋转平均方法     : $ROTATION_AVERAGING'
            echo '     • 平移平均方法     : $TRANSLATION_AVERAGING'
            echo ''
            echo '  🚀 执行全局SfM优化...'

            openMVG_main_SfM \
                --sfm_engine GLOBAL \
                --input_file $OUTPUT_DIR/reconstruction/sfm_data.bin \
                --match_dir $OUTPUT_DIR/matches/ \
                --match_file matches.bin \
                --output_dir $OUTPUT_DIR/reconstruction/ \
                --rotationAveraging $ROTATION_AVERAGING \
                --translationAveraging $TRANSLATION_AVERAGING || echo '  ⚠️  Warning: 全局SfM失败，继续使用增量结果'

            echo ''
            echo '  📊 步骤5结果:'
            ls -la $OUTPUT_DIR/reconstruction/ | sed 's/^/     /'
        else
            echo '  ⏭️  步骤5跳过: 未找到增量重建结果文件'
        fi

        echo ''
        echo '=========================================='
        echo '[$(date '+%H:%M:%S')] 步骤 6: 结构优化'
        echo '=========================================='
        echo '  📋 配置参数:'
        echo '     • 输入文件        : $OUTPUT_DIR/reconstruction/sfm_data.bin'
        echo '     • 匹配目录        : $OUTPUT_DIR/matches/'
        echo '     • 输出文件        : $OUTPUT_DIR/reconstruction/robust.bin'
        echo ''
        echo '  🚀 执行结构优化...'

        openMVG_main_ComputeStructureFromKnownPoses \
            -i $OUTPUT_DIR/reconstruction/sfm_data.bin \
            -m $OUTPUT_DIR/matches/ \
            -o $OUTPUT_DIR/reconstruction/robust.bin || exit 1

        echo ''
        echo '  📊 步骤6结果:'
        ls -la $OUTPUT_DIR/reconstruction/ | sed 's/^/     /'

        echo ''
        echo '=========================================='
        echo '[$(date '+%H:%M:%S')] 步骤 7: 导出为OpenMVS格式'
        echo '=========================================='
        echo '  📋 配置参数:'
        echo '     • 输入文件        : $OUTPUT_DIR/reconstruction/robust.bin'
        echo '     • 输出文件        : $OUTPUT_DIR/mvs/scene.mvs'
        echo '     • 图像输出目录     : $OUTPUT_DIR/mvs/images/'
        echo ''
        echo '  🚀 执行OpenMVS格式导出...'

        mkdir -p $OUTPUT_DIR/mvs/images/
        openMVG_main_openMVG2openMVS \
            -i $OUTPUT_DIR/reconstruction/robust.bin \
            -o $OUTPUT_DIR/mvs/scene.mvs \
            -d $OUTPUT_DIR/mvs/images/ || exit 1

        echo ''
        echo '  📊 步骤7结果:'
        echo '     • 导出图像数量     :' $(find $OUTPUT_DIR/mvs/images/ -type f 2>/dev/null | wc -l)
        echo '  📁 mvs目录内容:'
        ls -la $OUTPUT_DIR/mvs/ | sed 's/^/     /'

        echo ''
        echo '=========================================='
        echo '[$(date '+%H:%M:%S')] 🎉 处理完成！'
        echo '=========================================='
        echo '  📁 输出目录结构:'
        find $OUTPUT_DIR -type f -name '*.json' -o -name '*.bin' -o -name '*.mvs' | head -20 | sed 's/^/     /'
        echo ''
        echo '  ✅ OpenMVG处理流程全部完成！'
        echo '  📂 输出目录: /workspace/$OUTPUT_DIR'
        echo '  🔗 下一步: 可运行 run_openmvs.sh 进行密集重建'
        "

    # 完成处理，简化输出检查
    log_info "处理流程完成"
    log_info "输出目录: $WORKSPACE_PATH/$OUTPUT_DIR"

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

# 捕获中断信号，确保清理
trap 'log_error "处理被中断"; exit 130' INT TERM

# 执行主函数
main "$@"