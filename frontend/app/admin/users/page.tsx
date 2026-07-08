"use client";

import { useCallback, useEffect, useState } from "react";
import { useAuth } from "../../auth-context";
import {
  type AshRpcError,
  listUsers,
  registerWithRole,
  updateRole,
  managePermissions,
} from "@/lib/generated/ash_rpc";
import Link from "next/link";

type User = {
  id: string;
  email: string;
  role: "admin" | "user";
  /** Locally-tracked effective permissions (fetched per-user when needed) */
  permissions: string[];
};

const FIELDS: ["id", "email", "role"] = ["id", "email", "role"];

export default function AdminUsersPage() {
  const { isAuthenticated, isAdmin, logout, user } = useAuth();

  if (!isAuthenticated) {
    return (
      <main className="mx-auto flex min-h-screen max-w-md flex-col items-center justify-center gap-4 px-6">
        <h1 className="text-2xl font-semibold">Admin</h1>
        <p className="text-sm text-zinc-500">
          Please{" "}
          <Link href="/" className="text-indigo-500 underline underline-offset-2">
            sign in
          </Link>{" "}
          as an admin.
        </p>
      </main>
    );
  }

  if (!isAdmin) {
    return (
      <main className="mx-auto flex min-h-screen max-w-md flex-col items-center justify-center gap-4 px-6">
        <h1 className="text-2xl font-semibold">Access Denied</h1>
        <p className="text-sm text-zinc-500">
          You need admin privileges to access this page.
        </p>
        <Link
          href="/"
          className="text-indigo-500 underline underline-offset-2 text-sm"
        >
          Back to Home
        </Link>
      </main>
    );
  }

  return <UsersManager logout={logout} currentUser={user!} />;
}

function UsersManager({
  logout,
  currentUser,
}: {
  logout: () => Promise<void>;
  currentUser: User;
}) {
  const [users, setUsers] = useState<User[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  // New user form
  const [showNewUser, setShowNewUser] = useState(false);
  const [newEmail, setNewEmail] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [newRole, setNewRole] = useState<"admin" | "user">("user");
  const [creating, setCreating] = useState(false);

  // Role change
  const [changingRole, setChangingRole] = useState<string | null>(null);
  // Permission change
  const [changingPerms, setChangingPerms] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setLoading(true);
    setError(null);
    const result = await listUsers({ fields: FIELDS });
    if (!result.success) {
      setError(formatErrors(result.errors));
      setUsers([]);
    } else {
      const users = (result.data as any[]).map((u: any) => ({ ...u, permissions: [] }));
      // Fetch permissions for each user from the dedicated endpoint
      const withPerms = await Promise.all(
        users.map(async (u: User) => {
          try {
            const res = await fetch(`/api/auth/users/${u.id}/permissions`, {
              headers: { Authorization: `Bearer ${localStorage.getItem("auth_token")}` },
            });
            if (res.ok) {
              const data = await res.json();
              return { ...u, permissions: data.data.permissions };
            }
          } catch {}
          return u;
        })
      );
      setUsers(withPerms);
    }
    setLoading(false);
  }, []);

  useEffect(() => {
    refresh();
  }, [refresh]);

  async function handleCreateUser(e: React.FormEvent) {
    e.preventDefault();
    if (!newEmail.trim() || newPassword.length < 6) return;

    setCreating(true);
    setError(null);
    setSuccess(null);

    const result = await registerWithRole({
      input: {
        email: newEmail.trim(),
        password: newPassword,
        role: newRole,
      },
      fields: FIELDS,
    });

    if (!result.success) {
      setError(formatErrors(result.errors));
    } else {
      setSuccess(`User "${newEmail}" created successfully!`);
      setNewEmail("");
      setNewPassword("");
      setNewRole("user");
      setShowNewUser(false);
      await refresh();
    }
    setCreating(false);
  }

  async function handleChangeRole(userId: string, newRole: "admin" | "user") {
    setChangingRole(userId);
    setError(null);
    setSuccess(null);

    const result = await updateRole({
      identity: userId,
      input: { role: newRole },
      fields: FIELDS,
    });

    if (!result.success) {
      setError(formatErrors(result.errors));
    } else {
      setSuccess(`User role updated to "${newRole}".`);
      setUsers((current) =>
        current.map((u) => (u.id === userId ? { ...u, role: newRole } : u))
      );
    }
    setChangingRole(null);
  }

  async function handleTogglePermission(user: User, permission: string) {
    setChangingPerms(user.id);
    setError(null);
    setSuccess(null);

    const currentPerms = user.permissions || [];
    const newPerms = currentPerms.includes(permission)
      ? currentPerms.filter((p) => p !== permission)
      : [...currentPerms, permission];

    const result = await managePermissions({
      identity: user.id,
      input: { permissions: newPerms },
      fields: FIELDS,
    });

    if (!result.success) {
      setError(formatErrors(result.errors));
    } else {
      setSuccess(`Permissions updated for ${user.email}.`);
      setUsers((current) =>
        current.map((u) =>
          u.id === user.id ? { ...u, permissions: newPerms } : u
        )
      );
    }
    setChangingPerms(null);
  }

  return (
    <main className="mx-auto flex min-h-screen w-full max-w-4xl flex-col gap-8 px-6 py-12">
      {/* Header */}
      <header className="flex items-center justify-between">
        <div className="flex flex-col gap-1">
          <p className="text-xs font-semibold uppercase tracking-widest text-indigo-500">
            ash-ts-demo
          </p>
          <h1 className="text-3xl font-semibold">User Management</h1>
          <p className="text-sm text-zinc-500">
            Admins can create users, assign roles, and manage granular permissions
          </p>
        </div>
        <div className="flex items-center gap-3">
          <Link
            href="/"
            className="rounded-lg border border-zinc-300 px-3 py-1.5 text-sm text-zinc-600 transition hover:bg-zinc-100 dark:border-zinc-700 dark:text-zinc-400 dark:hover:bg-zinc-800"
          >
            Home
          </Link>
          <Link
            href="/posts"
            className="rounded-lg border border-zinc-300 px-3 py-1.5 text-sm text-zinc-600 transition hover:bg-zinc-100 dark:border-zinc-700 dark:text-zinc-400 dark:hover:bg-zinc-800"
          >
            Posts
          </Link>
          <button
            onClick={logout}
            className="rounded-lg border border-zinc-300 px-3 py-1.5 text-sm text-zinc-600 transition hover:bg-zinc-100 dark:border-zinc-700 dark:text-zinc-400 dark:hover:bg-zinc-800"
          >
            Sign Out
          </button>
        </div>
      </header>

      {/* Notifications */}
      {error && (
        <div
          role="alert"
          className="rounded-lg border border-red-300 bg-red-50 px-3 py-2 text-sm text-red-700 dark:border-red-800 dark:bg-red-950 dark:text-red-200"
        >
          {error}
        </div>
      )}
      {success && (
        <div
          role="alert"
          className="rounded-lg border border-green-300 bg-green-50 px-3 py-2 text-sm text-green-700 dark:border-green-800 dark:bg-green-950 dark:text-green-200"
        >
          {success}
        </div>
      )}

      {/* Create new user */}
      <section>
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-semibold text-zinc-800 dark:text-zinc-200">
            Users ({users.length})
          </h2>
          <button
            onClick={() => setShowNewUser(!showNewUser)}
            className="rounded-lg bg-indigo-600 px-4 py-1.5 text-sm font-medium text-white transition hover:bg-indigo-500"
          >
            {showNewUser ? "Cancel" : "+ New User"}
          </button>
        </div>

        {showNewUser && (
          <form
            onSubmit={handleCreateUser}
            className="mb-6 flex flex-col gap-4 rounded-lg border border-zinc-200 bg-white p-4 dark:border-zinc-800 dark:bg-zinc-900"
          >
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
              <label className="flex flex-col gap-1">
                <span className="text-sm font-medium text-zinc-700 dark:text-zinc-300">
                  Email
                </span>
                <input
                  type="email"
                  value={newEmail}
                  onChange={(e) => setNewEmail(e.target.value)}
                  required
                  placeholder="user@example.com"
                  className="rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-2 focus:ring-indigo-200 dark:border-zinc-700 dark:bg-zinc-800"
                />
              </label>
              <label className="flex flex-col gap-1">
                <span className="text-sm font-medium text-zinc-700 dark:text-zinc-300">
                  Password
                </span>
                <input
                  type="password"
                  value={newPassword}
                  onChange={(e) => setNewPassword(e.target.value)}
                  required
                  minLength={6}
                  placeholder="Min 6 characters"
                  className="rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-2 focus:ring-indigo-200 dark:border-zinc-700 dark:bg-zinc-800"
                />
              </label>
              <label className="flex flex-col gap-1">
                <span className="text-sm font-medium text-zinc-700 dark:text-zinc-300">
                  Role
                </span>
                <select
                  value={newRole}
                  onChange={(e) =>
                    setNewRole(e.target.value as "admin" | "user")
                  }
                  className="rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-2 focus:ring-indigo-200 dark:border-zinc-700 dark:bg-zinc-800"
                >
                  <option value="user">User</option>
                  <option value="admin">Admin</option>
                </select>
              </label>
            </div>
            <div className="flex justify-end">
              <button
                type="submit"
                disabled={creating || !newEmail.trim() || newPassword.length < 6}
                className="rounded-lg bg-indigo-600 px-6 py-2 text-sm font-medium text-white transition hover:bg-indigo-500 disabled:opacity-50"
              >
                {creating ? "Creating…" : "Create User"}
              </button>
            </div>
          </form>
        )}
      </section>

      {/* User list */}
      <section>
        {loading ? (
          <p className="text-sm text-zinc-500">Loading…</p>
        ) : users.length === 0 ? (
          <p className="text-sm text-zinc-500">No users found.</p>
        ) : (
          <div className="overflow-x-auto rounded-lg border border-zinc-200 dark:border-zinc-800">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-zinc-50 text-left text-xs font-semibold uppercase tracking-wider text-zinc-500 dark:bg-zinc-800/50 dark:text-zinc-400">
                  <th className="px-4 py-3">Email</th>
                  <th className="px-4 py-3">Role</th>
                  <th className="px-4 py-3">Permissions</th>
                  <th className="px-4 py-3">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-zinc-200 bg-white dark:divide-zinc-800 dark:bg-zinc-900">
                {users.map((u) => (
                  <tr key={u.id} className="group">
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-2">
                        <span className="font-medium text-zinc-900 dark:text-zinc-100">
                          {u.email}
                        </span>
                        {u.id === currentUser.id && (
                          <span className="rounded-full bg-indigo-100 px-2 py-0.5 text-xs font-medium text-indigo-700 dark:bg-indigo-900 dark:text-indigo-300">
                            You
                          </span>
                        )}
                      </div>
                    </td>
                    <td className="px-4 py-3">
                      <span
                        className={
                          "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium " +
                          (u.role === "admin"
                            ? "bg-purple-100 text-purple-700 dark:bg-purple-900 dark:text-purple-300"
                            : "bg-zinc-100 text-zinc-600 dark:bg-zinc-800 dark:text-zinc-400")
                        }
                      >
                        {u.role}
                      </span>
                    </td>
                    <td className="px-4 py-3">
                      {u.id !== currentUser.id ? (
                        <div className="flex items-center gap-3">
                          <label className="flex items-center gap-1 text-xs">
                            <input
                              type="checkbox"
                              checked={u.permissions.includes("post:create")}
                              onChange={() =>
                                handleTogglePermission(
                                  u,
                                  "post:create"
                                )
                              }
                              disabled={changingPerms === u.id}
                              className="h-3.5 w-3.5 rounded border-zinc-300 text-indigo-600 focus:ring-indigo-500"
                            />
                            Create
                          </label>
                          <label className="flex items-center gap-1 text-xs">
                            <input
                              type="checkbox"
                              checked={u.permissions.includes("post:update")}
                              onChange={() =>
                                handleTogglePermission(
                                  u,
                                  "post:update"
                                )
                              }
                              disabled={changingPerms === u.id}
                              className="h-3.5 w-3.5 rounded border-zinc-300 text-indigo-600 focus:ring-indigo-500"
                            />
                            Edit
                          </label>
                          <label className="flex items-center gap-1 text-xs">
                            <input
                              type="checkbox"
                              checked={u.permissions.includes("post:delete")}
                              onChange={() =>
                                handleTogglePermission(
                                  u,
                                  "post:delete"
                                )
                              }
                              disabled={changingPerms === u.id}
                              className="h-3.5 w-3.5 rounded border-zinc-300 text-indigo-600 focus:ring-indigo-500"
                            />
                            Delete
                          </label>
                          {changingPerms === u.id && (
                            <span className="text-xs text-zinc-400">
                              Saving…
                            </span>
                          )}
                        </div>
                      ) : (
                        <span className="text-xs text-zinc-400">
                          Manage own permissions not allowed
                        </span>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      {u.id !== currentUser.id && (
                        <div className="flex items-center gap-2">
                          <select
                            value={u.role}
                            onChange={(e) =>
                              handleChangeRole(
                                u.id,
                                e.target.value as "admin" | "user"
                              )
                            }
                            disabled={changingRole === u.id}
                            className="rounded-lg border border-zinc-300 bg-white px-2 py-1 text-xs outline-none focus:border-indigo-500 focus:ring-2 focus:ring-indigo-200 disabled:opacity-50 dark:border-zinc-700 dark:bg-zinc-800"
                          >
                            <option value="user">User</option>
                            <option value="admin">Admin</option>
                          </select>
                          {changingRole === u.id && (
                            <span className="text-xs text-zinc-400">
                              Updating…
                            </span>
                          )}
                        </div>
                      )}
                      {u.id === currentUser.id && (
                        <span className="text-xs text-zinc-400">
                          Cannot change your own role
                        </span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <footer className="text-xs text-zinc-400">
        <p>
          <strong>Role vs Permissions:</strong> Admin role grants full access
          to all posts. Regular users get no extra permissions by default —
          toggle individual permissions (Create / Edit / Delete) to grant
          fine-grained access.
        </p>
      </footer>
    </main>
  );
}

function formatErrors(errors: AshRpcError[]): string {
  return errors
    .map((e) => `${e.type}: ${e.shortMessage || e.message}`)
    .join("; ");
}
