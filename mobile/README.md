# 岐黄学堂 · 移动端（tcm_mobile）

中医学院**学员端**的 iOS 客户端，基于 **Mob**（BEAM-on-device）构建。

Mob 把完整的 Erlang/OTP 运行时打进 iOS App：界面与业务逻辑全部用 Elixir
编写，渲染为原生 SwiftUI 组件，无需写 Swift。开发期支持 `mix mob.connect`
热连设备、`mix mob.watch` 保存即热推。

> 当前仅保留 iOS 版本；Android 原生工程已移除（如需恢复见文末）。

## 功能（按学员端组织）

底部 4 个 Tab 栈 + 栈式详情导航：

| Tab | 功能 |
| --- | --- |
| 首页 | 学习统计、学习工具入口（测验/问答/模拟患者/MDT/错题/通知）、课程分类、热门课程 |
| 课程 | 课程列表（分类筛选 + 搜索）、课程详情、课时学习（正文 + 随堂测验 + 进度） |
| 学习 | 我的学习（在学课程进度）、测验考试、错题本、模拟患者、MDT、学习资料 |
| 我的 | 学员信息、通知、学习资料、关于、设置、帮助、退出登录 |

独立页面：学员登录、课程详情、课时学习、测验作答与结果解析、学习问答
（本地 AI）、模拟患者接诊与临床推理报告、MDT 会诊房间、通知中心、资料下载。

**学习资料（PDF）**：点按进入预览页，用 `WebView` + pdf.js 内嵌渲染 PDF；
「下载到本地 / 用系统打开」通过 `Mob.Device.open_url/1` 交给系统原生下载管理器
/ 查看器处理。

## 数据层

离线优先：`TcmMobile.Data.Catalog` 提供与后端种子一致的示例课程/题库/病案，
`TcmMobile.Store`（GenServer）持有会话与学习状态，`TcmMobile.Api` 是唯一数据
入口。

- `source: :remote`（默认）：**登录 / 身份走本地 Phoenix**，token 持久化在
  `Mob.State`，启动时自动恢复会话；课程目录、选课、课时进度、首页统计、通知、
  考试记录也全部来自后端 `/api/student/*`（见下表）。
- `source: :local`：纯离线演示账号，业务数据来自 `Data.Catalog`。

远程请求失败（未登录 / 断网 / 服务未启动 / 404）一律**静默回落本地数据**：读
请求带 15s 内存缓存、取不到数就退回上一次成功的结果，保证离线仍能进入界面；
写请求只对后端生成的 UUID 资源发起，本地目录里的假 id（`c1`…）仍然只写本地
`Store`。

## 对接本地后端

配置在 `mobile/config/config.exs`（也可用环境变量 `TCM_API_SOURCE` /
`TCM_API_URL` / `TCM_ORG_SLUG` 覆盖）：

```elixir
config :tcm_mobile,
  api_source: :remote,                 # 测试环境自动 :local
  api_url: "http://127.0.0.1:4011/api",
  api_org_slug: "gzu"                  # 登录用哪个租户；nil → tenant_default
```

### 三步跑通（Android 模拟器）

```bash
# 1. 后端（端口是 4011，不是 4000）
cd /path/to/tcm-edu && mix phx.server

# 2. 把模拟器的 127.0.0.1:4011 反向映射到宿主机 4011
adb reverse tcp:4011 tcp:4011

# 3. 部署并登录
cd mobile && mix mob.deploy --android
```

App 的 `network_security_config` 已放行 `127.0.0.1` / `localhost` 明文 HTTP，
`targetSdk 35` 也不会拦。

**演示账号**：`gzs@example.com` / `123456`（租户 `gzu` · 广州中医药大学）。
忘记密码时后端重置：

```bash
mix run -e '
require Ash.Query
q = Ash.Query.filter(TcmEdu.Accounts.User, email == "gzs@example.com")
{:ok, [u]} = Ash.read(q, tenant: "tenant_gzu", authorize?: false)
{:ok, _} = Ash.update(u, %{password: "123456", password_confirmation: "123456"},
  action: :reset_password, tenant: "tenant_gzu", authorize?: false)
IO.puts("ok")'
```

### 走的接口

认证（`AshAuthentication` 插件的 `AuthController`，普通 JSON）：

| 用途 | 请求 |
| --- | --- |
| 登录 | `POST /api/auth/user/password/sign_in`（body 带 `organization_slug`） |
| 身份 / 会话恢复 | `GET /api/auth/me`（`Authorization: Bearer …`） |
| 退出 | `POST /api/auth/sign_out` |

业务数据（**全部由 `ash_json_api` 从 Ash DSL 自动生成**，无手写 controller）：

| 用途 | 请求 |
| --- | --- |
| 首页统计 | `GET /api/student/enrollments/overview` |
| 课程目录 | `GET /api/student/courses?include=category,chapters.lessons` |
| 课程详情 | `GET /api/student/courses/:id?include=category,chapters.lessons` |
| 我的选课（含课时树 + 进度） | `GET /api/student/enrollments?include=course.chapters.lessons,progress_records` |
| 选课 | `POST /api/student/enrollments`（action `enroll`） |
| 课时进度 upsert | `POST /api/student/progress`（action `upsert_progress`） |
| 通知列表 | `GET /api/student/notifications` |
| 通知全部标记已读 | `POST /api/student/notifications/mark_all_read` |
| 我的考试记录 | `GET /api/student/exam-assignments?include=exam` |

**JSON:API 媒体类型**：`POST` 必须带 `content-type: application/vnd.api+json`，
否则后端返回 **415**；读请求带 `accept: application/vnd.api+json`。

**进度 upsert 的字段契约**：`Progress` 上任何带 `default` 的属性，后端
`on_conflict` 时都会用**本次请求的取值**覆盖（change 模块的默认值不参与
`SET` 列表）。因此 App 侧每次写入都必须显式带上 `status`、`progress_pct`、
`last_position_seconds`，否则已存的进度会被默认值抹掉。

**`include` 只能用资源上声明过的路径**：目标资源的 `json_api` 块里没写
`includes([...])`，请求里写了就是 `400 invalid_includes`；另外 `update`
action 无法生成路由，`mark_all_read` 因此写成了 generic action（结果是**裸的
顶层 JSON**，不包 `data`）。


## 目录结构

```
lib/tcm_mobile/
  app.ex            # Mob.App 入口：tab_bar 导航 + on_start
  theme.ex          # 中医品牌主题（Material 3 亮色：宣纸底/朱砂/草木绿）
  api.ex            # 数据访问层（远程 JSON:API + 缓存 + 离线回落）
  store.ex          # 会话/学习状态 GenServer
  ui.ex             # 共享 UI 组件（M3 风格：AppBar/TabBar/Card/ListTile/FeatureTile…）
  data/             # 示例数据 + 题库 + 本地 AI 应答
    catalog.ex      # 课程/课时/测验/模拟患者/MDT/通知/资料
    questions.ex    # 题库
    ai.ex           # 学习问答/SP 接诊/MDT 规则引擎
  screens/          # 屏幕（欢迎/登录/首页/课程/学习/我的 + 详情页）
```

---

## iOS 构建与运行

### 一、一次性环境准备

1. **安装完整 Xcode**（App Store 搜索 Xcode，或 `brew install --cask xcode`，
   约 15GB）。安装后指定命令行工具：
   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   xcodebuild -version   # 应输出版本号
   ```
2. **Elixir 1.20**（mise 管理，见 `.tool-versions`）：
   ```bash
   mise install          # 安装 erlang 27.3.4 + elixir 1.20.4
   ```
3. **mob_new archive**：
   ```bash
   mix archive.install hex mob_new
   ```
4. **Zig 编译器**（原生构建必需）。Mob 要求精确版本
   `0.17.0-dev.269+ebff43698`，该 nightly 已从 ziglang.org 下架，本机改用
   镜像的相邻 nightly `0.17.0-dev.215+8c5542bd3`：
   ```bash
   # 下载（aarch64 macOS）
   curl -L --http1.1 -o /tmp/zig.tar.xz \
     "http://mirrors.nektro.net/zig/0.17.0-dev.215%2B8c5542bd3/zig-aarch64-macos-0.17.0-dev.215%2B8c5542bd3.tar.xz"
   tar -xf /tmp/zig.tar.xz -C ~/.local/share/
   mkdir -p ~/.local/bin
   ln -sf ~/.local/share/zig-aarch64-macos-0.17.0-dev.215+8c5542bd3/zig ~/.local/bin/zig
   export PATH="$HOME/.local/bin:$PATH"   # 建议写入 ~/.zshrc
   zig version   # 0.17.0-dev.215+8c5542bd3
   ```
   然后让 Mob 接受该版本（`deps/` 不入库，`mix deps.get` 后需重做）：
   ```bash
   # 编辑 deps/mob_dev/lib/mob_dev/toolchain.ex，把 @required_zig_version
   # 改为 "0.17.0-dev.215+8c5542bd3"，再：
   mix deps.compile mob_dev --force
   ```

### 二、首次运行

```bash
mix deps.get          # 拉依赖
mix mob.install       # 下载 iOS 模拟器 OTP 运行时（~400MB，来自 GitHub Releases）
                      # 网络受限时用 curl --http1.1 手动下载后解压到 ~/.mob/cache/
mix mob.deploy --native --ios   # 首次：构建原生 App + 安装到模拟器 + 推送 BEAM
```

> `mix mob.install` 从 `github.com/GenericJam/mob/releases` 下载 OTP 运行时。
> 若直连超时，用 `curl -L --http1.1 --max-time 500` 手动下载
> `otp-ios-sim-5c9c69fc.tar.gz`，解压到 `~/.mob/cache/otp-ios-sim-5c9c69fc/`。

### 三、日常开发（秒级热推）

```bash
mix ios           # 部署到 iOS 模拟器（= mix mob.deploy --ios）
mix watch         # 保存 Elixir 文件即自动热推
mix connect       # 连接已运行的设备节点，进入远程 IEx
mix deploy        # 仅推 BEAM 并重启（改了 .ex 之后）
mix test          # 单元测试 52 个（Mob.ScreenCase 渲染契约 + Api 的 Req.Test 桩）
```

改了 Swift/原生代码才需要 `mix ios.native`（`--native`）重新构建。

### 四、真机

```bash
mix mob.provision   # 一次性：注册 bundle ID + 下载开发描述文件
mix mob.deploy --native --ios
```

---

## 关于 Android

Android 原生工程（`android/`）已删除。如需恢复：
```bash
# 重新生成原生工程骨架（会重建 android/ 与 ios/）
mix mob.new tcm_mobile --android   # 或在临时目录生成后取回 android/
```

### 打开 Android 模拟器（一条命令）

AVD `tcm_phone`（android-34 / arm64）已创建，启动：

```bash
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
export PATH="$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$PATH"
emulator -avd tcm_phone -no-snapshot -no-audio -no-metrics -gpu host &
```

> 用 `-gpu host`（宿主 GPU 硬件加速）文字才清晰；`swiftshader` 软件渲染会发虚。

> **只改 Elixir 代码时**：设备上已装有 App 时，`mix mob.deploy --android`
> 只推 BEAM 即可（秒级、无需 `android/` 工程、无需重下 OTP 运行时）。只有改
> 了原生代码（Swift/Kotlin/插件）才需要恢复 `android/` 并 `--native` 重建。

> 首次启动约 30–60 秒；`adb devices` 出现 `emulator-5554  device` 即就绪。
> 关闭：`adb emu kill`。列出所有 AVD：`emulator -list-avds`。
> 启动 App 用 `adb shell am start -n com.example.tcm_mobile/.MainActivity`
> （`monkey … LAUNCHER` 起不来）。已装 App 的模拟器上，`android/` 工程与
> Android OTP 运行时都不是必需的——那是首次安装才需要。

注意图标名：`TcmMobile.UI` 只使用 Mob 跨平台逻辑图标名
（home/user/star/check/info/error/search/back/chevron_right/close/forward/
chevron_down/settings/star_filled…），以保证两端一致；Android 端未知名字会
渲染成 `?`。

## 主题与 UI

Material 3 亮色：宣纸米白背景、朱砂红主色、草木绿点缀；卡片为白底描边
（outlined），功能入口用「彩色圆角块 + 汉字」的 shortcut 样式。全应用统一
由 `TcmMobile.Theme` 的语义 token 驱动。

开发总结见 [`DEVELOPMENT.md`](DEVELOPMENT.md)。
