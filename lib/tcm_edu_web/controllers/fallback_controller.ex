defmodule TcmEduWeb.FallbackController do
  @moduledoc """
  Serves the course dashboard static page from
  `priv/static/course/index.html`.

  The legacy Next.js SPA (`priv/app/`, `/app/*`, and the `/courses`,
  … fallbacks) was fully replaced by LiveView pages in
  Phase 3 — this controller now only keeps the standalone static course
  page.
  """

  use TcmEduWeb, :controller

  @doc """
  Serves the course dashboard static page from `priv/static/course/index.html`.
  """
  def course(conn, _params) do
    course_dir = Application.app_dir(:tcm_edu, "priv/static/course")
    index = Path.join(course_dir, "index.html")

    if File.regular?(index) do
      conn
      |> put_resp_content_type("text/html")
      |> send_file(200, index)
    else
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(200, """
      <!doctype html>
      <html><body style="font-family:sans-serif;padding:2rem">
        <h1>Course Dashboard</h1>
        <p>Static file not found at <code>priv/static/course/index.html</code>.</p>
        <p>Run: <code>cp /path/to/index.html priv/static/course/index.html</code></p>
      </body></html>
      """)
    end
  end
end
