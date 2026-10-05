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
入口（`source: :local`）。后端补 JSON API 后把 `config :tcm_mobile, :api_source`
切到 `:remote` 即可（Req 客户端已预留，见 `TcmMobile.Api`）。

## 目录结构

```
lib/tcm_mobile/
  app.ex            # Mob.App 入口：tab_bar 导航 + on_start
  theme.ex          # 中医品牌主题（Material 3 亮色：宣纸底/朱砂/草木绿）
  api.ex            # 数据访问层（本地 + 远程预留）
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
mix test          # 单元测试（Mob.ScreenCase：mount/render/事件/渲染契约）
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
> 注意：要在此模拟器上运行 App 需先恢复 `android/` 工程（见上），并让
> `mix mob.install` 重新下载 Android 的 OTP 运行时。

注意图标名：`TcmMobile.UI` 只使用 Mob 跨平台逻辑图标名
（home/user/star/check/info/error/search/back/chevron_right/close/forward/
chevron_down/settings/star_filled…），以保证两端一致；Android 端未知名字会
渲染成 `?`。

## 主题与 UI

Material 3 亮色：宣纸米白背景、朱砂红主色、草木绿点缀；卡片为白底描边
（outlined），功能入口用「彩色圆角块 + 汉字」的 shortcut 样式。全应用统一
由 `TcmMobile.Theme` 的语义 token 驱动。

开发总结见 [`DEVELOPMENT.md`](DEVELOPMENT.md)。
