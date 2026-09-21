"use client";

import { useCallback, useEffect, useState } from "react";
import { Badge, Button, Empty, List, Space, Spin, Tag, Typography, message } from "antd";
import { BellOutlined, CheckOutlined } from "@ant-design/icons";

import {
  listNotifications,
  markRead,
  markAllRead,
  type NotificationResourceSchema,
  type AshRpcError
} from "@tcm-edu/rpc-client";
import { useAuth } from "@/lib/auth/context";
import { useRequireAuth } from "@/lib/auth/guard";

type NotificationItem = Pick<
  NotificationResourceSchema,
  "id" | "type" | "title" | "body" | "readAt" | "isRead" | "payload"
>;

const { Title, Text } = Typography;

const NOTIF_FIELDS = ["id", "type", "title", "body", "readAt", "isRead", "payload"] as const;

function errMsg(errors: AshRpcError[] | undefined): string {
  const first = errors?.[0];
  if (!first) return "加载失败";
  return first.message ?? "加载失败";
}

const TYPE_LABEL: Record<string, { label: string; color: string }> = {
  system: { label: "系统", color: "blue" },
  enrollment: { label: "选课", color: "green" },
  course_published: { label: "课程发布", color: "purple" },
  progress: { label: "学习进度", color: "cyan" },
  quiz_graded: { label: "答题", color: "gold" },
  ai_lesson: { label: "AI 教学", color: "magenta" }
};

export default function NotificationsPage() {
  useRequireAuth();
  const { session } = useAuth();
  const [loading, setLoading] = useState(true);
  const [items, setItems] = useState<NotificationItem[]>([]);
  const [busy, setBusy] = useState(false);

  const unreadCount = items.filter((n) => !n.readAt && !n.isRead).length;

  const load = useCallback(async () => {
    if (!session?.tenant) return;
    setLoading(true);
    try {
      const res = await listNotifications({
        fields: [...NOTIF_FIELDS],
        tenant: session.tenant,
        page: { limit: 50 }
      });
      if (res.success) {
        setItems((res.data as NotificationItem[]) ?? []);
      } else {
        message.error(errMsg(res.errors));
      }
    } finally {
      setLoading(false);
    }
  }, [session?.tenant]);

  useEffect(() => {
    load();
  }, [load]);

  async function onMarkRead(id: string) {
    setBusy(true);
    try {
      const res = await markRead({
        fields: ["id", "readAt"],
        identity: id,
        tenant: session!.tenant!
      });
      if (res.success) {
        await load();
      } else {
        message.error(errMsg(res.errors));
      }
    } finally {
      setBusy(false);
    }
  }

  async function onMarkAllRead() {
    setBusy(true);
    try {
      const firstUnread = items.find((n) => !n.readAt && !n.isRead);
      if (!firstUnread) return;

      const res = await markAllRead({
        fields: [],
        identity: firstUnread.id,
        tenant: session!.tenant!
      });
      if (res.success) {
        await load();
      } else {
        message.error(errMsg(res.errors));
      }
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="p-6 max-w-4xl mx-auto space-y-4">
      <Title level={3}>
        <Space>
          <BellOutlined />
          通知中心
          {unreadCount > 0 && <Badge count={unreadCount} />}
        </Space>
      </Title>

      <div className="flex justify-end">
        <Button
          icon={<CheckOutlined />}
          onClick={onMarkAllRead}
          disabled={busy || unreadCount === 0}
        >
          全部已读
        </Button>
      </div>

      <Spin spinning={loading}>
        {items.length === 0 && !loading ? (
          <Empty description="暂无通知" />
        ) : (
          <List
            bordered
            dataSource={items}
            renderItem={(n) => {
              const meta = TYPE_LABEL[n.type ?? "system"] ?? TYPE_LABEL.system;
              const unread = !n.readAt;
              return (
                <List.Item
                  className={unread ? "bg-blue-50/40" : ""}
                  actions={[
                    unread ? (
                      <Button
                        key="read"
                        type="link"
                        onClick={() => onMarkRead(n.id)}
                        disabled={busy}
                      >
                        标为已读
                      </Button>
                    ) : (
                      <Text key="read" type="secondary">
                        已读
                      </Text>
                    )
                  ]}
                >
                  <List.Item.Meta
                    title={
                      <Space>
                        {unread && <Badge status="processing" />}
                        <Tag color={meta.color}>{meta.label}</Tag>
                        <Text strong={unread}>{n.title}</Text>
                      </Space>
                    }
                    description={
                      <Space direction="vertical" size={0}>
                        {n.body ? <Text type="secondary">{n.body}</Text> : null}
                      </Space>
                    }
                  />
                </List.Item>
              );
            }}
          />
        )}
      </Spin>
    </div>
  );
}