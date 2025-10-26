#!/bin/bash

# Определение цветов и жирного текста для вывода
RED='\033[1;31m'    # Красный жирный
GREEN='\033[1;32m'  # Зеленый жирный
YELLOW='\033[1;33m' # Желтый жирный
BLUE='\033[1;34m'   # Синий жирный
NC='\033[0m'        # Сброс цвета и жирности

# URL файла с подсетями
URL="https://gist.githubusercontent.com/sngvy/07cee7ac810c9d222fbebddff8c1d1b8/raw/974d3d87f190468e134e9b56f1e0a93c7caa0fcd/blacklist.txt"

# Временный файл для хранения подсетей
TEMP_FILE="/tmp/blacklist_subnets.txt"

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Ошибка: скрипт должен быть запущен от имени root (sudo)${NC}"
    exit 1
fi

# Функция для проверки и установки iptables и ip6tables
install_iptables() {
    if ! command -v iptables &>/dev/null; then
        echo -e "${BLUE}Установка iptables...${NC}"
        if [[ -f /etc/debian_version ]]; then
            apt-get update &>/dev/null && apt-get install -y iptables &>/dev/null
            if [[ $? -ne 0 ]]; then
                echo -e "${RED}Ошибка: не удалось установить iptables${NC}"
                exit 1
            fi
        elif [[ -f /etc/redhat-release ]]; then
            yum install -y iptables &>/dev/null
            if [[ $? -ne 0 ]]; then
                echo -e "${RED}Ошибка: не удалось установить iptables${NC}"
                exit 1
            fi
        else
            echo -e "${RED}Ошибка: неподдерживаемая система. Установите iptables вручную.${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}iptables уже установлен${NC}"
    fi

    if ! command -v ip6tables &>/dev/null; then
        echo -e "${BLUE}Установка ip6tables...${NC}"
        if [[ -f /etc/debian_version ]]; then
            apt-get install -y ip6tables &>/dev/null
            if [[ $? -ne 0 ]]; then
                echo -e "${RED}Ошибка: не удалось установить ip6tables${NC}"
                exit 1
            fi
        elif [[ -f /etc/redhat-release ]]; then
            yum install -y ip6tables &>/dev/null
            if [[ $? -ne 0 ]]; then
                echo -e "${RED}Ошибка: не удалось установить ip6tables${NC}"
                exit 1
            fi
        else
            echo -e "${RED}Ошибка: неподдерживаемая система. Установите ip6tables вручную.${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}ip6tables уже установлен${NC}"
    fi
}

# Функция для создания и настройки цепочки SCANNERS-BLOCK для iptables и ip6tables
setup_iptables_chain() {
    if ! iptables -L SCANNERS-BLOCK -n &>/dev/null; then
        echo -e "${BLUE}Создание цепочки SCANNERS-BLOCK для iptables...${NC}"
        iptables -N SCANNERS-BLOCK
    else
        echo -e "${YELLOW}Очистка существующей цепочки SCANNERS-BLOCK для iptables...${NC}"
        iptables -F SCANNERS-BLOCK
    fi
    if ! iptables -C INPUT -j SCANNERS-BLOCK &>/dev/null; then
        iptables -A INPUT -j SCANNERS-BLOCK
    fi

    if ! ip6tables -L SCANNERS-BLOCK -n &>/dev/null; then
        echo -e "${BLUE}Создание цепочки SCANNERS-BLOCK для ip6tables...${NC}"
        ip6tables -N SCANNERS-BLOCK
    else
        echo -e "${YELLOW}Очистка существующей цепочки SCANNERS-BLOCK для ip6tables...${NC}"
        ip6tables -F SCANNERS-BLOCK
    fi
    if ! ip6tables -C INPUT -j SCANNERS-BLOCK &>/dev/null; then
        ip6tables -A INPUT -j SCANNERS-BLOCK
    fi
}

# Функция для проверки формата подсети (IPv4 или IPv6)
is_ipv6() {
    local subnet=$1
    if [[ $subnet =~ : ]]; then
        return 0 # IPv6
    else
        return 1 # IPv4
    fi
}

# Функция для применения правил iptables и ip6tables
apply_iptables_rules() {
    echo -e "${BLUE}Скачивание списка подсетей...${NC}"
    curl -s "$URL" -o "$TEMP_FILE"
    if [[ ! -s "$TEMP_FILE" ]]; then
        echo -e "${RED}Ошибка: не удалось скачать файл подсетей${NC}"
        exit 1
    fi

    echo -e "${BLUE}Чтение подсетей...${NC}"
    subnets=$(cat "$TEMP_FILE")
    if [[ -z "$subnets" ]]; then
        echo -e "${RED}Ошибка: файл подсетей пуст${NC}"
        exit 1
    fi

    echo -e "${BLUE}Применение правил iptables и ip6tables...${NC}"
    while IFS= read -r subnet; do
        [[ -z "$subnet" ]] && continue
        if is_ipv6 "$subnet"; then
            ip6tables -A SCANNERS-BLOCK -s "$subnet" -j DROP
        else
            iptables -A SCANNERS-BLOCK -s "$subnet" -j DROP
        fi
    done <<< "$subnets"
}

# Функция для сохранения правил iptables и ip6tables
save_iptables() {
    echo -e "${BLUE}Сохранение правил iptables и ip6tables...${NC}"
    if [[ -f /etc/debian_version ]]; then
        # Проверка и установка netfilter-persistent и iptables-persistent
        if dpkg -l | grep -E '^ii\s+netfilter-persistent\s' >/dev/null || dpkg -l | grep -E '^ii\s+iptables-persistent\s' >/dev/null; then
            echo -e "${GREEN}Пакет netfilter-persistent или iptables-persistent уже установлен${NC}"
        else
            echo -e "${BLUE}Установка netfilter-persistent и iptables-persistent...${NC}"
            apt-get update &>/dev/null
            if ! DEBIAN_FRONTEND=noninteractive apt-get install -y netfilter-persistent iptables-persistent &>/dev/null; then
                echo -e "${RED}Ошибка: не удалось установить netfilter-persistent и iptables-persistent${NC}"
                echo -e "${YELLOW}Попробуйте установить вручную: 'apt-get update && apt-get install netfilter-persistent iptables-persistent'${NC}"
            else
                echo -e "${GREEN}Пакеты netfilter-persistent и iptables-persistent успешно установлены${NC}"
            fi
        fi

        # Создание директории /etc/iptables, если она не существует
        mkdir -p /etc/iptables
        iptables-save > /etc/iptables/rules.v4
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}Ошибка: не удалось сохранить правила iptables${NC}"
        fi
        ip6tables-save > /etc/iptables/rules.v6
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}Ошибка: не удалось сохранить правила ip6tables${NC}"
        fi
    elif [[ -f /etc/redhat-release ]]; then
        # Создание директории /etc/sysconfig, если она не существует
        mkdir -p /etc/sysconfig
        iptables-save > /etc/sysconfig/iptables
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}Ошибка: не удалось сохранить правила iptables${NC}"
        fi
        ip6tables-save > /etc/sysconfig/ip6tables
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}Ошибка: не удалось сохранить правила ip6tables${NC}"
        fi
        systemctl enable iptables &>/dev/null
        systemctl enable ip6tables &>/dev/null
    else
        echo -e "${YELLOW}Внимание: автоматическое сохранение правил не настроено для этой системы.${NC}"
        echo -e "${YELLOW}Сохраните правила вручную с помощью 'iptables-save > /etc/iptables.rules' и 'ip6tables-save > /etc/ip6tables.rules'${NC}"
    fi
}

# Основной процесс
echo -e "${BLUE}Запуск скрипта...${NC}"
install_iptables
setup_iptables_chain
apply_iptables_rules
save_iptables
rm -f "$TEMP_FILE"
echo -e "${GREEN}Скрипт успешно выполнен!${NC}"