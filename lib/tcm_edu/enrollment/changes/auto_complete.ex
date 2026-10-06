defmodule TcmEdu.Enrollment.Changes.AutoComplete do
  @moduledoc """
  进度自动完结：`progress_pct >= 100` 时落 `status = :completed` + `completed_at`。

  挂在 `Progress.upsert_progress` / `Progress.update` 上。
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    pct = Ash.Changeset.get_attribute(changeset, :progress_pct)

    if is_integer(pct) and pct >= 100 do
      changeset
      |> Ash.Changeset.change_attribute(:status, :completed)
      # completed_at 要写两条：
      #   * change_attribute —— 覆盖 INSERT 路径（新建进度记录）
      #   * atomic_update    —— 覆盖 upsert 冲突路径。ON CONFLICT DO UPDATE 的
      #     SET 列表取自 changeset.attributes（= 默认值 + 显式入参），change 塞进
      #     changes 的值不在其中；atomic 走 query_with_atomics，才进得了 SET。
      |> Ash.Changeset.change_attribute(:completed_at, DateTime.utc_now())
      |> Ash.Changeset.atomic_update(:completed_at, DateTime.utc_now())
    else
      changeset
    end
  end
end
