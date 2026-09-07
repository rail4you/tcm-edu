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
      |> Ash.Changeset.change_attribute(:completed_at, DateTime.utc_now())
    else
      changeset
    end
  end
end
