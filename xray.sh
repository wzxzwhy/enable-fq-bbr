#!/bin/bash

# 颜色定义
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"

# 确保脚本以root权限运行
[[ $EUID -ne 0 ]] && echo -e "${RED}错误：${PLAIN} 必须使用root用户运行此脚本！\n" && exit 1

# 系统配置路径
CONFIG_DIR="/usr/local/etc/xray"
CONFIG_FILE="$CONFIG_DIR/config.json"
SYSTEMD_FILE="/etc/systemd/system/xray.service"
XRAY_BIN="/usr/local/bin/xray"
LOG_DIR="/var/log/xray"

# 检测操作系统
check_os() {
    if [[ -f /etc/redhat-release ]]; then
        release="centos"
    elif cat /etc/issue | grep -Eqi "debian"; then
        release="debian"
    elif cat /etc/issue | grep -Eqi "ubuntu"; then
        release="ubuntu"
    elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
        release="centos"
    elif cat /proc/version | grep -Eqi "debian"; then
        release="debian"
    elif cat /proc/version | grep -Eqi "ubuntu"; then
        release="ubuntu"
    elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
        release="centos"
    else
        echo -e "${RED}未检测到系统版本，请联系脚本作者！${PLAIN}\n" && exit 1
    fi

    if [[ $release = "centos" ]]; then
        os_version=$(grep -oE "[0-9.]+" /etc/redhat-release | cut -d "." -f1)
        if [[ ${os_version} -lt 7 ]]; then
            echo -e "${RED}请使用 CentOS 7 或更高版本的系统！${PLAIN}\n" && exit 1
        fi
    fi
}

# 安装依赖
install_dependencies() {
    echo -e "${GREEN}正在安装依赖...${PLAIN}"
    if [[ $release = "centos" ]]; then
        yum update -y
        yum install -y wget curl tar socat jq
    else
        apt update -y
        apt install -y wget curl tar socat jq
    fi
}

# 安装或更新xray
install_update_xray() {
    echo -e "${GREEN}开始安装/更新 Xray...${PLAIN}"
    
    # 下载最新版本xray
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    
    # 创建配置目录（如果不存在）
    mkdir -p ${CONFIG_DIR}
    
    # 创建日志目录（如果不存在）
    mkdir -p ${LOG_DIR}
    
    # 如果配置文件不存在，创建一个基本配置
    cat >${CONFIG_FILE} <<-EOF
{
    "log": {
        "loglevel": "warning",
        "access": "${LOG_DIR}/access.log",
        "error": "${LOG_DIR}/error.log"
    },
    "inbounds": [],
    "outbounds": []
}
EOF
    
    # 设置权限
    chmod 644 ${CONFIG_FILE}
    chmod +x ${XRAY_BIN}
    
    # 启动服务
    systemctl enable xray
    systemctl restart xray
    
    echo -e "${GREEN}Xray 已安装/更新成功！${PLAIN}"
}

# 卸载xray
uninstall_xray() {
    echo -e "${YELLOW}正在卸载 Xray...${PLAIN}"
    systemctl stop xray
    systemctl disable xray
    
    # 使用官方卸载脚本
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove
    
    # 删除剩余文件
    rm -rf ${CONFIG_DIR}
    rm -rf ${LOG_DIR}
    
    echo -e "${GREEN}Xray 已成功卸载！${PLAIN}"
}

# 检查xray状态
check_xray_status() {
    echo -e "${BLUE}检查 Xray 状态...${PLAIN}"
    if systemctl is-active --quiet xray; then
        echo -e "${GREEN}Xray 服务状态: 运行中${PLAIN}"
        
        # 显示当前配置信息
        echo -e "${BLUE}当前配置概览:${PLAIN}"
        
        if [[ -f ${CONFIG_FILE} ]]; then
            # 显示入站连接数
            inbound_count=$(jq '.inbounds | length' ${CONFIG_FILE})
            echo -e "${GREEN}入站连接数: ${inbound_count}${PLAIN}"
            
            # 显示每个入站连接的协议和端口
            for ((i=0; i<${inbound_count}; i++)); do
                protocol=$(jq -r ".inbounds[$i].protocol" ${CONFIG_FILE})
                port=$(jq -r ".inbounds[$i].port" ${CONFIG_FILE})
                echo -e "${GREEN}[${i}] 协议: ${protocol}, 端口: ${port}${PLAIN}"
            done
        else
            echo -e "${RED}配置文件不存在！${PLAIN}"
        fi
        
        # 显示系统信息
        echo -e "\n${BLUE}系统信息:${PLAIN}"
        echo -e "$(cat /etc/os-release | grep "PRETTY_NAME" | cut -d "=" -f2 | tr -d '"')"
        echo -e "内核版本: $(uname -r)"
        
        # 显示网络信息
        echo -e "\n${BLUE}网络信息:${PLAIN}"
        ip=$(curl -s https://api.ipify.org)
        echo -e "公网IP: ${ip}"
        
        # 显示Xray版本
        echo -e "\n${BLUE}Xray 版本:${PLAIN}"
        ${XRAY_BIN} -version
    else
        echo -e "${RED}Xray 服务状态: 未运行${PLAIN}"
    fi
}

# 添加 Reality 节点
# 添加 Reality 节点
add_reality() {
    echo -e "${GREEN}添加 REALITY 节点...${PLAIN}"
    
    # 生成UUID
    uuid=$(xray uuid)
    echo -e "${GREEN}已生成UUID: ${uuid}${PLAIN}"
    
    # 生成 REALITY 密钥对
    key_pair=$(xray x25519)
    private_key=$(echo "$key_pair" | grep "Private" | awk '{print $3}')
    public_key=$(echo "$key_pair" | grep "Public" | awk '{print $3}')
    
    # 获取端口 (对外端口)
    read -p "请输入外部端口号 [默认: 443]: " port
    port=${port:-443}
    
    # 内部端口
    internal_port=4431
    
    # 获取服务器名称
    read -p "请输入服务器名称(SNI) [例如: speed.cloudflare.com]: " server_name
    server_name=${server_name:-speed.cloudflare.com}
    
    # 获取短ID
    short_ids_json=$(jq -n --arg id1 "" --arg id2 "$(openssl rand -hex 8)" '[$id1, $id2]')
    
    # 更新配置文件
    if [[ -f ${CONFIG_FILE} ]]; then
        # 备份配置文件
        cp ${CONFIG_FILE} ${CONFIG_FILE}.bak
        
        # 创建 dokodemo-door 入站配置
        dokodemo_config=$(cat <<EOF
{
    "tag": "dokodemo-in",
    "port": ${port},
    "protocol": "dokodemo-door",
    "settings": {
        "address": "127.0.0.1",
        "port": ${internal_port},
        "network": "tcp"
    },
    "sniffing": {
        "enabled": true,
        "destOverride": [
            "tls"
        ],
        "routeOnly": true
    }
}
EOF
)

        # 创建 vless 入站配置
        vless_config=$(cat <<EOF
{
    "listen": "127.0.0.1",
    "port": ${internal_port},
    "protocol": "vless",
    "settings": {
        "clients": [
            {
                "id": "${uuid}",
                "flow": "xtls-rprx-vision"
            }
        ],
        "decryption": "none"
    },
    "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
            "dest": "${server_name}:443",
            "serverNames": [
                "${server_name}"
            ],
            "privateKey": "${private_key}",
            "shortIds": ${short_ids_json},
            "publicKey": "${public_key}"
        }
    },
    "sniffing": {
        "enabled": true,
        "destOverride": [
            "http",
            "tls",
            "quic"
        ],
        "routeOnly": true
    }
}
EOF
)

        # 添加必要的出站配置
        outbounds_config=$(cat <<EOF
[
    {
        "protocol": "freedom",
        "tag": "direct"
    },
    {
        "protocol": "blackhole",
        "tag": "block"
    }
]
EOF
)

        # 添加路由规则
        routing_config=$(cat <<EOF
{
    "rules": [
        {
            "inboundTag": [
                "dokodemo-in"
            ],
            "domain": [
                "${server_name}"
            ],
            "outboundTag": "direct"
        },
        {
            "inboundTag": [
                "dokodemo-in"
            ],
            "outboundTag": "block"
        }
    ]
}
EOF
)
        
        # 添加新的入站配置和出站配置
        jq --argjson dokodemo "$dokodemo_config" --argjson vless "$vless_config" --argjson outbounds "$outbounds_config" --argjson routing "$routing_config" \
        '.inbounds = [.inbounds[] | select(.tag != "dokodemo-in")] + [$dokodemo, $vless] | .outbounds = $outbounds | .routing = $routing' \
        ${CONFIG_FILE} > ${CONFIG_FILE}.tmp
        mv ${CONFIG_FILE}.tmp ${CONFIG_FILE}
        
        # 重启xray服务
        systemctl restart xray
        
        # 显示客户端配置信息
        echo -e "\n${GREEN}安全的 REALITY 节点已添加成功!${PLAIN}"
        echo -e "${YELLOW}=== 客户端配置信息 ===${PLAIN}"
        echo -e "${GREEN}协议: VLESS${PLAIN}"
        echo -e "${GREEN}地址: $(curl -s https://api.ipify.org)${PLAIN}"
        echo -e "${GREEN}端口: ${port}${PLAIN}"
        echo -e "${GREEN}UUID: ${uuid}${PLAIN}"
        echo -e "${GREEN}流控: xtls-rprx-vision${PLAIN}"
        echo -e "${GREEN}传输协议: tcp${PLAIN}"
        echo -e "${GREEN}安全层: reality${PLAIN}"
        echo -e "${GREEN}SNI: ${server_name}${PLAIN}"
        echo -e "${GREEN}PublicKey: ${public_key}${PLAIN}"
        echo -e "${GREEN}ShortID: $(echo $short_ids_json | jq -r '.[1]')${PLAIN}"
        echo -e "${GREEN}请注意：这是使用dokodemo-door代理的安全Reality配置${PLAIN}"
        
        # 生成分享链接
        share_link="vless://${uuid}@$(curl -s https://api.ipify.org):${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${server_name}&fp=chrome&pbk=${public_key}&sid=$(echo $short_ids_json | jq -r '.[1]')#REALITY-${port}"
        echo -e "${GREEN}分享链接: ${share_link}${PLAIN}"
    else
        echo -e "${RED}配置文件不存在，请先安装xray！${PLAIN}"
    fi
}

# 添加 Shadowsocks 节点(单用户)
add_shadowsocks() {
    echo -e "${GREEN}添加 Shadowsocks 节点...${PLAIN}"
    
    # 获取端口
    read -p "请输入端口号 [默认: 8388]: " port
    port=${port:-8388}
    
    # 生成随机密码
    default_password=$(openssl rand -base64 12)
    read -p "请输入用户密码 [默认随机: ${default_password}]: " password
    password=${password:-$default_password}
    
    # 获取加密方法
    echo "请选择加密方法:"
    echo "1. aes-128-gcm"
    echo "2. aes-256-gcm (推荐)"
    echo "3. chacha20-poly1305"
    read -p "请选择 [1-3, 默认: 2]: " method_choice
    
    case $method_choice in
        1) method="aes-128-gcm" ;;
        3) method="chacha20-poly1305" ;;
        *) method="aes-256-gcm" ;;
    esac
    
    # 更新配置文件
    if [[ -f ${CONFIG_FILE} ]]; then
        # 创建 Shadowsocks 配置
        ss_config=$(cat <<EOF
{
  "protocol": "shadowsocks",
  "port": ${port},
  "settings": {
    "method": "${method}",
    "password": "${password}",
    "network": "tcp,udp"
  }
}
EOF
)
        
        # 备份配置文件
        cp ${CONFIG_FILE} ${CONFIG_FILE}.bak
        
        # 添加新的入站配置
        jq --argjson new_inbound "$ss_config" '.inbounds += [$new_inbound]' ${CONFIG_FILE} > ${CONFIG_FILE}.tmp
        
        # 确保有必要的出站配置
        outbounds_config=$(cat <<EOF
[
    {
        "protocol": "freedom",
        "tag": "direct"
    },
    {
        "protocol": "blackhole",
        "tag": "block"
    }
]
EOF
)
        
        # 如果没有出站配置，添加默认出站配置
        jq --argjson outbounds "$outbounds_config" 'if (.outbounds | length) == 0 then .outbounds = $outbounds else . end' ${CONFIG_FILE}.tmp > ${CONFIG_FILE}.tmp2
        mv ${CONFIG_FILE}.tmp2 ${CONFIG_FILE}
        
        # 重启xray服务
        systemctl restart xray
        
        # 显示客户端配置信息
        echo -e "\n${GREEN}Shadowsocks 节点已添加成功!${PLAIN}"
        echo -e "${YELLOW}=== 客户端配置信息 ===${PLAIN}"
        echo -e "${GREEN}服务器地址: $(curl -s https://api.ipify.org)${PLAIN}"
        echo -e "${GREEN}端口: ${port}${PLAIN}"
        echo -e "${GREEN}密码: ${password}${PLAIN}"
        echo -e "${GREEN}加密方法: ${method}${PLAIN}"
        
        # 生成SS URI
        ss_uri=$(echo -n "${method}:${password}@$(curl -s https://api.ipify.org):${port}" | base64 -w 0)
        echo -e "${GREEN}SS链接: ss://${ss_uri}#SS-${port}-${method}${PLAIN}"
    else
        echo -e "${RED}配置文件不存在，请先安装xray！${PLAIN}"
    fi
}


# 导出现有配置
# 导出现有配置
export_config() {
    echo -e "${GREEN}导出现有节点配置...${PLAIN}"
    
    if [[ -f ${CONFIG_FILE} ]]; then
        # 获取入站配置数量
        inbound_count=$(jq '.inbounds | length' ${CONFIG_FILE})
        
        if [[ ${inbound_count} -eq 0 ]]; then
            echo -e "${YELLOW}当前没有配置任何节点！${PLAIN}"
            return
        fi
        
        echo -e "${YELLOW}当前配置的节点列表:${PLAIN}"
        
        # 显示节点列表
        declare -a node_list
        declare -a node_type
        
        for ((i=0; i<${inbound_count}; i++)); do
            protocol=$(jq -r ".inbounds[$i].protocol" ${CONFIG_FILE})
            port=$(jq -r ".inbounds[$i].port" ${CONFIG_FILE})
            
            if [[ "$protocol" == "dokodemo-door" ]]; then
                tag=$(jq -r ".inbounds[$i].tag // \"\"" ${CONFIG_FILE})
                if [[ "$tag" == "dokodemo-in" ]]; then
                    # REALITY节点的外部入口
                    internal_port=$(jq -r ".inbounds[$i].settings.port" ${CONFIG_FILE})
                    node_list+=($i)
                    node_type+=("reality")
                    echo -e "${GREEN}[$i] REALITY节点 (外部端口: ${port})${PLAIN}"
                else
                    node_list+=($i)
                    node_type+=("other")
                    echo -e "${GREEN}[$i] ${protocol}节点 (端口: ${port})${PLAIN}"
                fi
            elif [[ "$protocol" == "shadowsocks" ]]; then
                # Shadowsocks节点
                node_list+=($i)
                node_type+=("ss")
                echo -e "${GREEN}[$i] Shadowsocks节点 (端口: ${port})${PLAIN}"
            elif [[ "$protocol" == "vless" ]]; then
                listen=$(jq -r ".inbounds[$i].listen // \"0.0.0.0\"" ${CONFIG_FILE})
                if [[ "$listen" == "127.0.0.1" ]]; then
                    # 这可能是REALITY的内部配置，跳过
                    continue
                else
                    node_list+=($i)
                    node_type+=("vless")
                    echo -e "${GREEN}[$i] VLESS节点 (端口: ${port})${PLAIN}"
                fi
            else
                node_list+=($i)
                node_type+=("other")
                echo -e "${GREEN}[$i] ${protocol}节点 (端口: ${port})${PLAIN}"
            fi
        done
        
        if [[ ${#node_list[@]} -eq 0 ]]; then
            echo -e "${YELLOW}没有可导出的节点配置！${PLAIN}"
            return
        fi
        
        read -p "请选择要导出的节点 [0-$((${#node_list[@]}-1))]: " node_index
        
        # 验证输入
        if [[ ! "$node_index" =~ ^[0-9]+$ ]] || [[ $node_index -ge ${#node_list[@]} ]]; then
            echo -e "${RED}输入无效！请输入有效的节点编号。${PLAIN}"
            return
        fi
        
        selected_index=${node_list[$node_index]}
        selected_type=${node_type[$node_index]}
        
        echo -e "\n${YELLOW}===== 节点详细配置 =====${PLAIN}"
        
        # 根据节点类型获取详细配置
        if [[ "$selected_type" == "reality" ]]; then
            # REALITY节点
            port=$(jq -r ".inbounds[$selected_index].port" ${CONFIG_FILE})
            internal_port=$(jq -r ".inbounds[$selected_index].settings.port" ${CONFIG_FILE})
            
            # 查找对应的vless入站
            vless_index=-1
            for ((i=0; i<${inbound_count}; i++)); do
                protocol=$(jq -r ".inbounds[$i].protocol" ${CONFIG_FILE})
                inner_port=$(jq -r ".inbounds[$i].port" ${CONFIG_FILE})
                listen=$(jq -r ".inbounds[$i].listen // \"0.0.0.0\"" ${CONFIG_FILE})
                
                if [[ "$protocol" == "vless" && "$inner_port" == "$internal_port" && "$listen" == "127.0.0.1" ]]; then
                    vless_index=$i
                    break
                fi
            done
            
            if [[ $vless_index -ne -1 ]]; then
                uuid=$(jq -r ".inbounds[$vless_index].settings.clients[0].id" ${CONFIG_FILE})
                server_name=$(jq -r ".inbounds[$vless_index].streamSettings.realitySettings.serverNames[0]" ${CONFIG_FILE})
                public_key=$(jq -r ".inbounds[$vless_index].streamSettings.realitySettings.publicKey" ${CONFIG_FILE})
                short_id=$(jq -r ".inbounds[$vless_index].streamSettings.realitySettings.shortIds[1] // \"\"" ${CONFIG_FILE})
                
                echo -e "${GREEN}协议: ${PLAIN}VLESS+REALITY"
                echo -e "${GREEN}地址: ${PLAIN}$(curl -s https://api.ipify.org)"
                echo -e "${GREEN}端口: ${PLAIN}${port}"
                echo -e "${GREEN}UUID: ${PLAIN}${uuid}"
                echo -e "${GREEN}流控: ${PLAIN}xtls-rprx-vision"
                echo -e "${GREEN}传输协议: ${PLAIN}tcp"
                echo -e "${GREEN}安全层: ${PLAIN}reality"
                echo -e "${GREEN}SNI: ${PLAIN}${server_name}"
                echo -e "${GREEN}PublicKey: ${PLAIN}${public_key}"
                echo -e "${GREEN}ShortID: ${PLAIN}${short_id}"
                
                # 生成分享链接
                share_link="vless://${uuid}@$(curl -s https://api.ipify.org):${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${server_name}&fp=chrome&pbk=${public_key}&sid=${short_id}#REALITY-${port}"
                echo -e "\n${GREEN}分享链接: ${PLAIN}${share_link}"
            else
                echo -e "${RED}未找到对应的REALITY VLESS配置！${PLAIN}"
            fi
        elif [[ "$selected_type" == "ss" ]]; then
            # Shadowsocks节点
            port=$(jq -r ".inbounds[$selected_index].port" ${CONFIG_FILE})
            
            # 判断是单用户还是多用户
            if jq -e ".inbounds[$selected_index].settings.password" ${CONFIG_FILE} > /dev/null; then
                # 单用户配置
                method=$(jq -r ".inbounds[$selected_index].settings.method" ${CONFIG_FILE})
                password=$(jq -r ".inbounds[$selected_index].settings.password" ${CONFIG_FILE})
                
                echo -e "${GREEN}协议: ${PLAIN}Shadowsocks"
                echo -e "${GREEN}地址: ${PLAIN}$(curl -s https://api.ipify.org)"
                echo -e "${GREEN}端口: ${PLAIN}${port}"
                echo -e "${GREEN}密码: ${PLAIN}${password}"
                echo -e "${GREEN}加密方法: ${PLAIN}${method}"
                
                # 生成SS URI
                ss_uri=$(echo -n "${method}:${password}@$(curl -s https://api.ipify.org):${port}" | base64 -w 0)
                echo -e "\n${GREEN}SS链接: ${PLAIN}ss://${ss_uri}#SS-${port}-${method}"
            else
                # 多用户配置（保留兼容性）
                echo -e "${YELLOW}这是一个多用户Shadowsocks节点，已不再支持。${PLAIN}"
                echo -e "${YELLOW}原始配置如下:${PLAIN}"
                jq ".inbounds[$selected_index]" ${CONFIG_FILE}
            fi
        else
            # 其他节点类型，直接显示完整配置
            echo -e "${YELLOW}节点原始配置:${PLAIN}"
            jq ".inbounds[$selected_index]" ${CONFIG_FILE}
        fi
    else
        echo -e "${RED}配置文件不存在，请先安装xray！${PLAIN}"
    fi
}
# 删除节点
# 删除节点
delete_node() {
    echo -e "${GREEN}删除节点...${PLAIN}"
    
    if [[ -f ${CONFIG_FILE} ]]; then
        # 获取入站配置数量
        inbound_count=$(jq '.inbounds | length' ${CONFIG_FILE})
        
        if [[ ${inbound_count} -eq 0 ]]; then
            echo -e "${YELLOW}当前没有配置任何节点！${PLAIN}"
            return
        fi
        
        # 创建节点列表，对配对的REALITY节点进行特殊处理
        declare -a node_list
        declare -a is_reality_pair
        declare -a reality_primary_index
        declare -a node_description
        
        # 首先检测REALITY节点对
        for ((i=0; i<${inbound_count}; i++)); do
            protocol=$(jq -r ".inbounds[$i].protocol" ${CONFIG_FILE})
            port=$(jq -r ".inbounds[$i].port" ${CONFIG_FILE})
            tag=$(jq -r ".inbounds[$i].tag // \"未命名\"" ${CONFIG_FILE})
            
            # 检查是否是dokodemo-door且是REALITY配置的一部分
            if [[ "$protocol" == "dokodemo-door" && "$tag" == "dokodemo-in" ]]; then
                # 查找关联的vless入站
                internal_port=$(jq -r ".inbounds[$i].settings.port" ${CONFIG_FILE})
                for ((j=0; j<${inbound_count}; j++)); do
                    if [[ $i -ne $j ]]; then
                        inner_protocol=$(jq -r ".inbounds[$j].protocol" ${CONFIG_FILE})
                        inner_port=$(jq -r ".inbounds[$j].port" ${CONFIG_FILE})
                        inner_listen=$(jq -r ".inbounds[$j].listen // \"0.0.0.0\"" ${CONFIG_FILE})
                        
                        # 检查是否为关联的vless REALITY入站
                        if [[ "$inner_protocol" == "vless" && "$inner_port" == "$internal_port" && "$inner_listen" == "127.0.0.1" ]]; then
                            security=$(jq -r ".inbounds[$j].streamSettings.security // \"none\"" ${CONFIG_FILE})
                            if [[ "$security" == "reality" ]]; then
                                # 找到REALITY配对
                                node_list+=($i)
                                is_reality_pair+=("true")
                                reality_primary_index+=($i)
                                node_description+=("REALITY节点 [dokodemo-door端口:${port} + vless端口:${internal_port}]")
                                break
                            fi
                        fi
                    fi
                done
            elif [[ "$protocol" != "vless" || $(jq -r ".inbounds[$i].listen // \"0.0.0.0\"" ${CONFIG_FILE}) != "127.0.0.1" ]]; then
                # 不是REALITY节点的内部vless入站，添加到常规列表
                security=$(jq -r ".inbounds[$i].streamSettings.security // \"none\"" ${CONFIG_FILE})
                node_list+=($i)
                is_reality_pair+=("false")
                reality_primary_index+=(-1)
                node_description+=("${protocol}节点 [端口:${port}]")
            fi
        done
        
        echo -e "${YELLOW}当前配置的节点列表:${PLAIN}"
        
        # 显示可删除的节点
        for ((i=0; i<${#node_list[@]}; i++)); do
            echo -e "${GREEN}[$i] ${node_description[$i]}${PLAIN}"
        done
        
        read -p "请输入要删除的节点编号 [0-$((${#node_list[@]}-1))]: " delete_index
        
        # 验证输入
        if [[ ! "$delete_index" =~ ^[0-9]+$ ]] || [ "$delete_index" -ge "${#node_list[@]}" ]; then
            echo -e "${RED}输入无效！请输入有效的节点编号。${PLAIN}"
            return
        fi
        
        # 备份配置
        cp ${CONFIG_FILE} ${CONFIG_FILE}.bak
        
        # 获取对应的实际节点索引
        actual_index=${node_list[$delete_index]}
        
        # 检查是否是REALITY节点对
        if [[ "${is_reality_pair[$delete_index]}" == "true" ]]; then
            echo -e "${YELLOW}正在删除REALITY节点配对...${PLAIN}"
            
            # 找到dokodemo-door和对应的vless入站
            dokodemo_index=$actual_index
            internal_port=$(jq -r ".inbounds[$dokodemo_index].settings.port" ${CONFIG_FILE})
            vless_index=-1
            
            # 查找对应的vless入站
            for ((i=0; i<${inbound_count}; i++)); do
                protocol=$(jq -r ".inbounds[$i].protocol" ${CONFIG_FILE})
                port=$(jq -r ".inbounds[$i].port" ${CONFIG_FILE})
                listen=$(jq -r ".inbounds[$i].listen // \"0.0.0.0\"" ${CONFIG_FILE})
                
                if [[ "$protocol" == "vless" && "$port" == "$internal_port" && "$listen" == "127.0.0.1" ]]; then
                    security=$(jq -r ".inbounds[$i].streamSettings.security // \"none\"" ${CONFIG_FILE})
                    if [[ "$security" == "reality" ]]; then
                        vless_index=$i
                        break
                    fi
                fi
            done
            
            if [[ $vless_index -ne -1 ]]; then
                # 删除dokodemo-door和vless入站
                # 获取删除前的配置内容
                temp_config=$(cat ${CONFIG_FILE})
                
                # 删除对应的路由规则
                server_name=$(jq -r ".inbounds[$vless_index].streamSettings.realitySettings.serverNames[0]" <<< "$temp_config")
                
                temp_config=$(jq "del(.routing.rules[] | select(.domain != null and .domain[0] == \"${server_name}\"))" <<< "$temp_config")
                temp_config=$(jq "del(.routing.rules[] | select(.inboundTag != null and .inboundTag[0] == \"dokodemo-in\"))" <<< "$temp_config")
                
                # 如果要删除的vless_index小于dokodemo_index，先删除vless_index
                if [[ $vless_index -lt $dokodemo_index ]]; then
                    temp_config=$(jq "del(.inbounds[$vless_index])" <<< "$temp_config")
                    # dokodemo_index索引需要减1
                    dokodemo_index=$((dokodemo_index-1))
                    temp_config=$(jq "del(.inbounds[$dokodemo_index])" <<< "$temp_config")
                else
                    temp_config=$(jq "del(.inbounds[$dokodemo_index])" <<< "$temp_config")
                    # vless_index索引需要减1
                    vless_index=$((vless_index-1))
                    temp_config=$(jq "del(.inbounds[$vless_index])" <<< "$temp_config")
                fi
                
                echo "$temp_config" > ${CONFIG_FILE}
                
                echo -e "${GREEN}已删除REALITY节点配对 (dokodemo-door和vless入站)以及相关路由规则！${PLAIN}"
            else
                echo -e "${RED}未找到对应的REALITY vless入站配置，只删除dokodemo-door入站！${PLAIN}"
                jq "del(.inbounds[$dokodemo_index])" ${CONFIG_FILE} > ${CONFIG_FILE}.tmp
                mv ${CONFIG_FILE}.tmp ${CONFIG_FILE}
                
                # 删除对应的路由规则
                jq "del(.routing.rules[] | select(.inboundTag != null and .inboundTag[0] == \"dokodemo-in\"))" ${CONFIG_FILE} > ${CONFIG_FILE}.tmp
                mv ${CONFIG_FILE}.tmp ${CONFIG_FILE}
            fi
        else {
            # 普通节点直接删除
            echo -e "${YELLOW}正在删除${node_description[$delete_index]}...${PLAIN}"
            jq "del(.inbounds[${actual_index}])" ${CONFIG_FILE} > ${CONFIG_FILE}.tmp
            mv ${CONFIG_FILE}.tmp ${CONFIG_FILE}
            echo -e "${GREEN}节点已成功删除！${PLAIN}"
        }
        fi
        
        # 重启xray服务
        systemctl restart xray
    else
        echo -e "${RED}配置文件不存在，请先安装xray！${PLAIN}"
    fi
}
# 查看 Xray 日志
view_log() {
    echo -e "${GREEN}查看 Xray 日志...${PLAIN}"
    
    echo "请选择要查看的日志类型:"
    echo "1. 访问日志 (access.log)"
    echo "2. 错误日志 (error.log)"
    read -p "请选择 [1-2]: " log_choice
    
    case "$log_choice" in
        1)
            if [ -f "${LOG_DIR}/access.log" ]; then
                echo -e "${YELLOW}最近50行访问日志:${PLAIN}"
                tail -n 50 ${LOG_DIR}/access.log
            else
                echo -e "${RED}访问日志文件不存在！${PLAIN}"
            fi
            ;;
        2)
            if [ -f "${LOG_DIR}/error.log" ]; then
                echo -e "${YELLOW}最近50行错误日志:${PLAIN}"
                tail -n 50 ${LOG_DIR}/error.log
            else
                echo -e "${RED}错误日志文件不存在！${PLAIN}"
            fi
            ;;
        *)
            echo -e "${RED}输入无效！${PLAIN}"
            ;;
    esac
}
# 查看当前Xray配置
view_config() {
    echo -e "${GREEN}查看当前Xray配置...${PLAIN}"
    
    if [[ -f ${CONFIG_FILE} ]]; then
        # 检查jq是否安装
        if ! command -v jq &> /dev/null; then
            echo -e "${YELLOW}jq工具未安装，正在安装...${PLAIN}"
            if [[ $release = "centos" ]]; then
                yum install -y jq
            else
                apt update -y && apt install -y jq
            fi
        fi
        
        # 获取基本信息
        echo -e "${BLUE}基本配置信息:${PLAIN}"
        
        # 获取日志级别
        log_level=$(jq -r '.log.loglevel' ${CONFIG_FILE})
        echo -e "${GREEN}日志级别: ${log_level}${PLAIN}"
        
        # 获取日志路径
        access_log=$(jq -r '.log.access' ${CONFIG_FILE})
        error_log=$(jq -r '.log.error' ${CONFIG_FILE})
        echo -e "${GREEN}访问日志: ${access_log}${PLAIN}"
        echo -e "${GREEN}错误日志: ${error_log}${PLAIN}"
        
        # 获取入站配置
        inbound_count=$(jq '.inbounds | length' ${CONFIG_FILE})
        echo -e "\n${BLUE}入站配置 (${inbound_count}个):${PLAIN}"
        
        # 创建节点列表
        declare -a normal_nodes
        declare -a reality_nodes
        
        # 识别节点类型
        for ((i=0; i<${inbound_count}; i++)); do
            protocol=$(jq -r ".inbounds[$i].protocol" ${CONFIG_FILE})
            port=$(jq -r ".inbounds[$i].port" ${CONFIG_FILE})
            tag=$(jq -r ".inbounds[$i].tag // \"未命名\"" ${CONFIG_FILE})
            listen=$(jq -r ".inbounds[$i].listen // \"0.0.0.0\"" ${CONFIG_FILE})
            
            # 检查是否是REALITY配对的一部分
            if [[ "$protocol" == "dokodemo-door" && "$tag" == "dokodemo-in" ]]; then
                # 找到关联的vless配置
                internal_port=$(jq -r ".inbounds[$i].settings.port" ${CONFIG_FILE})
                for ((j=0; j<${inbound_count}; j++)); do
                    if [[ $i -ne $j ]]; then
                        inner_protocol=$(jq -r ".inbounds[$j].protocol" ${CONFIG_FILE})
                        inner_port=$(jq -r ".inbounds[$j].port" ${CONFIG_FILE})
                        inner_listen=$(jq -r ".inbounds[$j].listen // \"0.0.0.0\"" ${CONFIG_FILE})
                        
                        if [[ "$inner_protocol" == "vless" && "$inner_port" == "$internal_port" && "$inner_listen" == "127.0.0.1" ]]; then
                            security=$(jq -r ".inbounds[$j].streamSettings.security // \"none\"" ${CONFIG_FILE})
                            if [[ "$security" == "reality" ]]; then
                                # REALITY配对
                                server_name=$(jq -r ".inbounds[$j].streamSettings.realitySettings.serverNames[0]" ${CONFIG_FILE})
                                uuid=$(jq -r ".inbounds[$j].settings.clients[0].id" ${CONFIG_FILE})
                                public_key=$(jq -r ".inbounds[$j].streamSettings.realitySettings.publicKey" ${CONFIG_FILE})
                                short_id=$(jq -r ".inbounds[$j].streamSettings.realitySettings.shortIds[1] // \"\"" ${CONFIG_FILE})
                                
                                reality_info="协议: VLESS+REALITY, 外部端口: ${port}, UUID: ${uuid:0:8}..., SNI: ${server_name}"
                                reality_nodes+=("$reality_info")
                                break
                            fi
                        fi
                    fi
                done
            elif [[ "$protocol" != "vless" || "$listen" != "127.0.0.1" ]]; then
                # 普通节点
                if [[ "$protocol" == "shadowsocks" ]]; then
                    # 检查是单用户还是多用户
                    if jq -e ".inbounds[$i].settings.password" ${CONFIG_FILE} > /dev/null; then
                        # 单用户
                        method=$(jq -r ".inbounds[$i].settings.method" ${CONFIG_FILE})
                        node_info="协议: Shadowsocks(单用户), 端口: ${port}, 加密方式: ${method}"
                    else
                        # 多用户
                        clients_count=$(jq ".inbounds[$i].settings.clients | length" ${CONFIG_FILE})
                        node_info="协议: Shadowsocks(多用户-${clients_count}个), 端口: ${port}"
                    fi
                else
                    node_info="协议: ${protocol}, 端口: ${port}"
                fi
                normal_nodes+=("$node_info")
            fi
        done
        
        # 显示REALITY节点
        if [[ ${#reality_nodes[@]} -gt 0 ]]; then
            echo -e "${YELLOW}REALITY节点:${PLAIN}"
            for ((i=0; i<${#reality_nodes[@]}; i++)); do
                echo -e "${GREEN}  [$i] ${reality_nodes[$i]}${PLAIN}"
            done
        fi
        
        # 显示普通节点
        if [[ ${#normal_nodes[@]} -gt 0 ]]; then
            echo -e "${YELLOW}其他节点:${PLAIN}"
            for ((i=0; i<${#normal_nodes[@]}; i++)); do
                echo -e "${GREEN}  [$i] ${normal_nodes[$i]}${PLAIN}"
            done
        fi
        
        # 获取出站配置
        outbound_count=$(jq '.outbounds | length' ${CONFIG_FILE})
        echo -e "\n${BLUE}出站配置 (${outbound_count}个):${PLAIN}"
        
        for ((i=0; i<${outbound_count}; i++)); do
            protocol=$(jq -r ".outbounds[$i].protocol" ${CONFIG_FILE})
            tag=$(jq -r ".outbounds[$i].tag // \"未命名\"" ${CONFIG_FILE})
            echo -e "${GREEN}  [$i] 协议: ${protocol}, 标签: ${tag}${PLAIN}"
        done
        
        # 检查路由规则
        echo -e "\n${BLUE}路由规则:${PLAIN}"
        if jq -e '.routing.rules' ${CONFIG_FILE} > /dev/null; then
            rules_count=$(jq '.routing.rules | length' ${CONFIG_FILE})
            echo -e "${GREEN}  规则数量: ${rules_count}${PLAIN}"
            
            for ((i=0; i<${rules_count}; i++)); do
                inbound_tag=$(jq -r ".routing.rules[$i].inboundTag // []" ${CONFIG_FILE})
                outbound_tag=$(jq -r ".routing.rules[$i].outboundTag // \"未指定\"" ${CONFIG_FILE})
                domain=$(jq -r ".routing.rules[$i].domain // []" ${CONFIG_FILE})
                
                echo -e "${GREEN}  [$i] 入站标签: ${inbound_tag}, 出站标签: ${outbound_tag}${PLAIN}"
                if [[ "$domain" != "[]" ]]; then
                    echo -e "${GREEN}      域名: ${domain}${PLAIN}"
                fi
            done
        else
            echo -e "${YELLOW}  未配置路由规则${PLAIN}"
        fi
        
        # 显示查看完整配置的选项
        echo -e "\n${YELLOW}是否查看完整配置文件内容? [y/n]: ${PLAIN}"
        read view_full
        
        if [[ "$view_full" == "y" || "$view_full" == "Y" ]]; then
            echo -e "${BLUE}完整配置文件内容:${PLAIN}"
            cat ${CONFIG_FILE} | jq
        fi
        
    else
        echo -e "${RED}配置文件不存在，请先安装xray！${PLAIN}"
    fi
}
# 显示菜单
show_menu() {
    clear
    echo -e "
  ${GREEN}╔═══════════════════════════════════════════════╗${PLAIN}
  ${GREEN}║              Xray 一键管理脚本               ║${PLAIN}
  ${GREEN}╚═══════════════════════════════════════════════╝${PLAIN}
  ${GREEN}————————————————— 基础选项 —————————————————${PLAIN}
  ${GREEN}1.${PLAIN} 显示 Xray 状态
  ${GREEN}2.${PLAIN} 安装/更新 Xray
  ${GREEN}3.${PLAIN} 卸载 Xray
  ${GREEN}————————————————— 节点管理 —————————————————${PLAIN}
  ${GREEN}4.${PLAIN} 添加 REALITY 节点
  ${GREEN}5.${PLAIN} 添加 Shadowsocks 节点(单用户)
  ${GREEN}6.${PLAIN} 导出现有节点配置
  ${GREEN}7.${PLAIN} 删除节点
  ${GREEN}8.${PLAIN} 查看 Xray 日志
  ${GREEN}9.${PLAIN} 查看当前 Xray 配置
  ${GREEN}————————————————— 其他选项 —————————————————${PLAIN}
  ${GREEN}0.${PLAIN} 退出脚本
    "
    echo && read -p "请输入选择 [0-9]: " num
    
    case "${num}" in
        0) exit 0 ;;
        1) check_xray_status ;;
        2) install_update_xray ;;
        3) uninstall_xray ;;
        4) add_reality ;;
        5) add_shadowsocks ;;
        6) export_config ;;
        7) delete_node ;;
        8) view_log ;;
        9) view_config ;;
        *) echo -e "${RED}请输入正确的数字 [0-9]${PLAIN}" ;;
    esac
}

# 执行主函数
# 主函数
main() {
    check_os
    install_dependencies
    
    while true; do
        show_menu
        echo ""
        echo -e "${YELLOW}按任意键继续...${PLAIN}"
        read -n 1 -s key
    done
}
main
