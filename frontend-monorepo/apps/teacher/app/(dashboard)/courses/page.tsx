"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import {
  Button,
  Card,
  Popconfirm,
  Segmented,
  Space,
  Table,
  Tag,
  Typography,
  message,
} from "antd";
import { AppstoreOutlined, BarsOutlined } from "@ant-design/icons";
import {
  archiveCourse,
  deleteCourse,
  listTeacherCourses,
  publishCourse,
  type AshRpcError,
} from "@tcm-edu/rpc-client";
import { useAuth, useRequireAuth } from "@/lib/auth";

interface CourseRow {
  id: string;
  title: string;
  subtitle?: string | null;
  status?: string | null;
  level?: string | null;
  priceCents?: number | null;
  lessonCount?: number | null;
}

const COURSE_FIELDS = [
  "id",
  "title",
  "subtitle",
  "status",
  "level",
  "priceCents",
  "lessonCount",
] as const;

const STATUS_TAG: Record<string, React.ReactNode> = {
  draft: <Tag color="default">草稿</Tag>,
  published: <Tag color="green">已发布</Tag>,
  archived: <Tag color="orange">已下架</Tag>,
};

const LEVEL_LABEL: Record<string, string> = {
  beginner: "初级",
  intermediate: "中级",
  advanced: "高级",
};

type StatusFilter = "all" | "draft" | "published" | "archived";

function errMsg(errors: AshRpcError[]): string {
  return errors?.[0]?.message ?? "操作失败";
}

export default function TeacherCoursesPage() {
  useRequireAuth();
  const router = useRouter();
  const { session } = useAuth();
  const [loading, setLoading] = useState(true);
  const [rows, setRows] = useState<CourseRow[]>([]);
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("all");
  const [view, setView] = useState<"table" | "card">("table");

  const load = useCallback(async () => {
    if (!session?.userId || !session?.tenant) return;
    setLoading(true);
    try {
      const res = await listTeacherCourses({
        fields: [...COURSE_FIELDS],
        tenant: session.tenant,
        input: { teacherId: session.userId },
      });
      if (res.success) {
        setRows(res.data as CourseRow[]);
      } else {
        message.error(errMsg(res.errors));
      }
    } finally {
      setLoading(false);
    }
  }, [session?.userId, session?.tenant]);

  useEffect(() => {
    if (session) load();
  }, [session, load]);

  const filtered = useMemo(
    () =>
      statusFilter === "all"
        ? rows
        : rows.filter((r) => r.status === statusFilter),
    [rows, statusFilter]
  );

  async function handlePublish(row: CourseRow) {
    if (!session?.tenant) return;
    const res = await publishCourse({
      identity: row.id,
      fields: ["id", "status"],
      tenant: session.tenant,
    });
    if (res.success) {
      message.success("已发布");
      load();
    } else {
      message.error(errMsg(res.errors));
    }
  }

  async function handleArchive(row: CourseRow) {
    if (!session?.tenant) return;
    const res = await archiveCourse({
      identity: row.id,
      fields: ["id", "status"],
      tenant: session.tenant,
    });
    if (res.success) {
      message.success("已下架");
      load();
    } else {
      message.error(errMsg(res.errors));
    }
  }

  async function handleDelete(row: CourseRow) {
    if (!session?.tenant) return;
    const res = await deleteCourse({ identity: row.id, tenant: session.tenant });
    if (res.success) {
      message.success(`已删除 ${row.title}`);
      load();
    } else {
      message.error(errMsg(res.errors));
    }
  }

  return (
    <div>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 16 }}>
        <Typography.Title level={4} style={{ margin: 0 }}>
          我的课程
        </Typography.Title>
        <Space>
          <Segmented
            value={view}
            onChange={(v) => setView(v as "table" | "card")}
            options={[
              { value: "table", icon: <BarsOutlined />, label: "表格" },
              { value: "card", icon: <AppstoreOutlined />, label: "卡片" },
            ]}
          />
          <Button type="primary" onClick={() => router.push("/courses/new")}>
            创建课程
          </Button>
        </Space>
      </div>
      <div style={{ marginBottom: 16 }}>
        <Segmented
          value={statusFilter}
          onChange={(v) => setStatusFilter(v as StatusFilter)}
          options={[
            { value: "all", label: `全部（${rows.length}）` },
            { value: "draft", label: `草稿（${rows.filter((r) => r.status === "draft").length}）` },
            { value: "published", label: `已发布（${rows.filter((r) => r.status === "published").length}）` },
            { value: "archived", label: `已下架（${rows.filter((r) => r.status === "archived").length}）` },
          ]}
        />
      </div>
      {view === "table" ? (
        <Card>
          <Table<CourseRow>
            rowKey="id"
            loading={loading}
            dataSource={filtered}
            pagination={{ pageSize: 10, showSizeChanger: false }}
            columns={[
              { title: "标题", dataIndex: "title" },
              {
                title: "状态",
                dataIndex: "status",
                render: (v: string) => STATUS_TAG[v] ?? <Tag>{v}</Tag>,
              },
              {
                title: "难度",
                dataIndex: "level",
                render: (v: string) => LEVEL_LABEL[v] ?? v ?? "-",
              },
              {
                title: "课时数",
                dataIndex: "lessonCount",
                render: (v: number | null) => v ?? "-",
              },
              {
                title: "价格",
                dataIndex: "priceCents",
                render: (v: number | null) =>
                  v == null ? "-" : v === 0 ? "免费" : `¥${(v / 100).toFixed(2)}`,
              },
              {
                title: "操作",
                key: "actions",
                render: (_, row) => (
                  <Space size="small">
                    <Button
                      type="link"
                      size="small"
                      onClick={() => router.push(`/courses/${row.id}/edit`)}
                    >
                      编辑
                    </Button>
                    {row.status === "draft" || row.status === "archived" ? (
                      <Button type="link" size="small" onClick={() => handlePublish(row)}>
                        发布
                      </Button>
                    ) : (
                      <Button type="link" size="small" onClick={() => handleArchive(row)}>
                        下架
                      </Button>
                    )}
                    <Popconfirm
                      title={`删除课程《${row.title}》？章节课时将一并删除。`}
                      okText="确认删除"
                      cancelText="取消"
                      okType="danger"
                      onConfirm={() => handleDelete(row)}
                    >
                      <Button type="link" size="small" danger>
                        删除
                      </Button>
                    </Popconfirm>
                  </Space>
                ),
              },
            ]}
          />
        </Card>
      ) : (
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(280px, 1fr))", gap: 16 }}>
          {filtered.map((row) => (
            <Card
              key={row.id}
              title={row.title}
              extra={STATUS_TAG[row.status ?? ""] ?? null}
              actions={[
                <Button key="edit" type="link" onClick={() => router.push(`/courses/${row.id}/edit`)}>
                  编辑
                </Button>,
                row.status === "published" ? (
                  <Button key="archive" type="link" onClick={() => handleArchive(row)}>
                    下架
                  </Button>
                ) : (
                  <Button key="publish" type="link" onClick={() => handlePublish(row)}>
                    发布
                  </Button>
                ),
              ]}
            >
              <Typography.Paragraph type="secondary" ellipsis={{ rows: 2 }}>
                {row.subtitle || "暂无简介"}
              </Typography.Paragraph>
              <Space>
                <Tag>{LEVEL_LABEL[row.level ?? ""] ?? row.level ?? "-"}</Tag>
                <Tag color="blue">{row.lessonCount ?? 0} 课时</Tag>
                <Tag color={row.priceCents ? "gold" : "green"}>
                  {row.priceCents == null || row.priceCents === 0
                    ? "免费"
                    : `¥${(row.priceCents / 100).toFixed(2)}`}
                </Tag>
              </Space>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
