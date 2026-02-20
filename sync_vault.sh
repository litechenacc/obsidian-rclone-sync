#!/bin/bash

# ==========================================
# Obsidian / Nvim Vault 雙向同步腳本
# ==========================================

set -euo pipefail

REMOTE="gd:vault"
LOCAL="$HOME/vault"
LOCKFILE="/tmp/rclone_vault_sync.lock"
LOGFILE="$HOME/.vault_sync.log"
SYNC_TRIGGER="manual"
NOTIFY_MODE="auto"
SYNC_LABEL="[Obsidian<->GDrive]"
FORCE_MODE=false

usage() {
    echo "用法: $0 [--trigger=manual|timer|watcher] [--notify=auto|on|off] [--force]"
}

format_summary() {
    local changes="$1"
    local new="$2"
    local newer="$3"
    local older="$4"
    local deleted="$5"
    local value
    local detail

    if [[ -z "$changes" ]]; then
        value="-"
        detail=""
    elif [[ "$changes" -eq 0 ]]; then
        value="no change needed"
        detail="new 0, newer 0, older 0, del 0"
    else
        value="$changes files"
        detail="new $new, newer $newer, older $older, del $deleted"
    fi

    printf "%s|%s\n" "$value" "$detail"
}

render_table() {
    local rows=()
    local row

    rows+=(" |Label|Value|Detail")
    rows+=("$1")
    rows+=("$2")
    rows+=("$3")
    rows+=("$4")
    rows+=("$5")
    rows+=("$6")

    if command -v column &> /dev/null; then
        printf '%s\n' "${rows[@]}" | column -t -s '|'
    else
        for row in "${rows[@]}"; do
            echo "${row//|/ | }"
        done
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --trigger=*)
            SYNC_TRIGGER="${1#*=}"
            shift
            ;;
        --trigger)
            shift
            SYNC_TRIGGER="${1:-}"
            shift
            ;;
        --notify=*)
            NOTIFY_MODE="${1#*=}"
            shift
            ;;
        --notify)
            shift
            NOTIFY_MODE="${1:-}"
            shift
            ;;
        --force)
            FORCE_MODE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "❌ 錯誤：未知參數 $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

case "$SYNC_TRIGGER" in
    manual|timer|watcher)
        ;;
    *)
        echo "❌ 錯誤：不支援的 trigger 值: $SYNC_TRIGGER" >&2
        usage >&2
        exit 1
        ;;
esac

case "$NOTIFY_MODE" in
    auto|on|off)
        ;;
    *)
        echo "❌ 錯誤：不支援的 notify 值: $NOTIFY_MODE" >&2
        usage >&2
        exit 1
        ;;
esac

check_reqs() {
    local missing=false

    if ! command -v rclone &> /dev/null; then
        echo "❌ 錯誤：找不到 rclone。" >&2
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [錯誤] 找不到 rclone。" >> "$LOGFILE"
        missing=true
    fi
    if ! command -v flock &> /dev/null; then
        echo "❌ 錯誤：找不到 flock。" >&2
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [錯誤] 找不到 flock。" >> "$LOGFILE"
        missing=true
    fi
    if [[ ! -d "$LOCAL" ]]; then
        echo "❌ 錯誤：找不到 Vault 資料夾 $LOCAL" >&2
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [錯誤] 找不到 Vault 資料夾 $LOCAL" >> "$LOGFILE"
        missing=true
    fi

    if [[ "$missing" == true ]]; then
        exit 1
    fi
}

check_reqs

# 1. 防撞車機制：使用 flock 確保同一時間只有一個同步程序在跑
# 資源代碼 200 綁定 LOCKFILE，-n 代表非阻塞 (拿不到鎖直接離開，不排隊死等)
exec 200>$LOCKFILE
if ! flock -n 200; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [跳過] 另一個同步程序正在進行中。" >> "$LOGFILE"
    if [[ "$SYNC_TRIGGER" == "manual" ]]; then
        echo "⏸️  $SYNC_LABEL 同步正在進行中，請稍後再試。"
    fi
    exit 0
fi

echo "=========================================" >> "$LOGFILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') - 開始同步..." >> "$LOGFILE"

if [[ "$SYNC_TRIGGER" == "manual" ]]; then
    echo "🟡 $SYNC_LABEL 同步啟動中..."
    echo "⏳ Running rclone bisync (trigger: $SYNC_TRIGGER)"
    echo "🧾 Log: $LOGFILE"
fi

SYNC_START_TS=$(date +%s)

# 2. 執行 rclone bisync 並捕捉輸出與錯誤碼
# --conflict-resolve newer : 發生衝突時，強制保留修改時間較新的檔案
# --create-empty-src-dirs  : 保持空資料夾結構 (對筆記軟體很重要)
# --resilient              : 遇到小錯誤不中斷整個程序
# -v                       : 輸出詳細資訊供日誌記錄
set +e
RCLONE_ARGS=(
    --conflict-resolve newer
    --create-empty-src-dirs
    --resilient
    -v
)

if [[ "$FORCE_MODE" == true ]]; then
    RCLONE_ARGS+=(--force)
fi

OUTPUT=$(rclone bisync "$REMOTE" "$LOCAL" "${RCLONE_ARGS[@]}" 2>&1)
EXIT_CODE=$?
set -e

FINAL_OUTPUT="$OUTPUT"
FINAL_EXIT_CODE=$EXIT_CODE
RESYNC_USED=false

# 3. 智慧判斷：檢查是否需要初次綁定 (--resync)
# 當 rclone 發現沒有歷史同步紀錄時，會報錯並提示需要 --resync
if [[ $EXIT_CODE -ne 0 ]] && [[ $OUTPUT == *"--resync"* ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [系統] 初次同步失敗，錯誤輸出如下：" >> "$LOGFILE"
    echo "$OUTPUT" >> "$LOGFILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [系統] 偵測到需要初次綁定，自動切換至 --resync 模式..." >> "$LOGFILE"
    
    set +e
    RESYNC_OUTPUT=$(rclone bisync "$REMOTE" "$LOCAL" --resync "${RCLONE_ARGS[@]}" 2>&1)
    RESYNC_CODE=$?
    set -e

    echo "$RESYNC_OUTPUT" >> "$LOGFILE"
    FINAL_OUTPUT="$RESYNC_OUTPUT"
    FINAL_EXIT_CODE=$RESYNC_CODE
    RESYNC_USED=true
    
    if [[ $RESYNC_CODE -eq 0 ]]; then
         echo "$(date '+%Y-%m-%d %H:%M:%S') - [成功] 初次綁定 (--resync) 完成！" >> "$LOGFILE"
    else
         echo "$(date '+%Y-%m-%d %H:%M:%S') - [錯誤] 初次綁定失敗，請檢查日誌: $LOGFILE" >> "$LOGFILE"
    fi
else
    # 正常同步的處理結果
    echo "$OUTPUT" >> "$LOGFILE"
    if [[ $EXIT_CODE -eq 0 ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [成功] 同步完成。" >> "$LOGFILE"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [錯誤] 同步發生異常 (代碼: $EXIT_CODE)，請檢查日誌: $LOGFILE" >> "$LOGFILE"
    fi
fi

SYNC_END_TS=$(date +%s)
SYNC_DURATION=$((SYNC_END_TS - SYNC_START_TS))

path1_changes=""
path1_new=""
path1_newer=""
path1_older=""
path1_deleted=""
path2_changes=""
path2_new=""
path2_newer=""
path2_older=""
path2_deleted=""

while IFS= read -r line; do
    if [[ $line =~ Path1:[[:space:]]*([0-9]+)[[:space:]]*changes:[[:space:]]*([0-9]+)[[:space:]]*new,[[:space:]]*([0-9]+)[[:space:]]*newer,[[:space:]]*([0-9]+)[[:space:]]*older,[[:space:]]*([0-9]+)[[:space:]]*deleted ]]; then
        path1_changes="${BASH_REMATCH[1]}"
        path1_new="${BASH_REMATCH[2]}"
        path1_newer="${BASH_REMATCH[3]}"
        path1_older="${BASH_REMATCH[4]}"
        path1_deleted="${BASH_REMATCH[5]}"
    elif [[ $line =~ Path2:[[:space:]]*([0-9]+)[[:space:]]*changes:[[:space:]]*([0-9]+)[[:space:]]*new,[[:space:]]*([0-9]+)[[:space:]]*newer,[[:space:]]*([0-9]+)[[:space:]]*older,[[:space:]]*([0-9]+)[[:space:]]*deleted ]]; then
        path2_changes="${BASH_REMATCH[1]}"
        path2_new="${BASH_REMATCH[2]}"
        path2_newer="${BASH_REMATCH[3]}"
        path2_older="${BASH_REMATCH[4]}"
        path2_deleted="${BASH_REMATCH[5]}"
    fi
done <<< "$FINAL_OUTPUT"

IFS='|' read -r up_value up_detail < <(format_summary "$path2_changes" "$path2_new" "$path2_newer" "$path2_older" "$path2_deleted")
IFS='|' read -r down_value down_detail < <(format_summary "$path1_changes" "$path1_new" "$path1_newer" "$path1_older" "$path1_deleted")

up_summary="$up_value"
down_summary="$down_value"
if [[ -n "$up_detail" ]]; then
    up_summary="$up_summary ($up_detail)"
fi
if [[ -n "$down_detail" ]]; then
    down_summary="$down_summary ($down_detail)"
fi

notify_enabled=false
if [[ "$NOTIFY_MODE" == "on" ]]; then
    notify_enabled=true
elif [[ "$NOTIFY_MODE" == "auto" ]]; then
    if [[ "$SYNC_TRIGGER" == "manual" ]]; then
        notify_enabled=true
    elif [[ $FINAL_EXIT_CODE -ne 0 ]]; then
        notify_enabled=true
    elif [[ -n "$path1_changes" || -n "$path2_changes" ]]; then
        if [[ ${path1_changes:-0} -gt 0 || ${path2_changes:-0} -gt 0 ]]; then
            notify_enabled=true
        fi
    fi
fi

if [[ "$notify_enabled" == true ]] && command -v notify-send &> /dev/null; then
    notify_title="$SYNC_LABEL"
    notify_body="󰜎 $SYNC_TRIGGER\n󰁞 $up_summary\n󰁆 $down_summary\n󱑂 ${SYNC_DURATION}s"
    if [[ "$RESYNC_USED" == true ]]; then
        notify_body="$notify_body\n󰆺 resync"
    fi

    if [[ $FINAL_EXIT_CODE -eq 0 ]]; then
        notify_send_body="$notify_body"
    else
        notify_send_body="󰗠 ERROR\n$notify_body"
    fi
    notify-send "$notify_title" "$notify_send_body"
fi

if [[ "$SYNC_TRIGGER" == "manual" ]]; then
    mode_value="normal"
    status_value="OK"
    status_detail=""
    if [[ "$RESYNC_USED" == true ]]; then
        mode_value="resync"
    fi
    if [[ $FINAL_EXIT_CODE -ne 0 ]]; then
        status_value="ERROR"
        status_detail="check $LOGFILE"
    fi

    echo "🗂️  $SYNC_LABEL"
    render_table \
        "󰜎|Trigger|$SYNC_TRIGGER|" \
        "󰁞|Up|$up_value|$up_detail" \
        "󰁆|Down|$down_value|$down_detail" \
        "󱑂|Time|${SYNC_DURATION}s|" \
        "󰆺|Mode|$mode_value|" \
        "󰗠|Status|$status_value|$status_detail"
fi
