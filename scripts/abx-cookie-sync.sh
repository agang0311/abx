#!/bin/bash
# abx-cookie-sync.sh - Cookie 同步管理
# 实现：Master Chrome 登录，其他 session 自动同步 Cookie

set -e

ABX_BASE_DIR="${HOME}/.openclaw/abx-sessions"
COOKIE_STORE="${ABX_BASE_DIR}/cookies"

mkdir -p "$COOKIE_STORE"

# ============================================
# 从 Chrome 导出 Cookie
# ============================================

export_cookies() {
    local port=${1:-9222}
    local domain=$2  # 可选：只导出特定域名的 cookie
    local output_file="${COOKIE_STORE}/cookies-$(date +%Y%m%d-%H%M%S).json"
    
    echo "[cookie-sync] Exporting cookies from Chrome (port: $port)..."
    
    # 使用 agent-browser eval 获取 cookie
    agent-browser connect "$port" 2>/dev/null || true
    sleep 0.5
    
    # 获取所有 cookie
    local cookies=$(agent-browser eval '
        (async () => {
            const cookies = await document.cookie;
            const cookieList = document.cookie.split("; ").map(c => {
                const [name, value] = c.split("=");
                return {name, value, domain: location.hostname};
            });
            return JSON.stringify(cookieList);
        })()
    ' 2>/dev/null || echo "[]")
    
    # 保存到文件
    echo "$cookies" > "$output_file"
    echo "[cookie-sync] Exported to: $output_file"
    
    # 更新最新链接
    ln -sf "$output_file" "${COOKIE_STORE}/latest.json"
    
    echo "$output_file"
}

# ============================================
# 导入 Cookie 到 Chrome
# ============================================

import_cookies() {
    local port=${1:-9222}
    local cookie_file=${2:-"${COOKIE_STORE}/latest.json"}
    
    if [ ! -f "$cookie_file" ]; then
        echo "[cookie-sync] No cookie file found: $cookie_file"
        return 1
    fi
    
    echo "[cookie-sync] Importing cookies to Chrome (port: $port)..."
    
    agent-browser connect "$port" 2>/dev/null || true
    sleep 0.5
    
    # 读取 cookie 并设置
    local cookies=$(cat "$cookie_file")
    
    # 使用 JavaScript 设置 cookie
    agent-browser eval "
        (async () => {
            const cookies = ${cookies};
            for (const c of cookies) {
                if (c.name && c.value) {
                    document.cookie = '\${c.name}=\${c.value}; domain=\${c.domain}; path=/';
                }
            }
            return 'Imported ' + cookies.length + ' cookies';
        })()
    " 2>/dev/null || echo "Import failed"
    
    echo "[cookie-sync] Cookies imported"
}

# ============================================
# 使用 Playwright 方式导出/导入（更可靠）
# ============================================

export_cookies_playwright() {
    local port=${1:-9222}
    local output="${COOKIE_STORE}/cookies-latest.json"
    
    # 使用 Node.js 脚本通过 CDP 获取 cookie
    node << EOF
const CDP = require('chrome-remote-interface');

async function getCookies() {
    const client = await CDP({port: $port});
    const {Network} = client;
    
    await Network.enable();
    const {cookies} = await Network.getAllCookies();
    
    fs.writeFileSync('$output', JSON.stringify(cookies, null, 2));
    console.log('Exported ' + cookies.length + ' cookies');
    
    await client.close();
}

getCookies().catch(console.error);
EOF
}

import_cookies_playwright() {
    local port=${1:-9222}
    local cookie_file=${2:-"${COOKIE_STORE}/cookies-latest.json"}
    
    if [ ! -f "$cookie_file" ]; then
        echo "No cookie file found"
        return 1
    fi
    
    node << EOF
const CDP = require('chrome-remote-interface');
const fs = require('fs');

async function setCookies() {
    const cookies = JSON.parse(fs.readFileSync('$cookie_file', 'utf8'));
    const client = await CDP({port: $port});
    const {Network} = client;
    
    await Network.enable();
    
    for (const cookie of cookies) {
        try {
            await Network.setCookie({
                name: cookie.name,
                value: cookie.value,
                domain: cookie.domain,
                path: cookie.path || '/',
                secure: cookie.secure,
                httpOnly: cookie.httpOnly,
                sameSite: cookie.sameSite
            });
        } catch (e) {
            // 忽略单个 cookie 错误
        }
    }
    
    console.log('Imported ' + cookies.length + ' cookies');
    await client.close();
}

setCookies().catch(console.error);
EOF
}

# ============================================
# 主逻辑
# ============================================

case "${1:-}" in
    export)
        export_cookies "${2:-}" "${3:-}"
        ;;
    import)
        import_cookies "${2:-}" "${3:-}"
        ;;
    export-pw)
        export_cookies_playwright "${2:-}"
        ;;
    import-pw)
        import_cookies_playwright "${2:-}"
        ;;
    sync)
        # 导出 master 的 cookie，导入到指定 port
        echo "[cookie-sync] Syncing cookies..."
        export_cookies "${2:-9222}"
        import_cookies "${3:-9223}" "${COOKIE_STORE}/latest.json"
        ;;
    *)
        echo "Usage: $0 {export|import|sync} [port] [file/domain]"
        echo ""
        echo "Commands:"
        echo "  export [port]              - Export cookies from Chrome"
        echo "  import [port] [file]       - Import cookies to Chrome"
        echo "  sync [master-port] [target-port]  - Sync cookies between Chrome instances"
        echo ""
        echo "Examples:"
        echo "  $0 export 9222                    # Export from master"
        echo "  $0 import 9223                    # Import to session"
        echo "  $0 sync 9222 9223                 # Sync from master to session"
        ;;
esac
