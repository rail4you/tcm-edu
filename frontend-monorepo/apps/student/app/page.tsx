"use client";

import { useCallback, useEffect, useState } from "react";
import { useAuth } from "./auth-context";
import Link from "next/link";
import {
  createTodo,
  deleteTodo,
  listTodos,
  updateTodo,
  type AshRpcError,
  type TodoAttributesOnlySchema,
} from "@tcm-edu/rpc-client";

type Todo = {
  id: string;
  title: string;
  completed: boolean;
  insertedAt: string;
  updatedAt: string;
};

function shapeTodo(row: TodoAttributesOnlySchema): Todo {
  return {
    id: row.id,
    title: row.title,
    completed: row.completed,
    insertedAt: row.insertedAt,
    updatedAt: row.updatedAt,
  };
}

const FIELDS: ["id", "title", "completed", "insertedAt", "updatedAt"] = [
  "id",
  "title",
  "completed",
  "insertedAt",
  "updatedAt",
];

export default function Page() {
  const { isAuthenticated, logout, login, register, loading: authLoading, error: authError, isAdmin } = useAuth();

  // ── Auth gate: show login/register form if not authenticated ──────
  if (!isAuthenticated) {
    return <InlineAuth login={login} register={register} loading={authLoading} error={authError} />;
  }

  return <TodoApp logout={logout} isAdmin={isAdmin} />;
}

/** Inline login/register form shown when the user is not authenticated. */
function InlineAuth({
  login,
  register,
  loading,
  error,
}: {
  login: (email: string, password: string) => Promise<{ success: boolean; error?: string }>;
  register: (email: string, password: string) => Promise<{ success: boolean; error?: string }>;
  loading: boolean;
  error: string | null;
}) {
  const [mode, setMode] = useState<"login" | "register">("login");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const fn = mode === "login" ? login : register;
    await fn(email, password);
  }

  return (
    <main className="mx-auto flex min-h-screen w-full max-w-md flex-col items-center justify-center gap-6 px-6">
      <header className="flex flex-col items-center gap-1 text-center">
        <p className="text-xs font-semibold uppercase tracking-widest text-indigo-500">
          TCM Education
        </p>
        <h1 className="text-2xl font-semibold">
          {mode === "login" ? "Sign In" : "Create Account"}
        </h1>
        <p className="text-sm text-zinc-500">
          Please sign in to access your todos.
        </p>
      </header>

      <form
        onSubmit={handleSubmit}
        className="flex w-full flex-col gap-4 rounded-lg border border-zinc-200 bg-white p-6 dark:border-zinc-800 dark:bg-zinc-900"
      >
        <label className="flex flex-col gap-1">
          <span className="text-sm font-medium text-zinc-700 dark:text-zinc-300">
            Email
          </span>
          <input
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
            placeholder="you@example.com"
            className="rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-2 focus:ring-indigo-200 dark:border-zinc-700 dark:bg-zinc-800"
          />
        </label>

        <label className="flex flex-col gap-1">
          <span className="text-sm font-medium text-zinc-700 dark:text-zinc-300">
            Password
          </span>
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
            minLength={6}
            placeholder="••••••••"
            className="rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-2 focus:ring-indigo-200 dark:border-zinc-700 dark:bg-zinc-800"
          />
        </label>

        {error && (
          <div
            role="alert"
            className="rounded-lg border border-red-300 bg-red-50 px-3 py-2 text-sm text-red-700 dark:border-red-800 dark:bg-red-950 dark:text-red-200"
          >
            {error}
          </div>
        )}

        <button
          type="submit"
          disabled={loading || !email || password.length < 6}
          className="rounded-lg bg-indigo-600 px-4 py-2 text-sm font-medium text-white transition hover:bg-indigo-500 disabled:opacity-50"
        >
          {loading
            ? "Please wait…"
            : mode === "login"
              ? "Sign In"
              : "Create Account"}
        </button>

        <button
          type="button"
          onClick={() => setMode(mode === "login" ? "register" : "login")}
          className="text-sm text-zinc-500 underline underline-offset-2 hover:text-indigo-500"
        >
          {mode === "login"
            ? "Don't have an account? Register"
            : "Already have an account? Sign in"}
        </button>
      </form>
    </main>
  );
}

/** The main Todo application, only rendered when authenticated. */
function TodoApp({ logout, isAdmin }: { logout: () => Promise<void>; isAdmin: boolean }) {
  const [todos, setTodos] = useState<Todo[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [draft, setDraft] = useState("");

  const refresh = useCallback(async () => {
    setLoading(true);
    setError(null);
    const result = await listTodos({ fields: FIELDS });
    if (!result.success) {
      setError(formatErrors(result.errors));
      setTodos([]);
    } else {
      setTodos((result.data as TodoAttributesOnlySchema[]).map(shapeTodo));
    }
    setLoading(false);
  }, []);

  useEffect(() => {
    refresh();
  }, [refresh]);

  async function handleAdd(e: React.FormEvent) {
    e.preventDefault();
    const title = draft.trim();
    if (!title) return;
    setError(null);
    const result = await createTodo({
      input: { title },
      fields: FIELDS,
    });
    if (!result.success) {
      setError(formatErrors(result.errors));
    } else {
      setDraft("");
      await refresh();
    }
  }

  async function handleToggle(todo: Todo) {
    setError(null);
    const result = await updateTodo({
      identity: todo.id,
      input: { completed: !todo.completed },
      fields: FIELDS,
    });
    if (!result.success) {
      setError(formatErrors(result.errors));
    } else {
      setTodos((current) =>
        current.map((t) =>
          t.id === todo.id ? { ...t, completed: !t.completed } : t
        )
      );
    }
  }

  async function handleDelete(todo: Todo) {
    setError(null);
    const result = await deleteTodo({ identity: todo.id });
    if (!result.success) {
      setError(formatErrors(result.errors));
    } else {
      setTodos((current) => current.filter((t) => t.id !== todo.id));
    }
  }

  return (
    <main className="mx-auto flex min-h-screen w-full max-w-2xl flex-col gap-8 px-6 py-12">
      <header className="flex flex-col gap-1">
        <p className="text-xs font-semibold uppercase tracking-widest text-indigo-500">
          TCM Education
        </p>
        <h1 className="text-3xl font-semibold">Todos</h1>
        <p className="text-sm text-zinc-500">
          RPC via{" "}
          <code className="rounded bg-zinc-200 px-1 py-0.5 text-xs dark:bg-zinc-800">
            /api/rpc/run
          </code>
        </p>
      </header>

      {/* Navigation tabs */}
      <nav className="flex items-center gap-1 border-b border-zinc-200 dark:border-zinc-800">
        <span className="rounded-t-lg border-b-2 border-indigo-500 px-4 py-2 text-sm font-medium text-indigo-600 dark:text-indigo-400">
          Todos
        </span>
        <Link
          href="/posts"
          className="rounded-t-lg border-b-2 border-transparent px-4 py-2 text-sm font-medium text-zinc-500 transition hover:border-zinc-300 hover:text-zinc-700 dark:hover:border-zinc-700 dark:hover:text-zinc-300"
        >
          Posts
        </Link>
        {isAdmin && (
          <Link
            href="/admin/users"
            className="rounded-t-lg border-b-2 border-transparent px-4 py-2 text-sm font-medium text-zinc-500 transition hover:border-zinc-300 hover:text-zinc-700 dark:hover:border-zinc-700 dark:hover:text-zinc-300"
          >
            Users
          </Link>
        )}
        <div className="ml-auto" />
        <button
          onClick={logout}
          className="rounded-lg border border-zinc-300 px-3 py-1.5 text-sm text-zinc-600 transition hover:bg-zinc-100 dark:border-zinc-700 dark:text-zinc-400 dark:hover:bg-zinc-800"
        >
          Sign Out
        </button>
      </nav>

      <form onSubmit={handleAdd} className="flex gap-2">
        <input
          type="text"
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          placeholder="What needs doing?"
          className="flex-1 rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-2 focus:ring-indigo-200 dark:border-zinc-700 dark:bg-zinc-900"
        />
        <button
          type="submit"
          className="rounded-lg bg-indigo-600 px-4 py-2 text-sm font-medium text-white transition hover:bg-indigo-500 disabled:opacity-50"
          disabled={!draft.trim()}
        >
          Add
        </button>
      </form>

      {error && (
        <div
          role="alert"
          className="rounded-lg border border-red-300 bg-red-50 px-3 py-2 text-sm text-red-700 dark:border-red-800 dark:bg-red-950 dark:text-red-200"
        >
          {error}
        </div>
      )}

      <section className="flex flex-col gap-1">
        {loading && todos.length === 0 ? (
          <p className="text-sm text-zinc-500">Loading…</p>
        ) : todos.length === 0 ? (
          <p className="text-sm text-zinc-500">No todos yet — add one above.</p>
        ) : (
          <ul className="divide-y divide-zinc-200 overflow-hidden rounded-lg border border-zinc-200 bg-white dark:divide-zinc-800 dark:border-zinc-800 dark:bg-zinc-900">
            {todos.map((todo) => (
              <li key={todo.id} className="flex items-center gap-3 px-4 py-3">
                <input
                  type="checkbox"
                  checked={todo.completed}
                  onChange={() => handleToggle(todo)}
                  className="h-4 w-4 rounded border-zinc-300 text-indigo-600 focus:ring-indigo-500"
                  aria-label={`Mark "${todo.title}" as ${todo.completed ? "incomplete" : "complete"}`}
                />
                <span
                  className={
                    "flex-1 text-sm " +
                    (todo.completed
                      ? "text-zinc-400 line-through"
                      : "text-zinc-900 dark:text-zinc-100")
                  }
                >
                  {todo.title}
                </span>
                <span className="font-mono text-xs text-zinc-400">
                  {todo.id.slice(0, 8)}
                </span>
                <button
                  onClick={() => handleDelete(todo)}
                  className="rounded px-2 py-1 text-xs text-zinc-500 transition hover:bg-red-50 hover:text-red-600 dark:hover:bg-red-950"
                  aria-label={`Delete "${todo.title}"`}
                >
                  Delete
                </button>
              </li>
            ))}
          </ul>
        )}
      </section>

      <footer className="text-xs text-zinc-400">
        <p>
          POST requests go through Next.js&apos; <code>rewrites</code> during dev
          and resolve directly to Phoenix in production.
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
