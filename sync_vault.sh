#!/bin/bash

# ==========================================
# Obsidian / Nvim Vault 雙向同步腳本
# ==========================================

set -euo pipefail

REMOTE="gd:vault"
LOCAL="$HOME/vault"
LOCKFILE="/tmp/rclone_vault_sync.lock"
LOGFILE="$HOME/.vault_sync.log"

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
    exit 0
fi

echo "=========================================" >> "$LOGFILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') - 開始同步..." >> "$LOGFILE"

# 2. 執行 rclone bisync 並捕捉輸出與錯誤碼
# --conflict-resolve newer : 發生衝突時，強制保留修改時間較新的檔案
# --create-empty-src-dirs  : 保持空資料夾結構 (對筆記軟體很重要)
# --resilient              : 遇到小錯誤不中斷整個程序
# -v                       : 輸出詳細資訊供日誌記錄
set +e
OUTPUT=$(rclone bisync "$REMOTE" "$LOCAL" \
    --conflict-resolve newer \
    --create-empty-src-dirs \
    --resilient \
    -v 2>&1)
EXIT_CODE=$?
set -e

# 3. 智慧判斷：檢查是否需要初次綁定 (--resync)
# 當 rclone 發現沒有歷史同步紀錄時，會報錯並提示需要 --resync
if [[ $EXIT_CODE -ne 0 ]] && [[ $OUTPUT == *"--resync"* ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [系統] 初次同步失敗，錯誤輸出如下：" >> "$LOGFILE"
    echo "$OUTPUT" >> "$LOGFILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [系統] 偵測到需要初次綁定，自動切換至 --resync 模式..." >> "$LOGFILE"
    
    set +e
    rclone bisync "$REMOTE" "$LOCAL" \
        --resync \
        --conflict-resolve newer \
        --create-empty-src-dirs \
        --resilient \
        -v >> "$LOGFILE" 2>&1
    RESYNC_CODE=$?
    set -e
    
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
