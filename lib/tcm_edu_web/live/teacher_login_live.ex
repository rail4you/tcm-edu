defmodule TcmEduWeb.TeacherLoginLive do
  @moduledoc """
  Teacher login at `/teacher/login` (split-screen auth, same pattern as
  the admin login). Teachers and tenant admins sign in with their tenant
  account; on success the form natively POSTs to
  `TeacherSessionController.create/2` via `phx-trigger-action`.
  """

  use TcmEduWeb, :live_view

  alias TcmEduWeb.TeacherAuth

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "教师端登录")
     |> assign(:form, TeacherAuth.login_form())
     |> assign(:trigger_action, false)}
  end

  @impl true
  def handle_event("validate", %{"teacher" => params}, socket) do
    {:noreply, assign(socket, :form, TeacherAuth.login_form(params))}
  end

  def handle_event("submit", %{"teacher" => params}, socket) do
    changeset = TeacherAuth.login_changeset(params)

    if changeset.valid? do
      {:noreply, assign(socket, form: TeacherAuth.login_form(params), trigger_action: true)}
    else
      {:noreply, assign(socket, :form, TeacherAuth.login_form(params))}
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
              <p class="text-xs opacity-60">教师端</p>
            </div>
          </div>
          <div class="relative flex flex-col gap-6">
            <p class="text-3xl font-semibold leading-snug">
              备好每一堂课，<br />带好每一位学生。
            </p>
            <div class="flex flex-col gap-4">
              <div class="card bg-base-100/10 shadow-xs">
                <div class="card-body flex-row items-center gap-4 p-4">
                  <span class="flex size-12 items-center justify-center rounded-full bg-base-100/10">
                    <.icon name="hero-book-open" class="size-5" />
                  </span>
                  <div>
                    <p class="font-medium">课程与章节</p>
                    <p class="text-xs opacity-60">创建课程、编排章节课时，一键发布</p>
                  </div>
                </div>
              </div>
              <div class="card bg-base-100/10 shadow-xs">
                <div class="card-body flex-row items-center gap-4 p-4">
                  <span class="flex size-12 items-center justify-center rounded-full bg-base-100/10">
                    <.icon name="hero-users" class="size-5" />
                  </span>
                  <div>
                    <p class="font-medium">学生与跟进</p>
                    <p class="text-xs opacity-60">本机构学生名录，学习情况尽在掌握</p>
                  </div>
                </div>
              </div>
            </div>
          </div>
          <p class="relative text-xs opacity-60">中医教育数字化 · 备课授课一体化</p>
        </div>

        <div class="flex items-center justify-center bg-base-200/10 p-4 sm:p-8">
          <div class="card w-full max-w-md bg-base-100 shadow-sm">
            <div class="card-body gap-2.5 p-6 sm:p-8">
              <p class="text-xl font-semibold">欢迎回来</p>
              <p class="text-xs text-base-content/60">使用机构账号登录教师端</p>

              <.form
                for={@form}
                id="teacher-login-form"
                action="/teacher/session"
                method="post"
                phx-change="validate"
                phx-submit="submit"
                phx-trigger-action={@trigger_action}
                class="mt-2 flex flex-col gap-2.5"
              >
                <.input
                  field={@form[:email]}
                  type="email"
                  label="邮箱"
                  placeholder="teacher@example.com"
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
end
