"use client";

import { useCallback, useEffect, useState } from "react";
import { Button, Card, Empty, Space, Spin, Tag, Typography, message } from "antd";
import { BookOutlined, RobotOutlined } from "@ant-design/icons";

import {
  myMistakes,
  type AttemptResourceSchema,
  type AshRpcError
} from "@tcm-edu/rpc-client";
import { useAuth } from "@/lib/auth/context";
import { useRequireAuth } from "@/lib/auth/guard";

type AttemptItem = Pick<
  AttemptResourceSchema,
  "id" | "answer" | "isCorrect" | "aiExplanation"
>;

const { Title, Paragraph, Text } = Typography;

const ATTEMPT_FIELDS = ["id", "answer", "isCorrect", "aiExplanation"] as const;

function errMsg(errors: AshRpcError[] | undefined): string {
  const first = errors?.[0];
  if (!first) return "加载失败";
  if (first.type === "forbidden") return "您没有权限";
  return first.message ?? "加载失败";
}

export default function MistakeBookPage() {
  useRequireAuth();
  const { session } = useAuth();
  const [loading, setLoading] = useState(true);
  const [items, setItems] = useState<AttemptItem[]>([]);

  const load = useCallback(async () => {
    if (!session?.userId || !session?.tenant) return;
    setLoading(true);
    try {
      const res = await myMistakes({
        fields: [...ATTEMPT_FIELDS],
        tenant: session.tenant
      });
      if (res.success) {
        setItems((res.data as AttemptItem[]) ?? []);
      } else {
        message.error(errMsg(res.errors));
      }
    } finally {
      setLoading(false);
    }
  }, [session?.userId, session?.tenant]);

  useEffect(() => {
    load();
  }, [load]);

  async function askAI(attemptId: string) {
    const token = localStorage.getItem("auth_token");
    try {
      const res = await fetch("/api/ai/mistake_explain", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(token ? { Authorization: `Bearer ${token}` } : {})
        },
        body: JSON.stringify({ attempt_id: attemptId })
      });
      const data = await res.json();
      if (res.ok && data.status === "queued") {
        message.success("AI 解析已加入队列，请稍后刷新");
        // 轮询简易刷新（生产可换 PubSub/SSE）
        setTimeout(() => load(), 3000);
      } else {
        message.error(data.reason ?? `提交失败 (${res.status})`);
      }
    } catch (e) {
      message.error(`网络错误：${(e as Error).message}`);
    }
  }

  return (
    <div className="p-6 max-w-4xl mx-auto space-y-4">
      <Title level={3}>
        <BookOutlined /> 我的错题本
      </Title>
      <Paragraph type="secondary">
        基于 <Text code>my_mistakes</Text>（TcmEdu.Quiz.Attempt · isCorrect == false）。
        点击「AI 解析」会触发 MistakeExplainerWorker，结果写回 <Text code>Attempt.aiExplanation</Text>。
      </Paragraph>

      <Spin spinning={loading}>
        {items.length === 0 && !loading ? (
          <Empty description="暂无错题，太棒了！" />
        ) : (
          <Space direction="vertical" size="middle" className="w-full">
            {items.map((a) => (
              <Card
                key={a.id}
                size="small"
                title={
                  <Space>
                    <Tag color="red">答错</Tag>
                  </Space>
                }
                extra={
                  <Button
                    icon={<RobotOutlined />}
                    onClick={() => askAI(a.id)}
                    disabled={!!a.aiExplanation}
                  >
                    {a.aiExplanation ? "已解析" : "AI 解析"}
                  </Button>
                }
              >
                <Paragraph>
                  <Text strong>你的答案：</Text> {a.answer ?? "—"}
                </Paragraph>
                {a.aiExplanation ? (
                  <Card type="inner" size="small" title="AI 解析" className="mt-2">
                    <pre className="whitespace-pre-wrap text-sm font-sans leading-6">
                      {a.aiExplanation}
                    </pre>
                  </Card>
                ) : null}
              </Card>
            ))}
          </Space>
        )}
      </Spin>
    </div>
  );
}