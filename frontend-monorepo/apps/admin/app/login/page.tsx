"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Alert, Button, Card, Form, Input, Tabs, Typography } from "antd";
import { useAuth } from "@/lib/auth";

export default function LoginPage() {
  const router = useRouter();
  const { loginSuperAdmin, loginTenantAdmin } = useAuth();
  const [tab, setTab] = useState("super");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function onFinish(values: { email: string; password: string }) {
    setSubmitting(true);
    setError(null);
    const fn = tab === "super" ? loginSuperAdmin : loginTenantAdmin;
    const result = await fn(values.email.trim(), values.password);
    setSubmitting(false);
    if (result.ok) {
      router.replace("/");
    } else {
      setError(result.error ?? "登录失败");
    }
  }

  return (
    <div className="login-wrap">
      <Card style={{ width: 400 }} title="中医教学 · 管理端">
        <Typography.Paragraph type="secondary">
          {tab === "super" ? "超级管理员登录（跨租户运营）" : "租户管理员登录（本机构用户管理）"}
        </Typography.Paragraph>
        <Tabs
          activeKey={tab}
          onChange={(k) => {
            setTab(k);
            setError(null);
          }}
          items={[
            { key: "super", label: "超级管理员" },
            { key: "tenant", label: "租户管理员" },
          ]}
        />
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
            <Input placeholder={tab === "super" ? "admin@example.com" : "机构管理员邮箱"} />
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
