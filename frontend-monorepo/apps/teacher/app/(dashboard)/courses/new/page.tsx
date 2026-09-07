"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Button, Card, Form, Input, InputNumber, Select, Typography, message } from "antd";
import {
  createCourse,
  listCategories,
  type AshRpcError,
} from "@tcm-edu/rpc-client";
import { useAuth, useRequireAuth } from "@/lib/auth";

interface CategoryOption {
  id: string;
  name: string;
}

const LEVEL_OPTIONS = [
  { value: "beginner", label: "初级" },
  { value: "intermediate", label: "中级" },
  { value: "advanced", label: "高级" },
];

function errMsg(errors: AshRpcError[]): string {
  const first = errors?.[0];
  if (!first) return "创建失败";
  if (first.type === "forbidden") return "您没有权限执行此操作";
  if (first.type === "network_error") return "网络错误，请稍后重试";
  return first.message ?? "创建失败";
}

export default function NewCoursePage() {
  useRequireAuth();
  const router = useRouter();
  const { session } = useAuth();
  const [submitting, setSubmitting] = useState(false);
  const [categories, setCategories] = useState<CategoryOption[]>([]);
  const [form] = Form.useForm();

  useEffect(() => {
    if (!session?.tenant) return;
    listCategories({ fields: ["id", "name"], tenant: session.tenant }).then((res) => {
      if (res.success) setCategories(res.data as CategoryOption[]);
    });
  }, [session?.tenant]);

  async function onFinish(values: {
    title: string;
    subtitle?: string;
    description?: string;
    coverImageUrl?: string;
    level?: "beginner" | "intermediate" | "advanced";
    priceYuan?: number;
    categoryId?: string;
  }) {
    if (!session?.userId || !session?.tenant) {
      message.error("登录信息缺失，请重新登录");
      return;
    }
    setSubmitting(true);
    try {
      const res = await createCourse({
        fields: ["id", "title", "status"],
        tenant: session.tenant,
        input: {
          title: values.title.trim(),
          subtitle: values.subtitle?.trim() || null,
          description: values.description?.trim() || null,
          coverImageUrl: values.coverImageUrl?.trim() || null,
          level: values.level ?? null,
          priceCents:
            values.priceYuan == null ? null : Math.round(values.priceYuan * 100),
          teacherId: session.userId,
          categoryId: values.categoryId || null,
        },
      });
      if (res.success) {
        const created = res.data as { id: string };
        message.success("课程已创建，继续添加章节与课时");
        router.replace(`/courses/${created.id}/edit`);
      } else {
        message.error(errMsg(res.errors));
      }
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div style={{ maxWidth: 720 }}>
      <Typography.Title level={4}>创建课程</Typography.Title>
      <Card>
        <Form form={form} layout="vertical" onFinish={onFinish} initialValues={{ level: "beginner", priceYuan: 0 }}>
          <Form.Item label="标题" name="title" rules={[{ required: true, message: "请输入课程标题" }]}>
            <Input placeholder="如：中医基础理论（上）" maxLength={100} />
          </Form.Item>
          <Form.Item label="副标题" name="subtitle">
            <Input placeholder="一句话介绍（可选）" maxLength={200} />
          </Form.Item>
          <Form.Item label="简介" name="description">
            <Input.TextArea rows={4} placeholder="课程介绍、适合人群、学习目标（可选）" maxLength={2000} />
          </Form.Item>
          <Form.Item label="封面图片 URL" name="coverImageUrl">
            <Input placeholder="https://...（可选，可先留空）" />
          </Form.Item>
          <Form.Item label="难度" name="level">
            <Select options={LEVEL_OPTIONS} />
          </Form.Item>
          <Form.Item label="价格（元，0 = 免费）" name="priceYuan">
            <InputNumber min={0} precision={2} style={{ width: "100%" }} />
          </Form.Item>
          <Form.Item label="分类" name="categoryId">
            <Select
              allowClear
              placeholder="选择分类（可选）"
              options={categories.map((c) => ({ value: c.id, label: c.name }))}
            />
          </Form.Item>
          <Form.Item>
            <Button type="primary" htmlType="submit" loading={submitting}>
              创建并去添加章节
            </Button>
          </Form.Item>
        </Form>
      </Card>
    </div>
  );
}
