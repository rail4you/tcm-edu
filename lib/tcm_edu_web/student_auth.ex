defmodule TcmEduWeb.StudentAuth do
  @moduledoc """
  Session-based authentication for the LiveView student portal.

  Students log in with their tenant account (looked up across tenant
  schemas, Bcrypt-verified) or register a fresh account in the default
  tenant. Session keys: `"student_id"` / `"student_role"` / `"student_tenant"`
  / `"student_email"` / `"student_name"`.
  """

  import Phoenix.LiveView, only: [put_flash: 3, redirect: 2]
  import Phoenix.Component, only: [assign: 3, to_form: 2]

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.System.Organization

  @default_tenant "tenant_default"

  def default_tenant, do: @default_tenant

  def on_mount(:ensure_student, _params, session, socket) do
    case current_student(session) do
      {:ok, student} ->
        {:cont, assign(socket, :current_student, student)}

      :error ->
        {:halt,
         socket
         |> put_flash(:error, "请先登录后继续")
         |> redirect(to: "/login")}
    end
  end

  @doc "Puts the current student on the socket when logged in, else nil."
  def on_mount(:fetch_student, _params, session, socket) do
    case current_student(session) do
      {:ok, student} -> {:cont, assign(socket, :current_student, student)}
      :error -> {:cont, assign(socket, :current_student, nil)}
    end
  end

  @doc "Session entries for an authenticated student."
  def build_session(%{role: "student"} = student) do
    %{
      "student_id" => student.id,
      "student_role" => student.role,
      "student_tenant" => student.tenant,
      "student_email" => student.email,
      "student_name" => student.name
    }
  end

  @doc "Loads the current student from the session or returns `:error`."
  def current_student(session) when is_map(session) do
    with id when is_binary(id) <- session["student_id"],
         "student" <- session["student_role"],
         tenant when is_binary(tenant) <- session["student_tenant"],
         {:ok, %User{role: :student, status: :active} = user} <-
           Ash.get(User, id, tenant: tenant, authorize?: false) do
      {:ok, student_map(user, tenant)}
    else
      _ -> :error
    end
  end

  @doc "Verifies student credentials across tenants."
  def authenticate(email, password) when is_binary(email) and is_binary(password) do
    email = String.trim(email)

    Enum.find_value(tenant_schemas(), {:error, :invalid_credentials}, fn schema ->
      with {:ok, [user]} <-
             User
             |> Ash.Query.filter(email == ^email)
             |> Ash.Query.limit(1)
             |> Ash.read(tenant: schema, authorize?: false),
           %User{role: :student, status: :active} = user <- user,
           true <- Bcrypt.verify_pass(password, user.hashed_password) do
        {:ok, student_map(user, schema)}
      else
        _ -> nil
      end
    end)
  end

  def authenticate(_email, _password), do: {:error, :invalid_credentials}

  @doc "Registers a new student in the default tenant and returns its map."
  def register(email, name, password) do
    attrs = %{
      email: String.trim(email),
      name: empty_to_nil(name),
      password: password,
      role: :student
    }

    case User
         |> Ash.Changeset.for_create(:register_with_role, attrs,
           tenant: @default_tenant,
           authorize?: false
         )
         |> Ash.create() do
      {:ok, user} -> {:ok, student_map(user, @default_tenant)}
      {:error, error} -> {:error, ash_message(error)}
    end
  end

  @doc "Login form (live validation)."
  def login_form(params \\ %{}) do
    params |> login_changeset() |> Map.put(:action, :validate) |> to_form(as: "student")
  end

  def login_changeset(params \\ %{}) do
    types = %{email: :string, password: :string}

    {%{}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:email, :password])
    |> Ecto.Changeset.validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/,
      message: "邮箱格式不正确"
    )
    |> Ecto.Changeset.validate_length(:password, min: 1, message: "请输入密码")
  end

  @doc "Registration form (live validation, incl. password confirmation)."
  def register_form(params \\ %{}) do
    params |> register_changeset() |> Map.put(:action, :validate) |> to_form(as: "student")
  end

  def register_changeset(params \\ %{}) do
    types = %{email: :string, name: :string, password: :string, password_confirmation: :string}

    {%{}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:email, :password, :password_confirmation])
    |> Ecto.Changeset.validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/,
      message: "邮箱格式不正确"
    )
    |> Ecto.Changeset.validate_length(:password, min: 6, message: "至少 6 位")
    |> Ecto.Changeset.validate_confirmation(:password, message: "两次输入的密码不一致")
  end

  # ── private ───────────────────────────────────────────────────────

  defp tenant_schemas do
    case Ash.read(Organization, authorize?: false) do
      {:ok, orgs} -> Enum.map(orgs, & &1.schema_name)
      _ -> [@default_tenant]
    end
  end

  defp student_map(%User{} = user, tenant) do
    %{
      id: user.id,
      role: "student",
      tenant: tenant,
      email: to_string(user.email),
      name: user.name || to_string(user.email),
      actor: user
    }
  end

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value) when is_binary(value), do: String.trim(value)

  defp ash_message(error) do
    Exception.message(error)
  rescue
    _ -> "注册失败，请稍后重试"
  end
end
