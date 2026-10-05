defmodule TcmMobile.App do
  @moduledoc """
  中医学院学员端 —— 应用入口与导航声明。

  导航为 4 个 tab 栈（首页 / 课程 / 学习 / 我的），每个栈保有独立历史；
  登录 / 欢迎页作为启动根，登录成功后 `reset_to :home` 清空全部栈。
  """

  use Mob.App, theme: TcmMobile.Theme

  alias TcmMobile.Screens

  @impl Mob.App
  def navigation(_platform) do
    tab_bar([
      stack(:home, root: Screens.HomeScreen, title: "首页"),
      stack(:courses, root: Screens.CoursesScreen, title: "课程"),
      stack(:learning, root: Screens.LearningScreen, title: "学习"),
      stack(:profile, root: Screens.ProfileScreen, title: "我的")
    ])
  end

  @impl Mob.App
  def on_start do
    # BEAM 在 iOS 上做 DNS 解析需要切换查找链，避免 hostname 直连失败。
    Mob.DNS.configure_pure_beam()

    # 屏幕状态持久化（SQLite）
    {:ok, _} = Application.ensure_all_started(:ecto_sqlite3)
    {:ok, _} = TcmMobile.Repo.start_link()

    Ecto.Migrator.with_repo(TcmMobile.Repo, fn repo ->
      Ecto.Migrator.run(repo, migrations_dir(), :up, all: true)
    end)

    # 学员端状态仓库
    {:ok, _} = TcmMobile.Store.start_link()

    # 启动：欢迎/登录页；登录成功后 reset_to :home
    Mob.Screen.start_root(Screens.WelcomeScreen)

    # 开发期热推（mix mob.connect / mix mob.watch）
    Mob.Dist.ensure_started(node: :"tcm_mobile_android@127.0.0.1", cookie: :mob_secret)
  end

  defp migrations_dir do
    case System.get_env("MOB_BEAMS_DIR") do
      nil -> Application.app_dir(:tcm_mobile, "priv/repo/migrations")
      beams_dir -> Path.join([beams_dir, "priv", "repo", "migrations"])
    end
  end
end
