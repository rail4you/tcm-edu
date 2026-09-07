"use client";

import { useCallback, useEffect, useState } from "react";
import {
  Button,
  Card,
  Form,
  Input,
  Modal,
  Popconfirm,
  Select,
  Space,
  Table,
  Tag,
  Typography,
  message,
} from "antd";
import {
  activateOrganization,
  archiveOrganization,
  createOrganization,
  deleteOrganization,
  listOrganizations,
  suspendOrganization,
  updateOrganization,
  type AshRpcError,
} from "@tcm-edu/rpc-client";
import { useAuth, useRequireAuth } from "@/lib/auth";

interface OrgRow {
  id: string;
  name: string;
  slug: string;
  schemaName?: string | null;
  status?: string | null;
  plan?: string | null;
  contactEmail?: string | null;
  contactPhone?: string | null;
  description?: string | null;
}

const ORG_FIELDS = [
  "id",
  "name",
  "slug",
  "schemaName",
  "status",
  "plan",
  "contactEmail",
  "contactPhone",
  "description",
] as const;

function errMsg(errors: AshRpcError[]): string {
  const first = errors?.[0];
  if (!first) return "操作失败";
  if (first.type === "forbidden") return "您没有权限执行此操作";
  if (first.type === "network_error") return "网络错误，请稍后重试";
  return first.message ?? "操作失败";
}

const STATUS_TAG: Record<string, React.ReactNode> = {
  active: <Tag color="green">运营中</Tag>,
  suspended: <Tag color="red">已暂停</Tag>,
  archived: <Tag>已归档</Tag>,
};

export default function TenantsPage() {
  useRequireAuth(["super_admin"]);
  const { session } = useAuth();
  const [loading, setLoading] = useState(true);
  const [rows, setRows] = useState<OrgRow[]>([]);
  const [createOpen, setCreateOpen] = useState(false);
  const [editing, setEditing] = useState<OrgRow | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [createForm] = Form.useForm();
  const [editForm] = Form.useForm();

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await listOrganizations({ fields: [...ORG_FIELDS] });
      if (res.success) {
        setRows(res.data as OrgRow[]);
      } else {
        message.error(errMsg(res.errors));
      }
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (session?.role === "super_admin") load();
  }, [session, load]);

  async function handleCreate(values: {
    name: string;
    slug: string;
    contactEmail?: string;
    plan?: "free" | "pro" | "enterprise";
  }) {
    setSubmitting(true);
    try {
      const res = await createOrganization({
        fields: [...ORG_FIELDS],
        input: {
          name: values.name.trim(),
          slug: values.slug.trim().toLowerCase(),
          contactEmail: values.contactEmail?.trim() || null,
          plan: values.plan ?? "free",
        },
      });
      if (res.success) {
        message.success(`租户已创建，schema：${(res.data as OrgRow).schemaName}`);
        setCreateOpen(false);
        createForm.resetFields();
        load();
      } else {
        message.error(errMsg(res.errors));
      }
    } finally {
      setSubmitting(false);
    }
  }

  async function handleEdit(values: {
    name: string;
    contactEmail?: string;
    contactPhone?: string;
    description?: string;
    plan?: "free" | "pro" | "enterprise";
  }) {
    if (!editing) return;
    setSubmitting(true);
    try {
      const res = await updateOrganization({
        identity: editing.id,
        fields: [...ORG_FIELDS],
        input: {
          name: values.name.trim(),
          contactEmail: values.contactEmail?.trim() || null,
          contactPhone: values.contactPhone?.trim() || null,
          description: values.description?.trim() || null,
          plan: values.plan ?? "free",
        },
      });
      if (res.success) {
        message.success("已保存");
        setEditing(null);
        load();
      } else {
        message.error(errMsg(res.errors));
      }
    } finally {
      setSubmitting(false);
    }
  }

  async function handleStatus(
    row: OrgRow,
    fn: typeof suspendOrganization,
    label: string
  ) {
    const res = await fn({ identity: row.id, fields: ["id", "status"] });
    if (res.success) {
      message.success(`${row.name}：${label}`);
      load();
    } else {
      message.error(errMsg(res.errors));
    }
  }

  async function handleDelete(row: OrgRow) {
    const res = await deleteOrganization({ identity: row.id });
    if (res.success) {
      message.success(`已删除租户 ${row.name}（schema 已级联删除）`);
      load();
    } else {
      message.error(errMsg(res.errors));
    }
  }

  return (
    <div>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 16, flexWrap: "wrap", gap: 8 }}>
        <Typography.Title level={4} style={{ margin: 0 }}>
          租户管理
        </Typography.Title>
        <Button type="primary" onClick={() => setCreateOpen(true)}>
          创建租户
        </Button>
      </div>
      <Card>
        <Table<OrgRow>
          rowKey="id"
          scroll={{ x: 720 }}
          loading={loading}
          dataSource={rows}
          pagination={{ pageSize: 10, showSizeChanger: false }}
          columns={[
            { title: "名称", dataIndex: "name" },
            { title: "Slug", dataIndex: "slug", render: (v: string) => <code>{v}</code> },
            { title: "Schema", dataIndex: "schemaName", render: (v: string) => <code>{v}</code> },
            { title: "状态", dataIndex: "status", render: (v: string) => STATUS_TAG[v] ?? <Tag>{v}</Tag> },
            { title: "套餐", dataIndex: "plan" },
            { title: "联系邮箱", dataIndex: "contactEmail" },
            {
              title: "操作",
              key: "actions",
              render: (_, row) => (
                <Space size="small">
                  <Button
                    type="link"
                    size="small"
                    onClick={() => {
                      setEditing(row);
                      editForm.setFieldsValue({
                        name: row.name,
                        contactEmail: row.contactEmail ?? "",
                        contactPhone: row.contactPhone ?? "",
                        description: row.description ?? "",
                        plan: row.plan ?? "free",
                      });
                    }}
                  >
                    编辑
                  </Button>
                  {row.status === "active" ? (
                    <Button type="link" size="small" onClick={() => handleStatus(row, suspendOrganization, "已暂停")}>
                      暂停
                    </Button>
                  ) : (
                    <Button type="link" size="small" onClick={() => handleStatus(row, activateOrganization, "已恢复")}>
                      恢复
                    </Button>
                  )}
                  {row.status !== "archived" && (
                    <Button type="link" size="small" onClick={() => handleStatus(row, archiveOrganization, "已归档")}>
                      归档
                    </Button>
                  )}
                  <Popconfirm
                    title={`删除租户 ${row.name}？`}
                    description="将级联删除该租户 schema 下所有数据，不可恢复。"
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

      <Modal
        title="创建租户"
        open={createOpen}
        onCancel={() => setCreateOpen(false)}
        footer={null}
        destroyOnClose
      >
        <Form form={createForm} layout="vertical" onFinish={handleCreate}>
          <Form.Item label="机构名称" name="name" rules={[{ required: true, message: "请输入机构名称" }]}>
            <Input placeholder="例：广州中医药大学" />
          </Form.Item>
          <Form.Item
            label="Slug（作为 schema 后缀，不可更改）"
            name="slug"
            rules={[
              { required: true, message: "请输入 slug" },
              { pattern: /^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$/, message: "小写字母/数字/连字符，3~32 位" },
            ]}
          >
            <Input placeholder="例：gzu-tcm" />
          </Form.Item>
          <Form.Item label="联系邮箱" name="contactEmail" rules={[{ type: "email", message: "邮箱格式不正确" }]}>
            <Input placeholder="admin@example.com" />
          </Form.Item>
          <Form.Item label="套餐" name="plan" initialValue="free">
            <Select options={[{ value: "free", label: "免费版" }, { value: "pro", label: "专业版" }, { value: "enterprise", label: "企业版" }]} />
          </Form.Item>
          <Form.Item>
            <Button type="primary" htmlType="submit" block loading={submitting}>
              创建（将自动建 schema 并初始化）
            </Button>
          </Form.Item>
        </Form>
      </Modal>

      <Modal
        title={`编辑租户：${editing?.name}`}
        open={!!editing}
        onCancel={() => setEditing(null)}
        footer={null}
        destroyOnClose
      >
        <Form form={editForm} layout="vertical" onFinish={handleEdit}>
          <Form.Item label="机构名称" name="name" rules={[{ required: true, message: "请输入机构名称" }]}>
            <Input />
          </Form.Item>
          <Form.Item label="联系邮箱" name="contactEmail" rules={[{ type: "email", message: "邮箱格式不正确" }]}>
            <Input />
          </Form.Item>
          <Form.Item label="联系电话" name="contactPhone">
            <Input />
          </Form.Item>
          <Form.Item label="简介" name="description">
            <Input.TextArea rows={3} />
          </Form.Item>
          <Form.Item label="套餐" name="plan">
            <Select options={[{ value: "free", label: "免费版" }, { value: "pro", label: "专业版" }, { value: "enterprise", label: "企业版" }]} />
          </Form.Item>
          <Form.Item>
            <Button type="primary" htmlType="submit" block loading={submitting}>
              保存
            </Button>
          </Form.Item>
        </Form>
      </Modal>
    </div>
  );
}
