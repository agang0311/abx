# abx 完整使用手册

**工具**: Agent Browser 快捷命令工具  
**位置**: `~/.openclaw/workspace/scripts/abx`  
**功能**: 浏览器自动化 CLI 工具  
**协议**: Chrome DevTools Protocol (CDP)  
**状态**: ✅ 已安装并可用

---

## 目录

1. [快速开始](#快速开始)
2. [模式说明](#模式说明)
3. [常用命令](#常用命令)
4. [Cookie 自动管理](#cookie-自动管理)
5. [Session 管理](#session-管理)
6. [完整命令参考](#完整命令参考)
7. [故障排查](#故障排查)
8. [最佳实践](#最佳实践)

---

## 快速开始

### 1. 添加别名

```bash
echo 'alias abx="~/.openclaw/workspace/scripts/abx"' >> ~/.zshrc
source ~/.zshrc
```

### 2. 立即使用

```bash
# 打开网页（默认隔离模式）
abx open https://x.com

# 获取页面快照
abx snapshot

# 点击元素
abx click @e5

# 截图
abx screenshot result.png
```

### 3. 查看帮助

```bash
abx --help
```

---

## 模式说明

### 隔离模式 vs 共享模式

| 模式 | 含义 | 适用场景 |
|------|------|----------|
| **隔离模式**（默认） | 每个 session 独立的 Chrome | 多账号、并发操作、自动化脚本 |
| **共享模式** | 所有 session 共用 1 个 Chrome | 单人使用、内存受限、简单任务 |

### 隔离模式（推荐）

```
Session A ──→ Chrome A (9223)
Session B ──→ Chrome B (9224)
Session C ──→ Chrome C (9225)
```

- ✅ 互不干扰，适合并发操作
- ✅ 多账号场景推荐
- ✅ 端口 9223-9322（动态分配）

```bash
# 默认就是隔离模式
abx open https://x.com

# 指定 session ID
ABX_SESSION_ID="bot-1" abx open https://x.com
ABX_SESSION_ID="bot-2" abx open https://x.com
```

### 共享模式

```
Session A ──┐
Session B ──┼──→ Chrome (9222)
Session C ──┘
```

- ⚠️ 所有 session 共用 1 个 Chrome
- ⚠️ 会互相覆盖页面
- ✅ 省内存，单人简单任务可用

```bash
# 需要指定
ABX_SHARED=1 abx open https://x.com
# 或
abx --shared open https://x.com
```

### Cookie 管理

**注意**: Cookie 在两种模式下都从中央仓库自动注入，都能自动登录。

```
Cookie 仓库 (~/.openclaw/abx-sessions/cookie-repo/by-domain/)
    ↑ 自动保存（检测到登录）
    ↓ 自动注入（打开网页前）
Chrome 实例（共享或隔离）
```

---

## 常用命令

### 基础操作

```bash
# 打开网页
abx open https://x.com/home

# 获取页面快照（AI 专用）
abx snapshot

# 点击元素
abx click @e5

# 填充表单
abx fill @e11 "评论内容"

# 按键
abx press Enter
abx press "Control+a"

# 截图
abx screenshot result.png
```

### 获取信息

```bash
# 获取页面标题
abx get title

# 获取当前 URL
abx get url

# 获取元素文本
abx get text @e5

# 获取元素数量
abx get count "article"
```

### 高级操作

```bash
# 双击
abx dblclick @e5

# 悬停
abx hover @e10

# 滚动
abx scroll down 500
abx scrollintoview @element

# 拖拽
abx drag @src @target

# 上传文件
abx upload @input "/path/to/file.jpg"
```

### 选择器类型

```bash
# Ref 选择器（推荐，来自 snapshot）
abx snapshot
abx click @e5

# CSS 选择器
abx click "#submit"
abx fill ".input-class" "text"

# XPath
abx click "//button[text()='Submit']"
```

---

## Cookie 自动管理

### 工作原理

```
打开网页前 → 自动注入 Cookie → 页面加载
检测到登录 → 自动保存 Cookie → 更新仓库
后台定时 → 自动同步所有 Chrome → 保持最新
```

### 自动注入

```bash
abx open https://x.com
```

1. 提取域名：`x.com`
2. 查找：`cookie-repo/by-domain/x.com.json`
3. 通过 CDP 注入 Cookie
4. 页面加载（已是登录状态）
5. 检测登录状态
6. 如果登录成功 → 异步保存最新 Cookie

### Cookie 仓库

```
~/.openclaw/abx-sessions/cookie-repo/
├── by-domain/
│   ├── x.com.json             # x.com Cookie
│   ├── github.com.json        # GitHub Cookie
│   └── ...
├── config.json                # 登录检测配置
└── last-sync.json             # 最后同步记录
```

### Cookie 文件格式

```json
{
  "domain": "x.com",
  "updated_at": "2026-03-12T21:30:00.000Z",
  "cookies": [
    {
      "name": "auth_token",
      "value": "xxxxxxxx...",
      "domain": ".x.com",
      "path": "/",
      "expires": 1735689600,
      "httpOnly": true,
      "secure": true
    }
  ]
}
```

### 后台同步（可选）

```bash
# 启动后台定时同步（每 5 分钟）
~/.openclaw/workspace/scripts/abx-cookie-daemon.sh start

# 查看状态
~/.openclaw/workspace/scripts/abx-cookie-daemon.sh status

# 停止
~/.openclaw/workspace/scripts/abx-cookie-daemon.sh stop
```

---

## Session 管理

### 查看 Sessions

```bash
abx --list
```

输出示例：
```
Active abx sessions:
====================
shared               | Port: 9222 | Status: ✓ running | Type: SHARED
--------------------
session_a1b2c3d4     | Port: 9223 | Status: ✓ running | Type: ISOLATED
session_e5f6g7h8     | Port: 9224 | Status: ✓ running | Type: ISOLATED
--------------------
Total: 3 session(s)

Mode:
  ISOLATED - 独立 Chrome（默认，互不干扰）
  SHARED   - 所有 session 共用（ABX_SHARED=1）
```

### 关闭 Sessions

```bash
# 关闭指定 session
abx --close session_a1b2c3d4

# 关闭所有
abx --close-all

# 清理死掉的 session
abx --cleanup
```

### Session 命名

```bash
# 默认自动推断
abx open https://x.com  # session_id: session_a1b2c3d4

# 手动指定（用于多账号）
ABX_SESSION_ID="twitter-acc-1" abx open https://x.com
ABX_SESSION_ID="twitter-acc-2" abx open https://x.com
```

---

## 完整命令参考

### 主命令

| 命令 | 说明 | 示例 |
|------|------|------|
| `abx open <url>` | 打开网页 | `abx open https://x.com` |
| `abx snapshot` | 获取页面快照 | `abx snapshot` |
| `abx click @ref` | 点击元素 | `abx click @e5` |
| `abx fill @ref "text"` | 填充表单 | `abx fill @e11 "text"` |
| `abx press <key>` | 按键 | `abx press Enter` |
| `abx screenshot [path]` | 截图 | `abx screenshot result.png` |
| `abx get title` | 获取标题 | `abx get title` |
| `abx get url` | 获取 URL | `abx get url` |

### 管理命令

| 命令 | 说明 |
|------|------|
| `abx --list` | 列出所有活跃 session |
| `abx --close <id>` | 关闭指定 session |
| `abx --close-all` | 关闭所有 session |
| `abx --cleanup` | 清理死掉的 session |
| `abx --help` | 显示帮助 |
| `abx --shared` | 使用共享模式 |

### 环境变量

| 变量 | 说明 | 示例 |
|------|------|------|
| `ABX_SHARED=1` | 使用共享模式 | `ABX_SHARED=1 abx open ...` |
| `ABX_SESSION_ID=<name>` | 指定 session 名称 | `ABX_SESSION_ID="bot-1" abx ...` |

---

## 故障排查

### Cookie 未注入

```bash
# 检查仓库中是否有该域名
ls ~/.openclaw/abx-sessions/cookie-repo/by-domain/ | grep x.com

# 手动触发同步
~/.openclaw/workspace/scripts/abx-cookie-auto.sh sync-now 9222
```

### 登录状态检测失败

```bash
# 检查配置中的选择器
jq '.check_login_selectors["x.com"]' \
   ~/.openclaw/abx-sessions/cookie-repo/config.json

# 手动验证
abx open https://x.com
abx eval "document.querySelector('[data-testid=\"...\"]') !== null"
```

### 端口冲突

```bash
# 查看占用端口的 Chrome
lsof -Pi :9222-9322 -sTCP:LISTEN

# 关闭所有 session
abx --close-all
```

### Chrome 启动失败

```bash
# 检查 Chrome 是否运行
ps aux | grep chrome

# 重启
abx --close-all
abx open https://x.com
```

---

## 最佳实践

### 1. 使用隔离模式（默认）

```bash
# 推荐：每个 session 独立
abx open https://x.com

# 多账号场景
ABX_SESSION_ID="twitter-acc-1" abx open https://x.com
ABX_SESSION_ID="twitter-acc-2" abx open https://x.com
```

### 2. Cookie 自动管理

```bash
# 首次打开并登录
abx open https://x.com
# ... 手动登录 ...
# Cookie 自动保存

# 后续使用
abx open https://x.com  # ✓ 自动注入 Cookie，已登录
```

### 3. 定期清理

```bash
# 每周清理死掉的 session
abx --cleanup
```

### 4. 使用 Ref 选择器

```bash
# 先获取快照
abx snapshot

# 使用 ref 点击
abx click @e5

# 比 CSS 选择器更稳定
```

### 5. 脚本化

```bash
#!/bin/bash
# auto-twitter.sh

# 打开 Twitter
abx open https://x.com/home

# 等待加载
sleep 3

# 截图
abx screenshot "twitter-$(date +%Y%m%d-%H%M).png"

# 提取推文文本
abx eval 'Array.from(document.querySelectorAll("[data-testid=tweetText]")).map(t => t.innerText).join("\n---\n")' > tweets.txt

echo "已保存推文截图和文本"
```

---

## 与 Scrapling 对比

| 特性 | abx | Scrapling |
|------|-----|-----------|
| **使用方式** | 命令行 | Python 代码 |
| **适用场景** | 快速测试/自动化 | 编程式爬虫 |
| **浏览器控制** | 外接 Chrome CDP | 内置浏览器 |
| **学习成本** | 简单命令 | 需要写代码 |
| **Cookie 管理** | 全自动 | 需手动处理 |
| **Session 管理** | 自动隔离 | 需手动配置 |

**推荐**:
- 快速查看/测试 → **abx**
- 编写爬虫程序 → **Scrapling**

---

## 相关文件

- **主脚本**: `~/.openclaw/workspace/scripts/abx`
- **Cookie 管理**: `~/.openclaw/workspace/scripts/abx-cookie-auto.sh`
- **后台同步**: `~/.openclaw/workspace/scripts/abx-cookie-daemon.sh`
- **本文档**: `~/.openclaw/workspace/docs/tools/abx-manual.md`
- **Cookie 仓库**: `~/.openclaw/abx-sessions/cookie-repo/`

---

**最后更新**: 2026-03-13  
**状态**: ✅ 已安装并可用  
**文档版本**: 1.0
