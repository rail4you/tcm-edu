defmodule TcmEduWeb.LoginIdentity do
  @moduledoc """
  登录身份双通道查找：邮箱或用户名均可登录。

  约定：输入含 `@` 按邮箱（`ci_string`，大小写不敏感）精确查找；
  否则按用户名（`name`）查找，取前 N 个候选，由调用方逐个验密码
  （用户名不唯一，同一租户内重名时只要密码对上即可登录）。
  """

  require Ash.Query

  @name_lookup_limit 5

  @doc """
  按登录身份查找候选用户列表。`read_opts` 透传给 `Ash.read/2`
  （租户资源传 `tenant:` + `authorize?: false`，`SuperAdmin` 只传
  `authorize?: false`）。
  """
  def lookup(resource, identity, read_opts \\ [])

  def lookup(resource, identity, read_opts) when is_binary(identity) do
    identity = String.trim(identity)

    query =
      if String.contains?(identity, "@") do
        resource
        |> Ash.Query.filter(email == ^identity)
        |> Ash.Query.limit(1)
      else
        resource
        |> Ash.Query.filter(name == ^identity)
        |> Ash.Query.limit(@name_lookup_limit)
      end

    case Ash.read(query, read_opts) do
      {:ok, users} -> users
      _ -> []
    end
  end

  def lookup(_resource, _identity, _read_opts), do: []
end
