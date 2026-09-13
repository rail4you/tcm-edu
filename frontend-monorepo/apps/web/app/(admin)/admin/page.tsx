"use client";

import { useCallback, useEffect, useState } from "react";
import { Card, Col, Row, Spin, Statistic, Table, Tag, Typography } from "antd";
import {
  listOrganizations,
  listUsers,
  listStudents,
  listTeachers,
} from "@tcm-edu/rpc-client";
import { useAuth } from "@/lib/auth/context";
import { useRequireAuth } from "@/lib/auth/guard";

interface OrgRow {
  id: string;
  name: string;
  slug: string;
  schemaName?: string | null;
  status?: string | null;
  plan?: string | null;
}

export default function DashboardPage() {
  const { session } = useAuth();
  useRequireAuth();
  const [loading, setLoading] = useState(true);
  const [orgs, setOrgs] = useState<OrgRow[]>([]);
  const [counts, setCounts] = useState({ users: 0, students: 0, teachers: 0 });

  const load = useCallback(async () => {
    if (!session) return;
    setLoading(true);
    try {
      if (session.role === "super_admin") {
        const res = await listOrganizations({
          fields: ["id", "name", "slug", "schemaName", "status", "plan"],
        });
        if (res.success) setOrgs(res.data as OrgRow[]);
      } else {
        const tenant = session.tenant;
        const [u, s, t] = await Promise.all([
          listUsers({ fields: ["id"], tenant }),
          listStudents({ fields: ["id"], tenant }),
          listTeachers({ fields: ["id"], tenant }),
        ]);
        setCounts({
          users: u.success ? u.data.length : 0,
          students: s.success ? s.data.length : 0,
          teachers: t.success ? t.data.length : 0,
        });
      }
    } finally {
      setLoading(false);
    }
  }, [session]);

  useEffect(() => {
    load();
  }, [load]);

  if (!session) {
    return (
      <div style={{ textAlign: "center", padding: 64 }}>
        <Spin />
      </div>
    );
  }

  if (session.role === "tenant_admin") {
    return (
      <div>
        <Typography.Title level={4}>本机构概览</Typography.Title>
        <Typography.Paragraph type="secondary">
          租户：<Tag color="blue">{session.tenant}</Tag>
        </Typography.Paragraph>
        <Row gutter={16}>
          <Col span={8}>
            <Card>
              <Statistic title="用户总数" value={loading ? "-" : counts.users} />
            </Card>
          </Col>
          <Col span={8}>
            <Card>
              <Statistic title="教师" value={loading ? "-" : counts.teachers} />
            </Card>
          </Col>
          <Col span={8}>
            <Card>
              <Statistic title="学生" value={loading ? "-" : counts.students} />
            </Card>
          </Col>
        </Row>
      </div>
    );
  }

  const active = orgs.filter((o) => o.status === "active").length;
  const suspended = orgs.filter((o) => o.status === "suspended").length;
  const archived = orgs.filter((o) => o.status === "archived").length;

  return (
    <div>
      <Typography.Title level={4}>平台总览</Typography.Title>
      <Row gutter={16} style={{ marginBottom: 16 }}>
        <Col span={6}>
          <Card>
            <Statistic title="租户总数" value={loading ? "-" : orgs.length} />
          </Card>
        </Col>
        <Col span={6}>
          <Card>
            <Statistic title="运营中" value={loading ? "-" : active} valueStyle={{ color: "#3f8600" }} />
          </Card>
        </Col>
        <Col span={6}>
          <Card>
            <Statistic title="已暂停" value={loading ? "-" : suspended} valueStyle={{ color: "#cf1322" }} />
          </Card>
        </Col>
        <Col span={6}>
          <Card>
            <Statistic title="已归档" value={loading ? "-" : archived} />
          </Card>
        </Col>
      </Row>
      <Card title="最近创建的租户" loading={loading}>
        <Table<OrgRow>
          rowKey="id"
          scroll={{ x: 720 }}
          dataSource={orgs.slice(0, 5)}
          pagination={false}
          columns={[
            { title: "名称", dataIndex: "name" },
            { title: "Slug", dataIndex: "slug" },
            {
              title: "状态",
              dataIndex: "status",
              render: (v: string) =>
                v === "active" ? (
                  <Tag color="green">运营中</Tag>
                ) : v === "suspended" ? (
                  <Tag color="red">已暂停</Tag>
                ) : (
                  <Tag>已归档</Tag>
                ),
            },
            { title: "套餐", dataIndex: "plan" },
          ]}
        />
      </Card>
    </div>
  );
}
