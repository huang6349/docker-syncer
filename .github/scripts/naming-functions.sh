#!/bin/bash
# ========================================
# 智能镜像命名函数库
# Smart Image Naming Functions
# ========================================
#
# 命名策略：
# 1. Registry 前缀处理：移除 docker.io 和标准域名
# 2. Namespace 转下划线：斜杠转下划线，跳过 library，去重
# 3. 名称规范化：小写转换，下划线转连字符
# 4. Tag 处理：支持 @sha256 格式，默认 latest
# 5. 架构后缀：--platform=linux/arm64 时追加 -arm64

# 智能计算目标镜像名称
# 参数: SRC_IMAGE INPUT_PLATFORM
# 输出: BASE_TAG (不包含 registry/namespace 前缀)
calculate_target_tag() {
    local SRC_IMAGE="$1"
    local INPUT_PLATFORM="$2"

    local REGISTRY_PREFIX=""
    local IMAGE_PATH="$SRC_IMAGE"

    # --- 1. Registry 前缀处理 ---
    # 检查是否有 registry 前缀，按优先级排序
    if [[ "$SRC_IMAGE" =~ ^docker\.io/(.+) ]]; then
        # docker.io 前缀：移除
        IMAGE_PATH="${BASH_REMATCH[1]}"
    elif [[ "$SRC_IMAGE" =~ ^([a-zA-Z0-9][a-zA-Z0-9.-]*\.[a-zA-Z]{2,})/([^/].*)$ ]]; then
        # 标准域名格式：registry.xyz.com/path (多级域名)
        IMAGE_PATH="${BASH_REMATCH[2]}"
    elif [[ "$SRC_IMAGE" =~ ^([a-zA-Z0-9][a-zA-Z0-9.-]*:[0-9]+)/([^/].*)$ ]]; then
        # 带端口的域名或 IP：registry.com:5000/path 或 192.168.1.100:5000/path
        IMAGE_PATH="${BASH_REMATCH[2]}"
    else
        # 其他情况（如 my-registry/my-app 或无域名的简单镜像）：保留原样
        :
    fi

    # --- 2. Namespace 处理 & 名称规范化 ---
    local NAMESPACE=""
    local BASE_NAME=""

    if [[ "$IMAGE_PATH" =~ ^([^/]+)/(.+)$ ]]; then
        NAMESPACE="${BASH_REMATCH[1]}"
        local REST="${BASH_REMATCH[2]}"

        # 提取 basename 和 tag
        if [[ "$REST" =~ ^([^:]+):(.+)$ ]]; then
            BASE_NAME="${BASH_REMATCH[1]}"
            local TAG="${BASH_REMATCH[2]}"
        else
            BASE_NAME="$REST"
            local TAG="latest"
        fi

        # 处理 library namespace
        if [[ "$NAMESPACE" == "library" ]]; then
            NAMESPACE=""
        # 去除重复 namespace (namespace 与 basename 相同)
        elif [[ "$NAMESPACE" == "$BASE_NAME" ]]; then
            NAMESPACE=""
        else
            # Namespace 转下划线
            NAMESPACE="${NAMESPACE//\//_}"
        fi
    else
        # 无 namespace
        if [[ "$IMAGE_PATH" =~ ^([^:]+):(.+)$ ]]; then
            BASE_NAME="${BASH_REMATCH[1]}"
            local TAG="${BASH_REMATCH[2]}"
        else
            BASE_NAME="$IMAGE_PATH"
            local TAG="latest"
        fi
    fi

    # --- 3. Tag 处理：支持 @sha256 格式 ---
    # 如果 Tag 包含 @sha256，保留完整格式
    local FINAL_TAG="$TAG"

    # --- 4. 组合名称 ---
    local BASE_TAG=""
    if [ -n "$NAMESPACE" ]; then
        BASE_TAG="${NAMESPACE}_${BASE_NAME}:${FINAL_TAG}"
    else
        BASE_TAG="${BASE_NAME}:${FINAL_TAG}"
    fi

    # --- 5. 名称规范化：小写 + 下划线转连字符 ---
    BASE_TAG=$(echo "$BASE_TAG" | tr '[:upper:]' '[:lower:]')
    BASE_TAG="${BASE_TAG//_/-}"

    # --- 6. 架构后缀处理 ---
    if [ -n "$INPUT_PLATFORM" ]; then
        # 提取架构名，如 linux/arm64 -> arm64
        local ARCH_SUFFIX=$(echo "$INPUT_PLATFORM" | sed 's/.*\///')
        BASE_TAG="${BASE_TAG%-${ARCH_SUFFIX}}"  # 移除已有的架构后缀（避免重复）
        BASE_TAG="${BASE_TAG}-${ARCH_SUFFIX}"
    fi

    echo "$BASE_TAG"
}

# 计算完整的 registry 目标地址
# 参数: BASE_TAG REGISTRY NAMESPACE
# 输出: 完整的目标地址
build_full_target() {
    local BASE_TAG="$1"
    local REGISTRY="$2"
    local NAMESPACE="$3"
    echo "${REGISTRY}/${NAMESPACE}/${BASE_TAG}"
}
