"use client";

import { useCallback, useEffect, useState } from "react";
import {
  Button,
  Card,
  Empty,
  Form,
  Input,
  List,
  Modal,
  Select,
  Space,
  Spin,
  Tag,
  Typography,
  message
} from "antd";
import { DatabaseOutlined, PlusOutlined } from "@ant-design/icons";

import {
  listQuestionBanks,
  listQuestionsByBank,
  createQuestionBank,
  createQuestion,
  type AshRpcError
} from "@tcm-edu/rpc-client";
import { useAuth } from "@/lib/auth/context";
import { useRequireAuth } from "@/lib/auth/guard";

const { Title, Text, Paragraph } = Typography;

const BANK_FIELDS = ["id", "name", "subject", "isPublic"] as const;
const QUESTION_FIELDS = ["id", "stem", "type", "difficulty", "options"] as const;

const SUBJECTS = [
  { value: "traditional_chinese_medicine", label: "中医" },
  { value: "western_medicine", label: "西医" },
  { value: "anatomy", label: "解剖" },
  { value: "physiology", label: "生理" },
  { value: "pathology", label: "病理" },
  { value: "pharmacology", label: "药理" },
  { value: "clinical", label: "临床" },
  { value: "nursing", label: "护理" },
  { value: "public_health", label: "公卫" }
];

function errMsg(errors: AshRpcError[] | undefined): string {
  const first = errors?.[0];
  if (!first) return "操作失败";
  return first.message ?? "操作失败";
}

export default function QuizPage() {
  useRequireAuth();
  const { session } = useAuth();
  const [loading, setLoading] = useState(true);
  const [banks, setBanks] = useState<{ id: string; name: string; subject?: string; isPublic?: boolean }[]>([]);
  const [selectedBankId, setSelectedBankId] = useState<string | null>(null);
  const [questions, setQuestions] = useState<unknown[]>([]);
  const [questionsLoading, setQuestionsLoading] = useState(false);

  const [createBankOpen, setCreateBankOpen] = useState(false);
  const [createQOpen, setCreateQOpen] = useState(false);
  const [bankForm] = Form.useForm();
  const [qForm] = Form.useForm();

  const tenant = session?.tenant;

  const loadBanks = useCallback(async () => {
    if (!tenant) return;
    setLoading(true);
    try {
      const res = await listQuestionBanks({
        fields: [...BANK_FIELDS],
        tenant
      });
      if (res.success) {
        setBanks((res.data as typeof banks) ?? []);
      } else {
        message.error(errMsg(res.errors));
      }
    } finally {
      setLoading(false);
    }
  }, [tenant]);

  const loadQuestions = useCallback(async (bankId: string) => {
    setQuestionsLoading(true);
    try {
      const res = await listQuestionsByBank({
        fields: [...QUESTION_FIELDS],
        tenant: tenant!,
        input: { bankId }
      });
      if (res.success) {
        setQuestions((res.data as unknown[]) ?? []);
      } else {
        message.error(errMsg(res.errors));
      }
    } finally {
      setQuestionsLoading(false);
    }
  }, [tenant]);

  useEffect(() => {
    loadBanks();
  }, [loadBanks]);

  useEffect(() => {
    if (selectedBankId) loadQuestions(selectedBankId);
  }, [selectedBankId, loadQuestions]);

  async function onCreateBank() {
    const values = await bankForm.validateFields();
    try {
      const res = await createQuestionBank({
        fields: ["id", "name"],
        tenant: tenant!,
        input: values
      });
      if (res.success) {
        message.success("题库已创建");
        setCreateBankOpen(false);
        bankForm.resetFields();
        loadBanks();
      } else {
        message.error(errMsg(res.errors));
      }
    } catch {
      /* validateFields handles */
    }
  }

  async function onCreateQuestion() {
    const values = await qForm.validateFields();
    try {
      const res = await createQuestion({
        fields: ["id"],
        tenant: tenant!,
        input: { ...values, bankId: selectedBankId }
      });
      if (res.success) {
        message.success("题目已添加");
        setCreateQOpen(false);
        qForm.resetFields();
        if (selectedBankId) loadQuestions(selectedBankId);
      } else {
        message.error(errMsg(res.errors));
      }
    } catch {
      /* */
    }
  }

  return (
    <div className="p-6 max-w-5xl mx-auto space-y-4">
      <Title level={3}>
        <DatabaseOutlined /> 题库管理
      </Title>
      <Paragraph type="secondary">
        维护题库与题目（<Text code>TcmEdu.Quiz.QuestionBank</Text> /{" "}
        <Text code>TcmEdu.Quiz.Question</Text>）。先建题库，再往里加题。
      </Paragraph>

      <Card
        title="题库列表"
        extra={
          <Button type="primary" icon={<PlusOutlined />} onClick={() => setCreateBankOpen(true)}>
            新建题库
          </Button>
        }
      >
        <Spin spinning={loading}>
          {banks.length === 0 && !loading ? (
            <Empty description="暂无题库" />
          ) : (
            <List
              dataSource={banks}
              renderItem={(b) => (
                <List.Item
                  className={selectedBankId === b.id ? "bg-blue-50/40" : "cursor-pointer"}
                  onClick={() => setSelectedBankId(b.id)}
                  actions={[
                    <Tag key="subj" color="blue">
                      {SUBJECTS.find((s) => s.value === b.subject)?.label ?? b.subject}
                    </Tag>,
                    b.isPublic ? <Tag key="pub" color="green">公开</Tag> : null
                  ].filter(Boolean)}
                >
                  <List.Item.Meta title={b.name} />
                </List.Item>
              )}
            />
          )}
        </Spin>
      </Card>

      {selectedBankId ? (
        <Card
          title={`题目（bank: ${selectedBankId}）`}
          extra={
            <Button icon={<PlusOutlined />} onClick={() => setCreateQOpen(true)}>
              添加题目
            </Button>
          }
        >
          <Spin spinning={questionsLoading}>
            {questions.length === 0 && !questionsLoading ? (
              <Empty description="该题库暂无题目" />
            ) : (
              <List
                dataSource={questions}
                renderItem={(q, idx) => {
                  const item = q as { id: string; type?: string; difficulty?: number; stem?: string; options?: { label: string; text: string }[] };
                  return (
                    <List.Item>
                      <List.Item.Meta
                        title={
                          <Space>
                            <Tag color="purple">{item.type}</Tag>
                            <Tag color="cyan">难度 {item.difficulty ?? "?"}</Tag>
                            <Text>第 {idx + 1} 题</Text>
                          </Space>
                        }
                        description={
                          <Space direction="vertical">
                            <Text>{item.stem}</Text>
                            <Text type="secondary" style={{ fontSize: 12 }}>
                              选项：{(item.options ?? []).map((o) => `${o.label}. ${o.text}`).join(" / ")}
                            </Text>
                          </Space>
                        }
                      />
                    </List.Item>
                  );
                }}
              />
            )}
          </Spin>
        </Card>
      ) : null}

      <Modal
        title="新建题库"
        open={createBankOpen}
        onCancel={() => setCreateBankOpen(false)}
        onOk={onCreateBank}
        okText="创建"
        cancelText="取消"
      >
        <Form form={bankForm} layout="vertical">
          <Form.Item name="name" label="名称" rules={[{ required: true }]}>
            <Input placeholder="如：中医基础题库" />
          </Form.Item>
          <Form.Item name="subject" label="学科" rules={[{ required: true }]} initialValue="traditional_chinese_medicine">
            <Select options={SUBJECTS} />
          </Form.Item>
          <Form.Item name="isPublic" label="公开" valuePropName="checked" initialValue={false}>
            <Select
              options={[
                { value: true, label: "公开" },
                { value: false, label: "仅本租户" }
              ]}
            />
          </Form.Item>
        </Form>
      </Modal>

      <Modal
        title="添加题目"
        open={createQOpen}
        onCancel={() => setCreateQOpen(false)}
        onOk={onCreateQuestion}
        okText="创建"
        cancelText="取消"
        width={720}
      >
        <Form form={qForm} layout="vertical">
          <Form.Item name="type" label="题型" rules={[{ required: true }]} initialValue="single">
            <Select
              options={[
                { value: "single", label: "单选" },
                { value: "multi", label: "多选" },
                { value: "judge", label: "判断" },
                { value: "essay", label: "简答" }
              ]}
            />
          </Form.Item>
          <Form.Item name="difficulty" label="难度（1-5）" rules={[{ required: true }]} initialValue={3}>
            <Select
              options={[1, 2, 3, 4, 5].map((n) => ({ value: n, label: String(n) }))}
            />
          </Form.Item>
          <Form.Item name="stem" label="题干" rules={[{ required: true }]}>
            <Input.TextArea rows={3} placeholder="支持 markdown" />
          </Form.Item>
          <Form.Item
            name="options"
            label="选项 JSON（[{label, text, correct}]）"
            rules={[{ required: true }]}
            extra='如 [{"label":"A","text":"活血祛瘀","correct":true},{"label":"B","text":"补气"}]'
          >
            <Input.TextArea rows={4} placeholder="[ ... ]" />
          </Form.Item>
          <Form.Item name="answer" label="正确答案">
            <Input placeholder="A 或 A,B 或 对/错" />
          </Form.Item>
          <Form.Item name="explanation" label="解析">
            <Input.TextArea rows={2} />
          </Form.Item>
        </Form>
      </Modal>
    </div>
  );
}