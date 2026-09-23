defmodule TcmEdu.Accounts.Validations.RestrictTenantAdminRole do
  @moduledoc """
  Only super admins may grant the `:tenant_admin` role.

  Tenant admins manage teachers/students inside their own tenant, but they
  cannot create peer admins or promote users to tenant_admin — that stays a
  super-admin privilege (enforced here in addition to the UI, so direct API
  calls can't escalate either).

  `nil` actors (seeds / tests running with `authorize?: false`) are allowed
  through; real requests without a privileged actor are still rejected by
  the resource policies.

  NOTE: the actor must be set when *building* the changeset/query
  (`for_create/for_update(..., actor: ...)`), not when calling the action
  (`Ash.create(changeset, actor: ...)`). Validations only see the
  build-time actor; policies see both. All LiveView call sites already
  follow the build-time style.
  """

  use Ash.Resource.Validation

  alias TcmEdu.System.SuperAdmin

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, context) do
    # 注意顺序：update_role 把新角色放在 argument 里，此时 attribute 还是旧值，
    # 必须先看 argument，否则短路放行。
    role =
      Ash.Changeset.get_argument(changeset, :role) ||
        Ash.Changeset.get_attribute(changeset, :role)

    cond do
      role != :tenant_admin ->
        :ok

      is_struct(context.actor, SuperAdmin) ->
        :ok

      is_nil(context.actor) ->
        :ok

      true ->
        {:error, field: :role, message: "只有超级管理员可以分配租户管理员角色"}
    end
  end
end
