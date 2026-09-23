defmodule TcmEduWeb.LoginLive do
  @moduledoc """
  The single login entrance at `/login`.

  Two login modes, isolated by tabs:

    * super admin (`admin` tab → `super` sub-tab): no tenant needed,
      verified against `public.super_admins`;
    * tenant users (`student` / `teacher` tabs, `admin` tab → `tenant`
      sub-tab): must pick their organization first, credentials are
      verified inside that tenant's schema.

  On submit the credentials are verified inline: failures render an
  inline error while the form (tab, tenant, email AND password) stays
  untouched. Only verified credentials trigger the native POST to
  `SessionController.create/2` via `phx-trigger-action`, which re-verifies,
  writes the portal session and redirects.

  There is no self-registration: accounts are provisioned by super admins
  (admins) and admins (teachers/students) in the admin panel.
  """

  use TcmEduWeb, :live_view

  import Ecto.Changeset, only: [add_error: 3, get_field: 2]

  alias TcmEdu.System.Organization
  alias TcmEduWeb.AdminAuth
  alias TcmEduWeb.StudentAuth
  alias TcmEduWeb.TeacherAuth

  @tabs ~w(student teacher admin)
  @admin_subs ~w(super tenant)

  @impl true
  def mount(params, _session, socket) do
    tab = if params["tab"] in @tabs, do: params["tab"], else: "student"
    admin_sub = if params["admin"] in @admin_subs, do: params["admin"], else: "super"

    {:ok,
     socket
     |> assign(:page_title, "登录")
     |> assign(:tabs, @tabs)
     |> assign(:tab, tab)
     |> assign(:admin_sub, admin_sub)
     |> assign(:tenants, list_tenants())
     |> assign(:auth_error, nil)
     |> assign(:student_form, StudentAuth.login_form())
     |> assign(:teacher_form, TeacherAuth.login_form())
     |> assign(:admin_form, AdminAuth.login_form())
     |> assign(:trigger_action, false)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = if params["tab"] in @tabs, do: params["tab"], else: socket.assigns.tab
    sub = if params["admin"] in @admin_subs, do: params["admin"], else: socket.assigns.admin_sub
    {:noreply, socket |> assign(:tab, tab) |> assign(:admin_sub, sub)}
  end

  @impl true
  def handle_event("switch-tab", %{"tab" => tab}, socket) when tab in @tabs do
    {:noreply,
     socket
     |> assign(:tab, tab)
     |> assign(:trigger_action, false)
     |> assign(:auth_error, nil)
     |> push_patch(to: "/login?tab=#{tab}")}
  end

  def handle_event("switch-admin-sub", %{"sub" => sub}, socket) when sub in @admin_subs do
    {:noreply,
     socket
     |> assign(:admin_sub, sub)
     |> assign(:trigger_action, false)
     |> assign(:auth_error, nil)}
  end

  def handle_event("validate", %{"login" => params}, socket) do
    {:noreply,
     socket
     |> assign(form_assign(socket.assigns.tab), submit_form(socket.assigns, params))
     |> assign(:auth_error, nil)}
  end

  def handle_event("submit", %{"login" => params}, socket) do
    %{tab: tab, admin_sub: sub} = socket.assigns
    form = submit_form(socket.assigns, params)

    if form.source.valid? do
      email = get_field(form.source, :email)
      password = get_field(form.source, :password)
      tenant = empty_to_nil(get_field(form.source, :tenant))

      case verify_credentials(tab, sub, email, password, tenant) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(form_assign(tab), form)
           |> assign(:trigger_action, true)
           |> assign(:auth_error, nil)}

        {:error, _} ->
          {:noreply,
           socket
           |> assign(form_assign(tab), form)
           |> assign(:trigger_action, false)
           |> assign(:auth_error, "邮箱或密码错误，请检查后重试")}
      end
    else
      {:noreply,
       socket
       |> assign(form_assign(tab), form)
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

  defp login_field(assigns) do
    field = assigns.form[assigns.field]
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns =
      assigns
      |> assign(:fname, field.name)
      |> assign(:fvalue, field.value)
      |> assign(:ferrors, Enum.map(errors, &TcmEduWeb.CoreComponents.translate_error/1))
      |> assign(:is_password, assigns.type == "password")
      |> assign(:is_select, not is_nil(assigns.options))

    ~H"""
    <div class="form-control w-full" id={@id} phx-hook={@is_password && "PasswordToggle"}>
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
          type={@type}
          id={"#{@id}-input"}
          name={@fname}
          value={Phoenix.HTML.Form.normalize_value(@type, @fvalue)}
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
          data-pw-toggle
          class="btn btn-ghost btn-sm btn-square absolute right-1 top-1/2 -translate-y-1/2"
          aria-label="显示密码"
        >
          <span data-eye><.icon name="hero-eye" class="size-5" /></span>
          <span data-eye-off class="hidden"><.icon name="hero-eye-slash" class="size-5" /></span>
        </button>
      </div>
      <.error :for={msg <- @ferrors}>{msg}</.error>
    </div>
    """
  end

  defp tab_label("student"), do: "学员"
  defp tab_label("teacher"), do: "教师"
  defp tab_label("admin"), do: "管理"

  defp tab_hint("student", _), do: "学员登录：选择所属机构后登录学习"
  defp tab_hint("teacher", _), do: "教师登录：选择所属机构后备课授课"
  defp tab_hint("admin", "super"), do: "超级管理员：跨租户运营"
  defp tab_hint("admin", _), do: "租户管理员：选择所属机构后管理本机构用户"

  defp tenant_options(tenants), do: Enum.map(tenants, &{&1.name, &1.schema_name})

  defp form_assign("student"), do: :student_form
  defp form_assign("teacher"), do: :teacher_form
  defp form_assign(_), do: :admin_form

  defp changeset_for("student", params), do: StudentAuth.login_changeset(params)
  defp changeset_for("teacher", params), do: TeacherAuth.login_changeset(params)
  defp changeset_for(_, params), do: AdminAuth.login_changeset(params)

  defp submit_form(%{tab: tab, admin_sub: sub}, params) do
    tab
    |> changeset_for(params)
    |> maybe_require_tenant(tab, sub)
    |> Map.put(:action, :validate)
    |> to_form(as: "login")
  end

  # 超管登录不需要选租户；其余都要，否则提交时给出明确提示而不是“没反应”。
  defp maybe_require_tenant(changeset, "admin", "super"), do: changeset

  defp maybe_require_tenant(changeset, _tab, _sub) do
    case empty_to_nil(get_field(changeset, :tenant)) do
      v when v in [nil, ""] -> add_error(changeset, :tenant, "请选择所属机构")
      _ -> changeset
    end
  end

  defp verify_credentials("student", _sub, email, password, tenant),
    do: StudentAuth.authenticate(email, password, tenant)

  defp verify_credentials("teacher", _sub, email, password, tenant),
    do: TeacherAuth.authenticate(email, password, tenant)

  defp verify_credentials("admin", sub, email, password, tenant),
    do: AdminAuth.authenticate(email, password, sub, tenant)

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
