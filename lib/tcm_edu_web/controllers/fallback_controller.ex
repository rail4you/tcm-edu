defmodule TcmEduWeb.FallbackController do
  @moduledoc """
  Serves Next.js static-export output from `priv/app/` for any request that
  isn't an API call.

  In production:

    * `pnpm --dir frontend build` writes the static export into `priv/app/`.
    * `Plug.Static` (configured in the endpoint) serves CSS/JS/asset files.
    * This controller is the catch-all that returns `index.html` for
      arbitrary paths so client-side routing works.

  In development:

    * `pnpm --dir frontend dev` runs the Next.js dev server on port 3000.
    * Visiting `http://localhost:4000/app/` falls back to whatever was last
      written to `priv/app/` (likely nothing, which is fine — use port 3000
      while developing the frontend).
  """

  use TcmEduWeb, :controller

  @priv_app_dir Application.app_dir(:tcm_edu, "priv/app")

  @doc """
  Serves the SPA root or a deep-linked HTML route. Always responds with
  `priv/app/index.html` if present; otherwise emits a helpful 200 message
  describing how to build the frontend.
  """
  def root(conn, _params) do
    send_spa_index(conn)
  end

  @doc """
  Serves the SPA for any client-side route (e.g. /posts, /posts/new).
  Returns the same index.html so Next.js client-side routing can take over.
  """
  def spa(conn, _params) do
    send_spa_index(conn)
  end

  @doc """
  Catch-all for requests under `/app/*`. Tries to serve an actual file from
  `priv/app/<path>` first; otherwise falls back to `index.html` so Next.js
  client-side routing can take over.
  """
  def app(conn, %{"path" => path_segments}) do
    relative_path =
      path_segments
      |> Enum.reject(&(&1 in ["", ".", ".."]))
      |> Enum.join("/")

    absolute = Path.join(priv_app_dir(), relative_path)

    cond do
      relative_path != "" and File.regular?(absolute) ->
        conn
        |> put_resp_content_type(MIME.from_path(absolute))
        |> send_file(200, absolute)

      true ->
        send_spa_index(conn)
    end
  end

  def app(conn, _params), do: send_spa_index(conn)

  defp send_spa_index(conn) do
    index = Path.join(priv_app_dir(), "index.html")

    if File.regular?(index) do
      conn
      |> put_resp_content_type("text/html")
      |> send_file(200, index)
    else
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(200, missing_app_html())
    end
  end

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

  defp priv_app_dir do
    # Application.app_dir/2 is resolved at compile-time above; recompute at
    # runtime as well so `mix phx.server` from a freshly-checked-out project
    # still finds the directory even when releases relocate priv/.
    Application.app_dir(:tcm_edu, "priv/app")
  end

  defp missing_app_html do
    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <title>tcm-edu</title>
        <style>
          body { font-family: -apple-system, system-ui, sans-serif; max-width: 36rem; margin: 4rem auto; padding: 0 1.5rem; line-height: 1.5; color: #1f2937; }
          code { background: #f3f4f6; padding: 0.1rem 0.4rem; border-radius: 0.25rem; }
          a { color: #2563eb; }
        </style>
      </head>
      <body>
        <h1>tcm-edu</h1>
        <p>The Next.js static export is not present at <code>#{priv_app_dir()}</code>.</p>
        <p>Build the frontend with:</p>
        <pre><code>pnpm --dir frontend install
    pnpm --dir frontend build</code></pre>
        <p>or run it in dev mode at <a href="http://localhost:3000">http://localhost:3000</a>.</p>
      </body>
    </html>
    """
  end

  # Quiet down dialyzer/credo about the unused module attribute on releases.
  _ = @priv_app_dir
end
