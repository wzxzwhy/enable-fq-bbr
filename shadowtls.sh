#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 检查是否为root用户
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}错误: 必须使用root用户运行此脚本!${PLAIN}"
    exit 1
fi

# 检查docker是否安装
check_docker() {
  if ! docker version &> /dev/null; then
    echo "未检测到 docker，正在安装..."
    curl -sSL https://get.docker.com | bash
    echo "docker 安装完成"
  else
    echo "docker 已安装"
  fi
}

# 创建配置文件
create_config() {
    echo -e "${GREEN}正在创建配置文件...${PLAIN}"
    
    # 创建docker-compose.yml
    mkdir -p /etc/shadowsocks-docker
    cat > /etc/shadowsocks-docker/docker-compose.yml << EOF
version: '3.5'
services:
  shadow-tls:
    image: ghcr.io/ihciah/shadow-tls:latest
    restart: always
    network_mode: "host"
    environment:
      - MODE=server
      - LISTEN=0.0.0.0:8443
      - SERVER=127.0.0.1:45678
      - TLS=icloud.com:443
      - PASSWORD=ixejvmdGp0fuIBkg4M2Diw==
      - RUST_LOG=info
    security_opt:
      - seccomp:unconfined
EOF
}

# 启动服务
start_service() {
    echo -e "${GREEN}正在启动服务...${PLAIN}"
    cd /etc/shadowsocks-docker && docker compose up -d
    if [ $? -ne 0 ]; then
        echo -e "${RED}服务启动失败，请检查配置和网络${PLAIN}"
        exit 1
    fi
    echo -e "${GREEN}服务启动成功${PLAIN}"
}

# 显示配置信息
show_config() {
    SHADOW_TLS_PASSWORD=$(grep "PASSWORD=" /etc/shadowsocks-docker/docker-compose.yml | tail -1 | cut -d'=' -f2- | tr -d ' ')

    echo -e "${YELLOW}Shadow-TLS 密码: ${PLAIN}${SHADOW_TLS_PASSWORD}"
    echo -e "${YELLOW}Shadow-TLS 版本: ${PLAIN}v3"
    echo -e "${YELLOW}混淆域名: ${PLAIN}icloud.com:443"
    echo -e "${GREEN}======================================================${PLAIN}"
    echo -e "${GREEN}配置文件路径: /etc/shadowsocks-docker/config.json${PLAIN}"
    echo -e "${GREEN}重启命令: cd /etc/shadowsocks-docker && docker compose restart${PLAIN}"
    echo -e "${GREEN}停止命令: cd /etc/shadowsocks-docker && docker compose down${PLAIN}"
    echo -e "${GREEN}======================================================${PLAIN}"
}

# 主函数
main() {
    echo -e "${GREEN}开始安装Shadow-TLS...${PLAIN}"
    check_docker
    create_config
    start_service
    show_config
}

main
