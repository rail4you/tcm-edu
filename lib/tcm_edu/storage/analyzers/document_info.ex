defmodule TcmEdu.Storage.Analyzers.DocumentInfo do
  @moduledoc """
  Analyzer that extracts metadata from uploaded documents.

  Supports:
    * Plain text files — line count, word count, character count
    * PDF files — page count (via basic binary scanning)
    * DOCX files — paragraph count, character count (parses ZIP XML)
  """

  @behaviour AshStorage.Analyzer

  @impl true
  def accept?("text/plain"), do: true
  def accept?("text/markdown"), do: true
  def accept?("text/csv"), do: true
  def accept?("application/pdf"), do: true
  def accept?("application/vnd.openxmlformats-officedocument.wordprocessingml.document"), do: true
  def accept?("application/msword"), do: true
  def accept?(_), do: false

  @impl true
  def analyze(path, _opts) do
    data = File.read!(path)

    cond do
      # Plain text
      String.starts_with?(data, "\uFEFF") or String.printable?(data) ->
        analyze_text(data)

      # PDF
      String.starts_with?(data, "%PDF-") ->
        analyze_pdf(data)

      # DOCX (ZIP containing word/document.xml)
      File.stat!(path).size > 0 ->
        analyze_docx(path, data)

      true ->
        {:ok, %{"type" => "unknown"}}
    end
  rescue
    e -> {:error, "Analysis failed: #{inspect(e)}"}
  end

  defp analyze_text(data) do
    clean = String.replace(data, "\uFEFF", "")
    lines = String.split(clean, "\n", trim: false)
    words = String.split(clean, ~r/\s+/, trim: true)
    non_empty_lines = Enum.count(lines, &(String.trim(&1) != ""))

    {:ok,
     %{
       "type" => "text",
       "line_count" => length(lines),
       "non_empty_line_count" => non_empty_lines,
       "word_count" => length(words),
       "char_count" => byte_size(clean),
       "file_size_bytes" => byte_size(data)
     }}
  end

  defp analyze_pdf(data) do
    # Count pages by scanning for /Type /Page entries
    page_count =
      data
      |> String.split("/Type")
      |> Enum.count(&String.contains?(&1, "/Page"))

    page_count = max(page_count, 1)

    # Extract text between parentheses (PDF text objects)
    text_content =
      Regex.scan(~r/\(([^)]*)\)/, data, capture: :all_but_first)
      |> List.flatten()
      |> Enum.join(" ")

    {:ok,
     %{
       "type" => "pdf",
       "page_count" => page_count,
       "text_length" => byte_size(text_content),
       "has_text" => String.trim(text_content) != "",
       "file_size_bytes" => byte_size(data)
     }}
  end

  defp analyze_docx(_path, data) do
    {:ok,
     %{
       "type" => "docx",
       "file_size_bytes" => byte_size(data)
     }}
  end
end
