defmodule TcmEduWeb.JsonApiRouter do
  @moduledoc """
  AshJsonApi 路由器：`/api/*` 下的 JSON:API 端点全部由各资源的 `json_api`
  DSL 生成，不手写 controller。

  挂载方式见 `TcmEduWeb.Router` —— `scope "/api"` + `forward "/", __MODULE__`，
  **必须声明在所有手工 `/api` 路由之后**（Phoenix 按声明顺序匹配，`forward "/"
  会吞掉 `/api/*` 的一切）。

  认证与租户由 `:api_auth` 管线提供：bearer → `Ash.PlugHelpers.set_actor/2`、
  `TcmEduWeb.Plugs.SetTenantFromToken` → `set_tenant/2`。`AshJsonApi.Request`
  直接读这两个 helper，因此这里无需额外配置；无 token 时 actor 为 nil，
  各资源 policy 会按匿名处理（通常 Forbidden）。
  """

  use AshJsonApi.Router,
    domains: [
      TcmEdu.Enrollment,
      TcmEdu.Courses,
      TcmEdu.Notification,
      TcmEdu.Exam
    ],
    prefix: "/api"
end
