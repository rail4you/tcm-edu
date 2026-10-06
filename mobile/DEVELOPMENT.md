# 岐黄学堂移动端 · 开发总结

本文记录移动端（`tcm-edu/mobile`）的完整开发过程：技术选型、架构、数据与 UI
设计、关键决策与踩坑、环境构建，以及后续计划。

---

## 1. 技术选型：Mob（BEAM-on-device）

需求是给现有 Phoenix + Ash 的中医学院做**学员端 iOS/Android 客户端**。选择
[Mob](https://hexdocs.pm/mob) 而非 Flutter / React Native / 原生：

| 维度 | Mob | 说明 |
| --- | --- | --- |
| 语言 | 纯 Elixir | 与后端同一套语言、OTP 模型，团队零移动端经验即可上手 |
| 运行时 | OTP 打进 App | `render/1` 返回组件树 map → JSON → 原生 Compose/SwiftUI |
| UI | 原生组件 | SwiftUI / Compose 真实控件，非自绘 canvas |
| 离线 | 天生离线优先 | 无服务器依赖；后端 API 是可选增量 |
| 调试 | 标准 Erlang 分发 | `mix mob.connect` 远程 IEx、`nl/1` 热推字节码 |

关键机制：`Mob.Screen` 是一个 GenServer（每屏一个进程）；`~MOB` 模板在编译期
编译成普通 map；事件经 NIF 回到屏幕进程的 `handle_info/2`；导航用
`Mob.Socket` 的 `push_screen/reset_to/switch_tab`。

## 2. 工程结构

```
lib/tcm_mobile/
  app.ex         # Mob.App：navigation/1 声明 4 个 tab 栈；on_start 启动 Repo/Store
  theme.ex       # Mob.Theme：Material 3 亮色 token
  ui.ex          # 共享 UI 组件（纯 Elixir 复合组件）
  api.ex         # 数据访问层（唯一入口，:local / :remote 可切换）
  store.ex       # 会话与学习状态 GenServer
  data/
    catalog.ex   # 课程/课时/题库/模拟患者/MDT/通知/资料 示例数据
    questions.ex # 题库
    ai.ex        # 本地规则式应答（问答 / SP / MDT）
  screens/       # 22 个屏幕
```

### 导航

`Mob.App.navigation/1` 声明 `tab_bar([stack(:home), stack(:courses),
stack(:learning), stack(:profile)])` —— 每个 tab 一个独立历史栈。
- 登录成功：`reset_to(socket, :home, %{}, scope: :all)` 清空全部旧栈。
- 退出登录：`reset_to(WelcomeScreen, scope: :all)`。
- 详情页：`push_screen/3` 推入当前栈（覆盖底部 Tab）。
- 底部 Tab：Mob 尚不自动绘制 chrome，因此每个 tab 根屏自行渲染
  `UI.tab_bar/1`，点击 → `switch_tab/2`。

### 数据层

`TcmMobile.Api` 是屏幕唯一的数据入口，返回与后端资源同形的数据：

```
Catalog（不可变示例数据） ─┐
Store（可变会话状态）     ─┼─→ Api ─→ Screens
Req（远程预留，:remote）  ─┘
```

`Store` 持有：当前学员、选课与进度、错题、通知、聊天、模拟患者会话、MDT
消息、测验作答。`Api.source()` 由 `config :tcm_mobile, :api_source` 控制，切到
`:remote` 后走 `Req`（后端补 JSON API 即可，界面无感）。

### 本地 AI

`Data.Ai` 用规则式逻辑实现三类应答，保证离线可用、可测试：
- `qa_reply/1`：按关键词（阴阳/五行/舌脉/方剂/针灸…）返回知识点。
- `sp_reply/2`：按脚本逐条释放标准化病人的回答，用尽后提示辨证。
- `sp_grade/2` / `mdt_reply/2`：辨证评分与 MDT 医师回应。

## 3. UI 设计系统（Material 3 / MUI）

`TcmMobile.Theme`（亮色）：

| Token | 值 | 用途 |
| --- | --- | --- |
| primary | `0xFF9A3324` | 朱砂红，主操作/强调 |
| secondary | `0xFF3E5C46` | 草木绿，成功/已选修 |
| background | `0xFFF7F5F1` | 暖白宣纸 |
| surface | `0xFFFFFFFF` | 卡片白底 |
| border | `0xFFE8E3D9` | 描边 |
| radius_lg/md | 16 / 12 | 卡片/小块圆角 |

`TcmMobile.UI` 组件（全部纯 Elixir、可复用）：
- `app_bar/3`、`detail_header/2`（surface 底 + 粗体标题 + 返回）
- `tab_bar/1`（M3 底部导航，选中项带胶囊指示）
- `card/2`（outlined 卡片：白底 + 1px 描边 + 16 圆角 + 16 内距）
- `list_tile/4`（leading + 标题/副标题 + trailing）
- `feature_tile/4`（彩色圆角块 + 汉字 + 标签，功能入口网格）
- `glyph_tile/3` / `icon_tile/3`、`stat_card/3`、`chip/2`、`progress_bar/1`、
  `empty_state/2`、`section_header/3`、`course_card/3`

设计要点：内容用**描边卡片**（Mob 无阴影 prop）；功能入口用「彩色圆角块 +
汉字」的 shortcut 风格，既好看又**不依赖图标映射**；配色用浅色容器
（`0x1F…` 约 12% alpha）+ 语义前景色，模拟 Material You 的 container 色。

## 4. 关键决策与踩坑

### 4.1 图标：prop 名是 `name`，不是 `icon_name`
Mob 的 `:icon` 组件在**两端都用 `name` 这个 prop**（iOS `mob_nif.m` 读
`MOB_PROP_name`，Android `MobBridge.kt` 的 `MobIcon` 读 `props["name"]`）。
早期误用了 `icon_name`（那是 iOS 内部属性名），导致 prop 缺失、全部回退成
`?`（QuestionMark）。修复：`TcmMobile.UI` 统一用 `name="…"`，且只用 Mob 跨
平台逻辑名（`home/user/star/check/info/error/search/back/forward/close/
chevron_right/chevron_down/settings/star_filled` 等）；功能入口用「彩色圆角
块 + 汉字」，不依赖图标映射。

### 4.2 `list_tile` 的 trailing：字符串 vs 节点
`list_tile(leading, title, subtitle, trailing:)` 早期把 `trailing` 一律当**图标
名字符串**（`<Icon name={trailing}/>`）。但多处传入的是**状态徽章节点**（map），
于是：
- 节点被当图标名 → 渲染成 `?`（测验/模拟患者的状态徽章）；
- 节点里若含 `on_tap` 元组或任意非 JSON 值 → `Mob.Renderer` JSON 编码报
  `unsupported_type`，整屏渲染失败（资料页）。

修复：`list_tile` 按类型分派——`%{type: _}` 直接用该节点；字符串当图标名；
nil 用占位。另：**trailing 内部不要再嵌 `on_tap` 的盒子**（嵌套 clickable
会挤占 Row 的权重列，导致标题不渲染）；把下载等次级动作放到详情页。

### 4.3 文字模糊：模拟器用软件渲染
`emulator -gpu swiftshader_indirect`（软件渲染）会让中文发虚。改用宿主 GPU
硬件加速即可清晰：`emulator -avd tcm_phone -gpu host …`。

### 4.4 PDF 预览与原生下载
- 预览：`<WebView url={pdf.js viewer + "?file=" + URI.encode_www_form(url)} />`
  —— pdf.js 用 canvas 渲染，跨平台、可控。
- 下载/打开：`Mob.Device.open_url(url)` 交给系统（Android 下载管理器 /
  系统 PDF 查看器；iOS 浏览器/预览）。

### 4.5 `~MOB` 模板语法陷阱
- **`@foo` 只在 sigil 内有效**：普通 Elixir 代码里 `@foo` 是模块属性，会报
  undefined；`render` 内要先用局部变量解构（`course = assigns.course`）。
- **多行 `{...}` 插值不可用**：heredoc 里的 `{Enum.map(...)}` 若跨多行会解析
  失败；改为在 sigil 外预构建节点列表，再 `{nodes}`。
- **根节点必须唯一**：`~MOB"""` 只能有一个根元素；多根（如 Scroll + 输入行）
  要包一层 `Column`。
- **`:"2xl"` 不是 `:2xl`**：字号 token 数字开头，必须写成 `:"2xl"`。
- **单行 `~MOB(<Row>…</Row>)` 不可靠**：嵌套标签/表达式属性时易解析失败，
  统一改用 heredoc。
- **`<UI.card>` 不是标签**：自定义函数组件要用表达式插值 `{UI.card([...])}`。
- **`@icon_x` 在 sigil 内被当作 assigns**：图标用字面量字符串。

### 4.3 导航与布局
- **Tab 点击事件**是 `{:tap, {:switch_tab, tab}}`（tag 被 `:tap` 包裹），
  handler 少写 `:tap` 会导致点击无效。
- **Row 内均分需要 `weight`**：子项用 `fill_width` 不会均分，Tab 栏曾只渲染
  出第一个标签。
- **课时 id 与正文键错位**：`with_index` 从 1 开始导致 `c1-l1` 对应了 0 基的
  正文；改为 0 基 id + `no: i+1` 显示。
- **map 点访问会抛 KeyError**：可选字段一律 `Map.get(map, :key)`。

### 4.4 测试隔离
`Store` 是全局命名单例，跨测试保留状态导致污染。加 `Store.reset/0` 并在
每个测试 `setup` 调用；屏幕测试用 `Mob.ScreenCase`（`mount_screen` /
`render_info` / `assert_renderable`），断言按钮文案要用
`find(view, :button, text: "…")` 而非 `text/1`（`text/1` 只取 `:text` 节点）。

### 4.6 对接本地后端（Android 实测）

**设备端不会自动启动依赖的 OTP application。** 只有应用自身 + 显式
`ensure_all_started` 的才会起来（这正是 `ecto_sqlite3` 在 `on_start` 里手动
启动的原因）。Req 不启动 → `Finch` 池不存在 → 每次请求在
`Finch.Pool.Manager.lookup_pool/3` 抛 `ArgumentError`，且**整屏 LiveView 崩溃
重启、输入全丢**（日志里看到 `screen … crashed and is being restarted`）。
修复：`on_start` 里 `_ = Application.ensure_all_started(:req)`。

**后端两处真实的租户 bug**（此前 `/api/auth` 登录永远落到 `tenant_default`）：

1. `Ash.get(Organization, slug: slug, authorize?: false)` —— `Ash.get/3` 的第 2 个
   参数是 id/filter，第 3 个才是 opts。这样写会把整个列表当 id，`authorize?: false`
   被当成过滤条件、授权照跑 → policy 拒绝 → 插件静默回退 `tenant_default`。
   正确写法：`Ash.get(Organization, [slug: slug], authorize?: false)`。
2. `AuthController.user_tenant/0` 写死 `"tenant_default"`，签发的 JWT 声明与实际
   登录租户不符，`/me` 再查一遍就查不到人。改为读
   `Ash.PlugHelpers.get_tenant(conn)`。

**模拟器访问宿主机**：`adb reverse tcp:4011 tcp:4011`，App 侧直接用
`http://127.0.0.1:4011`。Mob 生成的 `network_security_config` 已放行
`127.0.0.1` / `localhost` 明文，`targetSdk 35` 不会拦。

### 4.7 业务数据对接 AshJsonApi（Android 实测）

后端 `/api/student/*` 全部由 `ash_json_api` 从 Ash DSL 生成（`mix precommit`
下 478 tests 全绿，其中 `student_json_api_test.exs` 25 个专测这 9 个端点），
移动端 `Api` 侧踩过的坑：

- **媒体类型**：`POST` 必须 `content-type: application/vnd.api+json`，用
  `application/json` 会吃 **415**。`Req` 的 `body:` 传字符串时要自己设
  header，不要用 `json:` 选项。
- **`include` 必须在资源 `json_api` 块里声明过**，否则 `400 invalid_includes`。
  为此给 `CourseCategory` / `Exam` 补了 `AshJsonApi.Resource` 扩展与 `type/1`
  —— 没有扩展时关系仍会被序列化，但 `type` 是 `null`，属于非法 JSON:API。
- **`update` action 不能生成路由**：`mark_all_read` 改写成 generic action，
  结果是裸的顶层 JSON（不包 `data`）。generic action 没有 `:id` 段，可以和
  `index` 共存于同一 `base`。
- **upsert 会把带 `default` 的属性全部按本次取值覆盖**：`ON CONFLICT DO UPDATE
  SET` 的列来自 `changeset.attributes`（显式参数 + action 默认值），change
  模块里 `change_attribute` 的值不在其中。`AutoComplete` 因此同时写了
  `change_attribute(:completed_at, …)`（覆盖 INSERT）和
  `atomic_update(:completed_at, …)`（覆盖冲突分支），两条路径都验证过。
- **App 每次写进度必须显式带 `status` / `progress_pct` /
  `last_position_seconds`**，否则会被默认值抹平。
- **首页统计、考试记录来自 generic action**，`my_exams` 是 `index`，
  两者都不需要 id 段。
- **`teacher` 关系不 include**：`User` 没有 `AshJsonApi.Resource` 扩展，
  `relationships.teacher.data` 会是 `null`，故 App 侧自带占位教师名。

**Android 实测流程**（`android/` 工程已删，但设备上已装 App 时只需推 BEAM）：

```bash
adb reverse tcp:4011 tcp:4011
cd mobile && mix mob.deploy --android        # 597 个 BEAM，秒级
adb shell am start -n com.example.tcm_mobile/.MainActivity   # monkey 起不来，用 am start
```

实测覆盖：首页统计/分类/热门课程、课程目录（分类筛选 8→4）、我的学习
（3 门 + 20%/50%/0% 真实进度）、课程详情与课时树、课时页「标记完成」
（服务端立刻多出一行 `progress`）、通知列表、我的考试记录。

> **Tab 是 keep-alive 的**：`Mob.Socket.switch_tab/2` 保留 tab 状态，切回来不
> 重新 `mount`，所以首页/学习页的统计要等 tab 真正重挂载才刷新（传
> `mount_params:` 会强制重挂载，`courses` tab 跳转已经在用）。

**远程路径怎么测（`test/tcm_mobile/api_test.exs`）**：`Api` 在
`jsonapi_request/3` 与 `request/4` 里把
`Application.get_env(:tcm_mobile, :api_req_plug)` 拼进 Req 的 `opts`，测试
`put_env(:tcm_mobile, :api_req_plug, {Req.Test, :tcm_api})` 即可把整个 HTTP
层换掉，断言 `conn.method` / `request_path` / 请求头 / 解码后的 body。
覆盖：目录与详情解码、分类派生、15s 缓存（一次 expect 多次调用）、
500/503 回落本地、无 token 时不发任何请求、进度写入的三个字段与
`application/vnd.api+json` 头、本地 id（`c1`…）永不触网。

> **`plug` 必须写进 `mix.exs`**：它是 `req` 的可选依赖，不显式声明时
> `mix deps.compile req` 的 `Code.ensure_loaded?(Plug)` 为 false，req 会编进
> "missing plug dependency" 桩，`Req.Test` / `Req.Plug` 全部不可用。且要
> **按环境**编译：`MIX_ENV=test mix deps.compile plug req --force`
> （`mix deps.compile` 默认写 `_build/dev`，测试用的 `_build/test` 里仍是旧桩）。

## 5. 环境与构建

### 5.1 本机环境
- Elixir 1.20.4 / OTP 27（`mise`，见 `.tool-versions`；主后端项目仍用 1.18）。
- 无完整 Xcode（只有 CommandLineTools）→ **iOS 原生构建未能在本机验证**。
- Android SDK/NDK/模拟器已装，用于**验证 UI 与全部功能**（已删除 android/）。

### 5.2 网络受限的三个变通
1. **Hex registry 超时**：`HEX_OFFLINE=1 mix …` 跳过在线校验（依赖已在 `deps/`）。
2. **OTP 运行时**（GitHub Releases 直连超时）：`curl -L --http1.1 --max-time 500`
   手动下载 arm32/x86_64/iOS 模拟器 tarball，解压到 `~/.mob/cache/`。
3. **Zig 精确版本下架**：用镜像相邻 nightly，并改 `deps/mob_dev` 的
   `@required_zig_version` 后 `mix deps.compile mob_dev --force`。
4. **`mob_new` archive 让 1.18.4 的 `mix` 直接崩**：用 Elixir 1.20 安装的
   `~/.mix/archives/mob_new-0.6.5` 会让默认 1.18.4 在
   `Mix.Local.check_elixir_version_in_ebin` 里抛 `ets:lookup(Mix.State, …)`
   badarg（**任何** `mix` 命令都起不来）。移除该 archive 即恢复
   （`mob.new` 只在生成新工程时用，1.20 下可随时重装）。

### 5.3 构建流程
```
mix mob.install            # 下载设备 OTP 运行时（一次性）
mix mob.deploy --native --ios   # 首次：原生 App + BEAM（Gradle/Xcode 构建）
mix mob.deploy --ios       # 日常：仅推 BEAM（秒级）
```

## 6. 测试

52 个测试（`mix test`）：
- `Data.CatalogTest`：课程/课时/题库/病案数据自洽性。
- `StoreTest`：登录、选课进度、测验评分、错题收录、问答、SP 会话与评分。
- `ScreensTest`：用 `Mob.ScreenCase` 挂载各屏幕、驱动事件、校验渲染树只用
  可渲染节点（`assert_renderable`）。
- `ApiTest`：26 个，用 `:api_req_plug` + `Req.Test` 桩掉 HTTP，覆盖
  JSON:API 解码、缓存、离线回落与写入契约（见 §4.7）。

## 7. 后续计划

- [ ] 安装完整 Xcode 后验证 iOS 构建与真机运行（`mix mob.provision`）。
- [x] 后端补学员端 JSON API，`Api` 切 `:remote` —— 已完成：`ash_json_api` 生成
  `/api/student/*` 六读三写，`Api` 远程优先 + 离线回落，Android 模拟器实测通过。
- [ ] 学习问答 / 模拟患者 / MDT 接入真实大模型（替换 `Data.Ai` 规则引擎）。
- [ ] 测验增加倒计时与防作弊；课程视频课时接入播放器。
- [ ] 头像/课程封面接入 AshStorage（OSS）真实图片。
