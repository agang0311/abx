#!/bin/bash
# abx-cookie-manager.sh - 简化版 Cookie 管理
# 原理：直接复制 Chrome 的 Cookie 数据库文件

ABX_BASE_DIR="${HOME}/.openclaw/abx-sessions"
MASTER_DIR="${ABX_BASE_DIR}/chrome-data/shared"
COOKIE_BACKUP="${ABX_BASE_DIR}/cookies-backup"

mkdir -p "$COOKIE_BACKUP"

# ============================================
# 保存 Master Cookie
# ============================================

save_master_cookies() {
    local source_dir=${1:-"$MASTER_DIR"}
    local backup_name=${2:-"master-$(date +%Y%m%d-%H%M%S)"}
    
    if [ ! -d "$source_dir/Default" ]; then
        echo "[cookie] Master Chrome data not found: $source_dir"
        return 1
    fi
    
    # 复制关键文件
    mkdir -p "${COOKIE_BACKUP}/${backup_name}"
    
    cp "$source_dir/Default/Cookies" "${COOKIE_BACKUP}/${backup_name}/" 2>/dev/null || true
    cp "$source_dir/Default/Login Data" "${COOKIE_BACKUP}/${backup_name}/" 2>/dev/null || true
    cp "$source_dir/Default/Local Storage/"* "${COOKIE_BACKUP}/${backup_name}/" 2>/dev/null || true
    
    # 记录域名
    echo "$(date) - Saved from $source_dir" > "${COOKIE_BACKUP}/${backup_name}/.meta"
    
    # 更新最新链接
    ln -sfn "${backup_name}" "${COOKIE_BACKUP}/latest"
    
    echo "[cookie] Saved master cookies: ${backup_name}"
}

# ============================================
# 应用 Cookie 到 Session
# ============================================

apply_cookies() {
    local session_id=$1
    local source=${2:-"${COOKIE_BACKUP}/latest"}
    
    if [ -L "$source" ]; then
        source="${COOKIE_BACKUP}/$(readlink "$source")"
    fi
    
    if [ ! -d "$source" ]; then
        echo "[cookie] No cookie backup found. Run 'save' first."
        return 1
    fi
    
    local target_dir="${ABX_BASE_DIR}/chrome-data/${session_id}"
    
    if [ ! -d "$target_dir/Default" ]; then
        echo "[cookie] Session not initialized yet: $session_id"
        echo "[cookie] Cookie will be applied when Chrome starts"
        # 创建标记文件，启动时自动应用
        mkdir -p "$target_dir"
        touch "$target_dir/.apply-cookie-on-start"
        cp -r "$source" "$target_dir/cookie-template/" 2>/dev/null || true
        return 0
    fi
    
    # Chrome 必须在关闭状态才能复制 Cookie 文件
    local pid_file="${ABX_BASE_DIR}/sessions/${session_id}.json"
    if [ -f "$pid_file" ]; then
        local pid=$(jq -r '.pid // empty' "$pid_file" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "[cookie] Warning: Chrome is running. Please close it first:"
            echo "  abx --close $session_id"
            echo "Or cookie will be applied on next start"
            # 设置标记
            touch "$target_dir/.apply-cookie-on-start"
            cp -r "$source" "$target_dir/cookie-template/" 2>/dev/null || true
            return 0
        fi
    fi
    
    # 复制 Cookie 文件
    echo "[cookie] Applying cookies to session: $session_id"
    cp "${source}/Cookies" "$target_dir/Default/" 2>/dev/null || true
    cp "${source}/Login Data" "$target_dir/Default/" 2>/dev/null || true
    
    # 复制 Local Storage
    if [ -d "${source}/Local Storage" ]; then
        cp -r "${source}/Local Storage/"* "$target_dir/Default/Local Storage/" 2>/dev/null || true
    fi
    
    rm -f "$target_dir/.apply-cookie-on-start"
    echo "[cookie] Cookies applied to $session_id"
}

# ============================================
# 自动应用（在 Chrome 启动前调用）
# ============================================

auto_apply_if_needed() {
    local session_id=$1
    local target_dir="${ABX_BASE_DIR}/chrome-data/${session_id}"
    
    if [ -f "$target_dir/.apply-cookie-on-start" ] && [ -d "$target_dir/cookie-template" ]; then
        echo "[cookie] Auto-applying saved cookies..."
        cp "$target_dir/cookie-template/Cookies" "$target_dir/Default/" 2>/dev/null || true
        cp "$target_dir/cookie-template/Login Data" "$target_dir/Default/" 2>/dev/null || true
        rm -f "$target_dir/.apply-cookie-on-start"
    fi
}

# ============================================
# 主命令
# ============================================

case "${1:-}" in
    save)
        save_master_cookies "${2:-}" "${3:-}"
        ;;
    apply)
        apply_cookies "${2:-}" "${3:-}"
        ;;
    auto-apply)
        auto_apply_if_needed "${2:-}"
        ;;
    list)
        echo "Available cookie backups:"
        ls -la "${COOKIE_BACKUP}/" 2>/dev/null | grep -E "^d" | awk '{print $9}' | grep -v "^\\.$\\|\\.\\.$" || echo "  None"
        ;;
    *)
        cat << 'EOF'
abx-cookie-manager - Cookie 共享管理

原理：
  1. 在 Master Chrome 登录（共享 Chrome 或指定 session）
  2. 保存 Cookie：abx-cookie save
  3. 应用到其他 session：abx-cookie apply <session-id>

用法：
  save [chrome-data-dir] [name]     - 保存当前 Chrome 的 Cookie
  apply <session-id> [source]       - 应用 Cookie 到指定 session
  list                              - 列出保存的 Cookie 备份
  auto-apply <session-id>           - 自动应用（启动时调用）

示例：
  # 1. 启动 master 并登录
  abx open https://x.com
  # ... 手动登录 ...
  
  # 2. 保存 Cookie
  abx-cookie save
  
  # 3. 应用到其他 session
  ABX_ISOLATED=1 abx open https://x.com  # 新 session
  abx-cookie apply session_xxx           # 应用 cookie
  
  # 现在新 session 也是登录状态

注意：
  - Cookie 包含登录态，请妥善保管
  - 应用 Cookie 时目标 Chrome 必须关闭
  - 支持自动应用（设置标记后下次启动生效）

EOF
        ;;
esac
