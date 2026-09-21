defmodule TcmEduWeb.TeacherQuizLive do
  @moduledoc """
  Question bank management at `/teacher/quiz`.

  LiveView replacement for the React `teacher/quiz` page: maintain
  `TcmEdu.Quiz.QuestionBank` records, then add `TcmEdu.Quiz.Question`
  items into the selected bank. Follows the daisyUI dashboard skill
  (metric summary + table + modal forms).
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.TeacherComponents, only: [teacher_shell: 1]

  require Ash.Query

  alias TcmEdu.Quiz.Question
  alias TcmEdu.Quiz.QuestionBank

  on_mount {TcmEduWeb.TeacherAuth, :ensure_teacher}

  @subjects ~w(traditional_chinese_medicine western_medicine anatomy physiology pathology pharmacology clinical nursing public_health other)
  @types ~w(single multi judge essay)
  @per_page 10

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "题库管理")
     |> assign(:page_subtitle, "先建题库，再往里加题")
     |> assign(:selected_bank_id, nil)
     |> assign(:bank_modal, false)
     |> assign(:bank_form, bank_form(%{}))
     |> assign(:question_modal, false)
     |> assign(:question_form, question_form(%{}))
     |> assign(:question_type, "single")
     |> assign(:question_options, default_options())
     |> assign(:option_error, nil)
     |> assign(:question_page, 1)
     |> assign(:editing, nil)
     |> assign(:deleting, nil)
     |> load_banks()}
  end

  @impl true
  def handle_event("select-bank", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(selected_bank_id: id, question_page: 1, editing: nil)
     |> load_questions()}
  end

  def handle_event("open-bank", _params, socket) do
    {:noreply, assign(socket, bank_modal: true, bank_form: bank_form(%{}))}
  end

  def handle_event("close-bank", _params, socket) do
    {:noreply, assign(socket, :bank_modal, false)}
  end

  def handle_event("validate-bank", %{"bank" => params}, socket) do
    {:noreply, assign(socket, :bank_form, bank_form(params))}
  end

  def handle_event("create-bank", %{"bank" => params}, socket) do
    changeset = bank_changeset(params)

    if changeset.valid? do
      get = &Ecto.Changeset.get_field(changeset, &1)
      teacher = socket.assigns.current_teacher

      attrs = %{
        name: get.(:name) |> to_string() |> String.trim(),
        subject: String.to_existing_atom(get.(:subject) || "traditional_chinese_medicine"),
        description: empty_to_nil(get.(:description)),
        is_public: get.(:is_public) == true
      }

      case QuestionBank.create_question_bank(attrs,
             actor: teacher.actor,
             tenant: teacher.tenant
           ) do
        {:ok, bank} ->
          {:noreply,
           socket
           |> assign(bank_modal: false, selected_bank_id: bank.id)
           |> put_flash(:info, "题库《#{bank.name}》已创建")
           |> load_banks()
           |> load_questions()}

        {:error, error} ->
          {:noreply, put_flash(socket, :error, ash_message(error))}
      end
    else
      {:noreply, assign(socket, :bank_form, Phoenix.Component.to_form(changeset, as: "bank"))}
    end
  end

  def handle_event("open-question", _params, socket) do
    if socket.assigns.selected_bank_id do
      {:noreply,
       assign(socket,
         question_modal: true,
         editing: nil,
         question_form: question_form(%{}),
         question_type: "single",
         question_options: default_options(),
         option_error: nil
       )}
    else
      {:noreply, put_flash(socket, :error, "请先选择一个题库")}
    end
  end

  def handle_event("close-question", _params, socket) do
    {:noreply, assign(socket, question_modal: false, editing: nil)}
  end

  def handle_event("open-edit", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.questions, &(&1.id == id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "题目不存在")}

      question ->
        {:noreply,
         assign(socket,
           question_modal: true,
           editing: question,
           question_form: question_form(question_to_params(question)),
           question_type: to_string(question.type || :single),
           question_options: options_from_record(question),
           option_error: nil
         )}
    end
  end

  def handle_event("goto-page", %{"page" => page}, socket) do
    total = total_pages(length(socket.assigns.questions))

    next =
      case Integer.parse(to_string(page)) do
        {n, _} -> n
        :error -> 1
      end
      |> max(1)
      |> min(total)

    {:noreply, assign(socket, :question_page, next)}
  end

  def handle_event("confirm-delete", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.questions, &(&1.id == id)) do
      nil -> {:noreply, put_flash(socket, :error, "题目不存在")}
      question -> {:noreply, assign(socket, :deleting, question)}
    end
  end

  def handle_event("close-delete", _params, socket) do
    {:noreply, assign(socket, :deleting, nil)}
  end

  def handle_event("delete", _params, socket) do
    teacher = socket.assigns.current_teacher
    question = socket.assigns.deleting

    case Ash.destroy(question, actor: teacher.actor, tenant: teacher.tenant) do
      :ok ->
        {:noreply,
         socket
         |> assign(:deleting, nil)
         |> put_flash(:info, "题目已删除")
         |> load_banks()
         |> load_questions()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, ash_message(error))}
    end
  end

  def handle_event("validate-question", %{"question" => params} = all, socket) do
    options =
      case parse_option_params(all["options"]) do
        nil -> socket.assigns.question_options
        parsed -> parsed
      end

    {:noreply,
     assign(socket,
       question_form: question_form(params),
       question_type: params["type"] || "single",
       question_options: options,
       option_error: nil
     )}
  end

  # All question-modal submits funnel here so the typed option rows are never
  # lost: add/remove just mutate the option list, save persists the question.
  def handle_event("submit-question", %{"question" => qparams} = params, socket) do
    options =
      case parse_option_params(params["options"]) do
        nil -> socket.assigns.question_options
        parsed -> parsed
      end

    socket =
      assign(socket,
        question_form: question_form(qparams),
        question_type: qparams["type"] || "single",
        question_options: options,
        option_error: nil
      )

    case params["op"] do
      "add-option" ->
        if length(options) >= 8 do
          {:noreply, put_flash(socket, :error, "最多 8 个选项")}
        else
          {:noreply, assign(socket, :question_options, options ++ [blank_option()])}
        end

      "remove-" <> index ->
        case Integer.parse(index) do
          {idx, ""} when length(options) > 2 ->
            {:noreply, assign(socket, :question_options, List.delete_at(options, idx))}

          _ ->
            {:noreply, put_flash(socket, :error, "选择题至少保留 2 个选项")}
        end

      _ ->
        save_question(socket, qparams, options)
    end
  end

  defp save_question(socket, qparams, options) do
    changeset = question_changeset(qparams)
    type = qparams["type"] || "single"

    with true <- changeset.valid?,
         :ok <- validate_options(type, options) do
      get = &Ecto.Changeset.get_field(changeset, &1)

      attrs = %{
        type: String.to_existing_atom(type),
        difficulty: get.(:difficulty) || 3,
        stem: get.(:stem) |> to_string() |> String.trim(),
        options: build_options(options),
        answer: empty_to_nil(get.(:answer)),
        explanation: empty_to_nil(get.(:explanation))
      }

      case persist_question(socket.assigns.editing, attrs, socket) do
        {:ok, _} ->
          message = if socket.assigns.editing, do: "题目已更新", else: "题目已添加"

          {:noreply,
           socket
           |> assign(question_modal: false, editing: nil)
           |> put_flash(:info, message)
           |> load_banks()
           |> load_questions()}

        {:error, error} ->
          {:noreply, put_flash(socket, :error, ash_message(error))}
      end
    else
      false ->
        {:noreply,
         assign(socket, :question_form, Phoenix.Component.to_form(changeset, as: "question"))}

      {:error, message} ->
        {:noreply,
         socket
         |> assign(:question_form, Phoenix.Component.to_form(changeset, as: "question"))
         |> assign(:option_error, message)}
    end
  end

  defp persist_question(nil, attrs, socket) do
    teacher = socket.assigns.current_teacher

    Question.create_question(Map.put(attrs, :bank_id, socket.assigns.selected_bank_id),
      actor: teacher.actor,
      tenant: teacher.tenant
    )
  end

  defp persist_question(question, attrs, socket) do
    teacher = socket.assigns.current_teacher

    question
    |> Ash.Changeset.for_update(:update, attrs, actor: teacher.actor, tenant: teacher.tenant)
    |> Ash.update()
  end

  defp subject_label(:traditional_chinese_medicine), do: "中医"
  defp subject_label(:western_medicine), do: "西医"
  defp subject_label(:anatomy), do: "解剖"
  defp subject_label(:physiology), do: "生理"
  defp subject_label(:pathology), do: "病理"
  defp subject_label(:pharmacology), do: "药理"
  defp subject_label(:clinical), do: "临床"
  defp subject_label(:nursing), do: "护理"
  defp subject_label(:public_health), do: "公卫"
  defp subject_label(:other), do: "其他"
  defp subject_label(other), do: to_string(other)

  defp type_label(:single), do: "单选"
  defp type_label(:multi), do: "多选"
  defp type_label(:judge), do: "判断"
  defp type_label(:essay), do: "简答"
  defp type_label(other), do: to_string(other)

  defp subject_options,
    do: [
      {"中医", "traditional_chinese_medicine"},
      {"西医", "western_medicine"},
      {"解剖", "anatomy"},
      {"生理", "physiology"},
      {"病理", "pathology"},
      {"药理", "pharmacology"},
      {"临床", "clinical"},
      {"护理", "nursing"},
      {"公卫", "public_health"},
      {"其他", "other"}
    ]

  defp type_options,
    do: [{"单选", "single"}, {"多选", "multi"}, {"判断", "judge"}, {"简答", "essay"}]

  defp difficulty_options, do: Enum.map(1..5, &{to_string(&1), &1})

  defp load_banks(socket) do
    teacher = socket.assigns.current_teacher

    banks =
      try do
        QuestionBank
        |> Ash.Query.for_read(:read, %{}, actor: teacher.actor, tenant: teacher.tenant)
        |> Ash.Query.load([:question_count])
        |> Ash.read!()
        |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      rescue
        _ -> []
      end

    selected =
      cond do
        socket.assigns.selected_bank_id in Enum.map(banks, & &1.id) ->
          socket.assigns.selected_bank_id

        banks == [] ->
          nil

        true ->
          nil
      end

    assign(socket, banks: banks, selected_bank_id: selected, questions: [])
  end

  defp load_questions(socket) do
    if is_nil(socket.assigns.selected_bank_id) do
      assign(socket, questions: [], question_page: 1)
    else
      teacher = socket.assigns.current_teacher

      questions =
        try do
          Question
          |> Ash.Query.for_read(
            :list_by_bank,
            %{bank_id: socket.assigns.selected_bank_id},
            actor: teacher.actor,
            tenant: teacher.tenant
          )
          |> Ash.Query.sort(inserted_at: :desc)
          |> Ash.read!()
        rescue
          _ -> []
        end

      page =
        (socket.assigns[:question_page] || 1)
        |> max(1)
        |> min(total_pages(length(questions)))

      assign(socket, questions: questions, question_page: page)
    end
  end

  defp total_pages(0), do: 1
  defp total_pages(count), do: div(count + @per_page - 1, @per_page)

  defp paged_questions(questions, page) do
    Enum.slice(questions, (page - 1) * @per_page, @per_page)
  end

  # Windowed page numbers with :ellipsis markers for the join control.
  defp page_numbers(_page, total) when total <= 7, do: Enum.to_list(1..total)

  defp page_numbers(page, total) do
    inner = Enum.filter((page - 2)..(page + 2), &(&1 > 1 and &1 < total))

    ([1] ++ inner ++ [total])
    |> Enum.uniq()
    |> Enum.reduce([], fn
      n, [] -> [n]
      n, [prev | _] = acc when n - prev > 1 -> [n, :ellipsis | acc]
      n, acc -> [n | acc]
    end)
    |> Enum.reverse()
  end

  defp question_to_params(question) do
    %{
      "type" => to_string(question.type || :single),
      "difficulty" => question.difficulty || 3,
      "stem" => question.stem || "",
      "answer" => question.answer || "",
      "explanation" => question.explanation || ""
    }
  end

  defp options_from_record(question) do
    rows =
      (question.options || [])
      |> Enum.map(fn opt ->
        %{
          "text" => to_string(opt["text"] || opt[:text] || ""),
          "correct" => !!(opt["correct"] || opt[:correct])
        }
      end)
      |> Enum.reject(&(&1["text"] == ""))

    blanks = for _ <- 1..max(0, 2 - length(rows)), do: blank_option()

    case rows ++ blanks do
      [] -> default_options()
      list -> list
    end
  end

  defp bank_form(params) do
    params |> bank_changeset() |> Phoenix.Component.to_form(as: "bank")
  end

  defp bank_changeset(params) do
    {%{subject: "traditional_chinese_medicine", is_public: false},
     %{name: :string, subject: :string, description: :string, is_public: :boolean}}
    |> Ecto.Changeset.cast(params, [:name, :subject, :description, :is_public])
    |> Ecto.Changeset.validate_required([:name, :subject])
    |> Ecto.Changeset.validate_length(:name, max: 100)
    |> Ecto.Changeset.validate_inclusion(:subject, @subjects)
  end

  defp question_form(params) do
    params |> question_changeset() |> Phoenix.Component.to_form(as: "question")
  end

  defp question_changeset(params) do
    {%{type: "single", difficulty: 3},
     %{
       type: :string,
       difficulty: :integer,
       stem: :string,
       answer: :string,
       explanation: :string
     }}
    |> Ecto.Changeset.cast(params, [:type, :difficulty, :stem, :answer, :explanation])
    |> Ecto.Changeset.validate_required([:type, :stem])
    |> Ecto.Changeset.validate_inclusion(:type, @types)
    |> Ecto.Changeset.validate_number(:difficulty,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 5
    )
    |> Ecto.Changeset.validate_length(:stem, max: 2000)
  end

  defp blank_option, do: %{"text" => "", "correct" => false}

  defp default_options, do: Enum.map(1..4, fn _ -> blank_option() end)

  defp option_letter(index), do: <<65 + index>>

  # Options arrive as `%{"0" => %{"text" => _, "correct" => "true"}, ...}`.
  # Unchecked boxes are absent from params and default to false.
  # Returns nil when the option list isn't rendered (judge/essay).
  defp parse_option_params(nil), do: nil

  defp parse_option_params(params) when is_map(params) do
    params
    |> Enum.map(fn {key, value} ->
      {parse_index(key),
       %{
         "text" => value["text"] |> to_string() |> String.trim(),
         "correct" => value["correct"] == "true"
       }}
    end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end

  defp parse_option_params(_), do: nil

  defp parse_index(key) do
    case Integer.parse(to_string(key)) do
      {idx, _} -> idx
      :error -> 0
    end
  end

  defp validate_options(type, _options) when type in ["judge", "essay"], do: :ok

  defp validate_options(type, options) when type in ["single", "multi"] do
    filled = Enum.filter(options, &(&1["text"] != ""))
    correct = Enum.count(filled, & &1["correct"])

    cond do
      length(filled) < 2 -> {:error, "选择题至少需要 2 个有效选项"}
      type == "single" and correct != 1 -> {:error, "单选题请只勾选一个正确答案"}
      type == "multi" and correct < 1 -> {:error, "多选题请至少勾选一个正确答案"}
      true -> :ok
    end
  end

  defp validate_options(_, _), do: :ok

  defp build_options(options) do
    options
    |> Enum.filter(&(&1["text"] != ""))
    |> Enum.with_index()
    |> Enum.map(fn {opt, index} ->
      %{label: option_letter(index), text: opt["text"], correct: opt["correct"]}
    end)
  end

  defp options_text([]), do: "-"

  defp options_text(options) when is_list(options) do
    options
    |> Enum.map(fn
      %{"label" => label, "text" => text} -> "#{label}. #{text}"
      %{label: label, text: text} -> "#{label}. #{text}"
      other -> inspect(other)
    end)
    |> Enum.join(" / ")
  end

  defp options_text(_), do: "-"

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value) when is_binary(value), do: String.trim(value)
  defp empty_to_nil(value), do: value

  defp ash_message(error) do
    Exception.message(error)
  rescue
    _ -> "操作失败，请稍后重试"
  end
end
