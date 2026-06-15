"use client";

import { useRef, useState, useEffect } from "react";
import { useAuth } from "../auth-context";
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

const AGENTS: Agent[] = [
  { name: "chat_agent", label: "Chat Agent", description: "AI assistant with multiply tool" },
  { name: "counter_agent", label: "Counter Agent", description: "Counter manager" },
  { name: "quiz_agent", label: "Quiz Agent", description: "Generates quiz from text" },
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

// ─── Main Page ──────────────────────────────────────────────
export default function ChatPage() {
  const { isAuthenticated, logout, token } = useAuth();
  const [activeAgent, setActiveAgent] = useState<Agent>(AGENTS[0]);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [input, setInput] = useState("");
  const [streaming, setStreaming] = useState(false);
  const [loadingHistory, setLoadingHistory] = useState(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const abortRef = useRef<AbortController | null>(null);
  const scrollContainerRef = useRef<HTMLDivElement>(null);
  const scrollPositions = useRef<Record<string, number>>({});

  const sessionId = getSessionId(activeAgent.name);
  const baseUrl = typeof window !== "undefined" &&
    window.location.hostname === "localhost"
    ? "http://localhost:4011"
    : "";

  // Auto-scroll to bottom when new content arrives
  useEffect(() => {
    if (streaming) {
      messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
    }
  }, [messages, streaming]);

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
        <div className="border-t border-zinc-200 p-3 dark:border-zinc-800">
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
          <div>
            <h1 className="text-sm font-semibold text-zinc-800 dark:text-zinc-200">
              {activeAgent.label}
              {loadingHistory && (
                <span className="ml-2 text-xs font-normal text-zinc-400">loading…</span>
              )}
            </h1>
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
              <div
                key={tc.id}
                className="rounded-xl border border-amber-200 bg-amber-50 px-3 py-2 text-xs dark:border-amber-800 dark:bg-amber-950"
              >
                <div className="flex items-center gap-2">
                  <span className="font-mono font-semibold text-amber-700 dark:text-amber-400">
                    🔧 {tc.name}
                  </span>
                  {tc.status === "pending" && (
                    <span className="inline-flex gap-0.5">
                      <Dot delay="0s" /><Dot delay="0.15s" /><Dot delay="0.3s" />
                    </span>
                  )}
                </div>
                <div className="mt-1 text-amber-600 dark:text-amber-300">
                  {JSON.stringify(tc.args, null, 0)}
                </div>
                {tc.result && (
                  <div className="mt-1 rounded bg-white/50 px-2 py-1 font-mono text-amber-800 dark:bg-black/20 dark:text-amber-200">
                    → {tc.result}
                  </div>
                )}
              </div>
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
