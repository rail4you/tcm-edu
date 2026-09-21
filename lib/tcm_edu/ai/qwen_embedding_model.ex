defmodule TcmEdu.AI.QwenEmbeddingModel do
  @moduledoc """
  AshAi embedding model backed by DashScope Qwen `text-embedding-v3`.

  Used by the `vectorize` DSL on Ash resources (`embedding_model TcmEdu.AI.QwenEmbeddingModel`).
  Delegates to `TcmEdu.AI.Embeddings`, which reuses the app's Qwen API key
  resolution (`ApiKeyConfig` DB → env → test override).
  """

  use AshAi.EmbeddingModel

  alias TcmEdu.AI.Embeddings

  @impl true
  def dimensions(_opts), do: Embeddings.dimensions()

  @impl true
  def generate(texts, opts) do
    Embeddings.embed(texts, opts)
  end
end
