defmodule TcmEduWeb.TeacherAuth do
  @moduledoc """
  Session-based authentication for the LiveView teacher portal (`/teacher/*`).

  Teachers and tenant admins (who may also teach) log in with their tenant
  account. Like `AdminAuth`, the e-mail is looked up across all tenant
  schemas and the password is verified with Bcrypt.

  Session keys: `"teacher_id"` / `"teacher_role"` (`"teacher"` |
  `"tenant_admin"`) / `"teacher_tenant"` / `"teacher_email"` /
  `"teacher_name"`.
  """

  import Phoenix.LiveView, only: [put_flash: 3, redirect: 2]
  import Phoenix.Component, only: [assign: 3, to_form: 2]

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.System.Organization

  @teacher_roles [:teacher, :tenant_admin]

  def on_mount(:ensure_teacher, _params, session, socket) do
    case current_teacher(session) do
      {:ok, teacher} ->
        {:cont, assign(socket, :current_teacher, teacher)}

      :error ->
        {:halt,
         socket
         |> put_flash(:error, "请先登录教师端")
         |> redirect(to: "/login")}
    end
  end

  @doc "Session entries for a successfully authenticated teacher."
  def build_session(%{role: role} = teacher) when role in ["teacher", "tenant_admin"] do
    %{
      "teacher_id" => teacher.id,
      "teacher_role" => teacher.role,
      "teacher_tenant" => teacher.tenant,
      "teacher_email" => teacher.email,
      "teacher_name" => teacher.name
    }
  end

  @doc "Loads the current teacher from the session or returns `:error`."
  def current_teacher(session) when is_map(session) do
    with id when is_binary(id) <- session["teacher_id"],
         role when role in ["teacher", "tenant_admin"] <- session["teacher_role"],
         tenant when is_binary(tenant) <- session["teacher_tenant"],
         {:ok, %User{status: :active, role: user_role} = user} <-
           Ash.get(User, id, tenant: tenant, authorize?: false),
         true <- user_role in @teacher_roles do
      {:ok, teacher_map(user, tenant)}
    else
      _ -> :error
    end
  end

  @doc """
  Verifies teacher credentials. When `tenant` (a schema name) is given,
  only that tenant is checked; otherwise all tenants are scanned.
  Returns `{:ok, teacher_map}` or `{:error, :invalid_credentials}`.
  """
  def authenticate(email, password, tenant \\ nil)

  def authenticate(email, password, tenant) when is_binary(email) and is_binary(password) do
    email = String.trim(email)
    tenants = if tenant_present?(tenant), do: [tenant], else: tenant_schemas()

    Enum.find_value(tenants, {:error, :invalid_credentials}, fn schema ->
      with {:ok, [user]} <-
             User
             |> Ash.Query.filter(email == ^email)
             |> Ash.Query.limit(1)
             |> Ash.read(tenant: schema, authorize?: false),
           %User{status: :active, role: role} = user <- user,
           true <- role in @teacher_roles,
           true <- Bcrypt.verify_pass(password, user.hashed_password) do
        {:ok, teacher_map(user, schema)}
      else
        _ -> nil
      end
    end)
  end

  def authenticate(_, _, _), do: {:error, :invalid_credentials}

  @doc "Login form with live validation (mirrors `AdminAuth.login_form/1`)."
  def login_form(params \\ %{}) do
    params
    |> login_changeset()
    |> Map.put(:action, :validate)
    |> to_form(as: "login")
  end

  @doc "Validation changeset backing the login form."
  def login_changeset(params \\ %{}) do
    types = %{email: :string, password: :string, tenant: :string}

    {%{}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:email, :password])
    |> Ecto.Changeset.validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "邮箱格式不正确")
    |> Ecto.Changeset.validate_length(:password, min: 1, message: "请输入密码")
  end

  # ── private ───────────────────────────────────────────────────────

  defp tenant_present?(tenant) when is_binary(tenant) do
    tenant |> String.trim() |> byte_size() |> Kernel.>(0)
  end

  defp tenant_present?(_), do: false

  defp tenant_schemas do
    case Ash.read(Organization, authorize?: false) do
      {:ok, orgs} -> Enum.map(orgs, & &1.schema_name)
      _ -> []
    end
  end

  defp teacher_map(%User{} = user, tenant) do
    %{
      id: user.id,
      role: to_string(user.role),
      tenant: tenant,
      email: to_string(user.email),
      name: user.name || to_string(user.email),
      actor: user
    }
  end
end
