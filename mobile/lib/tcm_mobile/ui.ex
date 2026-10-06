defmodule TcmMobile.UI do
  @moduledoc """
  学员端共享 UI 复合组件 —— Material 3 / MUI 风格（纯 Elixir）。

  设计约定：
  - 卡片：白底 + 1px 描边 + 16 圆角 + 16 内距（outlined card）。
  - 图标：仅用 Mob 跨平台逻辑图标名（见 `@icons`），保证 iOS/Android 一致；
    功能入口用「彩色圆角块 + 汉字」的 shortcut 样式，避免依赖图标映射。
  - 间距：8 的倍数；标题层级：2xl 粗体 / lg 粗体 / base medium / sm 次要。
  - 事件统一路由到调用方屏幕的 `handle_info/2`。
  """

  import Mob.Sigil

  # 仅使用 Mob 跨平台逻辑图标名（iOS SF Symbol + Android Material 均支持）
  @icon_home "home"
  @icon_user "user"
  @icon_star "star"
  @icon_check "check"
  @icon_info "info"
  @icon_error "error"
  @icon_search "search"
  @icon_chevron "chevron_right"

  @tabs [
    %{key: :home, icon: @icon_home, label: "首页"},
    %{key: :courses, icon: @icon_star, label: "课程"},
    %{key: :learning, icon: @icon_check, label: "学习"},
    %{key: :profile, icon: @icon_user, label: "我的"}
  ]

  # 功能入口配色（浅色容器 + 前景色），Material You 风格
  @tints %{
    primary: {0x1F00B86B, :primary},
    secondary: {0x1F0F766E, :secondary},
    gold: {0x1FF59E0B, 0xFFF59E0B},
    teal: {0x1F0891B2, 0xFF0891B2},
    plum: {0x1FE11D48, 0xFFE11D48},
    error: {0x1FDC2626, :error}
  }

  # ── 图标（跨平台逻辑名）─────────────────────────────────────────────────────

  def icon_home, do: @icon_home
  def icon_user, do: @icon_user
  def icon_star, do: @icon_star
  def icon_check, do: @icon_check
  def icon_info, do: @icon_info
  def icon_error, do: @icon_error
  def icon_search, do: @icon_search
  def icon_chevron, do: @icon_chevron

  @doc "彩色圆角块 + 图标的 leading tile（列表/入口通用）。"
  def icon_tile(icon, tint \\ :primary, size \\ 44) do
    {bg, fg} = Map.fetch!(@tints, tint)

    ~MOB"""
    <Box width={size} height={size} corner_radius={:radius_md} background={bg} align={:center}>
      <Icon name={icon} text_size={22} text_color={fg} />
    </Box>
    """
  end

  @doc "彩色圆角块 + 汉字的功能入口图标（不依赖图标映射，永远可渲染）。"
  def glyph_tile(glyph, tint \\ :primary, size \\ 48) do
    {bg, fg} = Map.fetch!(@tints, tint)

    ~MOB"""
    <Box width={size} height={size} corner_radius={:radius_md} background={bg} align={:center}>
      <Text text={glyph} text_size={:lg} font_weight="bold" text_color={fg} />
    </Box>
    """
  end

  # ── 顶部栏 ──────────────────────────────────────────────────────────────────

  @doc "Tab 根屏顶部应用栏（MUI AppBar：surface 底、粗体标题、可选副标题/动作）。"
  def app_bar(title, subtitle \\ nil, action \\ nil) do
    subtitle_node =
      if subtitle do
        ~MOB(<Text text={subtitle} text_size={:sm} text_color={:muted} />)
      else
        %{type: :spacer, props: %{}, children: []}
      end

    action_node =
      case action do
        {icon, tag} ->
          tap = {self(), tag}

          ~MOB(<Box
  on_tap={tap}
  fill_width={false}
  padding={:space_sm}
  corner_radius={:radius_pill}
  background={:surface_raised}
>
  <Icon name={icon} text_size={20} text_color={:on_surface} />
</Box>)

        nil ->
          %{type: :spacer, props: %{}, children: []}
      end

    ~MOB"""
    <Row fill_width={true} align={:center} gap={:space_sm} padding_bottom={:space_sm}>
      <Column gap={2} weight={1}>
        <Text text={title} text_size={:"2xl"} font_weight="bold" text_color={:on_surface} />
        {subtitle_node}
      </Column>
      {action_node}
    </Row>
    """
  end

  @doc "带返回按钮 + 标题的详情页头部。"
  def detail_header(title, action \\ nil) do
    back = {self(), :back}

    action_node =
      case action do
        {icon, tag} ->
          tap = {self(), tag}

          ~MOB(<Box on_tap={tap} fill_width={false} padding={:space_sm} corner_radius={:radius_pill}>
  <Icon name={icon} text_size={20} text_color={:on_surface} />
</Box>)

        nil ->
          %{type: :spacer, props: %{}, children: []}
      end

    ~MOB"""
    <Row
      fill_width={true}
      align={:center}
      padding_left={:space_sm}
      padding_right={:space_md}
      padding_top={:space_sm}
      padding_bottom={:space_sm}
      gap={:space_xs}
      background={:surface}
      border_color={:border}
      border_bottom_width={1}
    >
      <Box on_tap={back} fill_width={false} padding={:space_sm} corner_radius={:radius_pill}>
        <Icon name="back" text_size={20} text_color={:on_surface} />
      </Box>
      <Text
        text={title}
        text_size={:lg}
        font_weight="medium"
        text_color={:on_surface}
        max_lines={1}
        weight={1}
      />
      {action_node}
    </Row>
    """
  end

  # ── 底部导航 ────────────────────────────────────────────────────────────────

  @doc "Material 3 底部导航栏（选中项带胶囊指示）。"
  def tab_bar(active) when active in [:home, :courses, :learning, :profile] do
    buttons =
      Enum.map(@tabs, fn tab ->
        selected = tab.key == active
        tap = {self(), {:switch_tab, tab.key}}

        icon_bg = if selected, do: 0x1F00B86B, else: 0x00000000
        color = if selected, do: :primary, else: :muted

        ~MOB"""
        <Column weight={1} gap={2} padding_top={:space_sm} padding_bottom={:space_xs} on_tap={tap}>
          <Box fill_width={true} align={:center}>
            <Box
              fill_width={false}
              corner_radius={:radius_pill}
              padding_left={:space_md}
              padding_right={:space_md}
              padding_top={4}
              padding_bottom={4}
              background={icon_bg}
            >
              <Icon name={tab.icon} text_size={20} text_color={color} />
            </Box>
          </Box>
          <Text
            text={tab.label}
            fill_width={true}
            text_align="center"
            text_size={:xs}
            text_color={color}
            font_weight={if selected, do: "medium", else: "regular"}
          />
        </Column>
        """
      end)

    %{
      type: :row,
      props: %{
        fill_width: true,
        background: :surface,
        border_color: :border,
        border_top_width: 1,
        padding_left: :space_sm,
        padding_right: :space_sm,
        align: :center
      },
      children: buttons
    }
  end

  # ── 容器 ────────────────────────────────────────────────────────────────────

  @doc "outlined 卡片容器。"
  def card(children, opts \\ []) do
    background = Keyword.get(opts, :background, :surface)
    padding = Keyword.get(opts, :padding, :space_md)
    radius = Keyword.get(opts, :radius, :radius_lg)
    gap = Keyword.get(opts, :gap, 8)
    border? = Keyword.get(opts, :border, true)
    on_tap = Keyword.get(opts, :on_tap)

    props =
      %{background: background, corner_radius: radius, padding: padding, fill_width: true}
      |> then(fn p ->
        if border?, do: Map.merge(p, %{border_color: :border, border_width: 1}), else: p
      end)
      |> then(fn p -> if on_tap, do: Map.put(p, :on_tap, on_tap), else: p end)

    %{
      type: :box,
      props: props,
      children: [%{type: :column, props: %{gap: gap, fill_width: true}, children: children}]
    }
  end

  @doc "区块标题（MUI ListSubheader 风格：主标题 + 可选右侧动作）。"
  def section_header(title, action_text \\ nil, action_tag \\ nil) do
    action =
      if action_text do
        tap = {self(), action_tag}

        ~MOB(<Text
  text={action_text}
  text_size={:sm}
  text_color={:primary}
  font_weight="medium"
  on_tap={tap}
/>)
      else
        %{type: :spacer, props: %{}, children: []}
      end

    ~MOB"""
    <Row fill_width={true} align={:center} gap={:space_sm}>
      <Text text={title} text_size={:lg} font_weight="bold" text_color={:on_surface} weight={1} />
      {action}
    </Row>
    """
  end

  @doc "MUI ListItem：leading tile + 标题/副标题 + 尾部箭头。"
  def list_tile(leading, title, subtitle \\ nil, opts \\ []) do
    on_tap = Keyword.get(opts, :on_tap)
    trailing = Keyword.get(opts, :trailing, @icon_chevron)

    subtitle_node =
      if subtitle do
        ~MOB(<Text text={subtitle} text_size={:sm} text_color={:muted} max_lines={1} />)
      else
        %{type: :spacer, props: %{}, children: []}
      end

    trailing_node =
      case trailing do
        nil -> %{type: :spacer, props: %{}, children: []}
        %{type: _} = node -> node
        icon when is_binary(icon) -> ~MOB(<Icon name={icon} text_size={18} text_color={:muted} />)
        _ -> %{type: :spacer, props: %{}, children: []}
      end

    tap_prop = if on_tap, do: %{on_tap: on_tap}, else: %{}

    %{
      type: :box,
      props:
        Map.merge(
          %{
            fill_width: true,
            background: :surface,
            corner_radius: :radius_lg,
            padding: :space_md,
            border_color: :border,
            border_width: 1
          },
          tap_prop
        ),
      children: [
        %{
          type: :row,
          props: %{fill_width: true, align: :center, gap: :space_md},
          children: [
            leading,
            %{
              type: :column,
              props: %{gap: 2, weight: 1},
              children: [
                %{
                  type: :text,
                  props: %{
                    text: title,
                    text_size: :base,
                    font_weight: "medium",
                    text_color: :on_surface,
                    max_lines: 1
                  },
                  children: []
                },
                subtitle_node
              ]
            },
            trailing_node
          ]
        }
      ]
    }
  end

  @doc "统计卡片（MUI：小标签在上、大数值在下）。"
  def stat_card(label, value, tint \\ :primary) do
    {_bg, fg} = Map.fetch!(@tints, tint)

    ~MOB"""
    <Box
      background={:surface}
      corner_radius={:radius_lg}
      padding={:space_md}
      weight={1}
      border_color={:border}
      border_width={1}
    >
      <Column gap={4} align={:start}>
        <Text text={label} text_size={:xs} text_color={:muted} />
        <Text text={value} text_size={:"2xl"} font_weight="bold" text_color={fg} />
      </Column>
    </Box>
    """
  end

  @doc "功能入口（彩色圆角块 + 标签，用于网格）。"
  def feature_tile(glyph, label, tint, on_tap) do
    ~MOB"""
    <Box
      background={:surface}
      corner_radius={:radius_lg}
      padding={:space_md}
      weight={1}
      on_tap={on_tap}
      border_color={:border}
      border_width={1}
    >
      <Column gap={:space_sm}>
        <Box fill_width={true} align={:center}>
          {glyph_tile(glyph, tint, 44)}
        </Box>
        <Text
          text={label}
          fill_width={true}
          text_align="center"
          text_size={:xs}
          text_color={:on_surface}
        />
      </Column>
    </Box>
    """
  end

  @doc "课程卡片：色块封面 + 标题 + 副题 + 元信息。"
  def course_card(course, on_tap, enrolled? \\ nil) do
    level_label =
      case course.level do
        :beginner -> "入门"
        :intermediate -> "进阶"
        :advanced -> "高阶"
        _ -> "入门"
      end

    lesson_count = Map.get(course, :lesson_count) || length(Map.get(course, :lessons, []))
    {cover_bg, cover_fg} = cover_tint(Map.get(course, :category))
    cover_glyph = Map.get(course, :cover_glyph) || String.slice(course.title, 0, 1)
    meta = "#{level_label} · #{lesson_count} 课时 · #{course.student_count} 人学过"

    enrolled_badge =
      if enrolled? do
        ~MOB(<Box
  fill_width={false}
  background={0x1F0F766E}
  corner_radius={:radius_pill}
  padding_top={2}
  padding_bottom={2}
  padding_left={:space_sm}
  padding_right={:space_sm}
>
  <Text text="已选修" text_size={:xs} text_color={:secondary} font_weight="medium" />
</Box>)
      else
        %{type: :spacer, props: %{}, children: []}
      end

    ~MOB"""
    <Box
      background={:surface}
      corner_radius={:radius_lg}
      padding={:space_md}
      fill_width={true}
      on_tap={on_tap}
      border_color={:border}
      border_width={1}
    >
      <Row gap={:space_md} align={:center}>
        <Box width={56} height={56} corner_radius={:radius_md} background={cover_bg} align={:center}>
          <Text text={cover_glyph} text_size={:"2xl"} text_color={cover_fg} font_weight="bold" />
        </Box>
        <Column gap={4} weight={1}>
          <Row gap={:space_sm} align={:center}>
            <Text
              text={course.title}
              text_size={:base}
              font_weight="medium"
              text_color={:on_surface}
              max_lines={1}
              weight={1}
            />
            {enrolled_badge}
          </Row>
          <Text text={course.subtitle} text_size={:sm} text_color={:muted} max_lines={1} />
          <Text text={meta} text_size={:xs} text_color={:muted} />
        </Column>
      </Row>
    </Box>
    """
  end

  @doc "进度条（0-100）。"
  def progress_bar(percent) do
    p = min(max(percent, 0), 100)

    ~MOB"""
    <Box height={6} corner_radius={:radius_pill} background={:border} fill_width={true}>
      <Box
        width={max(round(p / 100 * 320), 6)}
        height={6}
        corner_radius={:radius_pill}
        background={:primary}
      />
    </Box>
    """
  end

  @doc "胶囊标签（筛选 chip）。"
  def chip(label, selected \\ false) do
    bg = if selected, do: :primary, else: :surface
    fg = if selected, do: :on_primary, else: :on_surface

    ~MOB"""
    <Box
      background={bg}
      corner_radius={:radius_pill}
      padding_top={:space_xs}
      padding_bottom={:space_xs}
      padding_left={:space_md}
      padding_right={:space_md}
      fill_width={false}
      border_color={:border}
      border_width={if selected, do: 0, else: 1}
    >
      <Text text={label} text_size={:sm} text_color={fg} />
    </Box>
    """
  end

  @doc "空状态占位。"
  def empty_state(icon, text) do
    ~MOB"""
    <Column fill_width={true} padding={:space_xl} gap={:space_sm}>
      <Box fill_width={true} align={:center}>
        <Icon name={icon} text_size={40} text_color={:border} />
      </Box>
      <Text text={text} fill_width={true} text_size={:base} text_color={:muted} text_align="center" />
    </Column>
    """
  end

  @doc "小号次要文字。"
  def section_label(text) do
    ~MOB(<Text text={text} text_size={:sm} font_weight="medium" text_color={:muted} />)
  end

  # ── 内部 ────────────────────────────────────────────────────────────────────

  defp cover_tint(category) do
    case category do
      "materia-medica" -> Map.fetch!(@tints, :secondary)
      "acupuncture-tuina" -> Map.fetch!(@tints, :teal)
      "formulas" -> Map.fetch!(@tints, :gold)
      "clinical" -> Map.fetch!(@tints, :plum)
      _ -> Map.fetch!(@tints, :primary)
    end
  end
end
