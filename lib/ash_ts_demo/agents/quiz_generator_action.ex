defmodule AshTsDemo.Agents.QuizGeneratorAction do
  @moduledoc """
  Generates multiple-choice quiz questions from text.

  Uses text generation (DeepSeek doesn't support JSON mode),
  then parses and validates the output against the quiz schema.
  Returns an error if the LLM output cannot be parsed or validated.
  """

  use Jido.Action,
    name: "generate_quiz",
    description: "Generates multiple-choice quiz questions from text. Validates output format.",
    schema:
      Zoi.object(%{
        text: Zoi.string(),
        topic: Zoi.string() |> Zoi.optional(),
        count: Zoi.integer() |> Zoi.default(1)
      })

  @quiz_schema Zoi.object(%{
                 question: Zoi.string(),
                 options: Zoi.list(Zoi.string()),
                 correct_answer: Zoi.integer()
               })

  @impl true
  def run(params, _context) do
    text = params.text
    topic = Map.get(params, :topic, "")
    count = min(Map.get(params, :count, 1), 5)

    prompt = """
    Generate #{count} multiple-choice quiz question(s) from this text.
    Return ONLY valid JSON, no markdown, no explanation.

    JSON format:
    #{if count > 1, do: "[", else: ""}
    {
      "question": "the question text",
      "options": ["A. option1", "B. option2", "C. option3", "D. option4"],
      "correct_answer": 0
    }
    #{if count > 1, do: "]", else: ""}

    correct_answer must be 0-3 (index of correct option).

    Text: #{text}
    #{if topic != "", do: "Focus on: #{topic}", else: ""}

    JSON:
    """

    case Jido.AI.ask(prompt,
           model: :fast,
           system_prompt:
             "You output ONLY valid JSON. No markdown fences, no explanation. Just the JSON object.",
           temperature: 0.2
         ) do
      {:ok, raw} ->
        parse_and_validate(raw, count)

      {:error, reason} ->
        {:error, "LLM call failed: #{inspect(reason)}"}
    end
  end

  defp parse_and_validate(raw, count) do
    json_str = clean_json(raw)

    case Jason.decode(json_str) do
      {:ok, data} ->
        validate_quiz_data(data, count)

      {:error, reason} ->
        {:error, "Invalid JSON from LLM: #{inspect(reason)}\nRaw: #{String.slice(raw, 0, 200)}"}
    end
  end

  defp clean_json(raw) do
    raw
    |> String.trim()
    # Remove markdown code fences
    |> String.replace(~r/^```(?:json)?\s*\n/, "")
    |> String.replace(~r/\n```\s*$/, "")
    |> String.trim()
  end

  defp validate_quiz_data(data, count) when count > 1 and is_list(data) do
    results = Enum.map(data, &validate_single/1)
    errors = Enum.filter(results, &match?({:error, _}, &1))

    if errors == [] do
      quizzes = Enum.map(results, fn {:ok, q} -> q end)
      {:ok, %{quiz: quizzes}}
    else
      {:error,
       "Validation failed: #{Enum.map_join(errors, "; ", fn {:error, e} -> e end)}\nReceived: #{inspect(data)}"}
    end
  end

  defp validate_quiz_data(data, _count) when is_map(data) do
    validate_single(data)
  end

  defp validate_quiz_data(data, _count) do
    {:error, "Expected JSON object or array, got: #{inspect(data)}"}
  end

  defp validate_single(item) when is_map(item) do
    # Normalize keys: accept both snake_case and camelCase
    normalized =
      item
      |> normalize_keys()
      |> Map.update(:options, [], fn opts ->
        Enum.map(opts, fn o ->
          Regex.replace(~r/^[A-D][.)]\s*/, to_string(o), "")
        end)
      end)
      |> Map.update(:correct_answer, 0, fn a ->
        cond do
          is_integer(a) -> a
          is_float(a) -> trunc(a)
          is_binary(a) ->
            case Integer.parse(String.trim(a)) do
              {n, _} -> n
              :error -> String.upcase(a) |> index_from_letter()
            end
          true -> a
        end
      end)
      |> Map.update(:question, "", fn q -> to_string(q) end)

    case Zoi.parse(@quiz_schema, normalized) do
      {:ok, valid} ->
        # Ensure exactly 4 options
        if length(valid.options) == 4 do
          {:ok, valid}
        else
          {:error, "Expected 4 options, got #{length(valid.options)}"}
        end

      {:error, reason} ->
        {:error, "Schema validation failed: #{inspect(reason)}"}
    end
  end

  defp validate_single(other) do
    {:error, "Expected a JSON object, got: #{inspect(other)}"}
  end

  # Accept both snake_case and camelCase keys from LLM output
  defp normalize_keys(map) do
    Map.new(map, fn {k, v} -> {normalize_key(k), v} end)
  end

  defp normalize_key(k) when is_atom(k), do: k
  defp normalize_key(k) when is_binary(k), do: String.to_existing_atom(k)
  defp normalize_key(k), do: k

  defp index_from_letter("A"), do: 0
  defp index_from_letter("B"), do: 1
  defp index_from_letter("C"), do: 2
  defp index_from_letter("D"), do: 3
  defp index_from_letter(_), do: 0
end
