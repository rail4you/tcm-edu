defmodule TcmEduWeb.AdminLoginLive do
  @moduledoc """
  Admin login page at `/admin/login`.

  Split-screen auth layout (per the daisyUI dashboard skill): branding +
  value props on one side, the form on the other. Two login modes mirror
  the old React admin app — super admin (`public`) and tenant admin.

  The form validates live, and on success natively POSTs to
  `AdminSessionController.create/2` via `phx-trigger-action`, which writes
  the session cookie and redirects to `/admin`.
  """

  use TcmEduWeb, :live_view

  alias TcmEduWeb.AdminAuth

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "管理端登录")
     |> assign(:form, AdminAuth.login_form())
     |> assign(:trigger_action, false)}
  end

  @impl true
  def handle_event("validate", %{"admin" => params}, socket) do
    {:noreply, assign(socket, :form, AdminAuth.login_form(params))}
  end

  def handle_event("switch-mode", %{"mode" => mode}, socket) when mode in ["super", "tenant"] do
    params = %{"mode" => mode, "email" => "", "password" => ""}
    {:noreply, assign(socket, :form, AdminAuth.login_form(params))}
  end

  def handle_event("submit", %{"admin" => params}, socket) do
    changeset = AdminAuth.login_changeset(params)

    if changeset.valid? do
      {:noreply, assign(socket, form: AdminAuth.login_form(params), trigger_action: true)}
    else
      {:noreply, assign(socket, :form, AdminAuth.login_form(params))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin}>
      <div class="grid min-h-screen grid-cols-1 bg-base-100 lg:grid-cols-2">
        <div class="relative hidden flex-col justify-between overflow-hidden bg-neutral p-10 text-neutral-content lg:flex">
          <div
            class="pointer-events-none absolute inset-0 opacity-20"
            style="background-image: radial-gradient(circle at 1px 1px, currentColor 1px, transparent 0); background-size: 24px 24px;"
            aria-hidden="true"
          />
          <div class="relative flex items-center gap-2">
            <span class="flex size-10 items-center justify-center rounded-full bg-primary text-primary-content">
              <.icon name="hero-academic-cap" class="size-5" />
            </span>
            <div>
              <p class="font-semibold">中医教学</p>
              <p class="text-xs opacity-60">管理端</p>
            </div>
          </div>
          <div class="relative flex flex-col gap-6">
            <p class="text-3xl font-semibold leading-snug">
              一个入口，<br />管好所有机构与用户。
            </p>
            <div class="flex flex-col gap-4">
              <div class="card bg-base-100/10 shadow-xs">
                <div class="card-body flex-row items-center gap-4 p-4">
                  <span class="flex size-12 items-center justify-center rounded-full bg-base-100/10">
                    <.icon name="hero-building-office-2" class="size-5" />
                  </span>
                  <div>
                    <p class="font-medium">多租户运营</p>
                    <p class="text-xs opacity-60">租户开停、套餐与数据隔离一目了然</p>
                  </div>
                </div>
              </div>
              <div class="card bg-base-100/10 shadow-xs">
                <div class="card-body flex-row items-center gap-4 p-4">
                  <span class="flex size-12 items-center justify-center rounded-full bg-base-100/10">
                    <.icon name="hero-users" class="size-5" />
                  </span>
                  <div>
                    <p class="font-medium">用户与角色</p>
                    <p class="text-xs opacity-60">管理员、教师、学生的全生命周期管理</p>
                  </div>
                </div>
              </div>
            </div>
          </div>
          <p class="relative text-xs opacity-60">中医教育数字化 · 安全合规的教学管理</p>
        </div>

        <div class="flex items-center justify-center bg-base-200/10 p-4 sm:p-8">
          <div class="card w-full max-w-md bg-base-100 shadow-sm">
            <div class="card-body gap-2.5 p-6 sm:p-8">
              <p class="text-xl font-semibold">欢迎回来</p>
              <p class="text-xs text-base-content/60">登录中医教学管理端</p>

              <div role="tablist" class="tabs tabs-boxed mt-2" aria-label="登录方式">
                <button
                  role="tab"
                  class={["tab", mode(@form) == "super" && "tab-active"]}
                  phx-click="switch-mode"
                  phx-value-mode="super"
                >
                  超级管理员
                </button>
                <button
                  role="tab"
                  class={["tab", mode(@form) == "tenant" && "tab-active"]}
                  phx-click="switch-mode"
                  phx-value-mode="tenant"
                >
                  租户管理员
                </button>
              </div>

              <p class="text-xs text-base-content/60">
                {if mode(@form) == "super",
                  do: "跨租户运营：租户开停与平台总览",
                  else: "本机构管理：用户、教师与学生"}
              </p>

              <.form
                for={@form}
                id="admin-login-form"
                action="/admin/session"
                method="post"
                phx-change="validate"
                phx-submit="submit"
                phx-trigger-action={@trigger_action}
                class="flex flex-col gap-2.5"
              >
                <input type="hidden" name="admin[mode]" value={mode(@form)} />
                <.input
                  field={@form[:email]}
                  type="email"
                  label="邮箱"
                  placeholder="admin@example.com"
                  autocomplete="email"
                  required
                />
                <.input
                  field={@form[:password]}
                  type="password"
                  label="密码"
                  placeholder="请输入密码"
                  autocomplete="current-password"
                  required
                />
                <.button type="submit" class="btn-primary mt-2 w-full">
                  登录
                </.button>
              </.form>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp mode(form) do
    Phoenix.HTML.Form.input_value(form, :mode) || "super"
  end
end
