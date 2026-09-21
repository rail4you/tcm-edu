ExUnit.configure(exclude: [:ai_integration])
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(TcmEdu.Repo, :manual)

# OSS 签名用的 dummy 凭证：请求层全部被 Req.Test mock，
# 这里只提供签名形状所需的 key（生产 key 只走环境变量，不进仓库）。
System.put_env("OSS_ACCESS_KEY_ID", "test-ak")
System.put_env("OSS_ACCESS_KEY_SECRET", "test-sk")

# In-memory file storage backend for AshStorage tests (see config/test.exs).
AshStorage.Service.Test.start()
