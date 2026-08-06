# selenium_tests_prod — 生产环境只读冒烟测试

直接测试**部署在生产环境**的 Flutter Web 页面（Selenium），与
`frontend/selenium_tests/`（本地 mock 环境测试）完全隔离：

| | `selenium_tests/` | `selenium_tests_prod/`（本目录） |
|---|---|---|
| 目标 | 本地 mock backend (`localhost:9000`) | 真实生产部署（默认 `https://home.chenkaidi.top:507`、`http://10.0.0.122:8080`） |
| 操作 | 可读写（容器启停等） | **只读**（页面可访问、渲染、登录、导航），对生产零影响 |
| 登录凭据 | 默认 admin/password | 必须环境变量注入，缺失则跳过登录测试 |
| 多环境 | 单 URL | `TEST_PROD_URLS` 逗号分隔，每个环境独立跑一遍测试 |

## 快速开始

```bash
cd frontend/selenium_tests_prod

# 登录测试需要生产凭据（缺失时相关测试自动跳过）
export TEST_USERNAME=admin
export TEST_PASSWORD=your_prod_password

./run_tests.sh
```

凭据注入优先级：**环境变量 > 本目录 `.env` 文件 > launchctl（macOS GUI 会话）**。
不想每次 export 时，可写入 `.env`（已被 .gitignore 忽略，不会入库）：

```bash
cat > .env <<'EOF'
TEST_USERNAME=admin
TEST_PASSWORD=your_prod_password
EOF
```

**多套环境凭据不同**：`TEST_USERNAME`/`TEST_PASSWORD` 只覆盖一套环境（默认）。
其他环境按主机名覆盖，`TEST_USERNAME_<host>` / `TEST_PASSWORD_<host>`
（主机名中 `.` 替换为 `_`）。例如 `http://10.0.0.122:8080`：

```bash
cat >> .env <<'EOF'
TEST_USERNAME_10_0_0_122=admin
TEST_PASSWORD_10_0_0_122=other_password
EOF
```

登录 fixture 按浏览器当前打开的 URL 主机名自动选择凭据
（见 `config.per_host_creds`），凭据全部缺失时脚本会打印醒目警告，
登录相关测试自动跳过（`-rs` 显示原因）。

## 运行选项

```bash
./run_tests.sh                                  # 默认两个生产环境
./run_tests.sh --urls=https://home.chenkaidi.top:507   # 指定单个环境
./run_tests.sh --headed                          # 显示浏览器窗口（调试）
./run_tests.sh --html                            # 生成 report.html
./run_tests.sh -k nav                            # 按关键字筛选
```

环境变量：

- `TEST_PROD_URLS` — 生产环境地址，逗号分隔（默认如上）
- `TEST_USERNAME` / `TEST_PASSWORD` — Portainer 登录凭据（**必须注入，禁止硬编码**）
- `TEST_HEADLESS` / `TEST_BROWSER` / `TEST_DEBUG` — 无头 / 浏览器 / 调试模式

## 测试内容

### 只读冒烟（`tests/test_prod_smoke.py`，无写操作）

1. **连通性**：至少一个生产环境可达
2. **页面渲染**：flutter-view 出现、画布/语义树非空、无 JS 脚本错误
3. **登录**：凭据注入时验证登录成功、导航栏可见
4. **导航**：依次切换 Dashboard / Containers / Resources / Settings，
   每页均渲染出内容且无 JS 错误

### 网页授权添加服务器（`tests/test_prod_connect.py`，**写操作**）

在源服务器上通过网页授权流程添加目标服务器（默认在
`home.chenkaidi.top:507` 添加 `10.0.0.122:8080`）：

```
登录源服务器 → Settings → 网页授权添加 → 输入目标 URL → 探测/注册
→ 确认 → 目标服务器授权页登录/确认 → 302 回跳 → token 交换 → 列表新增
```

- 仅在有凭据时运行（缺失自动跳过）
- **会产生写操作**：目标服务器注册 public client、签发独立 apikey；
  源服务器本地列表新增记录。同 URL 重复添加覆盖 apikey（幂等），可重复运行
- 源/目标服务器可用环境变量覆盖：
  `TEST_CONNECT_SOURCE_URL` / `TEST_CONNECT_TARGET_URL`

**当前生产部署下的已知限制（测试会 skip 并说明原因）：**

1. **Mixed Content（前端已提前提示）**：https 源页面请求 http 目标
   （10.0.0.122:8080）被浏览器阻止，探测必然失败。前端在**输入 URL 时**
   即提示（`errorConnectMixedContent` 红色错误 + 禁用"继续"按钮），
   不再等点击后才失败。目标服务器配置 https 后提示自动消失，走成功路径。
   测试检测到提示时断言其出现与按钮禁用，然后按产品限制跳过。
2. **Private Network Access**：公网源页面请求私网目标被 Chrome 阻止；
   后端 FastAPI 对 PNA preflight 返回 400 "Disallowed CORS private-network"，
   需在 CORS 响应中增加 `Access-Control-Allow-Private-Network: true` 头。
3. **SSL 证书过期**：`home.chenkaidi.top:507` 的证书已过期，
   真实浏览器访问有安全警告（测试通过 `--ignore-certificate-errors` 绕过）。

上述问题解决后（目标上 https + 后端 PNA 头），
本测试将自动走完整成功路径。

只运行某一组：

```bash
pytest tests/test_prod_smoke.py     # 只读冒烟
pytest tests/test_prod_connect.py   # 网页授权添加（写操作）
```

## 设计说明

- 每个测试通过 `pytest_generate_tests` 对每个可达的生产环境参数化运行，
  结果中按 URL 标注环境，可区分哪套环境失败。
- 浏览器驱动逻辑（chromedriver 版本匹配、Flutter 语义树启用）沿用自
  `frontend/selenium_tests/conftest.py`，如有修复请同步两边。
- 语义树通过 URL 参数 `?enable_semantics=true` 启用，使 Flutter widget
  可通过 DOM 定位。
