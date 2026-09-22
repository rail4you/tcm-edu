defmodule TcmEduWeb.LoginLive do
  @moduledoc """
  The single login entrance at `/login`.

  Three tabs select the portal — student, teacher or admin (the admin tab
  further splits into super admin vs tenant admin, mirroring the legacy
  admin login). On success the form natively POSTs to
  `SessionController.create/2` via `phx-trigger-action`, which verifies
  the credentials, writes the portal session and redirects.

  There is no self-registration: accounts are provisioned by super admins
  (admins) and admins (teachers/students) in the admin panel.
  """

  use TcmEduWeb, :live_view

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
     |> assign(:student_form, StudentAuth.login_form())
     |> assign(:teacher_form, TeacherAuth.login_form())
     |> assign(:admin_form, AdminAuth.login_form())
     |> assign(:trigger_action, false)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = if params["tab"] in @tabs, do: params["tab"], else: socket.assigns.tab
    {:noreply, assign(socket, :tab, tab)}
  end

  @impl true
  def handle_event("switch-tab", %{"tab" => tab}, socket) when tab in @tabs do
    {:noreply,
     socket
     |> assign(:tab, tab)
     |> assign(:trigger_action, false)
     |> push_patch(to: "/login?tab=#{tab}")}
  end

  def handle_event("switch-admin-sub", %{"sub" => sub}, socket) when sub in @admin_subs do
    {:noreply, assign(socket, :admin_sub, sub)}
  end

  def handle_event("validate", %{"login" => params}, socket) do
    {:noreply, assign(socket, form_assign(socket.assigns.tab), form_for(socket.assigns, params))}
  end

  def handle_event("submit", %{"login" => params}, socket) do
    tab = socket.assigns.tab

    if changeset_for(tab, params).valid? do
      {:noreply,
       assign(socket, form_assign(tab), form_for(socket.assigns, params))
       |> assign(:trigger_action, true)}
    else
      {:noreply, assign(socket, form_assign(tab), form_for(socket.assigns, params))}
    end
  end

  defp tab_label("student"), do: "学员"
  defp tab_label("teacher"), do: "教师"
  defp tab_label("admin"), do: "管理"

  defp tab_hint("student", _), do: "学员登录：选课学习，进度云端同步"
  defp tab_hint("teacher", _), do: "教师 / 机构管理员登录：备课授课"
  defp tab_hint("admin", "super"), do: "超级管理员：跨租户运营"
  defp tab_hint("admin", _), do: "租户管理员：本机构用户管理"

  defp form_assign("student"), do: :student_form
  defp form_assign("teacher"), do: :teacher_form
  defp form_assign(_), do: :admin_form

  defp changeset_for("student", params), do: StudentAuth.login_changeset(params)
  defp changeset_for("teacher", params), do: TeacherAuth.login_changeset(params)
  defp changeset_for(_, params), do: AdminAuth.login_changeset(params)

  defp form_for(%{tab: "student"}, params), do: StudentAuth.login_form(params)
  defp form_for(%{tab: "teacher"}, params), do: TeacherAuth.login_form(params)
  defp form_for(_, params), do: AdminAuth.login_form(params)
end
