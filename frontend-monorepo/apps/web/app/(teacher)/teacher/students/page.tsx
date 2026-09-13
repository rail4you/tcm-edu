"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { Card, Input, Table, Tag, Typography, message } from "antd";
import { listStudents, type AshRpcError } from "@tcm-edu/rpc-client";
import { useAuth } from "@/lib/auth/context"; import { useRequireAuth } from "@/lib/auth/guard";

interface StudentRow {
  id: string;
  email: string;
  name?: string | null;
  status?: string | null;
}

const STUDENT_FIELDS = ["id", "email", "name", "status"] as const;

function errMsg(errors: AshRpcError[]): string {
  const first = errors?.[0];
  if (!first) return "加载失败";
  if (first.type === "forbidden") return "您没有权限执行此操作";
  if (first.type === "network_error") return "网络错误，请稍后重试";
  return first.message ?? "加载失败";
}

export default function TeacherStudentsPage() {
  useRequireAuth();
  const { session } = useAuth();
  const [loading, setLoading] = useState(true);
  const [rows, setRows] = useState<StudentRow[]>([]);
  const [keyword, setKeyword] = useState("");

  const load = useCallback(async () => {
    if (!session?.tenant) return;
    setLoading(true);
    try {
      const res = await listStudents({ fields: [...STUDENT_FIELDS], tenant: session.tenant });
      if (res.success) {
        setRows(res.data as StudentRow[]);
      } else {
        message.error(errMsg(res.errors));
      }
    } finally {
      setLoading(false);
    }
  }, [session?.tenant]);

  useEffect(() => {
    if (session) load();
  }, [session, load]);

  const filtered = useMemo(() => {
    const kw = keyword.trim().toLowerCase();
    if (!kw) return rows;
    return rows.filter(
      (r) =>
        r.email.toLowerCase().includes(kw) ||
        (r.name ?? "").toLowerCase().includes(kw)
    );
  }, [rows, keyword]);

  return (
    <div>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 16, flexWrap: "wrap", gap: 8 }}>
        <Typography.Title level={4} style={{ margin: 0 }}>
          我的学生
        </Typography.Title>
        <Input.Search
          placeholder="按邮箱 / 姓名筛选"
          allowClear
          style={{ width: 280 }}
          onSearch={setKeyword}
          onChange={(e) => {
            if (!e.target.value) setKeyword("");
          }}
        />
      </div>
      <Card>
        <Typography.Paragraph type="secondary">
          当前为本机构全部学生。选课关系（报名我课程的学生）待 Phase 7 选课域完成后自动按课程筛选。
        </Typography.Paragraph>
        <Table<StudentRow>
          rowKey="id"
          scroll={{ x: 720 }}
          loading={loading}
          dataSource={filtered}
          pagination={{ pageSize: 10, showSizeChanger: false }}
          columns={[
            { title: "邮箱", dataIndex: "email" },
            { title: "姓名", dataIndex: "name", render: (v: string | null) => v || "-" },
            {
              title: "状态",
              dataIndex: "status",
              render: (v: string) =>
                v === "active" ? <Tag color="green">启用</Tag> : <Tag color="red">停用</Tag>,
            },
          ]}
        />
      </Card>
    </div>
  );
}
