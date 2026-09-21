"use client";

import { useState } from "react";
import { Button, Card, Form, Input, Select, Space, Typography, message } from "antd";
import { BulbOutlined, CopyOutlined } from "@ant-design/icons";

import { useRequireAuth } from "@/lib/auth/guard";

const { Title, Paragraph } = Typography;

/**
 * 教师端 · AI 备课助手
 *
 * 调用 POST /api/ai/lesson_plan（qwen-flash），返回 markdown 教案渲染。
 */
export default function LessonPlanAssistantPage() {
  useRequireAuth();
  const [form] = Form.useForm();
  const [loading, setLoading] = useState(false);
  const [plan, setPlan] = useState<string>("");

  async function onFinish(values: {
    topic: string;
    subject?: string;
    level?: string;
    audience?: string;
  }) {
    setLoading(true);
    setPlan("");
    try {
      const sessionRaw = localStorage.getItem("tcm_session");
      const session = sessionRaw ? JSON.parse(sessionRaw) : null;
      const token = localStorage.getItem("auth_token");

      const res = await fetch("/api/ai/lesson_plan", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
          ...(session?.tenant ? { "X-Tenant": session.tenant } : {})
        },
        body: JSON.stringify(values)
      });

      const data = await res.json();
      if (!res.ok || data.status !== "ok") {
        message.error(data.reason ?? `请求失败 (${res.status})`);
        return;
      }

      setPlan(data.content ?? "");
    } catch (e) {
      message.error(`网络错误：${(e as Error).message}`);
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="p-6 max-w-4xl mx-auto space-y-4">
      <Title level={3}>
        <BulbOutlined /> AI 备课助手
      </Title>
      <Paragraph type="secondary">
        基于 qwen-flash（参考 KnowledgeHub 用法）生成结构化医学教案：教学目标、重点难点、教学过程、板书、作业。
      </Paragraph>

      <Card>
        <Form
          form={form}
          layout="vertical"
          onFinish={onFinish}
          initialValues={{ subject: "中医基础", level: "本科" }}
        >
          <Form.Item
            name="topic"
            label="章节 / 主题"
            rules={[{ required: true, message: "请输入主题" }]}
          >
            <Input placeholder="如：阴阳学说的基本内容" />
          </Form.Item>

          <Space size="middle" className="w-full">
            <Form.Item name="subject" label="学科" className="flex-1 min-w-[160px]">
              <Select
                options={[
                  { value: "中医基础", label: "中医基础" },
                  { value: "中医内科学", label: "中医内科学" },
                  { value: "解剖学", label: "解剖学" },
                  { value: "生理学", label: "生理学" },
                  { value: "病理学", label: "病理学" },
                  { value: "临床内科学", label: "临床内科学" },
                  { value: "护理学", label: "护理学" }
                ]}
              />
            </Form.Item>
            <Form.Item name="level" label="学段" className="flex-1 min-w-[140px]">
              <Select
                options={[
                  { value: "本科", label: "本科" },
                  { value: "规培", label: "规培" },
                  { value: "继续教育", label: "继续教育" }
                ]}
              />
            </Form.Item>
            <Form.Item name="audience" label="授课对象" className="flex-1 min-w-[160px]">
              <Input placeholder="如：中医学本科生" />
            </Form.Item>
          </Space>

          <Form.Item>
            <Button type="primary" htmlType="submit" loading={loading}>
              生成教案
            </Button>
          </Form.Item>
        </Form>
      </Card>

      {plan ? (
        <Card
          title="教案"
          extra={
            <Button
              icon={<CopyOutlined />}
              onClick={() => {
                navigator.clipboard.writeText(plan);
                message.success("已复制到剪贴板");
              }}
            >
              复制
            </Button>
          }
        >
          <pre className="whitespace-pre-wrap text-sm font-sans leading-6">{plan}</pre>
        </Card>
      ) : null}
    </div>
  );
}