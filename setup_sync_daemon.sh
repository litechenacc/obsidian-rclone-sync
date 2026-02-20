#!/bin/bash

# ==========================================
# Obsidian Sync Systemd 管理腳本
# 用法: 
#   ./setup_sync_daemon.sh install   (安裝並啟動自動同步)
#   ./setup_sync_daemon.sh uninstall (完全解除安裝並停止)
# ==========================================

# 變數設定
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
SYNC_SCRIPT="$HOME/.local/bin/sync_vault"
VAULT_DIR="$HOME/vault"

# 檢查必備工具與路徑
check_reqs() {
    if ! command -v inotifywait &> /dev/null; then
        echo "❌ 錯誤：找不到 inotifywait。請先執行 'sudo pacman -S inotify-tools'"
        exit 1
    fi
    if ! command -v systemctl &> /dev/null; then
        echo "❌ 錯誤：找不到 systemctl。請確認 systemd 已安裝並可用。"
        exit 1
    fi
    if [ ! -f "$SYNC_SCRIPT" ]; then
        echo "❌ 錯誤：找不到同步腳本 $SYNC_SCRIPT"
        exit 1
    fi
    if [ ! -d "$VAULT_DIR" ]; then
        echo "❌ 錯誤：找不到 Vault 資料夾 $VAULT_DIR"
        exit 1
    fi
}

install_daemon() {
    echo "🛠️ 開始建立 Systemd Daemon..."
    mkdir -p "$SYSTEMD_USER_DIR"

    # 1. 建立執行腳本的 Service (供定時器呼叫)
    cat << EOF > "$SYSTEMD_USER_DIR/vault-sync.service"
[Unit]
Description=Obsidian Vault Periodic Sync

[Service]
Type=oneshot
ExecStart=$SYNC_SCRIPT
EOF

    # 2. 建立 15 分鐘的 Timer
    cat << EOF > "$SYSTEMD_USER_DIR/vault-sync.timer"
[Unit]
Description=Run Vault Sync every 15 minutes

[Timer]
OnBootSec=5m
OnUnitActiveSec=15m

[Install]
WantedBy=timers.target
EOF

    # 3. 建立監控與登入登出觸發的 Daemon
    # ExecStartPre : 登入時先強制跑一次同步
    # ExecStart    : 進入 inotify 監控迴圈 (忽略 Obsidian 的即時設定檔變動，避免瘋狂觸發)
    # ExecStopPost : 登出(服務關閉)時跑最後一次同步
    cat << EOF > "$SYSTEMD_USER_DIR/vault-sync-watcher.service"
[Unit]
Description=Obsidian Vault Watcher & Login/Logout Sync

[Service]
Type=simple
ExecStartPre=-"$SYNC_SCRIPT"
ExecStart=/bin/bash -c "while inotifywait -qq -r -e close_write,moved_to,moved_from,delete --exclude '\\.obsidian/workspace(\\.json|-[^/]+)?' '$VAULT_DIR'; do sleep 5; '$SYNC_SCRIPT'; done"
ExecStopPost=-"$SYNC_SCRIPT"

[Install]
WantedBy=default.target
EOF

    # 重新載入 Systemd 設定並啟用服務
    echo "🔄 重新載入 Systemd 服務..."
    if ! systemctl --user daemon-reload; then
        echo "⚠️ 警告：systemctl --user daemon-reload 執行失敗，請手動檢查。" >&2
    fi
    systemctl --user enable --now vault-sync.timer
    systemctl --user enable --now vault-sync-watcher.service

    echo "✅ 安裝完成！你的 Vault 已經受到全天候雙向同步保護。"
    echo "你可以用以下指令查看狀態："
    echo "  systemctl --user status vault-sync-watcher.service"
    echo "  systemctl --user list-timers"
}

uninstall_daemon() {
    echo "🛑 正在停止並取消 Systemd Daemon..."
    
    systemctl --user disable --now vault-sync.timer 2>/dev/null
    systemctl --user disable --now vault-sync-watcher.service 2>/dev/null
    
    rm -f "$SYSTEMD_USER_DIR/vault-sync.service"
    rm -f "$SYSTEMD_USER_DIR/vault-sync.timer"
    rm -f "$SYSTEMD_USER_DIR/vault-sync-watcher.service"
    
    systemctl --user daemon-reload
    echo "🗑️ 取消安裝完成。自動同步已關閉。"
}

# 判斷輸入參數
case "$1" in
    install)
        check_reqs
        install_daemon
        ;;
    uninstall)
        uninstall_daemon
        ;;
    *)
        echo "用法: $0 {install|uninstall}"
        exit 1
        ;;
esac
