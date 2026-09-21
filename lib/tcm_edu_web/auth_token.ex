defmodule TcmEduWeb.AuthToken do
  @moduledoc """
  生成和验证带 `tenant` / `role` 声明的 JWT。

  与 AshAuthentication 共用同一签名密钥（`config :tcm_edu, :token_signing_secret`），
  所以生成的 JWT 可被现有 `set_actor` plug 解析，**也**支持新增的
  `SetTenantFromToken` plug 读取 tenant 上下文。

  ## Claims

    * `sub`    — 形如 `"user?id=<uuid>"`，AshAuthentication 兼容
    * `tenant` — `"public"` 或 `"tenant_<slug>"`
    * `role`   — `"super_admin"` / `"tenant_admin"` / `"teacher"` / `"student"`
    * `iat`    — 签发时间（unix seconds）
    * `exp`    — 过期时间（默认 24 小时）

  ## 安全

    * HS256 + 密钥取自 config（同 AshAuthentication）
    * 签名前需校验传入 payload 为 plain map
    * `verify/1` 失败统一返回 `:error`，由调用方决定回 401 / 403
  """

  alias Joken
  alias Joken.Signer

  @alg "HS256"
  # 24 小时
  @default_lifetime_seconds 60 * 60 * 24

  @doc """
  生成 JWT。

  ## 参数

    * `subject_id` — 主键 UUID
    * `claims`     — 任意附加声明（`tenant`、`role` 等）

  ## 返回

      {:ok, jwt_string, decoded_claims}
      | {:error, reason}
  """
  @spec generate(String.t(), map()) :: {:ok, String.t(), map()} | {:error, term()}
  def generate(subject_id, claims) when is_binary(subject_id) and is_map(claims) do
    now = System.system_time(:second)

    payload =
      claims
      |> Map.put("sub", "user?id=#{subject_id}")
      |> Map.put("iat", now)
      |> Map.put("exp", now + @default_lifetime_seconds)
      |> ensure_string_keys()

    signer = Signer.create(@alg, secret())

    # Joken API: token_config is for Joken.Claim modules; raw claims go as extra.
    # We pass empty config + payload as extra claims + explicit signer.
    Joken.generate_and_sign(%{}, payload, signer)
  end

  @doc """
  校验 JWT 签名 + 过期时间。返回 claims map。
  """
  @spec verify(String.t()) :: {:ok, map()} | {:error, term()}
  def verify(token) when is_binary(token) do
    # 2-arity verify expects default_signer; pass explicit one via tuple
    Joken.verify(token, Signer.create(@alg, secret()))
  end

  @doc """
  仅读取 claims（不验证签名）。用于调试或已通过其他渠道验证签名后的场景。
  """
  @spec peek(String.t()) :: {:ok, map()} | {:error, term()}
  def peek(token) when is_binary(token), do: Joken.peek_claims(token)

  # ── private ────────────────────────────────────────────────────────

  defp secret do
    Application.fetch_env!(:tcm_edu, :token_signing_secret)
  end

  defp ensure_string_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
