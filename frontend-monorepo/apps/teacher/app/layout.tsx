import type { Metadata } from "next";
import { AntdRegistry } from "@ant-design/nextjs-registry";
import { ConfigProvider } from "antd";
import zhCN from "antd/locale/zh_CN";
import "@ant-design/v5-patch-for-react-19";
import "./globals.css";
import { AuthProvider } from "@/lib/auth";

export const metadata: Metadata = {
  title: "中医教学 · 教师端",
  description: "TCM-Edu 课程创建与发布",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="zh-CN">
      <body>
        <AntdRegistry>
          <ConfigProvider
            locale={zhCN}
            theme={{
              token: {
                // 品牌色与管理端/学生端对齐：朱红；教师端点缀竹青
                colorPrimary: "#b83a2e",
                borderRadius: 6,
              },
            }}
          >
            <AuthProvider>{children}</AuthProvider>
          </ConfigProvider>
        </AntdRegistry>
      </body>
    </html>
  );
}
