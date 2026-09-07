"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Alert, Button, Card, Form, Input, Typography } from "antd";
import { useAuth } from "@/lib/auth";

export default function LoginPage() {
  const router = useRouter();
  const { login } = useAuth();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function onFinish(values: { email: string; password: string }) {
    setSubmitting(true);
    setError(null);
    const result = await login(values.email.trim(), values.password);
    setSubmitting(false);
    if (result.ok) {
      router.replace("/");
    } else {
      setError(result.error ?? "登录失败");
    }
  }

  return (
    <div className="login-wrap">
      <Card style={{ width: 400 }} title="中医教学 · 教师端">
        <Typography.Paragraph type="secondary">
          教师 / 机构管理员登录（课程创建与发布）
        </Typography.Paragraph>
        {error && (
          <Alert type="error" message={error} style={{ marginBottom: 16 }} showIcon />
        )}
        <Form layout="vertical" onFinish={onFinish} autoComplete="off">
          <Form.Item
            label="邮箱"
            name="email"
            rules={[
              { required: true, message: "请输入邮箱" },
              { type: "email", message: "邮箱格式不正确" },
            ]}
          >
            <Input placeholder="教师邮箱" />
          </Form.Item>
          <Form.Item
            label="密码"
            name="password"
            rules={[{ required: true, message: "请输入密码" }]}
          >
            <Input.Password placeholder="密码" />
          </Form.Item>
          <Form.Item>
            <Button type="primary" htmlType="submit" block loading={submitting}>
              登录
            </Button>
          </Form.Item>
        </Form>
      </Card>
    </div>
  );
}
