"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { Avatar, Dropdown, Spin, Tag, type MenuProps } from "antd";
import { LogoutOutlined, UserOutlined } from "@ant-design/icons";
import { ProLayout } from "@ant-design/pro-components";
import { useAuth, useRequireAuth } from "@/lib/auth";

const MENU = [
  { path: "/", name: "工作台" },
  { path: "/courses", name: "我的课程" },
  { path: "/students", name: "我的学生" },
];

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const { session, logout } = useAuth();
  const { loading } = useRequireAuth();

  const avatarMenu: MenuProps["items"] = [
    {
      key: "logout",
      icon: <LogoutOutlined />,
      label: "退出登录",
      onClick: () => {
        logout();
        router.replace("/login");
      },
    },
  ];

  if (loading || !session) {
    return (
      <div style={{ minHeight: "100vh", display: "flex", alignItems: "center", justifyContent: "center" }}>
        <Spin size="large" />
      </div>
    );
  }

  return (
    <ProLayout
      title="中医教学 · 教师端"
      logo={false}
      layout="mix"
      location={{ pathname }}
      route={{
        routes: MENU.map((m) => ({ path: m.path, name: m.name })),
      }}
      menuItemRender={(item, dom) => <Link href={item.path ?? "/"}>{dom}</Link>}
      avatarProps={{
        src: undefined,
        icon: <UserOutlined />,
        title: session.email,
        render: (_props, dom) => (
          <Dropdown menu={{ items: avatarMenu }} placement="bottomRight">
            <span style={{ cursor: "pointer", display: "inline-flex", alignItems: "center", gap: 8 }}>
              <Avatar icon={<UserOutlined />} />
              <span>{session.role === "tenant_admin" ? "机构管理员" : "教师"}</span>
              <Tag color="blue">{session.tenant}</Tag>
              {dom}
            </span>
          </Dropdown>
        ),
      }}
    >
      {children}
    </ProLayout>
  );
}
