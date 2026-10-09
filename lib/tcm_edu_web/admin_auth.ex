defmodule TcmEduWeb.AdminAuth do
  @moduledoc """
  Session-based authentication for the LiveView admin panel (`/admin/*`).

  Two login modes (mirroring the old React admin app):

    * `"super"` — SuperAdmin from the `public` schema, verified through the
      `sign_in_with_password` action.
    * `"tenant"` — tenant admin (`User` with `role == :tenant_admin`) looked
      up by email or username across all tenant schemas, password verified with Bcrypt.

  On success the session stores:

    * `"admin_id"` / `"admin_role"` (`"super_admin"` | `"tenant_admin"`)
    * `"admin_tenant"` (`"public"` for super admins)
    * `"admin_email"` / `"admin_name"`

  LiveViews use `on_mount({TcmEduWeb.AdminAuth, :ensure_admin})`, and the
  tenants page additionally requires `:ensure_super_admin`.
  """

  import Phoenix.LiveView, only: [put_flash: 3, redirect: 2]
  import Phoenix.Component, only: [assign: 3, to_form: 2]

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.System.Organization
  alias TcmEdu.System.SuperAdmin
  alias TcmEduWeb.LoginIdentity

  @session_keys ~w(admin_id admin_role admin_tenant admin_email admin_name)

  @doc "Session keys written on login (also useful for tests)."
  def session_keys, do: @session_keys

  # ── LiveView hooks ────────────────────────────────────────────────

  def on_mount(:ensure_admin, _params, session, socket) do
    case current_admin(session) do
      {:ok, admin} ->
        {:cont, assign(socket, :current_admin, admin)}

      :error ->
        {:halt,
         socket
         |> put_flash(:error, "请先登录管理端")
         |> redirect(to: "/login")}
    end
  end

  def on_mount(:ensure_super_admin, _params, session, socket) do
    case current_admin(session) do
      {:ok, %{role: "super_admin"} = admin} ->
        {:cont, assign(socket, :current_admin, admin)}

      {:ok, _} ->
        {:halt,
         socket
         |> put_flash(:error, "该页面仅超级管理员可访问")
         |> redirect(to: "/admin")}

      :error ->
        {:halt,
         socket
         |> put_flash(:error, "请先登录管理端")
         |> redirect(to: "/login")}
    end
  end

  @doc """
  Builds `%{...}` session entries for a successfully authenticated admin.
  """
  def build_session(%{role: role} = admin) when role in ["super_admin", "tenant_admin"] do
    %{
      "admin_id" => admin.id,
      "admin_role" => admin.role,
      "admin_tenant" => admin.tenant,
      "admin_email" => admin.email,
      "admin_name" => admin.name
    }
  end

  @doc """
  Loads the current admin from the session. Returns
  `{:ok, admin_map}` or `:error` (missing session, deleted user, or a
  tenant admin that has been disabled).
  """
  def current_admin(session) when is_map(session) do
    with id when is_binary(id) <- session["admin_id"],
         role when role in ["super_admin", "tenant_admin"] <- session["admin_role"],
         tenant when is_binary(tenant) <- session["admin_tenant"],
         {:ok, admin} <- load_actor(role, id, tenant) do
      {:ok, admin}
    else
      _ -> :error
    end
  end

  @doc """
  Verifies admin credentials. `mode` is `"super"` or `"tenant"`.
  When `tenant` (a schema name) is given with `"tenant"` mode, only that
  tenant is checked; otherwise all tenants are scanned. `"super"` mode
  ignores `tenant`. Returns `{:ok, admin_map}` or
  `{:error, :invalid_credentials}`.
  """
  def authenticate(identity, password, mode, tenant \\ nil)

  def authenticate(identity, password, mode, tenant)
      when is_binary(identity) and is_binary(password) do
    identity = String.trim(identity)

    case mode do
      "super" -> authenticate_super_admin(identity, password)
      "tenant" -> authenticate_tenant_admin(identity, password, tenant)
      _ -> {:error, :invalid_credentials}
    end
  end

  def authenticate(_, _, _, _), do: {:error, :invalid_credentials}

  @doc """
  Login form with live validation.

  The changeset always carries the `:validate` action (the same pattern
  `phx.gen.auth` uses) so field errors are available on every
  `phx-change`; `<.input>` still hides them until the field is actually
  used (`Phoenix.Component.used_input?/1`).
  """
  def login_form(params \\ %{}) do
    params
    |> login_changeset()
    |> Map.put(:action, :validate)
    |> to_form(as: "login")
  end

  @doc "Validation changeset backing the login form."
  def login_changeset(params \\ %{}) do
    types = %{email: :string, password: :string, mode: :string, tenant: :string}

    {%{mode: "super"}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:email, :password])
    |> Ecto.Changeset.validate_length(:email, min: 1, message: "请输入邮箱或用户名")
    |> Ecto.Changeset.validate_length(:password, min: 1, message: "请输入密码")
  end

  # ── private ───────────────────────────────────────────────────────

  defp load_actor("super_admin", id, _tenant) do
    case Ash.get(SuperAdmin, id, authorize?: false) do
      {:ok, %SuperAdmin{} = admin} ->
        {:ok,
         %{
           id: admin.id,
           role: "super_admin",
           tenant: "public",
           email: to_string(admin.email),
           name: admin.name || to_string(admin.email),
           actor: admin
         }}

      _ ->
        :error
    end
  end

  defp load_actor("tenant_admin", id, tenant) do
    case Ash.get(User, id, tenant: tenant, authorize?: false) do
      {:ok, %User{role: :tenant_admin, status: :active} = user} ->
        {:ok, user_to_admin(user, tenant)}

      _ ->
        :error
    end
  end

  defp authenticate_super_admin(identity, password) do
    input =
      Ash.ActionInput.for_action(SuperAdmin, :sign_in_with_password, %{
        identity: identity,
        password: password
      })

    case Ash.run_action(input, authorize?: false) do
      {:ok, %{admin: %SuperAdmin{} = admin}} ->
        {:ok,
         %{
           id: admin.id,
           role: "super_admin",
           tenant: "public",
           email: to_string(admin.email),
           name: admin.name || to_string(admin.email),
           actor: admin
         }}

      _ ->
        {:error, :invalid_credentials}
    end
  end

  defp authenticate_tenant_admin(identity, password, tenant) do
    schemas =
      if is_binary(tenant) and byte_size(String.trim(tenant)) > 0 do
        [tenant]
      else
        case Ash.read(Organization, authorize?: false) do
          {:ok, orgs} -> Enum.map(orgs, & &1.schema_name)
          _ -> []
        end
      end

    Enum.find_value(schemas, {:error, :invalid_credentials}, fn schema ->
      LoginIdentity.lookup(User, identity, tenant: schema, authorize?: false)
      |> Enum.find_value(fn
        %User{role: :tenant_admin, status: :active} = user ->
          if Bcrypt.verify_pass(password, user.hashed_password),
            do: {:ok, user_to_admin(user, schema)},
            else: nil

        _ ->
          nil
      end)
    end)
  end

  defp user_to_admin(%User{} = user, tenant) do
    %{
      id: user.id,
      role: "tenant_admin",
      tenant: tenant,
      email: to_string(user.email),
      name: user.full_name || user.name || to_string(user.email),
      full_name: user.full_name,
      actor: user
    }
  end
end
