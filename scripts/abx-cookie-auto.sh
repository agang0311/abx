#!/bin/bash
# abx-cookie-auto.sh - 全自动 Cookie 管理系统
# 自动维护 Cookie 仓库，无需手动操作

set -e

ABX_BASE_DIR="${HOME}/.openclaw/abx-sessions"
COOKIE_REPO="${ABX_BASE_DIR}/cookie-repo"
COOKIE_REPO_VERSION=1

mkdir -p "${COOKIE_REPO}/by-domain"
mkdir -p "${COOKIE_REPO}/sync-locks"

# ============================================
# Cookie 仓库结构
# ============================================
# ${COOKIE_REPO}/
#   config.json           - 全局配置
#   by-domain/
#     x.com.json          - x.com 的所有 Cookie
#     github.com.json     - github.com 的所有 Cookie
#   sync-locks/
#     x.com.lock          - 同步锁
#   last-sync.json        - 最后同步时间

# ============================================
# 初始化仓库
# ============================================

init_repo() {
    if [ ! -f "${COOKIE_REPO}/config.json" ]; then
        cat > "${COOKIE_REPO}/config.json" << 'EOF'
{
  "version": 1,
  "auto_sync_interval": 300,
  "check_login_selectors": {
    "x.com": ["[data-testid='SideNav_AccountSwitcher_Button']", "[aria-label='Profile']"],
    "github.com": [".Header-link[href='/login']", ".avatar"],
    "twitter.com": ["[data-testid='SideNav_AccountSwitcher_Button']"]
  },
  "login_pages": {
    "x.com": "https://x.com/i/flow/login",
    "twitter.com": "https://twitter.com/i/flow/login",
    "github.com": "https://github.com/login"
  }
}
EOF
        echo "[cookie-auto] Initialized cookie repo at ${COOKIE_REPO}"
    fi
}

# ============================================
# 从 Chrome 导出 Cookie（使用 CDP）
# ============================================

export_cookies_from_chrome() {
    local port=${1:-9222}
    local domain_filter=$2  # 可选：只导出特定域名
    
    # 使用 Node.js 通过 CDP 获取 Cookie
    node << NODE_EOF 2>/dev/null
const CDP = require('chrome-remote-interface');
const fs = require('fs');
const path = require('path');

async function exportCookies() {
    try {
        const client = await CDP({port: ${port}});
        const {Network} = client;
        
        await Network.enable();
        const {cookies} = await Network.getAllCookies();
        
        // 按域名分组
        const byDomain = {};
        for (const cookie of cookies) {
            if (!byDomain[cookie.domain]) {
                byDomain[cookie.domain] = [];
            }
            byDomain[cookie.domain].push({
                name: cookie.name,
                value: cookie.value,
                domain: cookie.domain,
                path: cookie.path,
                expires: cookie.expires,
                httpOnly: cookie.httpOnly,
                secure: cookie.secure,
                sameSite: cookie.sameSite
            });
        }
        
        // 保存到仓库
        for (const [domain, domainCookies] of Object.entries(byDomain)) {
            const cleanDomain = domain.replace(/^\./, '');
            const filePath = path.join('${COOKIE_REPO}/by-domain', cleanDomain + '.json');
            
            fs.writeFileSync(filePath, JSON.stringify({
                domain: cleanDomain,
                updated_at: new Date().toISOString(),
                cookies: domainCookies
            }, null, 2));
        }
        
        // 更新最后同步时间
        fs.writeFileSync('${COOKIE_REPO}/last-sync.json', JSON.stringify({
            time: new Date().toISOString(),
            port: ${port}
        }));
        
        console.log('Exported ' + cookies.length + ' cookies for ' + Object.keys(byDomain).length + ' domains');
        await client.close();
    } catch (e) {
        console.error('Export failed:', e.message);
        process.exit(1);
    }
}

exportCookies();
NODE_EOF
}

# ============================================
# 注入 Cookie 到 Chrome
# ============================================

import_cookies_to_chrome() {
    local port=${1:-9222}
    local target_domain=$2  # 目标域名，只注入相关 Cookie
    
    # 查找匹配的 Cookie 文件
    local domain_file="${COOKIE_REPO}/by-domain/${target_domain}.json"
    
    # 尝试 www. 前缀
    if [ ! -f "$domain_file" ] && [[ "$target_domain" != www.* ]]; then
        domain_file="${COOKIE_REPO}/by-domain/www.${target_domain}.json"
    fi
    
    # 尝试无前缀
    if [ ! -f "$domain_file" ] && [[ "$target_domain" == www.* ]]; then
        domain_file="${COOKIE_REPO}/by-domain/${target_domain#www.}.json"
    fi
    
    if [ ! -f "$domain_file" ]; then
        echo "[cookie-auto] No stored cookies for ${target_domain}"
        return 0
    fi
    
    echo "[cookie-auto] Injecting cookies for ${target_domain}..."
    
    node << NODE_EOF 2>/dev/null
const CDP = require('chrome-remote-interface');
const fs = require('fs');

async function importCookies() {
    try {
        const cookies = JSON.parse(fs.readFileSync('${domain_file}', 'utf8'));
        const client = await CDP({port: ${port}});
        const {Network} = client;
        
        await Network.enable();
        
        let success = 0;
        let failed = 0;
        
        for (const cookie of cookies.cookies) {
            try {
                // 跳过过期的 Cookie
                if (cookie.expires && cookie.expires !== -1) {
                    const expiresDate = new Date(cookie.expires * 1000);
                    if (expiresDate < new Date()) {
                        continue;  // 已过期，跳过
                    }
                }
                
                await Network.setCookie({
                    name: cookie.name,
                    value: cookie.value,
                    domain: cookie.domain,
                    path: cookie.path || '/',
                    expires: cookie.expires > 0 ? cookie.expires : undefined,
                    secure: cookie.secure,
                    httpOnly: cookie.httpOnly,
                    sameSite: cookie.sameSite
                });
                success++;
            } catch (e) {
                failed++;
            }
        }
        
        console.log('Injected: ' + success + ' cookies, Skipped: ' + failed);
        await client.close();
    } catch (e) {
        console.error('Import failed:', e.message);
    }
}

importCookies();
NODE_EOF
}

# ============================================
# 检查是否已登录（通过检查特定元素）
# ============================================

check_login_status() {
    local port=${1:-9222}
    local domain=$2
    
    # 从配置获取登录检查选择器
    local selectors=$(jq -r ".check_login_selectors[\"${domain}\"] // .check_login_selectors[\"www.${domain}\"] // []" "${COOKIE_REPO}/config.json" 2>/dev/null)
    
    if [ -z "$selectors" ] || [ "$selectors" = "[]" ]; then
        echo "unknown"
        return 0
    fi
    
    # 使用 agent-browser 检查元素
    local is_logged_in=false
    
    for selector in $(echo "$selectors" | jq -r '.[]'); do
        if agent-browser connect "$port" 2>/dev/null && agent-browser eval "document.querySelector('${selector}') !== null" 2>/dev/null | grep -q "true"; then
            is_logged_in=true
            break
        fi
    done
    
    if [ "$is_logged_in" = "true" ]; then
        echo "logged_in"
    else
        echo "not_logged_in"
    fi
}

# ============================================
# 自动同步任务（后台运行）
# ============================================

auto_sync_daemon() {
    local interval=${1:-300}  # 默认 5 分钟
    
    echo "[cookie-auto] Starting auto-sync daemon (interval: ${interval}s)"
    
    while true; do
        sleep "$interval"
        
        # 检查是否有 Chrome 在运行
        for session_file in "${ABX_BASE_DIR}/sessions"/*.json; do
            [ -f "$session_file" ] || continue
            
            local port=$(jq -r '.port // empty' "$session_file")
            local pid=$(jq -r '.pid // empty' "$session_file")
            
            if [ -n "$port" ] && [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                # 检查是否被锁定
                local session_id=$(basename "$session_file" .json)
                if [ ! -f "${COOKIE_REPO}/sync-locks/${session_id}.lock" ]; then
                    # 导出 Cookie
                    export_cookies_from_chrome "$port" >/dev/null 2>&1 || true
                fi
            fi
        done
    done
}

# ============================================
# 智能 Cookie 处理（主入口）
# ============================================

smart_cookie_handle() {
    local action=$1
    local port=$2
    local url=$3
    
    init_repo
    
    case "$action" in
        before-open)
            # 打开网页前：注入 Cookie
            local domain=$(echo "$url" | sed -E 's|^https?://||' | sed -E 's|/.*||' | sed -E 's|:.*||')
            echo "[cookie-auto] Preparing cookies for ${domain}..."
            import_cookies_to_chrome "$port" "$domain"
            ;;
            
        after-login)
            # 登录后：立即保存 Cookie
            echo "[cookie-auto] Login detected, saving cookies..."
            export_cookies_from_chrome "$port"
            ;;
            
        on-close)
            # 关闭前：保存 Cookie
            echo "[cookie-auto] Saving cookies before close..."
            export_cookies_from_chrome "$port"
            ;;
            
        check)
            # 检查登录状态
            local domain=$(echo "$url" | sed -E 's|^https?://||' | sed -E 's|/.*||')
            check_login_status "$port" "$domain"
            ;;
            
        sync-now)
            # 立即同步
            export_cookies_from_chrome "$port"
            ;;
            
        start-daemon)
            # 启动后台同步
            auto_sync_daemon "${2:-300}"
            ;;
    esac
}

# ============================================
# 主入口
# ============================================

init_repo

if [ $# -eq 0 ]; then
    cat << 'EOF'
abx-cookie-auto - 全自动 Cookie 管理系统

用法:
  abx-cookie-auto before-open <port> <url>    # 打开网页前注入 Cookie
  abx-cookie-auto after-login <port>          # 登录后保存 Cookie
  abx-cookie-auto on-close <port>             # 关闭前保存 Cookie
  abx-cookie-auto check <port> <url>          # 检查登录状态
  abx-cookie-auto sync-now <port>             # 立即同步 Cookie
  abx-cookie-auto start-daemon [interval]     # 启动后台自动同步

集成到 abx:
  在 abx 脚本中调用此脚本，实现全自动 Cookie 管理

特点:
  ✓ 自动注入：打开网页前自动注入已保存的 Cookie
  ✓ 自动保存：检测到登录后自动保存到仓库
  ✓ 定时同步：后台任务定期更新 Cookie
  ✓ 按域名管理：不同网站独立存储
  ✓ 过期检查：自动跳过过期 Cookie
EOF
    exit 0
fi

smart_cookie_handle "$@"
