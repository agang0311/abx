# abx - Agent Browser CLI

智能浏览器自动化命令行工具，支持多 Session 隔离、Cookie 自动管理。

## ✨ 特性

- 🚀 **浏览器自动化** - 基于 Chrome DevTools Protocol (CDP)
- 🔒 **Session 隔离** - 每个 session 独立的 Chrome 实例
- 🍪 **Cookie 自动管理** - 自动注入/保存/同步
- 📦 **多模式支持** - 隔离模式/共享模式
- 🤖 **AI 友好** - 专为 AI agent 设计

## 🚀 快速开始

### 安装

```bash
# 克隆仓库
git clone https://github.com/agang311/abx.git
cd abx

# 添加别名
echo 'alias abx="./scripts/abx"' >> ~/.zshrc
source ~/.zshrc
```

### 依赖

- Python 3.10+
- Google Chrome 浏览器
- Node.js (用于 agent-browser)

### 基本使用

```bash
# 打开网页
abx open https://x.com

# 获取页面快照
abx snapshot

# 点击元素
abx click @e5

# 截图
abx screenshot result.png

# 无头模式（后台运行）
ABX_HEADLESS=1 abx open https://x.com
abx --headless open https://x.com
```

## 📖 文档

详细使用手册：[docs/README.md](docs/README.md)

### 常用命令

| 命令 | 说明 |
|------|------|
| `abx open <url>` | 打开网页 |
| `abx snapshot` | 获取页面快照 |
| `abx click @ref` | 点击元素 |
| `abx fill @ref "text"` | 填充表单 |
| `abx screenshot` | 截图 |
| `abx --list` | 查看 sessions |
| `abx --close-all` | 关闭所有 sessions |

## 🍪 Cookie 自动管理

abx 会自动管理 Cookie：

1. **自动注入** - 打开网页前从仓库注入 Cookie
2. **自动保存** - 检测到登录后保存到仓库
3. **后台同步** - 定期同步所有 Chrome 实例

Cookie 仓库位置：`~/.openclaw/abx-sessions/cookie-repo/`

## 🔧 高级功能

### Session 管理

```bash
# 隔离模式（默认）
ABX_SESSION_ID="bot-1" abx open https://x.com
ABX_SESSION_ID="bot-2" abx open https://x.com

# 共享模式
ABX_SHARED=1 abx open https://x.com

# 无头模式（后台运行，无窗口）
ABX_HEADLESS=1 abx open https://x.com
abx --headless open https://x.com

# 无头 + 隔离 + 多账号
ABX_HEADLESS=1 ABX_SESSION_ID="bot-1" abx open https://x.com
ABX_HEADLESS=1 ABX_SESSION_ID="bot-2" abx open https://x.com
```

### 后台同步

```bash
# 启动 Cookie 同步守护进程
./scripts/abx-cookie-daemon.sh start

# 查看状态
./scripts/abx-cookie-daemon.sh status
```

## 📁 项目结构

```
abx/
├── scripts/
│   ├── abx                      # 主脚本
│   ├── abx-cookie-auto.sh       # Cookie 自动管理
│   ├── abx-cookie-daemon.sh     # 后台同步
│   └── ...
├── docs/
│   └── README.md                # 完整使用手册
└── README.md                    # 项目说明
```

## 🆚 对比

| 特性 | abx | Scrapling |
|------|-----|-----------|
| 使用方式 | 命令行 | Python 代码 |
| 适用场景 | 快速测试/自动化 | 编程式爬虫 |
| Cookie 管理 | 全自动 | 需手动处理 |
| Session 管理 | 自动隔离 | 需手动配置 |

## 📝 相关项目

- [agent-browser](https://github.com/vercel-labs/agent-browser) - 底层 CDP 工具
- [Scrapling](https://github.com/D4Vinci/Scrapling) - Python 爬虫框架
- [XiaohongshuSkills](https://github.com/white0dew/XiaohongshuSkills) - 小红书自动化工具

## 📄 License

MIT License

## 👨‍💻 Author

[@agang311](https://github.com/agang311)

---

**完整文档**: [docs/README.md](docs/README.md)
