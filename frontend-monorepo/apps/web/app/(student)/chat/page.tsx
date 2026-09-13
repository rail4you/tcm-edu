"use client";

import { useRef, useState, useEffect } from "react";
import { useAuth } from "@/lib/auth/compat";
import { StreamingMarkdown } from "./streaming-markdown";

// ─── Types ──────────────────────────────────────────────────
interface ChatMessage {
  id: string;
  role: "user" | "assistant";
  content: string;
  toolCalls?: ToolCall[];
}

interface ToolCall {
  id: string;
  name: string;
  args: Record<string, unknown>;
  result?: string;
  status: "pending" | "done";
}

interface Agent {
  name: string;
  label: string;
  description: string;
}

type TaskStatus = "pending" | "running" | "completed" | "failed";

interface TaskInfo {
  task_id: string;
  task_name: string;
  status: TaskStatus;
  session_id: string;
  duration_ms?: number;
  started_at?: string;
  completed_at?: string;
  job_id?: number;
}

const AGENTS: Agent[] = [
  { name: "chat_agent", label: "Chat Agent", description: "AI assistant with multiply tool" },
  { name: "counter_agent", label: "Counter Agent", description: "Counter manager" },
  { name: "quiz_agent", label: "Quiz Agent", description: "Generates quiz from text" },
  { name: "bg_task_agent", label: "BG Task Agent", description: "Background tasks only (minimal context)" },
  { name: "ping_agent", label: "Ping Agent (a)", description: "Calls other agents via call_agent tool" },
  { name: "pong_agent", label: "Pong Agent (b)", description: "Always replies 'pong'" },
];

function getSessionId(agentName: string): string {
  if (typeof window === "undefined") return "";
  const key = `chat_session_${agentName}`;
  let id = localStorage.getItem(key);
  if (!id) {
    id = crypto.randomUUID();
    localStorage.setItem(key, id);
  }
  return id;
}

// Pull a single `name: value` line out of an SSE event block.
function parseSseField(block: string, field: string): string {
  for (const line of block.split("\n")) {
    if (line.startsWith(field)) return line.slice(field.length).trim();
  }
  return "";
}

// ─── Main Page ──────────────────────────────────────────────
export default function ChatPage() {
  const { isAuthenticated, logout, token } = useAuth();
  const [activeAgent, setActiveAgent] = useState<Agent>(AGENTS[0]);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [input, setInput] = useState("");
  const [streaming, setStreaming] = useState(false);
  const [loadingHistory, setLoadingHistory] = useState(false);
  const [activeTasks, setActiveTasks] = useState<Record<string, TaskInfo>>({});
  const [completionBanner, setCompletionBanner] = useState<TaskInfo | null>(null);
  const [bannerVisible, setBannerVisible] = useState(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const abortRef = useRef<AbortController | null>(null);
  const scrollContainerRef = useRef<HTMLDivElement>(null);
  const scrollPositions = useRef<Record<string, number>>({});
  const bannerTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const sessionId = getSessionId(activeAgent.name);
  const baseUrl = typeof window !== "undefined" &&
    window.location.hostname === "localhost"
    ? "http://localhost:4011"
    : "";

  // Load history on initial mount for the default agent
  useEffect(() => {
    loadHistory(getSessionId(activeAgent.name));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Auto-scroll to bottom when new content arrives
  useEffect(() => {
    if (streaming) {
      messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
    }
  }, [messages, streaming]);

  // ── Subscribe to long-task lifecycle events (SSE) ──────────
  useEffect(() => {
    if (!token) return;

    const controller = new AbortController();
    let cancelled = false;

    (async () => {
      try {
        const res = await fetch(`${baseUrl}/api/chat/events`, {
          headers: token ? { Authorization: `Bearer ${token}` } : {},
          signal: controller.signal,
        });
        if (!res.ok || !res.body) return;

        const reader = res.body.getReader();
        const decoder = new TextDecoder();
        let buffer = "";

        while (!cancelled) {
          const { done, value } = await reader.read();
          if (done) break;
          buffer += decoder.decode(value, { stream: true });

          // SSE events separated by blank lines
          const parts = buffer.split("\n\n");
          buffer = parts.pop() || "";

          for (const part of parts) {
            if (!part.trim()) continue;
            const eventType = parseSseField(part, "event:");
            const data = parseSseField(part, "data:");
            if (!eventType || !data) continue;
            try {
              handleTaskEvent(eventType, JSON.parse(data));
            } catch {
              /* ignore malformed */
            }
          }
        }
      } catch (err) {
        if (err instanceof DOMException && err.name === "AbortError") return;
        // network blip — let useEffect re-run
      }
    })();

    return () => {
      cancelled = true;
      controller.abort();
    };

    function handleTaskEvent(type: string, data: TaskInfo | { tasks: TaskInfo[] }) {
      if (type === "task-list") {
        const tasks = (data as { tasks: TaskInfo[] }).tasks ?? [];
        setActiveTasks(
          Object.fromEntries(tasks.map((t) => [t.task_id, t]))
        );
        return;
      }

      const task = data as TaskInfo;
      if (!task?.task_id) return;

      const isTerminal = task.status === "completed" || task.status === "failed";

      setActiveTasks((prev) => {
        const next = { ...prev };
        if (isTerminal) {
          delete next[task.task_id];
        } else {
          next[task.task_id] = { ...(prev[task.task_id] || {}), ...task };
        }
        return next;
      });

      // Backend emits `task_completed` (underscore — derived from the
      // `:task_completed` atom via `Atom.to_string/1`). Earlier versions of
      // the frontend checked `"task-completed"` (hyphen) which never matched,
      // so the banner logic below was dead code.
      if (type === "task_completed") {
        setCompletionBanner({ ...task, status: "completed" });
        setBannerVisible(true);
        if (bannerTimer.current) clearTimeout(bannerTimer.current);
        bannerTimer.current = setTimeout(() => setBannerVisible(false), 6_000);

        // Mirror the message the worker persists into `chat_messages` so the
        // user sees the completion in the active chat without refreshing.
        // On a later refresh `loadHistory` will replace this synthetic entry
        // with the persisted row from DB; we dedupe by a stable id derived
        // from `task_id` so a re-broadcast won't double-insert.
        const seconds = Math.round((task.duration_ms || 0) / 1000);
        const completionMsg: ChatMessage = {
          id: `task-complete-${task.task_id}`,
          role: "assistant",
          content:
            `后台任务完成通知：任务 \`${task.task_name}\`（ID \`${task.task_id}\`）已成功执行，` +
            `耗时 ${seconds} 秒。你可以继续聊天，我会在这里等你。`,
        };
        setMessages((prev) =>
          prev.some((m) => m.id === completionMsg.id)
            ? prev
            : [...prev, completionMsg]
        );
      }
    }
  }, [token, baseUrl]);

  // Cleanup banner timer on unmount
  useEffect(() => {
    return () => {
      if (bannerTimer.current) clearTimeout(bannerTimer.current);
    };
  }, []);

  async function handleSend(e: React.FormEvent) {
    e.preventDefault();
    const text = input.trim();
    if (!text || streaming) return;

    const userMsg: ChatMessage = { id: crypto.randomUUID(), role: "user", content: text };
    const assistantId = crypto.randomUUID();
    const assistantMsg: ChatMessage = { id: assistantId, role: "assistant", content: "", toolCalls: [] };
    const updatedMessages = [...messages, userMsg, assistantMsg];

    setMessages(updatedMessages);
    setInput("");
    setStreaming(true);

    const controller = new AbortController();
    abortRef.current = controller;

    try {
      // In dev, call Phoenix directly to avoid Next.js proxy buffering SSE.
      const res = await fetch(`${baseUrl}/api/chat`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        body: JSON.stringify({
          agent_name: activeAgent.name,
          session_id: sessionId,
          messages: updatedMessages
            .filter((m) => m.role !== "assistant" || m.content !== "" || (m.toolCalls && m.toolCalls.length > 0))
            .map((m) => ({ role: m.role, content: m.content })),
        }),
        signal: controller.signal,
      });

      if (!res.ok) throw new Error("Chat request failed");

      const reader = res.body?.getReader();
      const decoder = new TextDecoder();
      let buffer = "";

      while (reader) {
        const { done, value } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });

        const lines = buffer.split("\n");
        buffer = lines.pop() || "";

        for (const line of lines) {
          if (!line) continue;
          const colonIdx = line.indexOf(":");
          if (colonIdx === -1) continue;

          const type = line.slice(0, colonIdx);
          const data = line.slice(colonIdx + 1);

          if (type === "0") {
            // Text delta
            try {
              const parsed = JSON.parse(data);
              const delta = parsed.textDelta || "";
              setMessages((prev) =>
                prev.map((m) =>
                  m.id === assistantId
                    ? { ...m, content: m.content + delta }
                    : m
                )
              );
            } catch { /* skip bad json */ }
          } else if (type === "8") {
            // Tool call
            try {
              const parsed = JSON.parse(data);
              setMessages((prev) =>
                prev.map((m) => {
                  if (m.id !== assistantId) return m;
                  const tcs = m.toolCalls || [];
                  if (parsed.type === "tool-call") {
                    return {
                      ...m,
                      toolCalls: [
                        ...tcs,
                        { id: parsed.toolCallId, name: parsed.toolName, args: parsed.args, status: "pending" as const },
                      ],
                    };
                  } else if (parsed.type === "tool-result") {
                    return {
                      ...m,
                      toolCalls: tcs.map((tc) =>
                        tc.id === parsed.toolCallId ? { ...tc, result: parsed.result, status: "done" as const } : tc
                      ),
                    };
                  }
                  return m;
                })
              );
            } catch { /* skip */ }
          }
        }
      }
    } catch (err: unknown) {
      if (err instanceof Error && err.name === "AbortError") return;
      setMessages((prev) =>
        prev.map((m) =>
          m.id === assistantId
            ? { ...m, content: `Error: ${err instanceof Error ? err.message : "Unknown"}` }
            : m
        )
      );
    } finally {
      setStreaming(false);
      abortRef.current = null;
    }
  }

  function handleStop() {
    abortRef.current?.abort();
    setStreaming(false);
  }

  function switchAgent(agent: Agent) {
    // Save current scroll position
    const container = scrollContainerRef.current;
    if (container && sessionId) {
      scrollPositions.current[sessionId] = container.scrollTop;
    }
    setActiveAgent(agent);
    loadHistory(getSessionId(agent.name));
  }

  async function loadHistory(sid: string) {
    if (!sid) return;
    setLoadingHistory(true);
    try {
      const res = await fetch(`${baseUrl}/api/rpc/run`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        body: JSON.stringify({
          action: "list_messages",
          fields: ["id", "role", "content", "insertedAt"],
          filter: { sessionId: { eq: sid } },
          sort: "insertedAt",
        }),
      });
      const data = await res.json();
      if (data.success && Array.isArray(data.data)) {
        setMessages(
          data.data.map((m: any) => ({
            id: m.id,
            role: m.role,
            content: m.content,
          }))
        );
      } else {
        setMessages([]);
      }
    } catch {
      setMessages([]);
    } finally {
      setLoadingHistory(false);
      // Restore scroll position after messages load
      requestAnimationFrame(() => {
        const container = scrollContainerRef.current;
        const saved = scrollPositions.current[sid];
        if (container && saved !== undefined) {
          container.scrollTop = saved;
        }
      });
    }
  }

  if (!isAuthenticated) {
    return (
      <main className="mx-auto flex min-h-screen max-w-md flex-col items-center justify-center gap-4 px-6">
        <p className="text-zinc-500">Please sign in to access chat.</p>
      </main>
    );
  }

  return (
    <div className="flex h-screen">
      {/* ── Sidebar ─────────────────────────────────── */}
      <aside className="flex w-64 shrink-0 flex-col border-r border-zinc-200 bg-white dark:border-zinc-800 dark:bg-zinc-900">
        <div className="border-b border-zinc-200 px-4 py-3 dark:border-zinc-800">
          <h2 className="text-sm font-semibold text-zinc-800 dark:text-zinc-200">Agents</h2>
        </div>
        <nav className="flex-1 overflow-y-auto p-2">
          {AGENTS.map((agent) => (
            <button
              key={agent.name}
              onClick={() => switchAgent(agent)}
              className={
                "w-full rounded-lg px-3 py-2 text-left text-sm transition " +
                (activeAgent.name === agent.name
                  ? "bg-indigo-50 text-indigo-700 dark:bg-indigo-950 dark:text-indigo-300"
                  : "text-zinc-600 hover:bg-zinc-100 dark:text-zinc-400 dark:hover:bg-zinc-800")
              }
            >
              <div className="font-medium">{agent.label}</div>
              <div className="text-xs text-zinc-400">{agent.description}</div>
            </button>
          ))}
        </nav>
        <div className="space-y-1 border-t border-zinc-200 p-3 dark:border-zinc-800">
          <a
            href="/course/"
            target="_blank"
            className="block rounded-lg px-3 py-1.5 text-left text-xs text-indigo-500 transition hover:bg-zinc-100 dark:text-indigo-400 dark:hover:bg-zinc-800"
          >
            Course Dashboard
          </a>
          <button
            onClick={logout}
            className="w-full rounded-lg px-3 py-1.5 text-left text-xs text-zinc-500 transition hover:bg-zinc-100 dark:hover:bg-zinc-800"
          >
            Sign Out
          </button>
        </div>
      </aside>

      {/* ── Chat Panel ──────────────────────────────── */}
      <main className="flex flex-1 flex-col">
        <header className="flex items-center justify-between border-b border-zinc-200 px-6 py-3 dark:border-zinc-800">
          <div className="flex items-center gap-3">
            <h1 className="text-sm font-semibold text-zinc-800 dark:text-zinc-200">
              {activeAgent.label}
              {loadingHistory && (
                <span className="ml-2 text-xs font-normal text-zinc-400">loading…</span>
              )}
            </h1>
            <TaskStatusIndicator tasks={Object.values(activeTasks)} />
          </div>
          {streaming && (
            <button
              onClick={handleStop}
              className="rounded-lg border border-zinc-300 px-3 py-1 text-xs text-zinc-600 hover:bg-zinc-100 dark:border-zinc-700 dark:text-zinc-400"
            >
              Stop
            </button>
          )}
        </header>

        {/* Completion banner — slides down for a few seconds after a task finishes. */}
        <CompletionBanner
          task={completionBanner}
          visible={bannerVisible}
          onDismiss={() => setBannerVisible(false)}
        />

        {/* Messages */}
        <div ref={scrollContainerRef} className="flex-1 overflow-y-auto px-6 py-4">
          {messages.length === 0 && (
            <div className="flex h-full items-center justify-center">
              <p className="text-sm text-zinc-400">
                Start a conversation with {activeAgent.label}
              </p>
            </div>
          )}

          <div className="mx-auto flex max-w-3xl flex-col gap-6">
            {messages.map((msg) => (
              <MessageBubble key={msg.id} msg={msg} />
            ))}
            <div ref={messagesEndRef} />
          </div>
        </div>

        {/* Input */}
        <form onSubmit={handleSend} className="border-t border-zinc-200 px-6 py-3 dark:border-zinc-800">
          <div className="mx-auto flex max-w-3xl gap-2">
            <input
              type="text"
              value={input}
              onChange={(e) => setInput(e.target.value)}
              placeholder={`Message ${activeAgent.label}…`}
              disabled={streaming}
              className="flex-1 rounded-xl border border-zinc-300 bg-white px-4 py-2.5 text-sm outline-none transition focus:border-indigo-500 focus:ring-2 focus:ring-indigo-200 disabled:opacity-50 dark:border-zinc-700 dark:bg-zinc-900"
            />
            <button
              type="submit"
              disabled={!input.trim() || streaming}
              className="rounded-xl bg-indigo-600 px-5 py-2.5 text-sm font-medium text-white transition hover:bg-indigo-500 disabled:opacity-50"
            >
              Send
            </button>
          </div>
        </form>
      </main>
    </div>
  );
}

// ─── Message Bubble with Tool Call Display ────────────────
function MessageBubble({ msg }: { msg: ChatMessage }) {
  const isUser = msg.role === "user";

  return (
    <div className={"flex " + (isUser ? "justify-end" : "justify-start")}>
      <div className="flex max-w-[80%] flex-col gap-2">
        {/* Tool calls */}
        {msg.toolCalls && msg.toolCalls.length > 0 && (
          <div className="flex flex-col gap-1">
            {msg.toolCalls.map((tc) => (
              <ToolCallBubble key={tc.id} tc={tc} />
            ))}
          </div>
        )}

        {/* Text content */}
        <div
          className={
            "rounded-2xl px-4 py-2.5 text-sm leading-relaxed " +
            (isUser
              ? "bg-indigo-600 text-white"
              : msg.content
                ? "bg-zinc-100 text-zinc-800 dark:bg-zinc-800 dark:text-zinc-200"
                : "bg-zinc-100 dark:bg-zinc-800")
          }
        >
          {isUser ? (
            msg.content
          ) : msg.content ? (
            <StreamingMarkdown text={msg.content} />
          ) : msg.toolCalls && msg.toolCalls.length > 0 ? null : (
            <TypingDots />
          )}
        </div>
      </div>
    </div>
  );
}

function Dot({ delay }: { delay: string }) {
  return (
    <span className="animate-bounce text-zinc-400" style={{ animationDelay: delay }}>
      ●
    </span>
  );
}

function TypingDots() {
  return (
    <span className="inline-flex gap-1">
      <Dot delay="0s" />
      <Dot delay="0.1s" />
      <Dot delay="0.2s" />
    </span>
  );
}

function ToolCallBubble({ tc }: { tc: ToolCall }) {
  const [expanded, setExpanded] = useState(false);
  const hasResult = tc.result && tc.status === "done";

  return (
    <div className="rounded-xl border border-slate-200 bg-slate-50 px-3 py-2 text-xs dark:border-slate-700 dark:bg-slate-900">
      <div className="flex items-center gap-2">
        <span className="font-mono font-semibold text-slate-600 dark:text-slate-300">
          🔧 {tc.name}
        </span>
        {tc.status === "pending" && (
          <span className="inline-flex gap-0.5">
            <Dot delay="0s" /><Dot delay="0.15s" /><Dot delay="0.3s" />
          </span>
        )}
      </div>
      <div className="mt-1 text-slate-500 dark:text-slate-400">
        {JSON.stringify(tc.args, null, 0)}
      </div>
      {hasResult && (
        <button
          onClick={() => setExpanded(!expanded)}
          className="mt-1 flex w-full items-center gap-1 rounded bg-white/60 px-2 py-1 text-left font-mono text-slate-600 hover:bg-white dark:bg-black/20 dark:text-slate-300 dark:hover:bg-black/30"
        >
          <span className="text-[10px]">{expanded ? "▼" : "▶"}</span>
          <span className="truncate">
            {expanded ? tc.result : String(tc.result).slice(0, 60) + "…"}
          </span>
        </button>
      )}
    </div>
  );
}

// ─── Background Task Status ──────────────────────────────────
function TaskStatusIndicator({ tasks }: { tasks: TaskInfo[] }) {
  const [expanded, setExpanded] = useState(false);
  if (tasks.length === 0) return null;

  return (
    <div className="relative" onMouseLeave={() => setExpanded(false)}>
      <button
        onClick={() => setExpanded((v) => !v)}
        className="inline-flex items-center gap-1.5 rounded-full border border-amber-200 bg-amber-50 px-2.5 py-1 text-xs font-medium text-amber-700 hover:bg-amber-100 dark:border-amber-800 dark:bg-amber-950/40 dark:text-amber-300 dark:hover:bg-amber-900/40"
        title="后台任务进行中"
      >
        <Spinner />
        <span>{tasks.length} 后台任务</span>
      </button>
      {expanded && (
        <div className="absolute right-0 top-full z-20 mt-1 w-72 rounded-lg border border-amber-200 bg-white p-2 text-xs shadow-lg dark:border-amber-800 dark:bg-zinc-900">
          {tasks.map((t) => (
            <div
              key={t.task_id}
              className="flex items-center justify-between border-b border-zinc-100 px-2 py-1.5 last:border-0 dark:border-zinc-800"
            >
              <div className="min-w-0 flex-1 truncate">
                <div className="truncate font-medium text-zinc-700 dark:text-zinc-200">
                  {t.task_name}
                </div>
                <div className="truncate text-[10px] text-zinc-400">
                  {t.status === "running"
                    ? `处理中 · ${Math.round((t.duration_ms || 15000) / 1000)}s`
                    : "排队中"}
                </div>
              </div>
              <span className="ml-2 inline-flex h-2 w-2 shrink-0 rounded-full bg-amber-500" />
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function Spinner() {
  return (
    <svg
      className="h-3 w-3 animate-spin text-amber-600 dark:text-amber-400"
      viewBox="0 0 24 24"
      fill="none"
    >
      <circle
        cx="12"
        cy="12"
        r="9"
        stroke="currentColor"
        strokeWidth="3"
        strokeOpacity="0.25"
      />
      <path
        d="M21 12a9 9 0 0 0-9-9"
        stroke="currentColor"
        strokeWidth="3"
        strokeLinecap="round"
      />
    </svg>
  );
}

function CompletionBanner({
  task,
  visible,
  onDismiss,
}: {
  task: TaskInfo | null;
  visible: boolean;
  onDismiss: () => void;
}) {
  if (!task) return null;

  return (
    <div
      className={
        "overflow-hidden border-b border-emerald-200 bg-emerald-50 text-emerald-800 transition-all duration-300 ease-out dark:border-emerald-800 dark:bg-emerald-950/40 dark:text-emerald-200 " +
        (visible ? "max-h-24 opacity-100" : "max-h-0 opacity-0")
      }
    >
      <div className="mx-auto flex max-w-3xl items-center gap-3 px-6 py-2.5 text-sm">
        <span className="text-base">✅</span>
        <div className="min-w-0 flex-1">
          <span className="font-semibold">后台任务已完成：</span>
          <span className="ml-1 truncate">{task.task_name}</span>
        </div>
        <button
          onClick={onDismiss}
          className="rounded p-1 text-emerald-700 hover:bg-emerald-100 dark:text-emerald-300 dark:hover:bg-emerald-900/40"
          aria-label="dismiss"
        >
          ✕
        </button>
      </div>
    </div>
  );
}
