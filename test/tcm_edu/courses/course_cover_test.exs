defmodule TcmEdu.Courses.CourseCoverTest do
  @moduledoc """
  课程封面（AshStorage `has_one_attached :cover_image`）测试。

  存储后端经 `config/test.exs` 覆盖为 `AshStorage.Service.Test`（内存），
  不发真实 OSS 请求。
  """

  use TcmEdu.DataCase, async: false

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.Courses.Course
  alias TcmEdu.Storage.CourseAttachment

  @tenant "tenant_default"
  @png <<137, 80, 78, 71, 13, 10, 26, 10>>

  setup do
    AshStorage.Service.Test.reset!()
    teacher = create_user!("cover-teacher", :teacher)
    {:ok, course} = create_course!(teacher, "封面课 #{uniq()}")
    {:ok, teacher: teacher, course: course}
  end

  test "attach stores blob + polymorphic attachment and exposes cover_image_url", %{
    teacher: teacher,
    course: course
  } do
    assert {:ok, %{blob: blob}} =
             AshStorage.Operations.attach(course, :cover_image, @png,
               filename: "cover.png",
               content_type: "image/png",
               actor: teacher,
               tenant: @tenant
             )

    assert blob.filename == "cover.png"

    assert {:ok, [attachment]} =
             CourseAttachment
             |> Ash.Query.filter(name == "cover_image" and record_id == ^course.id)
             |> Ash.read(authorize?: false)

    assert attachment.record_type == to_string(Course)
    assert attachment.blob_id == blob.id

    loaded =
      Ash.load!(course, :cover_image_url, actor: teacher, tenant: @tenant)

    assert is_binary(loaded.cover_image_url)
    assert loaded.cover_image_url =~ blob.key
  end

  test "attaching twice replaces the cover (has_one)", %{teacher: teacher, course: course} do
    {:ok, %{blob: first}} =
      AshStorage.Operations.attach(course, :cover_image, @png,
        filename: "first.png",
        content_type: "image/png",
        actor: teacher,
        tenant: @tenant
      )

    {:ok, %{blob: second}} =
      AshStorage.Operations.attach(course, :cover_image, @png,
        filename: "second.png",
        content_type: "image/png",
        actor: teacher,
        tenant: @tenant
      )

    refute first.id == second.id

    assert {:ok, attachments} =
             CourseAttachment
             |> Ash.Query.filter(name == "cover_image" and record_id == ^course.id)
             |> Ash.read(authorize?: false)

    assert length(attachments) == 1
    assert hd(attachments).blob_id == second.id
  end

  test "non-author cannot attach a cover", %{course: course} do
    other = create_user!("cover-other", :teacher)

    assert {:error, %Ash.Error.Forbidden{}} =
             AshStorage.Operations.attach(course, :cover_image, @png,
               filename: "hack.png",
               content_type: "image/png",
               actor: other,
               tenant: @tenant
             )
  end

  test "destroying the course purges the cover", %{teacher: teacher, course: course} do
    {:ok, %{blob: blob}} =
      AshStorage.Operations.attach(course, :cover_image, @png,
        filename: "cover.png",
        content_type: "image/png",
        actor: teacher,
        tenant: @tenant
      )

    assert :ok = Ash.destroy!(course, actor: teacher, tenant: @tenant) |> then(fn _ -> :ok end)

    assert {:ok, []} =
             CourseAttachment
             |> Ash.Query.filter(record_id == ^course.id)
             |> Ash.read(authorize?: false)

    refute AshStorage.Service.Test.exists?(blob.key)
  end

  # ── helpers ────────────────────────────────────────────────────────

  defp uniq, do: System.unique_integer([:positive])

  defp create_user!(prefix, role) do
    {:ok, user} =
      User
      |> Ash.Changeset.for_action(:register_with_role, %{
        email: "#{prefix}-#{uniq()}@example.com",
        password: "password123",
        role: role
      })
      |> Ash.create(tenant: @tenant, authorize?: false)

    user
  end

  defp create_course!(teacher, title) do
    Course
    |> Ash.Changeset.for_action(:create_course, %{title: title, teacher_id: teacher.id})
    |> Ash.create(actor: teacher, tenant: @tenant)
  end
end
