defmodule TcmEduWeb.TeacherAISimulatedPatientLive do
  @moduledoc """
  教师端「AI 模拟诊疗」栏目 at `/teacher/ai/simulated-patient`.

  三大子页面（URL 通过 `?tab=` 切换）：

    * `patients`     — 病人档案列表（默认 tab）
    * `assignments`  — 分配管理（教师把病人分配给学生）
    * `evaluations`  — 学生对话会话与 AI 评分

  病人档案的创建 / 编辑模态框内嵌两个 tab：

    * `basic`        — 基本信息（姓名 / 学科 / 主诉 / 病史 / 性格 / 说话方式 / 病人基本信息 key-value）
    * `rubric`       — 评分配置（评分要点 / rubric 维度权重 / 难度 / 轮次）

  教师在 modal 中可点击「加载示例病人」一键套用常见慢性病模板
  （参见 `TcmEdu.SimulatedPatient.Examples`）。

  学科列表翻译成中文显示；profile / rubric / key_points 用动态行
  （每行一个 key + 一个 value 字段），方便教师填写。
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.TeacherComponents, only: [teacher_shell: 1]

  require Ash.Query

  alias TcmEdu.SimulatedPatient.{ClinicalCases, Examples}
  alias TcmEdu.SimulatedPatient.RubricTranslations
  alias TcmEdu.SimulatedPatient.{Assignment, Evaluation, Patient, Session}

  alias TcmEdu.Accounts.User

  on_mount {TcmEduWeb.TeacherAuth, :ensure_teacher}

  @subjects ~w(traditional_chinese_medicine western_medicine anatomy physiology pathology pharmacology clinical nursing public_health other)a
  @per_page 20

  # ── lifecycle ─────────────────────────────────────────────

  @impl true
  def mount(params, _session, socket) do
    tab = normalize_tab(params["tab"])

    socket =
      socket
      |> assign(:page_title, "AI 模拟诊疗")
      |> assign(:page_subtitle, "创建标准化病人档案，分配给学生进行模拟问诊，并查看 AI 评分")
      |> assign(:tab, tab)
      |> assign(:patient_modal, nil)
      |> assign(:patient_form, patient_form(%{}))
      |> assign(:modal_tab, :basic)
      |> assign(:profile_rows, [%{"k" => "", "v" => ""}])
      |> assign(:rubric_rows, default_rubric_rows())
      |> assign(:key_points_lines, [""])
      |> assign(:assign_modal, nil)
      |> assign(:assign_form, assignment_form(%{}))
      |> assign(:search, "")
      |> assign(:status_filter, "all")
      |> load_patients()
      |> load_assignments()
      |> load_sessions()
      |> load_students()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = normalize_tab(params["tab"])
    {:noreply, socket |> assign(:tab, tab)}
  end

  @impl true
  def handle_event("switch-tab", %{"tab" => tab}, socket) do
    # 不要再 assign(:tab)，改由 handle_params 统一把 ?tab= 归一化成 atom，
    # 否则这里把字符串覆盖上去导致 case @tab 无子句匹配 → CaseClauseError。
    {:noreply, push_patch(socket, to: tab_path(tab))}
  end

  def handle_event("search", %{"search" => %{"q" => q}}, socket) do
    {:noreply, socket |> assign(:search, String.trim(q || "")) |> load_patients()}
  end

  def handle_event("filter-status", %{"filter" => %{"status" => status}}, socket) do
    {:noreply, socket |> assign(:status_filter, status) |> load_patients()}
  end

  # ── patient modal ─────────────────────────────────────────

  def handle_event("new-patient", _params, socket) do
    {:noreply,
     socket
     |> open_patient_modal(:new, nil)
     |> reset_modal_state()}
  end

  def handle_event("edit-patient", %{"id" => id}, socket) do
    patient = Enum.find(socket.assigns.patients, &(&1.id == id))

    if patient do
      {:noreply,
       socket
       |> open_patient_modal(:edit, id)
       |> hydrate_modal_from_patient(patient)
       |> assign(:patient_form, patient_form(patient_to_form_attrs(patient)))}
    else
      {:noreply, put_flash(socket, :error, "病人档案不存在或已被删除")}
    end
  end

  def handle_event("cancel-patient-modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:patient_modal, nil)
     |> assign(:patient_form, patient_form(%{}))}
  end

  def handle_event("validate-patient", %{"patient" => params}, socket) do
    {:noreply,
     socket
     |> assign(:patient_form, patient_form(params))
     |> assign(
       :profile_rows,
       params_to_rows(params["profile_keys"], params["profile_values"]) ||
         socket.assigns.profile_rows
     )
     |> assign(
       :rubric_rows,
       params_to_rows(params["rubric_keys"], params["rubric_values"]) ||
         socket.assigns.rubric_rows
     )
     |> assign(:key_points_lines, params_to_lines(params["key_points_lines"]))}
  end

  def handle_event("modal-switch-tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :modal_tab, normalize_modal_tab(tab))}
  end

  # 行级操作 ─────────────────────────────────────────────

  def handle_event("add-profile-row", _params, socket) do
    {:noreply,
     socket
     |> assign(:profile_rows, socket.assigns.profile_rows ++ [%{"k" => "", "v" => ""}])
     |> resync_profile_form()}
  end

  def handle_event("remove-profile-row", %{"idx" => idx}, socket) do
    {:noreply,
     socket
     |> assign(:profile_rows, remove_row_at(socket.assigns.profile_rows, idx))
     |> resync_profile_form()}
  end

  def handle_event("update-profile-row", %{"idx" => idx, "k" => k, "v" => v}, socket) do
    {:noreply,
     socket
     |> assign(:profile_rows, update_row_at(socket.assigns.profile_rows, idx, k, v))
     |> resync_profile_form()}
  end

  def handle_event("add-rubric-row", _params, socket) do
    {:noreply,
     socket
     |> assign(:rubric_rows, socket.assigns.rubric_rows ++ [%{"k" => "", "v" => ""}])
     |> resync_rubric_form()}
  end

  def handle_event("remove-rubric-row", %{"idx" => idx}, socket) do
    {:noreply,
     socket
     |> assign(:rubric_rows, remove_row_at(socket.assigns.rubric_rows, idx))
     |> resync_rubric_form()}
  end

  def handle_event("update-rubric-row", %{"idx" => idx, "k" => k, "v" => v}, socket) do
    {:noreply,
     socket
     |> assign(:rubric_rows, update_row_at(socket.assigns.rubric_rows, idx, k, v))
     |> resync_rubric_form()}
  end

  def handle_event("add-key-point", _params, socket) do
    {:noreply,
     socket
     |> assign(:key_points_lines, socket.assigns.key_points_lines ++ [""])
     |> resync_key_points_form()}
  end

  def handle_event("remove-key-point", %{"idx" => idx}, socket) do
    {:noreply,
     socket
     |> assign(:key_points_lines, remove_row_at(socket.assigns.key_points_lines, idx))
     |> resync_key_points_form()}
  end

  def handle_event("update-key-point", %{"idx" => idx, "v" => v}, socket) do
    {:noreply,
     socket
     |> assign(:key_points_lines, update_row_at(socket.assigns.key_points_lines, idx, nil, v))
     |> resync_key_points_form()}
  end

  # 加载示例病人 ─────────────────────────────────────────

  def handle_event("load-example", %{"key" => key}, socket) do
    # 先查全流程临床病例（包含标准路径与难度分级），再回退到普通 SP 模板
    params = ClinicalCases.to_form_params(key) || Examples.to_form_params(key)

    case params do
      nil ->
        {:noreply, put_flash(socket, :error, "示例模板不存在")}

      params ->
        # 把 red_flags_lines 数组映射成表单的 red_flags_text 文本框（每行一条）
        params =
          Map.put_new(
            params,
            "red_flags_text",
            (params["red_flags_lines"] || []) |> Enum.join("\n")
          )

        {:noreply,
         socket
         |> assign(:patient_form, patient_form(params))
         |> assign(
           :profile_rows,
           params_to_rows(params["profile_keys"], params["profile_values"]) ||
             default_profile_rows()
         )
         |> assign(
           :rubric_rows,
           params_to_rows(params["rubric_keys"], params["rubric_values"]) || default_rubric_rows()
         )
         |> assign(:key_points_lines, params_to_lines(params["key_points_lines"]))
         |> assign(:modal_tab, :basic)
         |> put_flash(:info, "已加载示例病人模板，可继续编辑后保存")}
    end
  end

  def handle_event("save-patient", %{"patient" => params}, socket) do
    teacher = socket.assigns.current_teacher

    case socket.assigns.patient_modal do
      %{mode: :new} ->
        create_patient(socket, params, teacher)

      %{mode: :edit, id: id} ->
        update_patient(socket, id, params, teacher)

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("publish-patient", %{"id" => id}, socket) do
    teacher = socket.assigns.current_teacher

    with %Patient{} = patient <- Enum.find(socket.assigns.patients, &(&1.id == id)),
         {:ok, _} <-
           patient
           |> Ash.Changeset.for_update(:publish, %{},
             actor: teacher.actor,
             tenant: teacher.tenant
           )
           |> Ash.update() do
      {:noreply,
       socket
       |> load_patients()
       |> put_flash(:info, "已发布《#{patient.name}》，可分配给学生")}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "病人档案不存在")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "发布失败：#{ash_message(error)}")}
    end
  end

  def handle_event("archive-patient", %{"id" => id}, socket) do
    teacher = socket.assigns.current_teacher

    with %Patient{} = patient <- Enum.find(socket.assigns.patients, &(&1.id == id)),
         {:ok, _} <-
           patient
           |> Ash.Changeset.for_update(:archive, %{},
             actor: teacher.actor,
             tenant: teacher.tenant
           )
           |> Ash.update() do
      {:noreply,
       socket
       |> load_patients()
       |> put_flash(:info, "已归档《#{patient.name}》")}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "病人档案不存在")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "归档失败：#{ash_message(error)}")}
    end
  end

  def handle_event("delete-patient", %{"id" => id}, socket) do
    teacher = socket.assigns.current_teacher

    case Enum.find(socket.assigns.patients, &(&1.id == id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "病人档案不存在")}

      patient ->
        case Ash.destroy(patient, actor: teacher.actor, tenant: teacher.tenant) do
          :ok ->
            {:noreply,
             socket
             |> load_patients()
             |> put_flash(:info, "已删除《#{patient.name}》")}

          {:error, error} ->
            {:noreply, put_flash(socket, :error, "删除失败：#{ash_message(error)}")}
        end
    end
  end

  # ── assignment modal ──────────────────────────────────────

  def handle_event("open-assign", %{"patient_id" => patient_id}, socket) do
    patient = Enum.find(socket.assigns.patients, &(&1.id == patient_id))

    if patient && patient.status == :published do
      {:noreply,
       socket
       |> assign(:assign_modal, %{patient_id: patient_id, patient_name: patient.name})
       |> assign(:assign_form, assignment_form(%{"patient_id" => patient_id}))}
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         "该病人档案尚未发布，请先发布后再分配"
       )}
    end
  end

  def handle_event("cancel-assign", _params, socket) do
    {:noreply,
     socket
     |> assign(:assign_modal, nil)
     |> assign(:assign_form, assignment_form(%{}))}
  end

  def handle_event("validate-assign", %{"assign" => params}, socket) do
    {:noreply, assign(socket, :assign_form, assignment_form(params))}
  end

  def handle_event("save-assign", %{"assign" => params}, socket) do
    teacher = socket.assigns.current_teacher
    student_id = params["student_id"]

    case Enum.find(socket.assigns.students, &(&1.id == student_id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "请选择学生")}

      student ->
        deadline = parse_deadline(params["deadline"])

        attrs = %{
          patient_id: params["patient_id"],
          student_id: student.id,
          deadline: deadline,
          notes: blank_to_nil(params["notes"]),
          assigned_by_id: teacher.id,
          assigned_by_email: teacher.email
        }

        case Assignment.create_assignment(attrs, actor: teacher.actor, tenant: teacher.tenant) do
          {:ok, _assignment} ->
            {:noreply,
             socket
             |> assign(:assign_modal, nil)
             |> assign(:assign_form, assignment_form(%{}))
             |> load_assignments()
             |> put_flash(
               :info,
               "已把《#{socket.assigns.assign_modal.patient_name}》分配给 #{student.name}"
             )}

          {:error, error} ->
            {:noreply, put_flash(socket, :error, "分配失败：#{ash_message(error)}")}
        end
    end
  end

  def handle_event("delete-assignment", %{"id" => id}, socket) do
    teacher = socket.assigns.current_teacher

    case Enum.find(socket.assigns.assignments, &(&1.id == id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "分配记录不存在")}

      assignment ->
        case Ash.destroy(assignment, actor: teacher.actor, tenant: teacher.tenant) do
          :ok ->
            {:noreply,
             socket
             |> load_assignments()
             |> put_flash(:info, "已删除分配记录")}

          {:error, error} ->
            {:noreply, put_flash(socket, :error, "删除失败：#{ash_message(error)}")}
        end
    end
  end

  def handle_event("retry-evaluation", %{"id" => session_id}, socket) do
    teacher = socket.assigns.current_teacher

    with %Session{} = session <- Enum.find(socket.assigns.sessions, &(&1.id == session_id)) do
      args = %{"tenant" => teacher.tenant, "session_id" => session.id}

      case TcmEdu.Workers.SimulatedPatientEvaluationWorker.new(args) |> Oban.insert() do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "已重新提交 AI 评分，稍后刷新页面")}

        {:error, error} ->
          {:noreply, put_flash(socket, :error, "提交失败：#{inspect(error)}")}
      end
    else
      nil -> {:noreply, put_flash(socket, :error, "会话不存在")}
    end
  end

  # ── save / update helpers ─────────────────────────────────

  defp create_patient(socket, params, teacher) do
    attrs = build_patient_attrs(socket, params, teacher)

    case Patient.create_patient(attrs, actor: teacher.actor, tenant: teacher.tenant) do
      {:ok, patient} ->
        {:noreply,
         socket
         |> assign(:patient_modal, nil)
         |> reset_modal_state()
         |> load_patients()
         |> put_flash(:info, "已创建病人档案《#{patient.name}》")}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(:patient_form, patient_form(params))}
        |> put_flash(:error, "保存失败：#{ash_message(error)}")
    end
  end

  defp update_patient(socket, id, params, teacher) do
    case Enum.find(socket.assigns.patients, &(&1.id == id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "病人档案不存在")}

      patient ->
        attrs =
          build_patient_attrs(socket, params, teacher)
          |> Map.delete(:created_by_id)
          |> Map.delete(:created_by_email)

        case patient
             |> Ash.Changeset.for_update(:update, attrs,
               actor: teacher.actor,
               tenant: teacher.tenant
             )
             |> Ash.update() do
          {:ok, updated} ->
            {:noreply,
             socket
             |> assign(:patient_modal, nil)
             |> reset_modal_state()
             |> load_patients()
             |> put_flash(:info, "已更新《#{updated.name}》")}

          {:error, error} ->
            {:noreply,
             socket
             |> assign(:patient_form, patient_form(params))
             |> put_flash(:error, "保存失败：#{ash_message(error)}")}
        end
    end
  end

  defp build_patient_attrs(socket, params, teacher) do
    # 行级数据直接读 socket assigns（最可靠，不会被 hidden input 丢值）
    profile = rows_to_map(socket.assigns.profile_rows)
    rubric = rows_to_map(socket.assigns.rubric_rows)

    key_points =
      socket.assigns.key_points_lines |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

    %{
      name: blank_to_nil(params["name"]) || "未命名病人",
      subject: parse_subject(params["subject"]),
      scenario_title: blank_to_nil(params["scenario_title"]),
      profile: profile,
      complaint: blank_to_nil(params["complaint"]) || "未填写主诉",
      history: blank_to_nil(params["history"]),
      personality: blank_to_nil(params["personality"]),
      talking_style: blank_to_nil(params["talking_style"]),
      key_points: key_points,
      rubric: rubric,
      difficulty: parse_int(params["difficulty"], 3) |> clamp(1, 5),
      difficulty_level:
        parse_difficulty_level(
          params["difficulty_level"] ||
            patient_form_attr(socket.assigns.patient_form, "difficulty_level")
        ),
      standard_pathway:
        parse_pathway_json(
          params["standard_pathway_json"] ||
            patient_form_attr(socket.assigns.patient_form, "standard_pathway_json")
        ),
      red_flags:
        parse_red_flags(
          params["red_flags_text"] ||
            patient_form_attr(socket.assigns.patient_form, "red_flags_text")
        ),
      min_questions: parse_int(params["min_questions"], 5) |> clamp(3, 30),
      max_turns: parse_int(params["max_turns"], 20) |> clamp(5, 100),
      status: parse_status(params["status"]) || :draft,
      created_by_id: teacher.id,
      created_by_email: teacher.email
    }
  end

  # ── loading ───────────────────────────────────────────────

  defp load_patients(socket) do
    teacher = socket.assigns.current_teacher
    search = String.downcase(socket.assigns.search || "")
    status = socket.assigns.status_filter

    query =
      Patient
      |> Ash.Query.for_read(:read, %{}, actor: teacher.actor, tenant: teacher.tenant)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(@per_page)

    patients =
      case Ash.read(query) do
        {:ok, list} -> list
        _ -> []
      end

    patients =
      patients
      |> Enum.filter(fn p ->
        cond do
          search == "" -> true
          true -> String.contains?(String.downcase(p.name || ""), search)
        end
      end)
      |> Enum.filter(fn p ->
        case status do
          "all" -> true
          s when is_binary(s) -> to_string(p.status) == s
          _ -> true
        end
      end)

    assign(socket, :patients, patients)
  rescue
    _ -> assign(socket, :patients, [])
  end

  defp load_assignments(socket) do
    teacher = socket.assigns.current_teacher

    assignments =
      try do
        Assignment
        |> Ash.Query.for_read(:read, %{}, actor: teacher.actor, tenant: teacher.tenant)
        |> Ash.Query.load([:patient])
        |> Ash.Query.sort(inserted_at: :desc)
        |> Ash.Query.limit(@per_page)
        |> Ash.read!()
      rescue
        _ -> []
      end

    assign(socket, :assignments, assignments)
  end

  defp load_sessions(socket) do
    teacher = socket.assigns.current_teacher

    sessions =
      try do
        Session
        |> Ash.Query.for_read(:read, %{}, actor: teacher.actor, tenant: teacher.tenant)
        |> Ash.Query.sort(inserted_at: :desc)
        |> Ash.Query.limit(@per_page)
        |> Ash.Query.load([:patient, :evaluation, student: []])
        |> Ash.read!()
      rescue
        _ -> []
      end

    assign(socket, :sessions, sessions)
  end

  defp load_students(socket) do
    teacher = socket.assigns.current_teacher
    actor = set_role_atom(teacher.actor)

    students =
      try do
        User
        |> Ash.Query.for_read(:read, %{}, actor: actor, tenant: teacher.tenant)
        |> Ash.Query.filter(role == :student)
        |> Ash.Query.sort(name: :asc)
        |> Ash.Query.limit(500)
        |> Ash.read!(authorize?: false)
      rescue
        _ -> []
      end

    assign(socket, :students, students)
  end

  defp set_role_atom(%{role: role} = actor) when is_binary(role),
    do: Map.put(actor, :role, String.to_existing_atom(role))

  defp set_role_atom(actor), do: actor

  # ── forms ─────────────────────────────────────────────────

  # 病人档案表单只放「顶层」字段；行级（profile / rubric / key_points）
  # 通过隐藏 inputs 同步，详见 `resync_*_form/1`。
  defp patient_form(params) do
    types = %{
      name: :string,
      subject: :string,
      scenario_title: :string,
      complaint: :string,
      history: :string,
      personality: :string,
      talking_style: :string,
      difficulty: :integer,
      difficulty_level: :string,
      standard_pathway_json: :string,
      red_flags_text: :string,
      min_questions: :integer,
      max_turns: :integer,
      status: :string,
      profile_keys: {:array, :string},
      profile_values: {:array, :string},
      rubric_keys: {:array, :string},
      rubric_values: {:array, :string},
      key_points_lines: {:array, :string}
    }

    defaults = %{
      name: "",
      subject: "traditional_chinese_medicine",
      scenario_title: "",
      complaint: "",
      history: "",
      personality: "",
      talking_style: "",
      difficulty: 3,
      difficulty_level: "introductory",
      standard_pathway_json: "",
      red_flags_text: "",
      min_questions: 5,
      max_turns: 20,
      status: "draft",
      profile_keys: [],
      profile_values: [],
      rubric_keys: [],
      rubric_values: [],
      key_points_lines: []
    }

    {defaults, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:name, :complaint])
    |> Ecto.Changeset.validate_length(:complaint, max: 500)
    |> Ecto.Changeset.validate_length(:history, max: 10_000)
    |> Phoenix.Component.to_form(as: "patient")
  end

  defp assignment_form(params) do
    {%{deadline: ""},
     %{patient_id: :string, student_id: :string, deadline: :string, notes: :string}}
    |> Ecto.Changeset.cast(params, [:patient_id, :student_id, :deadline, :notes])
    |> Phoenix.Component.to_form(as: "assign")
  end

  defp default_rubric_rows do
    RubricTranslations.default_label_rows()
  end

  defp default_profile_rows do
    [%{"k" => "", "v" => ""}]
  end

  # ── row helpers ───────────────────────────────────────────

  defp open_patient_modal(socket, mode, id) do
    assign(socket, :patient_modal, %{mode: mode, id: id})
  end

  defp reset_modal_state(socket) do
    socket
    |> assign(:modal_tab, :basic)
    |> assign(:profile_rows, [%{"k" => "", "v" => ""}])
    |> assign(:rubric_rows, default_rubric_rows())
    |> assign(:key_points_lines, [""])
    |> assign(:patient_form, patient_form(%{}))
  end

  defp hydrate_modal_from_patient(socket, %Patient{} = patient) do
    profile_rows =
      (patient.profile || %{})
      |> Enum.map(fn {k, v} -> %{"k" => to_string(k), "v" => to_string(v)} end)
      |> case do
        [] -> [%{"k" => "", "v" => ""}]
        rows -> rows
      end

    rubric_rows =
      (patient.rubric || %{})
      |> Enum.map(fn {k, v} ->
        %{"k" => RubricTranslations.to_label(to_string(k)), "v" => to_string(v)}
      end)
      |> case do
        [] -> default_rubric_rows()
        rows -> rows
      end

    key_points_lines =
      case patient.key_points do
        nil -> [""]
        [] -> [""]
        list -> Enum.map(list, &to_string/1)
      end

    socket
    |> assign(:profile_rows, profile_rows)
    |> assign(:rubric_rows, rubric_rows)
    |> assign(:key_points_lines, key_points_lines)
    |> assign(:modal_tab, :basic)
  end

  # 行级变更后，把当前行状态同步进 form（覆盖对应 hidden 字段），
  # 这样 to_form 后再用 hidden inputs 提交回去不会丢值。
  defp resync_profile_form(socket) do
    rows = socket.assigns.profile_rows

    {keys, values} =
      Enum.reduce(rows, {[], []}, fn %{"k" => k, "v" => v}, {ks, vs} ->
        {ks ++ [k], vs ++ [v]}
      end)

    params =
      socket.assigns.patient_form.params
      |> Map.put("profile_keys", keys)
      |> Map.put("profile_values", values)

    assign(socket, :patient_form, patient_form(params))
  end

  defp resync_rubric_form(socket) do
    rows = socket.assigns.rubric_rows

    {keys, values} =
      Enum.reduce(rows, {[], []}, fn %{"k" => k, "v" => v}, {ks, vs} ->
        {ks ++ [k], vs ++ [v]}
      end)

    params =
      socket.assigns.patient_form.params
      |> Map.put("rubric_keys", keys)
      |> Map.put("rubric_values", values)

    assign(socket, :patient_form, patient_form(params))
  end

  defp resync_key_points_form(socket) do
    params =
      socket.assigns.patient_form.params
      |> Map.put("key_points_lines", socket.assigns.key_points_lines)

    assign(socket, :patient_form, patient_form(params))
  end

  defp params_to_rows(keys, values) when is_list(keys) and is_list(values) do
    keys
    |> Enum.zip(values)
    |> Enum.map(fn {k, v} -> %{"k" => to_string(k || ""), "v" => to_string(v || "")} end)
    |> case do
      [] -> nil
      rows -> rows
    end
  end

  defp params_to_rows(_keys, _values), do: nil

  defp params_to_lines(lines) when is_list(lines) do
    Enum.map(lines, &to_string/1)
  end

  defp params_to_lines(_), do: []

  defp remove_row_at(rows, idx_str) do
    idx = parse_int(idx_str, -1)

    if idx >= 0 do
      rows
      |> Enum.with_index()
      |> Enum.reject(fn {_, i} -> i == idx end)
      |> Enum.map(fn {r, _} -> r end)
      |> case do
        [] -> [%{"k" => "", "v" => ""}]
        result -> result
      end
    else
      rows
    end
  end

  defp update_row_at(rows, idx_str, _k, v) do
    idx = parse_int(idx_str, -1)

    if idx >= 0 do
      Enum.with_index(rows)
      |> Enum.map(fn
        {row, ^idx} when is_map(row) -> %{"k" => row["k"] || "", "v" => v || ""}
        {_row, ^idx} -> v || ""
        {row, _} -> row
      end)
    else
      rows
    end
  end

  defp rows_to_map(nil), do: %{}

  defp rows_to_map(rows) when is_list(rows) do
    rows
    |> Enum.map(fn
      %{"k" => k, "v" => v} when is_binary(k) and is_binary(v) and k != "" ->
        {RubricTranslations.normalize_key(k), String.trim(v)}

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(fn {k, _} -> k == "" end)
    |> Map.new()
  end

  # ── display helpers ───────────────────────────────────────

  defp tab_path(tab), do: "/teacher/ai/simulated-patient?tab=#{tab}"
  defp normalize_tab(nil), do: :patients
  defp normalize_tab("patients"), do: :patients
  defp normalize_tab("assignments"), do: :assignments
  defp normalize_tab("evaluations"), do: :evaluations
  defp normalize_tab(_), do: :patients

  defp normalize_modal_tab(nil), do: :basic
  defp normalize_modal_tab("basic"), do: :basic
  defp normalize_modal_tab("rubric"), do: :rubric
  defp normalize_modal_tab("clinical"), do: :clinical
  defp normalize_modal_tab(_), do: :basic

  defp parse_subject(nil), do: :traditional_chinese_medicine

  defp parse_subject(s) when is_binary(s) do
    # 选项显示的是中文标签（避免英文 atom 直接呈现给学生），这里反向查 atom key
    case Enum.find(@subjects, &(subject_label(&1) == s)) do
      nil -> :traditional_chinese_medicine
      atom -> atom
    end
  end

  defp parse_subject(_), do: :traditional_chinese_medicine

  defp parse_status(nil), do: :draft
  defp parse_status(s) when is_binary(s), do: String.to_existing_atom(s)
  defp parse_status(_), do: :draft

  defp parse_difficulty_level(nil), do: :introductory

  defp parse_difficulty_level(s) when is_binary(s) do
    case String.to_existing_atom(s) do
      l when l in [:introductory, :advanced, :expert, :emergency] -> l
      _ -> :introductory
    end
  rescue
    _ -> :introductory
  end

  defp parse_difficulty_level(_), do: :introductory

  # 解析标准路径 JSON 文本；空或非法回退 %{}（保持原问诊模式）
  defp parse_pathway_json(nil), do: %{}
  defp parse_pathway_json(""), do: %{}

  defp parse_pathway_json(text) when is_binary(text) do
    case Jason.decode(String.trim(text)) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  defp parse_pathway_json(_), do: %{}

  # 把 red flags 文本框按行拆成数组
  defp parse_red_flags(nil), do: []
  defp parse_red_flags(""), do: []

  defp parse_red_flags(text) when is_binary(text) do
    text
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_red_flags(_), do: []

  defp parse_int(nil, _default), do: nil
  defp parse_int("", default), do: default
  defp parse_int(value, _default) when is_integer(value), do: value

  defp parse_int(value, _default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp parse_int(_, default), do: default

  defp clamp(value, _min, _max) when not is_integer(value), do: value
  defp clamp(value, min, _max) when is_integer(value) and value < min, do: min
  defp clamp(value, _min, max) when is_integer(value) and value > max, do: max
  defp clamp(value, _min, _max) when is_integer(value), do: value

  defp parse_deadline(""), do: nil
  defp parse_deadline(nil), do: nil

  defp parse_deadline(text) when is_binary(text) do
    case DateTime.from_iso8601(text) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_deadline(_), do: nil

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value) when is_binary(value), do: String.trim(value)
  defp blank_to_nil(value), do: value

  defp patient_to_form_attrs(patient) do
    profile_lines = map_to_pairs(patient.profile)

    rubric_lines =
      (patient.rubric || %{})
      |> Enum.map(fn {k, v} -> {RubricTranslations.to_label(to_string(k)), to_string(v)} end)
      |> Enum.sort_by(&elem(&1, 0))

    %{
      "name" => patient.name || "",
      "subject" => subject_label(patient.subject || :traditional_chinese_medicine),
      "scenario_title" => patient.scenario_title || "",
      "complaint" => patient.complaint || "",
      "history" => patient.history || "",
      "personality" => patient.personality || "",
      "talking_style" => patient.talking_style || "",
      "key_points_lines" => patient.key_points || [],
      "profile_keys" => Enum.map(profile_lines, &elem(&1, 0)),
      "profile_values" => Enum.map(profile_lines, &elem(&1, 1)),
      "rubric_keys" => Enum.map(rubric_lines, &elem(&1, 0)),
      "rubric_values" => Enum.map(rubric_lines, &elem(&1, 1)),
      "difficulty" => patient.difficulty || 3,
      "difficulty_level" => to_string(patient.difficulty_level || :introductory),
      "standard_pathway_json" => encode_pathway(patient.standard_pathway),
      "red_flags_text" => Enum.join(patient.red_flags || [], "\n"),
      "min_questions" => patient.min_questions || 5,
      "max_turns" => patient.max_turns || 20,
      "status" => to_string(patient.status || "draft")
    }
  end

  defp encode_pathway(nil), do: ""
  defp encode_pathway(%{} = map) when map_size(map) == 0, do: ""

  defp encode_pathway(map) when is_map(map) do
    Jason.encode!(map)
  end

  defp encode_pathway(_), do: ""

  defp map_to_pairs(nil), do: []

  defp map_to_pairs(map) when is_map(map) do
    map |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end) |> Enum.sort_by(&elem(&1, 0))
  end

  defp subject_options do
    Enum.map(@subjects, fn s -> {subject_label(s), subject_label(s)} end)
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

  defp status_badge(:draft), do: "badge-ghost"
  defp status_badge(:published), do: "badge-success"
  defp status_badge(:archived), do: "badge-warning"
  defp status_badge(_), do: "badge-ghost"

  defp status_text(:draft), do: "草稿"
  defp status_text(:published), do: "已发布"
  defp status_text(:archived), do: "已归档"
  defp status_text(_), do: "未知"

  defp student_name(students, user_id) do
    case Enum.find(students, &(&1.id == user_id)) do
      nil -> "—"
      user -> user.name || user.email || "—"
    end
  end

  defp assignment_patient_name(%{patient: %Patient{name: name}}) when is_binary(name), do: name
  defp assignment_patient_name(_), do: "—"

  defp truncate(text, max) when is_binary(text) do
    if String.length(text) > max, do: String.slice(text, 0, max) <> "…", else: text
  end

  defp truncate(_, _), do: ""

  defp ash_message(error) do
    Exception.message(error)
  rescue
    _ -> "操作失败，请稍后重试"
  end

  defp format_date(nil), do: "—"

  defp format_date(%DateTime{} = dt) do
    Calendar.strftime(dt, "%m-%d %H:%M")
  end

  defp format_date(_), do: "—"

  defp evaluation_status_badge(:none), do: "badge-ghost"
  defp evaluation_status_badge(:pending), do: "badge-info"
  defp evaluation_status_badge(:running), do: "badge-warning"
  defp evaluation_status_badge(:completed), do: "badge-success"
  defp evaluation_status_badge(:failed), do: "badge-error"
  defp evaluation_status_badge(_), do: "badge-ghost"

  defp evaluation_status_text(:none), do: "未评分"
  defp evaluation_status_text(:pending), do: "排队中"
  defp evaluation_status_text(:running), do: "评分中"
  defp evaluation_status_text(:completed), do: "已评分"
  defp evaluation_status_text(:failed), do: "评分失败"
  defp evaluation_status_text(_), do: "未知"

  defp evaluation_for(sessions, session_id) do
    case Enum.find(sessions, &(&1.id == session_id)) do
      %Session{evaluation: %Evaluation{} = eval} -> eval
      _ -> nil
    end
  end

  # ── render ────────────────────────────────────────────────

  # ── tabs（与 teacher_courses 的 daisyUI tabs tabs-box 风格统一）──

  attr :tab, :atom, required: true
  attr :current, :atom, required: true
  attr :label, :string, required: true
  attr :count, :integer, default: 0

  defp tab_button(assigns) do
    ~H"""
    <button
      type="button"
      role="tab"
      phx-click="switch-tab"
      phx-value-tab={@tab}
      class={["tab", @current == @tab && "tab-active"]}
    >
      {@label}
      <span class={["badge badge-xs ms-1", @current == @tab && "badge-primary", @current != @tab && "badge-ghost"]}>
        {@count}
      </span>
    </button>
    """
  end

  defp patients_tab(assigns) do
    ~H"""
    <div class="card border border-base-300 bg-base-100">
      <div class="card-body gap-3 p-4 sm:p-6">
        <div class="flex flex-wrap items-center gap-2">
          <.form
            for={%{}}
            as={:search}
            phx-change="search"
            id="patient-search"
            class="flex items-center gap-2"
          >
            <label class="input input-sm input-bordered flex items-center gap-2">
              <.icon name="hero-magnifying-glass" class="size-4" />
              <input
                type="text"
                name="search[q]"
                value={@search}
                placeholder="按姓名搜索"
                class="grow"
              />
            </label>
          </.form>
          <.form
            for={%{}}
            as={:filter}
            phx-change="filter-status"
            id="patient-filter"
            class="flex items-center gap-2"
          >
            <select name="filter[status]" class="select select-sm select-bordered">
              <option value="all" selected={@status_filter == "all"}>全部状态</option>
              <option value="draft" selected={@status_filter == "draft"}>草稿</option>
              <option value="published" selected={@status_filter == "published"}>已发布</option>
              <option value="archived" selected={@status_filter == "archived"}>已归档</option>
            </select>
          </.form>
        </div>

        <p :if={@patients == []} class="py-10 text-center text-sm text-base-content/60">
          还没有病人档案。点击右上角「新建病人档案」开始。
        </p>

        <div :if={@patients != []} class="grid items-start gap-4 lg:grid-cols-2 xl:grid-cols-3">
          <article
            :for={patient <- @patients}
            id={"patient-#{patient.id}"}
            class="card border border-base-300 bg-base-100"
          >
            <div class="card-body gap-2 p-4">
              <div class="flex items-start justify-between gap-2">
                <div class="flex flex-col gap-0.5">
                  <p class="text-base font-semibold">{patient.name}</p>
                  <p class="text-xs text-base-content/60">{subject_label(patient.subject)}</p>
                </div>
                <span class={["badge badge-soft", status_badge(patient.status)]}>
                  {status_text(patient.status)}
                </span>
              </div>

              <p :if={patient.scenario_title} class="text-sm font-medium">
                {patient.scenario_title}
              </p>
              <p class="line-clamp-3 text-sm text-base-content/80">
                <span class="text-base-content/60">主诉：</span>
                {patient.complaint}
              </p>

              <div class="mt-1 flex flex-wrap items-center gap-1 text-xs">
                <span class="badge badge-soft badge-sm">
                  难度 {patient.difficulty}/5
                </span>
                <span class="badge badge-soft badge-sm">
                  {length(patient.key_points || [])} 个评分点
                </span>
                <span class="badge badge-soft badge-sm">
                  {patient.min_questions}-{patient.max_turns} 轮
                </span>
              </div>

              <div class="mt-2 flex flex-wrap items-center gap-2">
                <button
                  type="button"
                  id={"edit-patient-#{patient.id}"}
                  phx-click="edit-patient"
                  phx-value-id={patient.id}
                  class="btn btn-ghost btn-xs"
                >
                  <.icon name="hero-pencil-square" class="size-3.5" /> 编辑
                </button>
                <button
                  :if={patient.status == :draft}
                  type="button"
                  id={"publish-patient-#{patient.id}"}
                  phx-click="publish-patient"
                  phx-value-id={patient.id}
                  class="btn btn-ghost btn-xs text-success"
                >
                  <.icon name="hero-check-circle" class="size-3.5" /> 发布
                </button>
                <button
                  :if={patient.status != :archived}
                  type="button"
                  id={"archive-patient-#{patient.id}"}
                  phx-click="archive-patient"
                  phx-value-id={patient.id}
                  class="btn btn-ghost btn-xs"
                >
                  <.icon name="hero-archive-box" class="size-3.5" /> 归档
                </button>
                <button
                  :if={patient.status == :published}
                  type="button"
                  id={"assign-patient-#{patient.id}"}
                  phx-click="open-assign"
                  phx-value-patient_id={patient.id}
                  class="btn btn-primary btn-xs"
                >
                  <.icon name="hero-user-plus" class="size-3.5" /> 分配给学生
                </button>
                <button
                  type="button"
                  id={"delete-patient-#{patient.id}"}
                  phx-click="delete-patient"
                  phx-value-id={patient.id}
                  data-confirm="确定删除该病人档案吗？相关分配与历史评分会保留但不可继续分配。"
                  class="btn btn-ghost btn-xs ms-auto text-error"
                >
                  <.icon name="hero-trash" class="size-3.5" />
                </button>
              </div>
            </div>
          </article>
        </div>
      </div>
    </div>
    """
  end

  defp assignments_tab(assigns) do
    ~H"""
    <div class="card border border-base-300 bg-base-100">
      <div class="card-body gap-3 p-4 sm:p-6">
        <p class="font-medium">已分配的任务（最近 20 条）</p>
        <p :if={@assignments == []} class="py-10 text-center text-sm text-base-content/60">
          暂无分配记录。回到「病人档案」标签页，把已发布的病人分配给学生。
        </p>
        <div :if={@assignments != []} class="overflow-x-auto">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>病人</th>
                <th>学生</th>
                <th>状态</th>
                <th>截止</th>
                <th>创建时间</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={assignment <- @assignments} id={"assignment-#{assignment.id}"}>
                <td class="font-medium">{assignment_patient_name(assignment)}</td>
                <td>{student_name(@students, assignment.student_id)}</td>
                <td>
                  <span class={["badge badge-soft", assignment_badge(assignment.status)]}>
                    {assignment_status_text(assignment.status)}
                  </span>
                </td>
                <td>{format_date(assignment.deadline)}</td>
                <td class="text-xs text-base-content/60">{format_date(assignment.inserted_at)}</td>
                <td>
                  <button
                    type="button"
                    id={"delete-assignment-#{assignment.id}"}
                    phx-click="delete-assignment"
                    phx-value-id={assignment.id}
                    data-confirm="确定删除该分配记录吗？"
                    class="btn btn-ghost btn-xs text-error"
                  >
                    <.icon name="hero-trash" class="size-3.5" />
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  defp evaluations_tab(assigns) do
    ~H"""
    <div class="card border border-base-300 bg-base-100">
      <div class="card-body gap-3 p-4 sm:p-6">
        <p class="font-medium">学生对话与 AI 评分（最近 20 条会话）</p>
        <p :if={@sessions == []} class="py-10 text-center text-sm text-base-content/60">
          暂无对话记录。
        </p>
        <div :if={@sessions != []} class="grid items-start gap-4 lg:grid-cols-2">
          <article
            :for={session <- @sessions}
            id={"session-#{session.id}"}
            class="card border border-base-300 bg-base-100"
          >
            <div class="card-body gap-2 p-4">
              <div class="flex items-start justify-between gap-2">
                <div class="flex flex-col gap-0.5">
                  <p class="text-base font-semibold">
                    {(session.patient && session.patient.name) || session.patient_id}
                  </p>
                  <p class="text-xs text-base-content/60">
                    学生：{student_name(@students, session.student_id)} · 轮次：{session.turn_count}
                  </p>
                </div>
                <span class={["badge badge-soft", evaluation_status_badge(session.evaluation_status)]}>
                  {evaluation_status_text(session.evaluation_status)}
                </span>
              </div>

              {eval_summary(assigns, session)}

              <div class="mt-1 flex flex-wrap items-center gap-2 text-xs">
                <span class="text-base-content/60">
                  会话状态：{session_status_text(session.status)}
                </span>
                <span :if={session.ended_reason} class="text-base-content/60">
                  · {session.ended_reason}
                </span>
                <span class="ms-auto">{format_date(session.inserted_at)}</span>
              </div>

              <div :if={session.evaluation_error} class="alert alert-warning alert-soft text-xs">
                <span>{truncate(session.evaluation_error, 200)}</span>
              </div>

              <div class="mt-2 flex flex-wrap items-center gap-2">
                <button
                  :if={session.evaluation_status == :failed}
                  type="button"
                  id={"retry-eval-#{session.id}"}
                  phx-click="retry-evaluation"
                  phx-value-id={session.id}
                  class="btn btn-primary btn-xs"
                >
                  <.icon name="hero-arrow-path" class="size-3.5" /> 重试评分
                </button>
              </div>
            </div>
          </article>
        </div>
      </div>
    </div>
    """
  end

  defp eval_summary(assigns, session) do
    case evaluation_for(assigns.sessions, session.id) do
      %Evaluation{} = evaluation ->
        assigns =
          assigns
          |> assign(:evaluation, evaluation)
          |> assign(:highlights_text, Enum.join(evaluation.highlights || [], "；"))
          |> assign(:weaknesses_text, Enum.join(evaluation.weaknesses || [], "；"))

        ~H"""
        <div class="rounded-box border border-base-300 bg-base-200/30 p-3 text-sm">
          <div class="grid grid-cols-3 gap-2 text-center">
            <.score_cell label="专业度" value={@evaluation.professional_score} />
            <.score_cell label="同理心" value={@evaluation.empathy_score} />
            <.score_cell label="沟通" value={@evaluation.communication_score} />
          </div>
          <p class="mt-2 text-center text-base font-semibold">
            总分 {Decimal.to_string(@evaluation.total_score, :normal)}
            <span class="ms-2 badge badge-soft badge-success">{grade_label(@evaluation.grade)}</span>
          </p>
          <details class="mt-2 text-xs">
            <summary class="cursor-pointer text-base-content/70">查看亮点 / 不足 / 评语</summary>
            <p :if={@evaluation.highlights not in [nil, []]} class="mt-2">
              <span class="font-medium text-success">亮点：</span>
              {@highlights_text}
            </p>
            <p :if={@evaluation.weaknesses not in [nil, []]} class="mt-1">
              <span class="font-medium text-warning">不足：</span>
              {@weaknesses_text}
            </p>
            <p class="mt-2 whitespace-pre-line text-base-content/80">{@evaluation.feedback}</p>
          </details>
        </div>
        """

      nil ->
        # 会话尚未评分（evaluation 为空）：显示“未评分 / 评分中”状态，而不是崩溃
        eval_error = session.evaluation_error

        assigns =
          assigns
          |> assign(:session_eval_status, session.evaluation_status)
          |> assign(:has_eval_error?, not is_nil(eval_error))
          |> assign(:eval_error_text, truncate(eval_error, 200))

        ~H"""
        <div :if={!@has_eval_error?}
          class="rounded-box border border-base-300 bg-base-200/30 p-3 text-sm text-base-content/70"
        >
          <span class="flex items-center gap-1">
            {evaluation_status_text(@session_eval_status)}
          </span>
        </div>
        <div :if={@has_eval_error?}
          class="alert alert-warning alert-soft text-xs"
        >
          <span>评分失败：{@eval_error_text}</span>
        </div>
        """
    end
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true

  defp score_cell(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-0.5">
      <span class="text-2xl font-semibold tabular-nums">{@value}</span>
      <span class="text-xs text-base-content/60">{@label}</span>
    </div>
    """
  end

  defp grade_label(:excellent), do: "优秀"
  defp grade_label(:good), do: "良好"
  defp grade_label(:pass), do: "及格"
  defp grade_label(:borderline), do: "边缘"
  defp grade_label(:fail), do: "不及格"
  defp grade_label(_), do: "—"

  defp session_status_text(:active), do: "进行中"
  defp session_status_text(:completed), do: "已完成"
  defp session_status_text(:abandoned), do: "已放弃"
  defp session_status_text(_), do: "—"

  defp assignment_badge(:assigned), do: "badge-info"
  defp assignment_badge(:in_progress), do: "badge-warning"
  defp assignment_badge(:completed), do: "badge-success"
  defp assignment_badge(:expired), do: "badge-error"
  defp assignment_badge(_), do: "badge-ghost"

  defp assignment_status_text(:assigned), do: "已分配"
  defp assignment_status_text(:in_progress), do: "进行中"
  defp assignment_status_text(:completed), do: "已完成"
  defp assignment_status_text(:expired), do: "已过期"
  defp assignment_status_text(_), do: "—"

  attr :field, Phoenix.HTML.FormField, required: true

  defp subject_select(assigns) do
    current = assigns.field.value || "中医"
    assigns = assign(assigns, :current, current)
    assigns = assign(assigns, :opts, subject_options())

    ~H"""
    <div class="form-control w-full">
      <label class="label" for={@field.id}>
        <span class="label-text">学科</span>
      </label>
      <select
        id={@field.id}
        name={@field.name}
        class={["select select-bordered w-full", @field.errors != [] && "select-error"]}
      >
        <option :for={{label, value} <- @opts} value={value} selected={value == @current}>{label}</option>
      </select>
      <.error :for={msg <- @field.errors}>{msg}</.error>
    </div>
    """
  end

  # ── modals ────────────────────────────────────────────────

  defp patient_modal(assigns) do
    ~H"""
    <div :if={@patient_modal} class="modal modal-open" aria-modal="true">
      <div class="modal-box max-w-4xl">
        <div class="mb-3 flex flex-wrap items-center gap-2">
          <h3 class="text-lg font-semibold">
            {if @patient_modal.mode == :new, do: "新建病人档案", else: "编辑病人档案"}
          </h3>

          <div class="ms-auto flex items-center gap-1">
            <details class="dropdown dropdown-end" id="example-patient-dropdown">
              <summary class="btn btn-soft btn-sm">
                <.icon name="hero-book-open" class="size-4" /> 加载示例病人
              </summary>
              <ul class="menu dropdown-content z-10 mt-2 w-80 rounded-box border border-base-300 bg-base-100 p-2 shadow-md">
                <li class="menu-title">全流程临床病例（带标准路径与难度分级）</li>
                <li :for={ex <- ClinicalCases.list()}>
                  <button
                    type="button"
                    phx-click="load-example"
                    phx-value-key={ex.key}
                    class="text-left"
                  >
                    {ex.label}
                  </button>
                </li>
                <li class="menu-title mt-1">常见慢性病模板（普通问诊）</li>
                <li :for={ex <- examples()}>
                  <button
                    type="button"
                    phx-click="load-example"
                    phx-value-key={ex.key}
                    class="text-left"
                  >
                    {ex.label}
                  </button>
                </li>
              </ul>
            </details>
          </div>
        </div>

        <%!-- modal 内部 tab：基本信息 / 评分配置 --%>
        <div class="mb-3 flex items-center gap-2 border-b border-base-300">
          <button
            type="button"
            id="modal-tab-basic"
            phx-click="modal-switch-tab"
            phx-value-tab="basic"
            class={[
              "btn btn-ghost btn-sm rounded-b-none",
              @modal_tab == :basic && "border-b-2 border-primary text-primary"
            ]}
          >
            <.icon name="hero-user" class="size-4" /> 病人基本信息
          </button>
          <button
            type="button"
            id="modal-tab-rubric"
            phx-click="modal-switch-tab"
            phx-value-tab="rubric"
            class={[
              "btn btn-ghost btn-sm rounded-b-none",
              @modal_tab == :rubric && "border-b-2 border-primary text-primary"
            ]}
          >
            <.icon name="hero-clipboard-document-check" class="size-4" /> 评分配置
          </button>
          <button
            type="button"
            id="modal-tab-clinical"
            phx-click="modal-switch-tab"
            phx-value-tab="clinical"
            class={[
              "btn btn-ghost btn-sm rounded-b-none",
              @modal_tab == :clinical && "border-b-2 border-primary text-primary"
            ]}
          >
            <.icon name="hero-academic-cap" class="size-4" /> 临床流程
          </button>
        </div>

        <.form
          for={@patient_form}
          id="patient-modal-form"
          phx-change="validate-patient"
          phx-submit="save-patient"
          class="flex flex-col gap-3"
        >
          {basic_tab_content(assigns)}
          {rubric_tab_content(assigns)}
          {clinical_tab_content(assigns)}

          <div class="flex items-center justify-between gap-2 border-t border-base-300 pt-3">
            <button
              type="button"
              phx-click="cancel-patient-modal"
              class="btn btn-ghost btn-sm"
            >
              取消
            </button>
            <div class="flex items-center gap-2">
              <select name="patient[status]" class="select select-sm select-bordered">
                <option value="draft" selected={@patient_form.params["status"] in [nil, "draft"]}>草稿</option>
                <option value="published" selected={@patient_form.params["status"] == "published"}>已发布</option>
                <option value="archived" selected={@patient_form.params["status"] == "archived"}>已归档</option>
              </select>
              <button type="submit" class="btn btn-primary btn-sm">
                <.icon name="hero-check" class="size-4" /> 保存
              </button>
            </div>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  defp basic_tab_content(assigns) do
    ~H"""
    <div class={["flex flex-col gap-3", @modal_tab != :basic && "hidden"]}>
      <div class="grid items-start gap-3 md:grid-cols-2">
        <.input field={@patient_form[:name]} type="text" label="姓名" required maxlength="100" />
        <.subject_select field={@patient_form[:subject]} />
      </div>

      <.input
        field={@patient_form[:scenario_title]}
        type="text"
        label="情境标题（可选）"
        placeholder="例：心悸 3 天，加重 1 天"
        maxlength="200"
      />

      <.input
        field={@patient_form[:complaint]}
        type="textarea"
        label="主诉（开场）"
        placeholder="一句话描述就医主要原因"
        rows="3"
        required
        maxlength="500"
      />

      <.input
        field={@patient_form[:history]}
        type="textarea"
        label="病史背景（现病史 / 既往史 / 查体 / 辅助检查）"
        placeholder="学生问及时才揭开的信息"
        rows="6"
        maxlength="10000"
      />

      <div class="grid items-start gap-3 md:grid-cols-2">
        <.input
          field={@patient_form[:personality]}
          type="textarea"
          label="性格特点"
          placeholder="焦虑 / 配合 / 健谈 / 回避..."
          rows="3"
        />
        <.input
          field={@patient_form[:talking_style]}
          type="textarea"
          label="说话方式"
          placeholder="句长、方言、情绪化..."
          rows="3"
        />
      </div>

      <div>
        <div class="mb-2 flex items-center justify-between">
          <p class="text-sm font-medium">
            病人基本信息
            <span class="ms-1 text-xs text-base-content/60">（每行一组 key / value，例如：年龄：52）</span>
          </p>
          <button
            type="button"
            phx-click="add-profile-row"
            class="btn btn-ghost btn-xs"
          >
            <.icon name="hero-plus" class="size-3.5" /> 添加一行
          </button>
        </div>
        <div class="flex flex-col gap-2 rounded-box border border-base-300 bg-base-200/20 p-3">
          <div
            :for={{row, idx} <- Enum.with_index(@profile_rows)}
            class="flex items-center gap-2"
          >
            <input
              type="text"
              value={row["k"]}
              phx-blur="update-profile-row"
              phx-value-idx={idx}
              phx-value-k={row["k"]}
              phx-value-v={row["v"]}
              placeholder="键（如：年龄）"
              class="input input-sm input-bordered flex-1"
            />
            <input
              type="text"
              value={row["v"]}
              phx-blur="update-profile-row"
              phx-value-idx={idx}
              phx-value-k={row["k"]}
              phx-value-v={row["v"]}
              placeholder="值（如：52）"
              class="input input-sm input-bordered flex-1"
            />
            <button
              type="button"
              phx-click="remove-profile-row"
              phx-value-idx={idx}
              class="btn btn-ghost btn-xs text-error"
              aria-label="删除该行"
            >
              <.icon name="hero-trash" class="size-4" />
            </button>
          </div>
          <p
            :if={@profile_rows == [%{"k" => "", "v" => ""}]}
            class="text-center text-xs text-base-content/60"
          >
            留空则不展示「病人基本信息」区。
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp rubric_tab_content(assigns) do
    ~H"""
    <div class={["flex flex-col gap-3", @modal_tab != :rubric && "hidden"]}>
      <div>
        <div class="mb-2 flex items-center justify-between">
          <p class="text-sm font-medium">评分要点清单</p>
          <button
            type="button"
            phx-click="add-key-point"
            class="btn btn-ghost btn-xs"
          >
            <.icon name="hero-plus" class="size-3.5" /> 添加一条
          </button>
        </div>
        <div class="flex flex-col gap-2 rounded-box border border-base-300 bg-base-200/20 p-3">
          <div
            :for={{line, idx} <- Enum.with_index(@key_points_lines)}
            class="flex items-center gap-2"
          >
            <span class="badge badge-soft badge-sm">{idx + 1}</span>
            <input
              type="text"
              value={line}
              phx-blur="update-key-point"
              phx-value-idx={idx}
              phx-value-v={line}
              placeholder="例如：问发作时间和诱因"
              class="input input-sm input-bordered flex-1"
            />
            <button
              type="button"
              phx-click="remove-key-point"
              phx-value-idx={idx}
              class="btn btn-ghost btn-xs text-error"
              aria-label="删除该评分点"
            >
              <.icon name="hero-trash" class="size-4" />
            </button>
          </div>
          <p :if={@key_points_lines == [""]} class="text-center text-xs text-base-content/60">
            添加需要 AI 重点关注的问诊 / 沟通动作。
          </p>
        </div>
      </div>

      <div>
        <div class="mb-2 flex items-center justify-between">
          <p class="text-sm font-medium">
            评分维度权重
            <span class="ms-1 text-xs text-base-content/60">
              （key = 维度标识，value = 权重百分比；总和建议 100）
            </span>
          </p>
          <button
            type="button"
            phx-click="add-rubric-row"
            class="btn btn-ghost btn-xs"
          >
            <.icon name="hero-plus" class="size-3.5" /> 添加一行
          </button>
        </div>
        <div class="flex flex-col gap-2 rounded-box border border-base-300 bg-base-200/20 p-3">
          <div
            :for={{row, idx} <- Enum.with_index(@rubric_rows)}
            class="flex items-center gap-2"
          >
            <input
              type="text"
              value={row["k"]}
              phx-blur="update-rubric-row"
              phx-value-idx={idx}
              phx-value-k={row["k"]}
              phx-value-v={row["v"]}
              placeholder="维度（如：专业度）"
              class="input input-sm input-bordered flex-1"
            />
            <input
              type="number"
              min="0"
              max="100"
              value={row["v"]}
              phx-blur="update-rubric-row"
              phx-value-idx={idx}
              phx-value-k={row["k"]}
              phx-value-v={row["v"]}
              placeholder="权重"
              class="input input-sm input-bordered w-24"
            />
            <button
              type="button"
              phx-click="remove-rubric-row"
              phx-value-idx={idx}
              class="btn btn-ghost btn-xs text-error"
              aria-label="删除该行"
            >
              <.icon name="hero-trash" class="size-4" />
            </button>
          </div>
          <p :if={rubric_total(@rubric_rows) != 100} class="text-xs text-warning">
            当前总和 {rubric_total(@rubric_rows)}，建议调整为 100。
          </p>
        </div>
      </div>

      <div class="grid grid-cols-3 gap-2">
        <.input field={@patient_form[:difficulty]} type="number" label="难度 1-5" min="1" max="5" />
        <.input
          field={@patient_form[:min_questions]}
          type="number"
          label="最少问诊"
          min="3"
          max="30"
        />
        <.input
          field={@patient_form[:max_turns]}
          type="number"
          label="最多轮次"
          min="5"
          max="100"
        />
      </div>
    </div>
    """
  end

  defp rubric_total(rows) do
    rows
    |> Enum.map(fn %{"v" => v} -> parse_int(v, 0) end)
    |> Enum.sum()
  end

  defp clinical_tab_content(assigns) do
    ~H"""
    <div class={["flex flex-col gap-3", @modal_tab != :clinical && "hidden"]}>
      <div class="alert alert-info alert-soft text-sm">
        配置「标准诊疗路径」后，学生端将启动<b>全流程临床模拟</b>
        （问诊→体格检查→辅助检查→诊断→鉴别诊断→治疗方案→随访），
        并实时对比标准路径标注思维漏洞。留空则保持普通问诊对话。
      </div>

      <div class="grid items-start gap-3 md:grid-cols-2">
        <div>
          <p class="mb-1 text-sm font-medium">难度分级</p>
          <select
            name="patient[difficulty_level]"
            class="select select-bordered w-full"
          >
            <option
              :for={{label, value} <- ClinicalCases.difficulty_levels()}
              value={value}
              selected={patient_form_attr(@patient_form, "difficulty_level") == to_string(value)}
            >
              {label}
            </option>
          </select>
          <p class="mt-1 text-xs text-base-content/60">
            入门(典型) / 进阶(复杂) / 专家(疑难) / 急诊(危重，red flag 强约束)
          </p>
        </div>
      </div>

      <div>
        <p class="mb-1 text-sm font-medium">
          急诊危重信号（red_flags）
          <span class="ms-1 text-xs text-base-content/60">（每行一条，急诊病例建议填写）</span>
        </p>
        <.input
          field={@patient_form[:red_flags_text]}
          type="textarea"
          label="急诊危重信号（每行一条）"
          placeholder="例：持续胸痛 >20 分钟伴大汗"
          rows="3"
        />
      </div>

      <div>
        <p class="mb-1 text-sm font-medium">标准诊疗路径（JSON）</p>
        <.input
          field={@patient_form[:standard_pathway_json]}
          type="textarea"
          label="标准诊疗路径 JSON"
          placeholder="填七阶段标准动作 JSON，或用「加载临床病例」一键填好"
          rows="10"
        />
        <p class="mt-1 text-xs text-base-content/60">
          用「加载临床病例」可一键填好。键为阶段：inquiry / physical_exam / auxiliary /
          diagnosis / differential / treatment / follow_up。
        </p>
      </div>
    </div>
    """
  end

  # 从表单 params 取指定键（缺省空串）
  defp patient_form_attr(form, key) do
    form.params[key] || form.params[String.to_atom(key)] || ""
  end

  defp examples do
    Examples.list()
  end

  defp assign_modal(assigns) do
    ~H"""
    <div :if={@assign_modal} class="modal modal-open" aria-modal="true">
      <div class="modal-box max-w-xl">
        <.form
          for={@assign_form}
          id="assign-modal-form"
          phx-change="validate-assign"
          phx-submit="save-assign"
          class="flex flex-col gap-3"
        >
          <h3 class="text-lg font-semibold">
            分配《{@assign_modal.patient_name}》给学生
          </h3>
          <input type="hidden" name="assign[patient_id]" value={@assign_modal.patient_id} />

          <.input
            field={@assign_form[:student_id]}
            type="select"
            label="学生"
            prompt="请选择学生"
            options={student_options(@students)}
          />

          <.input
            field={@assign_form[:deadline]}
            type="text"
            label="截止时间（ISO 8601，可留空）"
            placeholder="2025-12-31T23:59:59Z"
          />

          <.input
            field={@assign_form[:notes]}
            type="textarea"
            label="给学生的说明（可选）"
            rows="3"
          />

          <div class="flex items-center justify-end gap-2 border-t border-base-300 pt-3">
            <button
              type="button"
              phx-click="cancel-assign"
              class="btn btn-ghost btn-sm"
            >
              取消
            </button>
            <button type="submit" class="btn btn-primary btn-sm">
              <.icon name="hero-paper-airplane" class="size-4" /> 分配
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  defp student_options(students) do
    Enum.map(students, fn s -> {s.name || s.email, s.id} end)
  end
end
