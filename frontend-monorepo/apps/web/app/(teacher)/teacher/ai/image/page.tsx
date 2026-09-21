"use client";

import { useState } from "react";
import {
  Button,
  Card,
  Empty,
  Form,
  Image,
  Input,
  Select,
  Space,
  Spin,
  Typography,
  message
} from "antd";
import { PictureOutlined } from "@ant-design/icons";

import { useRequireAuth } from "@/lib/auth/guard";

const { Title, Paragraph, Text } = Typography;

const STYLES = [
  { value: "<flat illustration>", label: "扁平插画（推荐教学图）" },
  { value: "<sketch>", label: "素描" },
  { value: "<watercolor>", label: "水彩" },
  { value: "<photography>", label: "摄影写实" },
  { value: "<3d cartoon>", label: "3D 卡通" },
  { value: "<oil painting>", label: "油画" }
];

const SIZES = [
  { value: "1024*1024", label: "1024 × 1024" },
  { value: "720*1280", label: "720 × 1280（竖版）" },
  { value: "1280*720", label: "1280 × 720（横版）" }
];

const PRESETS = [
  { label: "心脏解剖（标注冠状血管）", value: "解剖示意图：心脏横截面，标注冠状动脉，扁平插画，白底，清晰教学图" },
  { label: "肺脏解剖（主支气管）", value: "肺脏解剖示意图，标注主支气管，扁平插画，白底教学图" },
  { label: "肝脏 / 门静脉", value: "肝脏解剖示意图，显示门静脉走行，扁平插画，白底，医学教学" },
  { label: "骨关节正侧位", value: "膝关节正侧位示意，骨与韧带，扁平插画，白底教学图" },
  { label: "药材图（人参/黄芪）", value: "中医饮片：人参切片特写，白底，高清，医学教学配图" },
  { label: "针灸穴位定位", value: "人体针灸穴位示意图，经络路线，扁平插画，白底教学图" }
];

export default function AIMedicalImagePage() {
  useRequireAuth();
  const [form] = Form.useForm();
  const [loading, setLoading] = useState(false);
  const [images, setImages] = useState<string[]>([]);
  const [usedPrompt, setUsedPrompt] = useState("");

  async function onFinish(values: {
    prompt: string;
    style?: string;
    size?: string;
  }) {
    setLoading(true);
    setImages([]);
    try {
      const token = localStorage.getItem("auth_token");
      const res = await fetch("/api/ai/image", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(token ? { Authorization: `Bearer ${token}` } : {})
        },
        body: JSON.stringify({
          prompt: values.prompt,
          style: values.style,
          size: values.size,
          key_prefix: "ai"
        })
      });
      const data = await res.json();
      if (!res.ok || data.status !== "ok") {
        message.error(data.reason ?? `请求失败 (${res.status})`);
        return;
      }
      setImages(data.urls ?? []);
      setUsedPrompt(values.prompt);
    } catch (e) {
      message.error(`网络错误：${(e as Error).message}`);
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="p-6 max-w-4xl mx-auto space-y-4">
      <Title level={3}>
        <PictureOutlined /> AI 医学图片生成
      </Title>
      <Paragraph type="secondary">
        基于 <Text code>wanx2.1-t2i-turbo</Text>（DashScope 文生图），生成后自动存入{" "}
        <Text code>xingningshu</Text> OSS，返回预签名 URL（1 小时有效，图片地址以{" "}
        <Text code>OSSAccessKeyId</Text> 标识）。
      </Paragraph>

      <Card>
        <Form
          form={form}
          layout="vertical"
          onFinish={onFinish}
          initialValues={{ style: "<flat illustration>", size: "1024*1024" }}
        >
          <Form.Item
            name="prompt"
            label="图片描述"
            rules={[{ required: true, message: "请输入图片描述" }]}
          >
            <Input.TextArea
              rows={3}
              placeholder="如：解剖示意图：心脏横截面，标注冠状动脉，扁平插画，白底，清晰教学图"
            />
          </Form.Item>

          <div className="mb-4">
            <Text type="secondary" className="mb-1 block">
              快捷模板：
            </Text>
            <Space wrap>
              {PRESETS.map((p) => (
                <Button
                  key={p.label}
                  size="small"
                  onClick={() => form.setFieldValue("prompt", p.value)}
                >
                  {p.label}
                </Button>
              ))}
            </Space>
          </div>

          <Space size="middle" className="w-full">
            <Form.Item name="style" label="风格" className="flex-1 min-w-[200px]">
              <Select options={STYLES} />
            </Form.Item>
            <Form.Item name="size" label="尺寸" className="flex-1 min-w-[160px]">
              <Select options={SIZES} />
            </Form.Item>
          </Space>

          <Form.Item>
            <Button type="primary" htmlType="submit" loading={loading}>
              生成图片
            </Button>
          </Form.Item>
        </Form>
      </Card>

      {images.length > 0 ? (
        <Card title={`生成结果（${usedPrompt.slice(0, 30)}…）`}>
          <Space direction="vertical" size="middle" className="w-full">
            {images.map((src, i) => (
              <div key={i}>
                <Image src={src} alt="AI 生成医学图" width={480} />
                <div className="mt-2">
                  <Text copyable={{ text: src }} type="secondary" style={{ fontSize: 12 }}>
                    复制图链接
                  </Text>
                </div>
              </div>
            ))}
          </Space>
        </Card>
      ) : loading ? (
        <Card>
          <div className="flex flex-col items-center gap-3 py-8">
            <Spin size="large" />
            <Text type="secondary">正在生成（文生图任务约 5-15 秒），请稍候…</Text>
          </div>
        </Card>
      ) : (
        <Card>
          <Empty description="生成结果会显示在这里" />
        </Card>
      )}
    </div>
  );
}