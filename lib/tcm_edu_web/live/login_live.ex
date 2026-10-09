defmodule TcmEduWeb.LoginLive do
  @moduledoc """
  The single login entrance at `/login`.

  Two login modes:

    * tenant mode (default): pick the organization FIRST (top selector),
      then the role (`student` / `teacher` / `tenant_admin`), then
      credentials. Verified inside that tenant's schema.
    * super-admin mode (`/login?mode=super`, reached from the bottom link):
      no tenant selector, verified against `public.super_admins`.

  On submit the credentials are verified inline: failures render an
  inline error while the form stays untouched. Only verified credentials
  trigger the native POST to `SessionController.create/2` via
  `phx-trigger-action`, which re-verifies, writes the portal session and
  redirects.

  Legacy `?tab=` / `?admin=` params are still honored and mapped onto the
  new mode/role state.

  There is no self-registration: accounts are provisioned by super admins
  (admins) and admins (teachers/students) in the admin panel.
  """

  use TcmEduWeb, :live_view

  import Ecto.Changeset, only: [add_error: 3, get_field: 2]

  alias TcmEdu.System.Organization
  alias TcmEduWeb.AdminAuth
  alias TcmEduWeb.StudentAuth
  alias TcmEduWeb.TeacherAuth

  @modes ~w(tenant super)
  @roles ~w(student teacher tenant_admin)

  @impl true
  def mount(params, _session, socket) do
    {mode, role} = resolve_mode_role(params)

    {:ok,
     socket
     |> assign(:page_title, "登录")
     |> assign(:mode, mode)
     |> assign(:role, role)
     |> assign(:roles, @roles)
     |> assign(:tenants, list_tenants())
     |> assign(:auth_error, nil)
     |> assign(:login_form, login_form(mode, %{}))
     |> assign(:show_password, false)
     |> assign(:trigger_action, false)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {mode, role} = resolve_mode_role(params, {socket.assigns.mode, socket.assigns.role})
    {:noreply, socket |> assign(:mode, mode) |> assign(:role, role)}
  end

  @impl true
  def handle_event("switch-mode", %{"mode" => mode}, socket) when mode in @modes do
    role = if mode == "super", do: nil, else: socket.assigns.role || "student"

    {:noreply,
     socket
     |> assign(:mode, mode)
     |> assign(:role, role)
     |> assign(:login_form, login_form(mode, %{}))
     |> assign(:trigger_action, false)
     |> assign(:auth_error, nil)
     |> assign(:show_password, false)
     |> push_patch(to: mode_path(mode, role))}
  end

  def handle_event("switch-role", %{"role" => role}, socket) when role in @roles do
    {:noreply,
     socket
     |> assign(:role, role)
     |> assign(:trigger_action, false)
     |> assign(:auth_error, nil)
     |> assign(:show_password, false)
     |> push_patch(to: mode_path(socket.assigns.mode, role))}
  end

  def handle_event("toggle-password", _params, socket) do
    {:noreply, assign(socket, :show_password, not socket.assigns.show_password)}
  end

  def handle_event("validate", %{"login" => params}, socket) do
    %{mode: mode, role: role} = socket.assigns

    {:noreply,
     socket
     |> assign(:login_form, submit_form(mode, params))
     |> assign(:role, params["role"] || role)
     |> assign(:auth_error, nil)}
  end

  def handle_event("submit", %{"login" => params}, socket) do
    %{mode: mode, role: role} = socket.assigns
    role = params["role"] || role
    form = submit_form(mode, params)

    if form.source.valid? do
      email = get_field(form.source, :email)
      password = get_field(form.source, :password)
      tenant = empty_to_nil(get_field(form.source, :tenant))

      case verify_credentials(mode, role, email, password, tenant) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:login_form, form)
           |> assign(:role, role)
           |> assign(:trigger_action, true)
           |> assign(:auth_error, nil)}

        {:error, _} ->
          {:noreply,
           socket
           |> assign(:login_form, form)
           |> assign(:role, role)
           |> assign(:trigger_action, false)
           |> assign(:auth_error, "账号或密码错误，请检查后重试")}
      end
    else
      {:noreply,
       socket
       |> assign(:login_form, form)
       |> assign(:role, role)
       |> assign(:trigger_action, false)
       |> assign(:auth_error, nil)}
    end
  end

  attr :form, :any, required: true
  attr :field, :atom, required: true
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :type, :string, default: "text"
  attr :icon, :string, required: true
  attr :placeholder, :string, default: ""
  attr :options, :list, default: nil
  attr :prompt, :string, default: nil
  attr :autocomplete, :string, default: nil
  attr :required, :boolean, default: false
  attr :show_password, :boolean, default: false

  defp login_field(assigns) do
    field = assigns.form[assigns.field]
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    input_type =
      if assigns.type == "password" and assigns.show_password, do: "text", else: assigns.type

    assigns =
      assigns
      |> assign(:fname, field.name)
      |> assign(:fvalue, field.value)
      |> assign(:ferrors, Enum.map(errors, &TcmEduWeb.CoreComponents.translate_error/1))
      |> assign(:is_password, assigns.type == "password")
      |> assign(:is_select, not is_nil(assigns.options))
      |> assign(:input_type, input_type)

    ~H"""
    <div class="form-control w-full" id={@id}>
      <label class="label" for={"#{@id}-input"}>
        <span class="label-text">{@label}</span>
      </label>
      <div class="relative">
        <.icon
          name={@icon}
          class="pointer-events-none absolute left-3 top-1/2 z-10 size-5 -translate-y-1/2 text-base-content/40"
        />
        <input
          :if={!@is_select}
          type={@input_type}
          id={"#{@id}-input"}
          name={@fname}
          value={Phoenix.HTML.Form.normalize_value(@input_type, @fvalue)}
          class={[
            "input input-bordered w-full pl-10",
            @is_password && "pr-11",
            @ferrors != [] && "input-error"
          ]}
          placeholder={@placeholder}
          autocomplete={@autocomplete}
          required={@required}
        />
        <select
          :if={@is_select}
          id={"#{@id}-input"}
          name={@fname}
          class={["select select-bordered w-full pl-10", @ferrors != [] && "select-error"]}
          required={@required}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @fvalue)}
        </select>
        <button
          :if={@is_password}
          type="button"
          phx-click="toggle-password"
          class="btn btn-ghost btn-sm btn-square absolute right-1 top-1/2 -translate-y-1/2"
          aria-label={if @show_password, do: "隐藏密码", else: "显示密码"}
        >
          <span :if={!@show_password}><.icon name="hero-eye" class="size-5" /></span>
          <span :if={@show_password}><.icon name="hero-eye-slash" class="size-5" /></span>
        </button>
      </div>
      <.error :for={msg <- @ferrors}>{msg}</.error>
    </div>
    """
  end

  defp role_label("student"), do: "学员"
  defp role_label("teacher"), do: "教师"
  defp role_label("tenant_admin"), do: "租户管理"
  defp role_label(_), do: "学员"

  defp submit_label("student"), do: "登录学习"
  defp submit_label("teacher"), do: "进入教师端"
  defp submit_label("tenant_admin"), do: "进入管理端"
  defp submit_label(_), do: "登录"

  defp mode_path("super", _role), do: "/login?mode=super"
  defp mode_path(_mode, "student"), do: "/login"
  defp mode_path(_mode, role), do: "/login?role=#{role}"

  defp tenant_options(tenants), do: Enum.map(tenants, &{&1.name, &1.schema_name})

  defp login_form("super", params), do: AdminAuth.login_form(params)
  defp login_form(_mode, params), do: StudentAuth.login_form(params)

  defp submit_form("super", params) do
    params
    |> AdminAuth.login_changeset()
    |> Map.put(:action, :validate)
    |> to_form(as: "login")
  end

  defp submit_form(_mode, params) do
    params
    |> StudentAuth.login_changeset()
    |> maybe_require_tenant()
    |> Map.put(:action, :validate)
    |> to_form(as: "login")
  end

  # 租户模式必须选机构，否则提交时给出明确提示而不是“没反应”。
  defp maybe_require_tenant(changeset) do
    case empty_to_nil(get_field(changeset, :tenant)) do
      v when v in [nil, ""] -> add_error(changeset, :tenant, "请选择所属机构")
      _ -> changeset
    end
  end

  defp verify_credentials("super", _role, email, password, _tenant),
    do: AdminAuth.authenticate(email, password, "super")

  defp verify_credentials(_mode, "teacher", email, password, tenant),
    do: TeacherAuth.authenticate(email, password, tenant)

  defp verify_credentials(_mode, "tenant_admin", email, password, tenant),
    do: AdminAuth.authenticate(email, password, "tenant", tenant)

  defp verify_credentials(_mode, _role, email, password, tenant),
    do: StudentAuth.authenticate(email, password, tenant)

  # 新参数 ?mode= / ?role= 优先；旧 ?tab= / ?admin= 映射兼容。
  defp resolve_mode_role(params, default \\ {"tenant", "student"})
  defp resolve_mode_role(%{"mode" => "super"}, _default), do: {"super", nil}

  defp resolve_mode_role(%{"mode" => "tenant"} = params, _default),
    do: {"tenant", role_from(params, "student")}

  defp resolve_mode_role(%{"role" => role}, _default) when role in @roles,
    do: {"tenant", role}

  defp resolve_mode_role(%{"tab" => "teacher"}, _default), do: {"tenant", "teacher"}
  defp resolve_mode_role(%{"tab" => "student"}, _default), do: {"tenant", "student"}

  defp resolve_mode_role(%{"tab" => "admin", "admin" => "tenant"}, _default),
    do: {"tenant", "tenant_admin"}

  defp resolve_mode_role(%{"tab" => "admin"}, _default), do: {"super", nil}
  defp resolve_mode_role(_params, default), do: default

  defp role_from(%{"role" => role}, _default) when role in @roles, do: role
  defp role_from(_params, default), do: default

  defp list_tenants do
    case Ash.read(Organization, authorize?: false) do
      {:ok, orgs} ->
        orgs
        |> Enum.map(&%{name: &1.name, schema_name: &1.schema_name})
        |> Enum.sort_by(& &1.name)

      _ ->
        []
    end
  end

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value) when is_binary(value), do: String.trim(value)
  defp empty_to_nil(value), do: value
end
