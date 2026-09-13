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
  deleteUser,
  listOrganizations,
  listUsers,
  registerWithRole,
  updateUserRole,
  updateUserStatus,
  type AshRpcError,
} from "@tcm-edu/rpc-client";
import { useAuth } from "@/lib/auth/context";
import { useRequireAuth } from "@/lib/auth/guard";

interface UserRow {
  id: string;
  email: string;
  name?: string | null;
  role?: string | null;
  status?: string | null;
}

interface TenantOption {
  slug: string;
  schemaName: string;
  name: string;
}

const USER_FIELDS = ["id", "email", "name", "role", "status"] as const;

const ROLE_OPTIONS = [
  { value: "tenant_admin", label: "租户管理员" },
  { value: "teacher", label: "教师" },
  { value: "student", label: "学生" },
];

const ROLE_TAG: Record<string, React.ReactNode> = {
  tenant_admin: <Tag color="purple">租户管理员</Tag>,
  teacher: <Tag color="blue">教师</Tag>,
  student: <Tag color="green">学生</Tag>,
};

function errMsg(errors: AshRpcError[]): string {
  const first = errors?.[0];
  if (!first) return "操作失败";
  if (first.type === "forbidden") return "您没有权限执行此操作";
  if (first.type === "network_error") return "网络错误，请稍后重试";
  return first.message ?? "操作失败";
}

export default function UsersPage() {
  useRequireAuth();
  const { session } = useAuth();
  const [loading, setLoading] = useState(true);
  const [rows, setRows] = useState<UserRow[]>([]);
  const [tenants, setTenants] = useState<TenantOption[]>([]);
  const [activeTenant, setActiveTenant] = useState<string | null>(null);
  const [createOpen, setCreateOpen] = useState(false);
  const [roleEditing, setRoleEditing] = useState<UserRow | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [createForm] = Form.useForm();
  const [roleForm] = Form.useForm();

  const isSuper = session?.role === "super_admin";
  // 超管按所选租户查询（tenant override）；租户管理员固定走自己的 tenant。
  const effectiveTenant = isSuper ? activeTenant : (session?.tenant ?? null);

  const loadTenants = useCallback(async () => {
    const res = await listOrganizations({ fields: ["name", "slug", "schemaName"] });
    if (res.success) {
      const opts = (res.data as { name: string; slug: string; schemaName: string }[]).map(
        (o) => ({ name: o.name, slug: o.slug, schemaName: o.schemaName })
      );
      setTenants(opts);
      if (!activeTenant && opts.length > 0) {
        const def = opts.find((o) => o.schemaName === "tenant_default") ?? opts[0];
        setActiveTenant(def.schemaName);
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const loadUsers = useCallback(async () => {
    if (!effectiveTenant) return;
    setLoading(true);
    try {
      const res = await listUsers({ fields: [...USER_FIELDS], tenant: effectiveTenant });
      if (res.success) {
        setRows(res.data as UserRow[]);
      } else {
        message.error(errMsg(res.errors));
      }
    } finally {
      setLoading(false);
    }
  }, [effectiveTenant]);

  useEffect(() => {
    if (!session) return;
    if (isSuper) {
      loadTenants();
    } else {
      setActiveTenant(session.tenant);
    }
  }, [session, isSuper, loadTenants]);

  useEffect(() => {
    if (effectiveTenant) loadUsers();
  }, [effectiveTenant, loadUsers]);

  async function handleCreate(values: {
    email: string;
    name?: string;
    password: string;
    role: "tenant_admin" | "teacher" | "student";
  }) {
    if (!effectiveTenant) return;
    setSubmitting(true);
    try {
      const res = await registerWithRole({
        fields: [...USER_FIELDS],
        tenant: effectiveTenant,
        input: {
          email: values.email.trim(),
          name: values.name?.trim() || null,
          password: values.password,
          role: values.role,
        },
      });
      if (res.success) {
        message.success(`已创建用户 ${values.email}`);
        setCreateOpen(false);
        createForm.resetFields();
        loadUsers();
      } else {
        message.error(errMsg(res.errors));
      }
    } finally {
      setSubmitting(false);
    }
  }

  async function handleRoleChange(values: { role: "tenant_admin" | "teacher" | "student" }) {
    if (!roleEditing || !effectiveTenant) return;
    setSubmitting(true);
    try {
      const res = await updateUserRole({
        identity: roleEditing.id,
        fields: [...USER_FIELDS],
        tenant: effectiveTenant,
        input: { role: values.role },
      });
      if (res.success) {
        message.success("角色已更新");
        setRoleEditing(null);
        loadUsers();
      } else {
        message.error(errMsg(res.errors));
      }
    } finally {
      setSubmitting(false);
    }
  }

  async function handleStatus(row: UserRow, status: "active" | "disabled") {
    if (!effectiveTenant) return;
    const res = await updateUserStatus({
      identity: row.id,
      fields: ["id", "status"],
      tenant: effectiveTenant,
      input: { status },
    });
    if (res.success) {
      message.success(status === "active" ? "已启用" : "已停用");
      loadUsers();
    } else {
      message.error(errMsg(res.errors));
    }
  }

  async function handleDelete(row: UserRow) {
    if (!effectiveTenant) return;
    const res = await deleteUser({ identity: row.id, tenant: effectiveTenant });
    if (res.success) {
      message.success(`已删除 ${row.email}`);
      loadUsers();
    } else {
      message.error(errMsg(res.errors));
    }
  }

  return (
    <div>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 16, flexWrap: "wrap", gap: 8 }}>
        <Typography.Title level={4} style={{ margin: 0 }}>
          用户管理
        </Typography.Title>
        <Space>
          {isSuper ? (
            <Select
              style={{ width: 260 }}
              placeholder="选择租户"
              value={activeTenant}
              onChange={setActiveTenant}
              options={tenants.map((t) => ({
                value: t.schemaName,
                label: `${t.name}（${t.schemaName}）`,
              }))}
            />
          ) : (
            <Tag color="blue">{session?.tenant}</Tag>
          )}
          <Button type="primary" onClick={() => setCreateOpen(true)} disabled={!effectiveTenant}>
            创建用户
          </Button>
        </Space>
      </div>
      <Card>
        <Table<UserRow>
          rowKey="id"
          scroll={{ x: 720 }}
          loading={loading}
          dataSource={rows}
          pagination={{ pageSize: 10, showSizeChanger: false }}
          columns={[
            { title: "邮箱", dataIndex: "email" },
            { title: "姓名", dataIndex: "name", render: (v: string | null) => v || "-" },
            { title: "角色", dataIndex: "role", render: (v: string) => ROLE_TAG[v] ?? <Tag>{v}</Tag> },
            {
              title: "状态",
              dataIndex: "status",
              render: (v: string) =>
                v === "active" ? <Tag color="green">启用</Tag> : <Tag color="red">停用</Tag>,
            },
            {
              title: "操作",
              key: "actions",
              render: (_, row) => (
                <Space size="small">
                  <Button
                    type="link"
                    size="small"
                    onClick={() => {
                      setRoleEditing(row);
                      roleForm.setFieldsValue({ role: row.role });
                    }}
                  >
                    改角色
                  </Button>
                  {row.status === "active" ? (
                    <Button type="link" size="small" onClick={() => handleStatus(row, "disabled")}>
                      停用
                    </Button>
                  ) : (
                    <Button type="link" size="small" onClick={() => handleStatus(row, "active")}>
                      启用
                    </Button>
                  )}
                  <Popconfirm
                    title={`删除用户 ${row.email}？`}
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

      <Modal title="创建用户" open={createOpen} onCancel={() => setCreateOpen(false)} footer={null} destroyOnClose>
        <Form form={createForm} layout="vertical" onFinish={handleCreate}>
          <Form.Item label="邮箱" name="email" rules={[{ required: true, message: "请输入邮箱" }, { type: "email", message: "邮箱格式不正确" }]}>
            <Input placeholder="user@example.com" />
          </Form.Item>
          <Form.Item label="姓名" name="name">
            <Input placeholder="可选" />
          </Form.Item>
          <Form.Item label="初始密码" name="password" rules={[{ required: true, message: "请输入初始密码" }, { min: 6, message: "至少 6 位" }]}>
            <Input.Password placeholder="至少 6 位" />
          </Form.Item>
          <Form.Item label="角色" name="role" initialValue="student">
            <Select options={ROLE_OPTIONS} />
          </Form.Item>
          <Form.Item>
            <Button type="primary" htmlType="submit" block loading={submitting}>
              创建
            </Button>
          </Form.Item>
        </Form>
      </Modal>

      <Modal
        title={`修改角色：${roleEditing?.email}`}
        open={!!roleEditing}
        onCancel={() => setRoleEditing(null)}
        footer={null}
        destroyOnClose
      >
        <Form form={roleForm} layout="vertical" onFinish={handleRoleChange}>
          <Form.Item label="角色" name="role" rules={[{ required: true, message: "请选择角色" }]}>
            <Select options={ROLE_OPTIONS} />
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
