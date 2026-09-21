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
     |> load_banks()}
  end

  @impl true
  def handle_event("select-bank", %{"id" => id}, socket) do
    {:noreply, socket |> assign(:selected_bank_id, id) |> load_questions()}
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
      {:noreply, assign(socket, question_modal: true, question_form: question_form(%{}))}
    else
      {:noreply, put_flash(socket, :error, "请先选择一个题库")}
    end
  end

  def handle_event("close-question", _params, socket) do
    {:noreply, assign(socket, :question_modal, false)}
  end

  def handle_event("validate-question", %{"question" => params}, socket) do
    {:noreply, assign(socket, :question_form, question_form(params))}
  end

  def handle_event("create-question", %{"question" => params}, socket) do
    changeset = question_changeset(params)

    if changeset.valid? do
      get = &Ecto.Changeset.get_field(changeset, &1)
      teacher = socket.assigns.current_teacher

      attrs = %{
        bank_id: socket.assigns.selected_bank_id,
        type: String.to_existing_atom(get.(:type) || "single"),
        difficulty: get.(:difficulty) || 3,
        stem: get.(:stem) |> to_string() |> String.trim(),
        options: parse_options(get.(:options)),
        answer: empty_to_nil(get.(:answer)),
        explanation: empty_to_nil(get.(:explanation))
      }

      case Question.create_question(attrs, actor: teacher.actor, tenant: teacher.tenant) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:question_modal, false)
           |> put_flash(:info, "题目已添加")
           |> load_questions()
           |> load_banks()}

        {:error, error} ->
          {:noreply, put_flash(socket, :error, ash_message(error))}
      end
    else
      {:noreply,
       assign(socket, :question_form, Phoenix.Component.to_form(changeset, as: "question"))}
    end
  end

  def handle_event("archive-question", %{"id" => id}, socket) do
    teacher = socket.assigns.current_teacher

    with question when not is_nil(question) <-
           Enum.find(socket.assigns.questions, &(&1.id == id)),
         {:ok, _} <-
           question
           |> Ash.Changeset.for_update(:archive, %{},
             actor: teacher.actor,
             tenant: teacher.tenant
           )
           |> Ash.update() do
      {:noreply, socket |> put_flash(:info, "题目已归档") |> load_questions()}
    else
      nil -> {:noreply, put_flash(socket, :error, "题目不存在")}
      {:error, error} -> {:noreply, put_flash(socket, :error, ash_message(error))}
    end
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
      assign(socket, :questions, [])
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

      assign(socket, :questions, questions)
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
       options: :string,
       answer: :string,
       explanation: :string
     }}
    |> Ecto.Changeset.cast(params, [:type, :difficulty, :stem, :options, :answer, :explanation])
    |> Ecto.Changeset.validate_required([:type, :stem])
    |> Ecto.Changeset.validate_inclusion(:type, @types)
    |> Ecto.Changeset.validate_number(:difficulty,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 5
    )
    |> Ecto.Changeset.validate_length(:stem, max: 2000)
  end

  defp parse_options(nil), do: []
  defp parse_options(""), do: []

  defp parse_options(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, options} when is_list(options) ->
        Enum.map(options, fn
          %{"label" => label, "text" => text} = opt ->
            %{label: label, text: text, correct: opt["correct"] == true}

          other ->
            %{label: "?", text: inspect(other), correct: false}
        end)

      _ ->
        []
    end
  end

  defp parse_options(options) when is_list(options), do: options

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
