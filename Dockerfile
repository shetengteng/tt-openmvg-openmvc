# OpenMVG + OpenMVS Docker Image
FROM ubuntu:20.04

# 设置时区，避免交互式提示
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

# 安装基础依赖
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    wget \
    unzip \
    pkg-config \
    libjpeg-dev \
    libpng-dev \
    libtiff-dev \
    libglu1-mesa-dev \
    libxmu-dev \
    libxi-dev \
    libboost-all-dev \
    libceres-dev \
    libeigen3-dev \
    libopencv-dev \
    libcgal-dev \
    libvcg-dev \
    libglfw3-dev \
    libglew-dev \
    && rm -rf /var/lib/apt/lists/*

# 创建工作目录
WORKDIR /opt

# 安装 OpenMVG
RUN git clone --recursive https://github.com/openMVG/openMVG.git && \
    cd openMVG && \
    mkdir build && \
    cd build && \
    cmake -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_INSTALL_PREFIX=/usr/local \
          -DOpenMVG_BUILD_SHARED=ON \
          -DOpenMVG_BUILD_TESTS=OFF \
          -DOpenMVG_BUILD_DOC=OFF \
          -DOpenMVG_BUILD_EXAMPLES=ON \
          -DOpenMVG_BUILD_OPENGL_EXAMPLES=OFF \
          -DOpenMVG_BUILD_SOFTWARES=ON \
          -DOpenMVG_BUILD_GUI_SOFTWARES=OFF \
          .. && \
    make -j$(nproc) && \
    make install

# 安装 OpenMVS
RUN git clone https://github.com/cdcseacave/openMVS.git && \
    cd openMVS && \
    mkdir build && \
    cd build && \
    cmake -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_INSTALL_PREFIX=/usr/local \
          -DOpenMVS_BUILD_TOOLS=ON \
          -DOpenMVS_BUILD_SHARED=ON \
          .. && \
    make -j$(nproc) && \
    make install

# 更新链接库路径
RUN ldconfig

# 设置环境变量
ENV PATH="/usr/local/bin:${PATH}"
ENV LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH}"

# 创建工作目录用于数据处理
WORKDIR /workspace

# 添加示例脚本
COPY pipeline.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/pipeline.sh

CMD ["/bin/bash"]