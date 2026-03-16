#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Лог-файл
LOG_FILE="/var/log/zombie_killer.log"

log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

find_zombies() {
    ps -eo pid,ppid,stat,user,cmd | awk '$3 ~ /^Z/ {print $1, $2, $4, $5}'
}

count_zombies() {
    ps -eo stat | grep -c '^Z' || echo "0"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}❌ Этот скрипт должен запускаться с правами root${NC}"
        exit 1
    fi
}

handle_zombies() {
    local zombies=$(find_zombies)
    
    if [ -z "$zombies" ]; then
        log "${GREEN}✅ Зомби-процессы не найдены${NC}"
        return 0
    fi
    
    local count=$(echo "$zombies" | wc -l)
    log "${YELLOW}⚠️ Найдено зомби-процессов: $count${NC}"
    log "PID    PPID   USER     COMMAND"
    log "----------------------------------------"
    
    echo "$zombies" | while read -r pid ppid user cmd; do
        log "$pid    $ppid   $user     $cmd"
        
        # Проверяем, не является ли родительский процесс системным
        if [[ "$ppid" -le 2 ]] || [[ "$ppid" -eq 1 ]]; then
            log "${YELLOW}⚠️ Пропускаем системный родительский процесс PPID=$ppid${NC}"
            continue
        fi
        
        # Пытаемся мягко обработать
        log "${BLUE}⚙️ Отправка SIGCHLD родительскому процессу $ppid${NC}"
        kill -s SIGCHLD "$ppid" 2>/dev/null
        
        sleep 1
        
        # Проверяем, исчез ли конкретный зомби
        if ps -p "$pid" 2>/dev/null | grep -q "Z"; then
            log "${YELLOW}⚠️ Зомби $pid все еще существует. Отправляем SIGCHLD повторно${NC}"
            kill -s SIGCHLD "$ppid" 2>/dev/null
            sleep 1
        fi
        
        # Если все еще существует, запрашиваем действие
        if ps -p "$pid" 2>/dev/null | grep -q "Z"; then
            if [ "$AUTO_MODE" = true ]; then
                log "${RED}💀 Автоматическое завершение родительского процесса $ppid${NC}"
                kill -9 "$ppid" 2>/dev/null
            else
                echo -e -n "${YELLOW}❓ Завершить родительский процесс $ppid? (y/n/a - все) : ${NC}"
                read -r choice
                case $choice in
                    [Yy])
                        kill -9 "$ppid" 2>/dev/null
                        log "${RED}💀 Завершен родительский процесс $ppid${NC}"
                        ;;
                    [Aa])
                        AUTO_MODE=true
                        kill -9 "$ppid" 2>/dev/null
                        log "${RED}💀 Завершен родительский процесс $ppid (автоматический режим включен)${NC}"
                        ;;
                    *)
                        log "${BLUE}⏭️ Пропускаем процесс $ppid${NC}"
                        ;;
                esac
            fi
        fi
    done
    
    sleep 2
    
    # Финальная проверка
    local remaining=$(count_zombies)
    if [ "$remaining" -eq 0 ]; then
        log "${GREEN}✅ Все зомби-процессы очищены!${NC}"
    else
        log "${RED}⚠️ Осталось зомби-процессов: $remaining${NC}"
        log "${YELLOW}Некоторые зомби могут быть от системных процессов, которые нельзя завершить${NC}"
    fi
}

show_help() {
    echo "Использование: $0 [опции]"
    echo "Опции:"
    echo "  -a, --auto    Автоматический режим (без запросов)"
    echo "  -l, --log     Показать лог-файл"
    echo "  -c, --count   Показать количество зомби"
    echo "  -h, --help    Показать эту справку"
}

# Основная логика
AUTO_MODE=false

case "$1" in
    -a|--auto)
        AUTO_MODE=true
        check_root
        handle_zombies
        ;;
    -l|--log)
        if [ -f "$LOG_FILE" ]; then
            less "$LOG_FILE"
        else
            echo "Лог-файл не найден"
        fi
        ;;
    -c|--count)
        echo "Зомби-процессов: $(count_zombies)"
        ;;
    -h|--help)
        show_help
        ;;
    *)
        check_root
        handle_zombies
        ;;
esac
