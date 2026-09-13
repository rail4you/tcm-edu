"use client";

import { use, useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import {
  Button,
  Card,
  Collapse,
  Form,
  Input,
  InputNumber,
  Modal,
  Popconfirm,
  Select,
  Space,
  Switch,
  Tag,
  Typography,
  message,
} from "antd";
import {
  archiveCourse,
  createChapter,
  createLesson,
  deleteChapter,
  deleteLesson,
  getCourse,
  listCategories,
  publishCourse,
  updateChapter,
  updateCourse,
  updateLesson,
  type AshRpcError,
} from "@tcm-edu/rpc-client";
import { useAuth } from "@/lib/auth/context"; import { useRequireAuth } from "@/lib/auth/guard";

interface LessonRow {
  id: string;
  title: string;
  contentType?: string | null;
  contentUrl?: string | null;
  durationSeconds?: number | null;
  sortOrder?: number | null;
  isFreePreview?: boolean | null;
}

interface ChapterRow {
  id: string;
  title: string;
  sortOrder?: number | null;
  lessons?: LessonRow[];
}

interface CourseDetail {
  id: string;
  title: string;
  subtitle?: string | null;
  description?: string | null;
  coverImageUrl?: string | null;
  status?: string | null;
  level?: string | null;
  priceCents?: number | null;
  categoryId?: string | null;
  chapters?: ChapterRow[];
}

const LEVEL_OPTIONS = [
  { value: "beginner", label: "初级" },
  { value: "intermediate", label: "中级" },
  { value: "advanced", label: "高级" },
];

const CONTENT_TYPE_OPTIONS = [
  { value: "video", label: "视频" },
  { value: "article", label: "文章" },
  { value: "pdf", label: "PDF" },
];

function errMsg(errors: AshRpcError[]): string {
  const first = errors?.[0];
  if (!first) return "操作失败";
  if (first.type === "forbidden") return "您没有权限执行此操作";
  if (first.type === "network_error") return "网络错误，请稍后重试";
  return first.message ?? "操作失败";
}

function sorted<T extends { sortOrder?: number | null }>(items: T[] | undefined): T[] {
  return [...(items ?? [])].sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0));
}

export default function EditCoursePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  useRequireAuth();
  const router = useRouter();
  const { session } = useAuth();
  const [loading, setLoading] = useState(true);
  const [course, setCourse] = useState<CourseDetail | null>(null);
  const [categories, setCategories] = useState<{ id: string; name: string }[]>([]);
  const [saving, setSaving] = useState(false);
  const [basicForm] = Form.useForm();

  // 章节 Modal
  const [chapterModal, setChapterModal] = useState<{ open: boolean; editing?: ChapterRow }>({ open: false });
  const [chapterForm] = Form.useForm();
  // 课时 Modal
  const [lessonModal, setLessonModal] = useState<{ open: boolean; chapterId?: string; editing?: LessonRow }>({ open: false });
  const [lessonForm] = Form.useForm();

  const tenant = session?.tenant;

  const load = useCallback(async () => {
    if (!tenant) return;
    setLoading(true);
    try {
      const res = await getCourse({
        getBy: { id },
        fields: [
          "id",
          "title",
          "subtitle",
          "description",
          "coverImageUrl",
          "status",
          "level",
          "priceCents",
          "categoryId",
          {
            chapters: [
              "id",
              "title",
              "sortOrder",
              {
                lessons: [
                  "id",
                  "title",
                  "contentType",
                  "contentUrl",
                  "durationSeconds",
                  "sortOrder",
                  "isFreePreview",
                ],
              },
            ],
          },
        ],
        tenant,
      });
      if (res.success) {
        const c = res.data as CourseDetail;
        setCourse(c);
        basicForm.setFieldsValue({
          title: c.title,
          subtitle: c.subtitle ?? undefined,
          description: c.description ?? undefined,
          coverImageUrl: c.coverImageUrl ?? undefined,
          level: c.level ?? undefined,
          priceYuan: c.priceCents == null ? 0 : c.priceCents / 100,
          categoryId: c.categoryId ?? undefined,
        });
      } else {
        message.error(errMsg(res.errors));
      }
    } finally {
      setLoading(false);
    }
  }, [id, tenant, basicForm]);

  useEffect(() => {
    if (session) {
      load();
      listCategories({ fields: ["id", "name"], tenant: session.tenant }).then((res) => {
        if (res.success) setCategories(res.data as { id: string; name: string }[]);
      });
    }
  }, [session, load]);

  async function handleSaveBasic(values: {
    title: string;
    subtitle?: string;
    description?: string;
    coverImageUrl?: string;
    level?: "beginner" | "intermediate" | "advanced";
    priceYuan?: number;
    categoryId?: string;
  }) {
    if (!tenant) return;
    setSaving(true);
    try {
      const res = await updateCourse({
        identity: id,
        fields: ["id", "title"],
        tenant,
        input: {
          title: values.title.trim(),
          subtitle: values.subtitle?.trim() || null,
          description: values.description?.trim() || null,
          coverImageUrl: values.coverImageUrl?.trim() || null,
          level: values.level ?? null,
          priceCents: values.priceYuan == null ? null : Math.round(values.priceYuan * 100),
          categoryId: values.categoryId || null,
        },
      });
      if (res.success) {
        message.success("基本信息已保存");
        load();
      } else {
        message.error(errMsg(res.errors));
      }
    } finally {
      setSaving(false);
    }
  }

  async function handlePublish() {
    if (!tenant) return;
    const res = await publishCourse({ identity: id, fields: ["id", "status"], tenant });
    if (res.success) {
      message.success("已发布");
      load();
    } else {
      message.error(errMsg(res.errors));
    }
  }

  async function handleArchive() {
    if (!tenant) return;
    const res = await archiveCourse({ identity: id, fields: ["id", "status"], tenant });
    if (res.success) {
      message.success("已下架");
      load();
    } else {
      message.error(errMsg(res.errors));
    }
  }

  // ─── 章节 ───
  function openCreateChapter() {
    chapterForm.resetFields();
    setChapterModal({ open: true });
  }

  function openEditChapter(ch: ChapterRow) {
    chapterForm.setFieldsValue({ title: ch.title });
    setChapterModal({ open: true, editing: ch });
  }

  async function submitChapter(values: { title: string }) {
    if (!tenant) return;
    if (chapterModal.editing) {
      const res = await updateChapter({
        identity: chapterModal.editing.id,
        fields: ["id", "title"],
        tenant,
        input: { title: values.title.trim() },
      });
      if (!res.success) {
        message.error(errMsg(res.errors));
        return;
      }
      message.success("章节已更新");
    } else {
      const maxOrder = Math.max(0, ...sorted(course?.chapters).map((c) => c.sortOrder ?? 0));
      const res = await createChapter({
        fields: ["id", "title"],
        tenant,
        input: { title: values.title.trim(), courseId: id, sortOrder: maxOrder + 1 },
      });
      if (!res.success) {
        message.error(errMsg(res.errors));
        return;
      }
      message.success("章节已创建");
    }
    setChapterModal({ open: false });
    load();
  }

  async function handleDeleteChapter(ch: ChapterRow) {
    if (!tenant) return;
    const res = await deleteChapter({ identity: ch.id, tenant });
    if (res.success) {
      message.success(`已删除章节 ${ch.title}（含其课时）`);
      load();
    } else {
      message.error(errMsg(res.errors));
    }
  }

  // ─── 课时 ───
  function openCreateLesson(chapterId: string) {
    lessonForm.resetFields();
    lessonForm.setFieldsValue({ contentType: "video", isFreePreview: false });
    setLessonModal({ open: true, chapterId });
  }

  function openEditLesson(chapterId: string, ls: LessonRow) {
    lessonForm.setFieldsValue({
      title: ls.title,
      contentType: ls.contentType ?? "video",
      contentUrl: ls.contentUrl ?? undefined,
      durationSeconds: ls.durationSeconds ?? undefined,
      isFreePreview: ls.isFreePreview ?? false,
    });
    setLessonModal({ open: true, chapterId, editing: ls });
  }

  async function submitLesson(values: {
    title: string;
    contentType: "video" | "article" | "pdf";
    contentUrl?: string;
    durationSeconds?: number;
    isFreePreview?: boolean;
  }) {
    if (!tenant || !lessonModal.chapterId) return;
    if (lessonModal.editing) {
      const res = await updateLesson({
        identity: lessonModal.editing.id,
        fields: ["id", "title"],
        tenant,
        input: {
          title: values.title.trim(),
          contentType: values.contentType,
          contentUrl: values.contentUrl?.trim() || null,
          durationSeconds: values.durationSeconds ?? null,
          isFreePreview: values.isFreePreview ?? null,
        },
      });
      if (!res.success) {
        message.error(errMsg(res.errors));
        return;
      }
      message.success("课时已更新");
    } else {
      const parent = course?.chapters?.find((c) => c.id === lessonModal.chapterId);
      const maxOrder = Math.max(0, ...sorted(parent?.lessons).map((l) => l.sortOrder ?? 0));
      const res = await createLesson({
        fields: ["id", "title"],
        tenant,
        input: {
          title: values.title.trim(),
          contentType: values.contentType,
          contentUrl: values.contentUrl?.trim() || null,
          durationSeconds: values.durationSeconds ?? null,
          sortOrder: maxOrder + 1,
          isFreePreview: values.isFreePreview ?? false,
          chapterId: lessonModal.chapterId,
        },
      });
      if (!res.success) {
        message.error(errMsg(res.errors));
        return;
      }
      message.success("课时已创建");
    }
    setLessonModal({ open: false });
    load();
  }

  async function handleDeleteLesson(ls: LessonRow) {
    if (!tenant) return;
    const res = await deleteLesson({ identity: ls.id, tenant });
    if (res.success) {
      message.success(`已删除课时 ${ls.title}`);
      load();
    } else {
      message.error(errMsg(res.errors));
    }
  }

  const chapters = sorted(course?.chapters);
  const canPublish = chapters.length > 0 && chapters.some((c) => (c.lessons ?? []).length > 0);

  return (
    <div style={{ maxWidth: 900 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 16 }}>
        <Typography.Title level={4} style={{ margin: 0 }}>
          编辑课程 {course?.status === "published" ? <Tag color="green">已发布</Tag> : course?.status === "archived" ? <Tag color="orange">已下架</Tag> : <Tag>草稿</Tag>}
        </Typography.Title>
        <Space>
          <Button onClick={() => router.push("/courses")}>返回列表</Button>
          {course?.status === "published" ? (
            <Button onClick={handleArchive}>下架</Button>
          ) : (
            <Button type="primary" onClick={handlePublish} disabled={!canPublish} title={canPublish ? "" : "至少需要 1 个章节且章节下有 1 个课时才能发布"}>
              发布课程
            </Button>
          )}
        </Space>
      </div>

      <Card title="基本信息" loading={loading} style={{ marginBottom: 16 }}>
        <Form form={basicForm} layout="vertical" onFinish={handleSaveBasic} initialValues={{ level: "beginner", priceYuan: 0 }}>
          <Form.Item label="标题" name="title" rules={[{ required: true, message: "请输入课程标题" }]}>
            <Input maxLength={100} />
          </Form.Item>
          <Form.Item label="副标题" name="subtitle">
            <Input maxLength={200} />
          </Form.Item>
          <Form.Item label="简介" name="description">
            <Input.TextArea rows={3} maxLength={2000} />
          </Form.Item>
          <Form.Item label="封面图片 URL" name="coverImageUrl">
            <Input placeholder="https://...（AshStorage 接入后可直传，见 Phase 5 后续）" />
          </Form.Item>
          <Form.Item label="难度" name="level">
            <Select options={LEVEL_OPTIONS} />
          </Form.Item>
          <Form.Item label="价格（元，0 = 免费）" name="priceYuan">
            <InputNumber min={0} precision={2} style={{ width: "100%" }} />
          </Form.Item>
          <Form.Item label="分类" name="categoryId">
            <Select allowClear placeholder="选择分类" options={categories.map((c) => ({ value: c.id, label: c.name }))} />
          </Form.Item>
          <Form.Item>
            <Button type="primary" htmlType="submit" loading={saving}>
              保存基本信息
            </Button>
          </Form.Item>
        </Form>
      </Card>

      <Card
        title="章节与课时"
        loading={loading}
        extra={<Button type="primary" onClick={openCreateChapter}>添加章节</Button>}
      >
        {chapters.length === 0 ? (
          <Typography.Paragraph type="secondary">暂无章节，点击右上「添加章节」开始备课。</Typography.Paragraph>
        ) : (
          <Collapse
            defaultActiveKey={chapters.map((c) => c.id)}
            items={chapters.map((ch, ci) => ({
              key: ch.id,
              label: `第 ${ci + 1} 章 · ${ch.title}（${ch.lessons?.length ?? 0} 课时）`,
              extra: (
                <Space size="small" onClick={(e) => e.stopPropagation()}>
                  <Button type="link" size="small" onClick={() => openEditChapter(ch)}>改名</Button>
                  <Popconfirm title={`删除章节 ${ch.title}？其下课时将一并删除。`} okText="确认删除" cancelText="取消" okType="danger" onConfirm={() => handleDeleteChapter(ch)}>
                    <Button type="link" size="small" danger>删除</Button>
                  </Popconfirm>
                </Space>
              ),
              children: (
                <div>
                  {sorted(ch.lessons).map((ls, li) => (
                    <div key={ls.id} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: "8px 0", borderBottom: "1px solid #f0f0f0" }}>
                      <Space>
                        <Tag>{li + 1}</Tag>
                        <span>{ls.title}</span>
                        <Tag color="blue">{CONTENT_TYPE_OPTIONS.find((o) => o.value === ls.contentType)?.label ?? ls.contentType}</Tag>
                        {ls.isFreePreview && <Tag color="green">试看</Tag>}
                        {ls.durationSeconds ? <Tag>{Math.round(ls.durationSeconds / 60)} 分钟</Tag> : null}
                      </Space>
                      <Space size="small">
                        <Button type="link" size="small" onClick={() => openEditLesson(ch.id, ls)}>编辑</Button>
                        <Popconfirm title={`删除课时 ${ls.title}？`} okText="确认删除" cancelText="取消" okType="danger" onConfirm={() => handleDeleteLesson(ls)}>
                          <Button type="link" size="small" danger>删除</Button>
                        </Popconfirm>
                      </Space>
                    </div>
                  ))}
                  <Button type="dashed" block style={{ marginTop: 8 }} onClick={() => openCreateLesson(ch.id)}>
                    + 添加课时
                  </Button>
                </div>
              ),
            }))}
          />
        )}
      </Card>

      <Modal title={chapterModal.editing ? `重命名章节` : "添加章节"} open={chapterModal.open} onCancel={() => setChapterModal({ open: false })} footer={null} destroyOnClose>
        <Form form={chapterForm} layout="vertical" onFinish={submitChapter}>
          <Form.Item label="章节标题" name="title" rules={[{ required: true, message: "请输入章节标题" }]}>
            <Input placeholder="如：第一章 阴阳五行" maxLength={100} />
          </Form.Item>
          <Form.Item>
            <Button type="primary" htmlType="submit" block>保存</Button>
          </Form.Item>
        </Form>
      </Modal>

      <Modal title={lessonModal.editing ? "编辑课时" : "添加课时"} open={lessonModal.open} onCancel={() => setLessonModal({ open: false })} footer={null} destroyOnClose>
        <Form form={lessonForm} layout="vertical" onFinish={submitLesson}>
          <Form.Item label="课时标题" name="title" rules={[{ required: true, message: "请输入课时标题" }]}>
            <Input placeholder="如：1.1 阴阳学说概述" maxLength={100} />
          </Form.Item>
          <Form.Item label="类型" name="contentType">
            <Select options={CONTENT_TYPE_OPTIONS} />
          </Form.Item>
          <Form.Item label="内容链接" name="contentUrl">
            <Input placeholder="视频/ PDF URL（文章类型可留空）" />
          </Form.Item>
          <Form.Item label="时长（秒）" name="durationSeconds">
            <InputNumber min={0} style={{ width: "100%" }} />
          </Form.Item>
          <Form.Item label="免费试看" name="isFreePreview" valuePropName="checked">
            <Switch />
          </Form.Item>
          <Form.Item>
            <Button type="primary" htmlType="submit" block>保存</Button>
          </Form.Item>
        </Form>
      </Modal>
    </div>
  );
}
