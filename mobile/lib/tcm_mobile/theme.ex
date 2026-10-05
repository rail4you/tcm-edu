defmodule TcmMobile.Theme do
  @moduledoc """
  中医学院学员端品牌主题 —— Material 3 亮色，宣纸底、朱砂主色、草木绿点缀。

  Design tokens resolve at render time, so every screen picks these up
  automatically. Raw colours are `0xAARRGGBB` integers (alpha first).
  """

  @spec theme() :: Mob.Theme.t()
  def theme do
    %Mob.Theme{
      # 主色：朱砂红
      primary: 0xFF9A3324,
      on_primary: 0xFFFFFFFF,
      # 次色：草木绿
      secondary: 0xFF3E5C46,
      on_secondary: 0xFFFFFFFF,
      # 背景：暖白宣纸
      background: 0xFFF7F5F1,
      on_background: 0xFF201C17,
      # 表面：纯白卡片
      surface: 0xFFFFFFFF,
      surface_raised: 0xFFFCFAF6,
      on_surface: 0xFF201C17,
      muted: 0xFF7C766B,
      error: 0xFFBA1A1A,
      on_error: 0xFFFFFFFF,
      border: 0xFFE8E3D9,
      type_scale: 1.0,
      space_scale: 1.0,
      radius_sm: 8,
      radius_md: 12,
      radius_lg: 16,
      radius_pill: 100
    }
  end
end
