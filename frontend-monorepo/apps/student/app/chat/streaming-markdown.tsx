"use client";

import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import remarkMath from "remark-math";
import rehypeKatex from "rehype-katex";
import { Prism as SyntaxHighlighter } from "react-syntax-highlighter";
import { oneDark } from "react-syntax-highlighter/dist/esm/styles/prism";
import { useMemo } from "react";

import "katex/dist/katex.min.css";

/**
 * Streaming-safe Markdown renderer with:
 *  - GFM (tables, strikethrough, etc.)
 *  - Syntax-highlighted code blocks
 *  - LaTeX math (inline $...$ and block $$...$$)
 *
 * Handles partial/incomplete markdown by splitting at newlines.
 */
export function StreamingMarkdown({ text }: { text: string }) {
  const { completePart, partialPart } = useMemo(() => {
    if (!text) return { completePart: "", partialPart: "" };

    const lines = text.split("\n");
    const lastIdx = lines.length - 1;

    return {
      completePart: lines.slice(0, lastIdx).join("\n"),
      partialPart: lines[lastIdx],
    };
  }, [text]);

  const components = useMemo(
    () => ({
      code({ className, children, ...props }: any) {
        const match = /language-(\w+)/.exec(className || "");
        const codeStr = String(children).replace(/\n$/, "");

        if (match) {
          return (
            <div className="my-2 overflow-hidden rounded-lg">
              <div className="bg-zinc-700 px-3 py-1 text-xs text-zinc-300">
                {match[1]}
              </div>
              <SyntaxHighlighter
                style={oneDark}
                language={match[1]}
                PreTag="div"
                customStyle={{ margin: 0, borderRadius: "0 0 8px 8px" }}
              >
                {codeStr}
              </SyntaxHighlighter>
            </div>
          );
        }

        return (
          <code className="rounded bg-zinc-200 px-1 py-0.5 text-xs dark:bg-zinc-700" {...props}>
            {children}
          </code>
        );
      },
    }),
    []
  );

  return (
    <div className="prose prose-sm dark:prose-invert max-w-none break-words text-sm">
      {completePart && (
        <ReactMarkdown
          remarkPlugins={[remarkGfm, remarkMath]}
          rehypePlugins={[rehypeKatex]}
          components={components}
        >
          {completePart}
        </ReactMarkdown>
      )}

      {/* Incomplete last line as plain text to avoid broken syntax */}
      <ReactMarkdown
        remarkPlugins={[remarkGfm, remarkMath]}
        rehypePlugins={[rehypeKatex]}
        components={{
          p: ({ children }) => <span>{children}</span>,
          ...components,
        }}
      >
        {partialPart}
      </ReactMarkdown>
    </div>
  );
}
