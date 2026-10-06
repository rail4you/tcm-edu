defmodule TcmMobile.Theme do
  @moduledoc """
  杏宁树学员端品牌主题 —— Material 3 亮色，与主站 `storefront` 主题同色板。

  Design tokens resolve at render time, so every screen picks these up
  automatically. Raw colours are `0xAARRGGBB` integers (alpha first).
  """

  @spec theme() :: Mob.Theme.t()
  def theme do
    %Mob.Theme{
      # 主色：storefront primary #00b86b
      primary: 0xFF00B86B,
      on_primary: 0xFFFFFFFF,
      # 次色：storefront secondary #0f766e
      secondary: 0xFF0F766E,
      on_secondary: 0xFFFFFFFF,
      # 背景：storefront base-200 #f1f5f2
      background: 0xFFF1F5F2,
      on_background: 0xFF1F2937,
      # 表面：base-100 纯白卡片
      surface: 0xFFFFFFFF,
      surface_raised: 0xFFF7FAF8,
      on_surface: 0xFF1F2937,
      muted: 0xFF6B7280,
      # storefront error #dc2626
      error: 0xFFDC2626,
      on_error: 0xFFFFFFFF,
      # storefront base-300 #e5ebe5
      border: 0xFFE5EBE5,
      type_scale: 1.0,
      space_scale: 1.0,
      radius_sm: 8,
      radius_md: 12,
      radius_lg: 16,
      radius_pill: 100
    }
  end
end
