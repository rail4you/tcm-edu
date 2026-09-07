defmodule TcmEdu.Agents.WebFetchAction do
  @moduledoc """
  Fetches a web page and returns its content as markdown.

  Uses jido_browser's stateless web_fetch — no browser session needed.
  Useful for agents that need to read web content.
  """

  use Jido.Action,
    name: "web_fetch",
    description:
      "Fetches a URL and returns its content as markdown text. Use this to read web pages.",
    schema:
      Zoi.object(%{
        url: Zoi.string(),
        format: Zoi.string() |> Zoi.default("markdown")
      })

  @impl true
  def run(params, _context) do
    format = String.to_existing_atom(params.format)

    case Jido.Browser.web_fetch(params.url,
           format: format,
           timeout: 30_000
         ) do
      {:ok, %{content: content}} ->
        # Truncate very long content for LLM context window
        truncated =
          if byte_size(content) > 8000 do
            String.slice(content, 0, 8000) <> "\n\n... (truncated)"
          else
            content
          end

        {:ok, %{content: truncated, url: params.url, status: "success"}}

      {:error, reason} ->
        {:error, "Failed to fetch #{params.url}: #{inspect(reason)}"}
    end
  end
end
