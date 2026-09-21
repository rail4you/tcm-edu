defmodule Mix.Tasks.TcmEdu.SeedSuperAdmin do
  @moduledoc """
  创建初始超级管理员账号。

  用法：

      mix tcm_edu.seed_super_admin EMAIL=admin@example.com PASSWORD=password123 NAME="Root Admin"

  也支持环境变量：

      TCM_EDU_SUPER_ADMIN_EMAIL / TCM_EDU_SUPER_ADMIN_PASSWORD / TCM_EDU_SUPER_ADMIN_NAME

  幂等：已存在则跳过（按 email 去重）。
  """

  use Mix.Task

  alias TcmEdu.System.SuperAdmin

  @shortdoc "创建初始超级管理员账号"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    kv_opts = parse_kv_args(args)

    email = kv_opts[:email] || System.get_env("TCM_EDU_SUPER_ADMIN_EMAIL") || "admin@example.com"
    password = kv_opts[:password] || System.get_env("TCM_EDU_SUPER_ADMIN_PASSWORD")
    name = kv_opts[:name] || System.get_env("TCM_EDU_SUPER_ADMIN_NAME") || "Root Admin"

    if is_nil(password) or password == "" do
      Mix.shell().error(
        "Password is required: pass PASSWORD=... or set TCM_EDU_SUPER_ADMIN_PASSWORD"
      )

      exit({:shutdown, 1})
    end

    if String.length(password) < 8 do
      Mix.shell().error("Password must be at least 8 characters")
      exit({:shutdown, 1})
    end

    require Ash.Query

    case SuperAdmin |> Ash.Query.filter(email == ^email) |> Ash.read(authorize?: false) do
      {:ok, [%SuperAdmin{} = existing]} ->
        Mix.shell().info("✓ SuperAdmin #{email} already exists (id=#{existing.id})")

      {:ok, []} ->
        create_super_admin(email, name, password)

      {:error, reason} ->
        Mix.shell().error("Failed to query super admins: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp create_super_admin(email, name, password) do
    changeset =
      SuperAdmin
      |> Ash.Changeset.for_action(:register, %{
        email: email,
        name: name,
        password: password
      })

    case Ash.create(changeset, authorize?: false) do
      {:ok, %SuperAdmin{} = admin} ->
        Mix.shell().info("✓ Created SuperAdmin: #{admin.email} (id=#{admin.id})")
        Mix.shell().info("  Login at: POST /api/auth/super_admin_sign_in")

      {:error, reason} ->
        Mix.shell().error("Failed to create super admin: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  # Mix tasks receive args as ["EMAIL=foo", "PASSWORD=bar"] rather than
  # ["--email", "foo"], so we parse KEY=VALUE manually.
  defp parse_kv_args(args) do
    Enum.reduce(args, %{}, fn arg, acc ->
      case String.split(arg, "=", parts: 2) do
        [key, value] ->
          Map.put(acc, String.to_atom(String.downcase(key)), value)

        _ ->
          acc
      end
    end)
  end
end
