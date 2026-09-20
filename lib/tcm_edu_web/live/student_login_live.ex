defmodule TcmEduWeb.StudentLoginLive do
  @moduledoc """
  Student login / registration at `/login`.

  Two tabs share one trigger-action form posting to
  `StudentSessionController.create/2` with `student[mode]` of `"login"` or
  `"register"`. `?mode=register` deep-links the registration tab.
  """

  use TcmEduWeb, :live_view

  alias TcmEduWeb.StudentAuth

  @impl true
  def mount(params, _session, socket) do
    mode = if params["mode"] == "register", do: "register", else: "login"

    {:ok,
     socket
     |> assign(:page_title, "登录")
     |> assign(:mode, mode)
     |> assign(:login_form, StudentAuth.login_form())
     |> assign(:register_form, StudentAuth.register_form())
     |> assign(:trigger_action, false)}
  end

  @impl true
  def handle_event("switch-mode", %{"mode" => mode}, socket) when mode in ["login", "register"] do
    {:noreply,
     socket
     |> assign(:mode, mode)
     |> assign(:trigger_action, false)
     |> push_patch(to: if(mode == "register", do: "/login?mode=register", else: "/login"))}
  end

  def handle_event("validate-login", %{"student" => params}, socket) do
    {:noreply, assign(socket, :login_form, StudentAuth.login_form(params))}
  end

  def handle_event("submit-login", %{"student" => params}, socket) do
    if StudentAuth.login_changeset(params).valid? do
      {:noreply, assign(socket, login_form: StudentAuth.login_form(params), trigger_action: true)}
    else
      {:noreply, assign(socket, :login_form, StudentAuth.login_form(params))}
    end
  end

  def handle_event("validate-register", %{"student" => params}, socket) do
    {:noreply, assign(socket, :register_form, StudentAuth.register_form(params))}
  end

  def handle_event("submit-register", %{"student" => params}, socket) do
    if StudentAuth.register_changeset(params).valid? do
      {:noreply,
       assign(socket, register_form: StudentAuth.register_form(params), trigger_action: true)}
    else
      {:noreply, assign(socket, :register_form, StudentAuth.register_form(params))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin}>
      <div class="flex min-h-screen items-center justify-center bg-base-200/10 p-4 sm:p-8">
        <div class="card w-full max-w-md bg-base-100 shadow-sm">
          <div class="card-body gap-2.5 p-6 sm:p-8">
            <div class="flex items-center gap-2">
              <span class="flex size-10 items-center justify-center rounded-full bg-primary text-primary-content">
                <.icon name="hero-academic-cap" class="size-5" />
              </span>
              <div>
                <p class="text-xl font-semibold">中医教学</p>
                <p class="text-xs text-base-content/60">学员登录 · 注册即学</p>
              </div>
            </div>

            <div role="tablist" class="tabs tabs-boxed mt-2" aria-label="登录或注册">
              <button
                role="tab"
                class={["tab", @mode == "login" && "tab-active"]}
                phx-click="switch-mode"
                phx-value-mode="login"
              >
                登录
              </button>
              <button
                role="tab"
                class={["tab", @mode == "register" && "tab-active"]}
                phx-click="switch-mode"
                phx-value-mode="register"
              >
                免费注册
              </button>
            </div>

            <.form
              :if={@mode == "login"}
              for={@login_form}
              id="student-login-form"
              action="/student/session"
              method="post"
              phx-change="validate-login"
              phx-submit="submit-login"
              phx-trigger-action={@trigger_action}
              class="flex flex-col gap-2.5"
            >
              <input type="hidden" name="student[mode]" value="login" />
              <.input field={@login_form[:email]} type="email" label="邮箱" placeholder="you@example.com" autocomplete="email" required />
              <.input field={@login_form[:password]} type="password" label="密码" placeholder="请输入密码" autocomplete="current-password" required />
              <.button type="submit" phx-disable-with="登录中..." class="btn-primary mt-2 w-full">
                登录
              </.button>
            </.form>

            <.form
              :if={@mode == "register"}
              for={@register_form}
              id="student-register-form"
              action="/student/session"
              method="post"
              phx-change="validate-register"
              phx-submit="submit-register"
              phx-trigger-action={@trigger_action}
              class="flex flex-col gap-2.5"
            >
              <input type="hidden" name="student[mode]" value="register" />
              <.input field={@register_form[:email]} type="email" label="邮箱" placeholder="you@example.com" autocomplete="email" required />
              <.input field={@register_form[:name]} type="text" label="姓名" placeholder="怎么称呼你（可选）" autocomplete="nickname" />
              <.input field={@register_form[:password]} type="password" label="密码" placeholder="至少 6 位" autocomplete="new-password" required />
              <.input field={@register_form[:password_confirmation]} type="password" label="确认密码" placeholder="再输入一次" autocomplete="new-password" required />
              <.button type="submit" phx-disable-with="注册中..." class="btn-primary mt-2 w-full">
                免费注册
              </.button>
            </.form>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
