# Seeds file — creates RBAC structure and sample users.
#
# Run with: mix run priv/repo/seeds.exs

IO.puts("Seeding RBAC data…")

alias TcmEdu.Accounts
import Ash.Query

# ── Helper: find or create ──────────────────────────────────────────

defmodule SeedHelper do
  def ensure_user(email, password, role_name) do
    user =
      TcmEdu.Accounts.User
      |> Ash.Query.filter(email == ^email)
      |> Ash.read_one!(authorize?: false)

    user =
      case user do
        nil ->
          TcmEdu.Accounts.User
          |> Ash.Changeset.for_create(:register_with_role, %{
            email: email,
            password: password,
            role: String.to_existing_atom(role_name)
          })
          |> Ash.create!(authorize?: false)

        u ->
          u
          |> Ash.Changeset.for_update(:update_role, %{role: String.to_existing_atom(role_name)})
          |> Ash.update!(authorize?: false)

          u
      end

    # Fetch or create the role
    role = TcmEdu.Accounts.Role |> Ash.Query.filter(name == ^role_name) |> Ash.read_one!(authorize?: false)

    if role do
      # Ensure user has this role
      existing_ur =
        TcmEdu.Accounts.UserRole
        |> Ash.Query.filter(user_id == ^user.id and role_id == ^role.id)
        |> Ash.read_one!(authorize?: false)

      unless existing_ur do
        TcmEdu.Accounts.UserRole
        |> Ash.Changeset.for_create(:create, %{user_id: user.id, role_id: role.id})
        |> Ash.create!(authorize?: false)
      end
    end

    user
  end

  def ensure_role(name, description) do
    existing =
      TcmEdu.Accounts.Role
      |> Ash.Query.filter(name == ^name)
      |> Ash.read_one!(authorize?: false)

    case existing do
      nil ->
        TcmEdu.Accounts.Role
        |> Ash.Changeset.for_create(:create, %{name: name, description: description})
        |> Ash.create!(authorize?: false)

      r ->
        r
        |> Ash.Changeset.for_update(:update, %{description: description})
        |> Ash.update!(authorize?: false)

        r
    end
  end

  def ensure_permission(name, description) do
    existing =
      TcmEdu.Accounts.Permission
      |> Ash.Query.filter(name == ^name)
      |> Ash.read_one!(authorize?: false)

    case existing do
      nil ->
        TcmEdu.Accounts.Permission
        |> Ash.Changeset.for_create(:create, %{name: name, description: description})
        |> Ash.create!(authorize?: false)

      p -> p
    end
  end

  def ensure_role_permission(role_name, perm_name) do
    role = TcmEdu.Accounts.Role |> Ash.Query.filter(name == ^role_name) |> Ash.read_one!(authorize?: false)
    perm = TcmEdu.Accounts.Permission |> Ash.Query.filter(name == ^perm_name) |> Ash.read_one!(authorize?: false)

    if role && perm do
      existing =
        TcmEdu.Accounts.RolePermission
        |> Ash.Query.filter(role_id == ^role.id and permission_id == ^perm.id)
        |> Ash.read_one!(authorize?: false)

      unless existing do
        TcmEdu.Accounts.RolePermission
        |> Ash.Changeset.for_create(:create, %{role_id: role.id, permission_id: perm.id})
        |> Ash.create!(authorize?: false)
      end
    end
  end
end

# ── Roles ───────────────────────────────────────────────────────────

admin_role = SeedHelper.ensure_role("admin", "Full access to all resources")
IO.puts("  ✓ Role: admin")

user_role = SeedHelper.ensure_role("user", "Basic user with only read access by default")
IO.puts("  ✓ Role: user")

# ── Permissions ─────────────────────────────────────────────────────

perms = %{
  "post:create" => "Create new posts",
  "post:update" => "Edit existing posts",
  "post:delete" => "Delete posts"
}

for {name, desc} <- perms do
  SeedHelper.ensure_permission(name, desc)
  IO.puts("  ✓ Permission: #{name}")
end

# ── Role ↔ Permission mappings ──────────────────────────────────────

# Admin gets all permissions
for name <- Map.keys(perms) do
  SeedHelper.ensure_role_permission("admin", name)
end
IO.puts("  ✓ Admin role has all permissions")

# User gets no extra permissions by default
IO.puts("  ✓ User role has default permissions (read only)")

# ── Sample users ────────────────────────────────────────────────────

SeedHelper.ensure_user("admin@example.com", "password123", "admin")
IO.puts("  ✓ Admin user: admin@example.com / password123")

SeedHelper.ensure_user("user@example.com", "password123", "user")
IO.puts("  ✓ Regular user: user@example.com / password123")

IO.puts("")
IO.puts("Done! Use these credentials to sign in.")
IO.puts("  Admin: admin@example.com / password123")
IO.puts("  User:  user@example.com / password123")
