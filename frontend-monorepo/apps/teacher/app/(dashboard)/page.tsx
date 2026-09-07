"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Button, Card, Col, Row, Statistic, Typography, message } from "antd";
import { listTeacherCourses, type AshRpcError } from "@tcm-edu/rpc-client";
import { useAuth, useRequireAuth } from "@/lib/auth";

const COURSE_FIELDS = ["id", "status"] as const;

function errMsg(errors: AshRpcError[]): string {
  return errors?.[0]?.message ?? "加载失败";
}

export default function TeacherHomePage() {
  useRequireAuth();
  const router = useRouter();
  const { session } = useAuth();
  const [loading, setLoading] = useState(true);
  const [counts, setCounts] = useState({ total: 0, draft: 0, published: 0, archived: 0 });

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
        const rows = res.data as { status?: string }[];
        setCounts({
          total: rows.length,
          draft: rows.filter((r) => r.status === "draft").length,
          published: rows.filter((r) => r.status === "published").length,
          archived: rows.filter((r) => r.status === "archived").length,
        });
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

  return (
    <div>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 16 }}>
        <Typography.Title level={4} style={{ margin: 0 }}>
          工作台
        </Typography.Title>
        <Button type="primary" onClick={() => router.push("/courses/new")}>
          创建课程
        </Button>
      </div>
      <Row gutter={16}>
        <Col span={6}>
          <Card><Statistic title="全部课程" value={counts.total} loading={loading} /></Card>
        </Col>
        <Col span={6}>
          <Card><Statistic title="草稿" value={counts.draft} loading={loading} /></Card>
        </Col>
        <Col span={6}>
          <Card><Statistic title="已发布" value={counts.published} loading={loading} /></Card>
        </Col>
        <Col span={6}>
          <Card><Statistic title="已下架" value={counts.archived} loading={loading} /></Card>
        </Col>
      </Row>
      <Card style={{ marginTop: 16 }}>
        <Typography.Paragraph type="secondary" style={{ marginBottom: 8 }}>
          备课流程：创建课程 → 添加章节与课时 → 发布。上架后学生即可在学生端看到并选课。
        </Typography.Paragraph>
        <Button type="link" onClick={() => router.push("/courses")} style={{ paddingLeft: 0 }}>
          前往我的课程 →
        </Button>
      </Card>
    </div>
  );
}
