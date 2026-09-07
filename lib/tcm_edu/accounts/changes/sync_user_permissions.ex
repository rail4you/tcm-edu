defmodule TcmEdu.Accounts.Changes.SyncUserPermissions do
  @moduledoc """
  Synchronises `UserPermission` rows for a user based on an argument
  `permissions` (a list of permission name strings like "post:create").

  Looks up permission IDs by name, removes stale grant rows, and inserts
  any new ones.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    user = changeset.data
    permission_names = Ash.Changeset.get_argument(changeset, :permissions) || []

    changeset
    |> Ash.Changeset.before_transaction(fn _changeset ->
      repo = TcmEdu.Repo
      import Ecto.Query

      # Resolve permission names to IDs
      perm_ids =
        if permission_names == [] do
          []
        else
          repo.all(
            from p in {"permissions", TcmEdu.Accounts.Permission},
              where: p.name in ^permission_names,
              select: {p.name, p.id}
          )
          |> Map.new()
        end

      # Remove all existing direct grants for this user
      repo.delete_all(
        from up in {"user_permissions", TcmEdu.Accounts.UserPermission},
          where: up.user_id == ^user.id
      )

      # Insert new grants
      for p_name <- permission_names do
        if pid = perm_ids[p_name] do
          TcmEdu.Accounts.UserPermission
          |> Ash.Changeset.for_create(:create, %{user_id: user.id, permission_id: pid})
          |> Ash.create!(authorize?: false)
        end
      end

      changeset
    end)
  end
end
