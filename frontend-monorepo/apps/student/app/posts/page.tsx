"use client";

import { useCallback, useEffect, useState } from "react";
import { useAuth, can } from "../auth-context";
import {
  type AshRpcError,
  listPosts,
  deletePost,
} from "@tcm-edu/rpc-client";
import Link from "next/link";

type Post = {
  id: string;
  title: string;
  body: string | null;
  coverImageUrl: string | null;
  attachmentsUrls: string[] | null;
  attachmentsThumbnailUrls: string[] | null;
  insertedAt: string;
  updatedAt: string;
};

const FIELDS: ["id", "title", "body", "coverImageUrl", "attachmentsUrls", "attachmentsThumbnailUrls", "insertedAt", "updatedAt"] = [
  "id",
  "title",
  "body",
  "coverImageUrl",
  "attachmentsUrls",
  "attachmentsThumbnailUrls",
  "insertedAt",
  "updatedAt",
];

export default function PostsPage() {
  const { isAuthenticated, logout, isAdmin, user } = useAuth();

  if (!isAuthenticated) {
    return (
      <main className="mx-auto flex min-h-screen max-w-md flex-col items-center justify-center gap-4 px-6">
        <h1 className="text-2xl font-semibold">Posts</h1>
        <p className="text-sm text-zinc-500">
          Please{" "}
          <Link href="/" className="text-indigo-500 underline underline-offset-2">
            sign in
          </Link>{" "}
          to view posts.
        </p>
      </main>
    );
  }

  return <PostsApp logout={logout} isAdmin={isAdmin} user={user} />;
}

function PostsApp({ logout, isAdmin, user }: { logout: () => Promise<void>; isAdmin: boolean; user: import("../auth-context").UserProfile | null }) {
  const canCreate = can(user, "post:create");
  const canDelete = can(user, "post:delete");
  const [posts, setPosts] = useState<Post[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [detailPost, setDetailPost] = useState<Post | null>(null);

  const refresh = useCallback(async () => {
    setLoading(true);
    setError(null);
    const result = await listPosts({ fields: FIELDS });
    if (!result.success) {
      setError(formatErrors(result.errors));
      setPosts([]);
    } else {
      setPosts((result.data as any[]).map(shapePost));
    }
    setLoading(false);
  }, []);

  useEffect(() => {
    refresh();
  }, [refresh]);

  async function handleDelete(post: Post) {
    if (!confirm(`Delete "${post.title}"?`)) return;
    setError(null);
    const result = await deletePost({ identity: post.id });
    if (!result.success) {
      setError(formatErrors(result.errors));
    } else {
      setPosts((current) => current.filter((p) => p.id !== post.id));
      if (detailPost?.id === post.id) setDetailPost(null);
    }
  }

  return (
    <>
      <main className="mx-auto flex min-h-screen w-full max-w-3xl flex-col gap-8 px-6 py-12">
        {/* Header */}
        <header className="flex flex-col gap-1">
          <p className="text-xs font-semibold uppercase tracking-widest text-indigo-500">
            TCM Education
          </p>
          <h1 className="text-3xl font-semibold">Posts</h1>
          <p className="text-sm text-zinc-500">
            Manage posts with file attachments via AshStorage
          </p>
        </header>

        {/* Navigation tabs */}
        <nav className="flex items-center gap-1 border-b border-zinc-200 dark:border-zinc-800">
          <Link
            href="/"
            className="rounded-t-lg border-b-2 border-transparent px-4 py-2 text-sm font-medium text-zinc-500 transition hover:border-zinc-300 hover:text-zinc-700 dark:hover:border-zinc-700 dark:hover:text-zinc-300"
          >
            Todos
          </Link>
          <span className="rounded-t-lg border-b-2 border-indigo-500 px-4 py-2 text-sm font-medium text-indigo-600 dark:text-indigo-400">
            Posts
          </span>
          {isAdmin && (
            <Link
              href="/admin/users"
              className="rounded-t-lg border-b-2 border-transparent px-4 py-2 text-sm font-medium text-zinc-500 transition hover:border-zinc-300 hover:text-zinc-700 dark:hover:border-zinc-700 dark:hover:text-zinc-300"
            >
              Users
            </Link>
          )}
          <div className="ml-auto flex items-center gap-3">
            {canCreate && (
              <Link
                href="/posts/new"
                className="rounded-lg bg-indigo-600 px-4 py-1.5 text-sm font-medium text-white transition hover:bg-indigo-500"
              >
                + New Post
              </Link>
            )}
            <button
              onClick={logout}
              className="rounded-lg border border-zinc-300 px-3 py-1.5 text-sm text-zinc-600 transition hover:bg-zinc-100 dark:border-zinc-700 dark:text-zinc-400 dark:hover:bg-zinc-800"
            >
              Sign Out
            </button>
          </div>
        </nav>

        {/* Error */}
        {error && (
          <div
            role="alert"
            className="rounded-lg border border-red-300 bg-red-50 px-3 py-2 text-sm text-red-700 dark:border-red-800 dark:bg-red-950 dark:text-red-200"
          >
            {error}
          </div>
        )}

        {/* Post list */}
        <section className="flex flex-col gap-4">
          {loading && posts.length === 0 ? (
            <p className="text-sm text-zinc-500">Loading…</p>
          ) : posts.length === 0 ? (
            <div className="rounded-lg border border-zinc-200 bg-white p-8 text-center dark:border-zinc-800 dark:bg-zinc-900">
              <p className="text-sm text-zinc-500">No posts yet.</p>
              {canCreate && (
                <Link
                  href="/posts/new"
                  className="mt-2 inline-block text-sm font-medium text-indigo-500 underline underline-offset-2"
                >
                  Create your first post
                </Link>
              )}
            </div>
          ) : (
            <div className="grid gap-4">
              {posts.map((post) => (
                <PostCard
                  key={post.id}
                  post={post}
                  onClick={() => setDetailPost(post)}
                  onDelete={handleDelete}
                  canDelete={canDelete}
                />
              ))}
            </div>
          )}
        </section>
      </main>

      {/* Detail modal */}
      {detailPost && (
        <PostDetailModal
          post={detailPost}
          onClose={() => setDetailPost(null)}
          onDelete={handleDelete}
          canDelete={canDelete}
        />
      )}
    </>
  );
}

/* ── Post Card ───────────────────────────────────── */

function PostCard({
  post,
  onClick,
  onDelete,
  canDelete,
}: {
  post: Post;
  onClick: () => void;
  onDelete: (post: Post) => void;
  canDelete: boolean;
}) {
  return (
    <div
      className="cursor-pointer overflow-hidden rounded-lg border border-zinc-200 bg-white transition hover:border-zinc-300 hover:shadow-sm dark:border-zinc-800 dark:bg-zinc-900 dark:hover:border-zinc-700"
      onClick={onClick}
    >
      {/* Cover image preview */}
      {post.coverImageUrl && (
        <div className="h-48 w-full overflow-hidden bg-zinc-100 dark:bg-zinc-800">
          <img
            src={post.coverImageUrl}
            alt={post.title}
            className="h-full w-full object-cover"
            onError={(e) => {
              (e.target as HTMLImageElement).style.display = "none";
            }}
          />
        </div>
      )}

      <div className="p-4">
        <div className="flex items-start justify-between gap-4">
          <div className="flex-1">
            <h2 className="text-lg font-semibold text-zinc-900 dark:text-zinc-100">
              {post.title}
            </h2>
            <p className="mt-0.5 text-xs text-zinc-400">
              {new Date(post.insertedAt).toLocaleDateString("zh-CN", {
                year: "numeric",
                month: "short",
                day: "numeric",
                hour: "2-digit",
                minute: "2-digit",
              })}
            </p>
          </div>
          {canDelete && (
            <button
              onClick={(e) => {
                e.stopPropagation();
                onDelete(post);
              }}
              className="shrink-0 rounded px-2 py-1 text-xs text-zinc-500 transition hover:bg-red-50 hover:text-red-600 dark:hover:bg-red-950"
            >
              Delete
            </button>
          )}
        </div>

        {post.body && (
          <p className="mt-2 line-clamp-2 text-sm text-zinc-600 dark:text-zinc-400">
            {post.body}
          </p>
        )}

        {post.attachmentsUrls && post.attachmentsUrls.length > 0 && (
          <p className="mt-2 text-xs text-indigo-500">
            {post.attachmentsUrls.length} attachment(s)
          </p>
        )}
      </div>
    </div>
  );
}

/* ── Post Detail Modal ───────────────────────────── */

function PostDetailModal({
  post,
  onClose,
  onDelete,
  canDelete,
}: {
  post: Post;
  onClose: () => void;
  onDelete: (post: Post) => void;
  canDelete: boolean;
}) {
  // Close on Escape
  useEffect(() => {
    function handler(e: KeyboardEvent) {
      if (e.key === "Escape") onClose();
    }
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [onClose]);

  // Close on backdrop click
  function handleBackdrop(e: React.MouseEvent) {
    if (e.target === e.currentTarget) onClose();
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4 backdrop-blur-sm"
      onClick={handleBackdrop}
    >
      <div className="relative max-h-[90vh] w-full max-w-2xl overflow-y-auto rounded-xl bg-white shadow-2xl dark:bg-zinc-900">
        {/* Close button */}
        <button
          onClick={onClose}
          className="absolute right-4 top-4 z-10 rounded-full bg-white/80 p-1.5 text-zinc-600 shadow-sm backdrop-blur transition hover:bg-white hover:text-zinc-900 dark:bg-zinc-800/80 dark:text-zinc-400 dark:hover:bg-zinc-800 dark:hover:text-zinc-100"
        >
          <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>

        {/* Cover image — full width */}
        {post.coverImageUrl && (
          <div className="w-full bg-zinc-100 dark:bg-zinc-800">
            <img
              src={post.coverImageUrl}
              alt={post.title}
              className="max-h-[50vh] w-full object-contain"
              onError={(e) => {
                (e.target as HTMLImageElement).style.display = "none";
              }}
            />
          </div>
        )}

        <div className="p-6">
          {/* Title + meta */}
          <div className="flex items-start justify-between gap-4">
            <div>
              <h2 className="text-2xl font-bold text-zinc-900 dark:text-zinc-100">
                {post.title}
              </h2>
              <p className="mt-1 text-sm text-zinc-400">
                {new Date(post.insertedAt).toLocaleDateString("zh-CN", {
                  year: "numeric",
                  month: "long",
                  day: "numeric",
                  hour: "2-digit",
                  minute: "2-digit",
                })}
              </p>
            </div>
            {canDelete && (
              <button
                onClick={() => {
                  if (confirm(`Delete "${post.title}"?`)) {
                    onDelete(post);
                    onClose();
                  }
                }}
                className="shrink-0 rounded-lg border border-red-200 px-3 py-1.5 text-xs font-medium text-red-600 transition hover:bg-red-50 dark:border-red-800 dark:text-red-400 dark:hover:bg-red-950"
              >
                Delete
              </button>
            )}
          </div>

          {/* Full body text */}
          {post.body && (
            <div className="mt-4 whitespace-pre-wrap text-sm leading-relaxed text-zinc-700 dark:text-zinc-300">
              {post.body}
            </div>
          )}

          {/* Attachments list */}
          {post.attachmentsUrls && post.attachmentsUrls.length > 0 && (
            <div className="mt-6">
              <h3 className="mb-2 text-sm font-semibold text-zinc-700 dark:text-zinc-300">
                Attachments ({post.attachmentsUrls.length})
              </h3>
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4">
                {post.attachmentsUrls.map((url, i) => {
                  const isVideo = /\.(mp4|webm|mov|avi|mkv)$/i.test(url);
                  const isImage = /\.(png|jpe?g|gif|webp|svg|bmp|ico)$/i.test(url);
                  const thumbUrl = post.attachmentsThumbnailUrls?.[i];

                  return (
                    <div key={i} className="group relative">
                      {isVideo ? (
                        <a
                          href={url}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="block overflow-hidden rounded-lg border border-zinc-200 bg-black/5 transition hover:shadow-md dark:border-zinc-700"
                        >
                          {/* Video thumbnail or placeholder */}
                          <div className="relative aspect-video w-full">
                            {thumbUrl ? (
                              <img
                                src={thumbUrl}
                                alt={`Video ${i + 1}`}
                                className="h-full w-full object-cover"
                              />
                            ) : (
                              <div className="flex h-full w-full items-center justify-center bg-zinc-200 dark:bg-zinc-800">
                                <svg className="h-8 w-8 text-zinc-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z" />
                                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                                </svg>
                              </div>
                            )}
                            {/* Play icon overlay */}
                            <div className="absolute inset-0 flex items-center justify-center">
                              <div className="flex h-10 w-10 items-center justify-center rounded-full bg-black/40 text-white shadow-lg backdrop-blur">
                                <svg className="ml-0.5 h-5 w-5" fill="currentColor" viewBox="0 0 24 24">
                                  <path d="M8 5v14l11-7z" />
                                </svg>
                              </div>
                            </div>
                          </div>
                          <div className="px-2 py-1.5 text-xs text-zinc-500 dark:text-zinc-400">
                            Video {i + 1}
                          </div>
                        </a>
                      ) : isImage ? (
                        <a
                          href={url}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="block overflow-hidden rounded-lg border border-zinc-200 transition hover:shadow-md dark:border-zinc-700"
                        >
                          <img
                            src={url}
                            alt={`Image ${i + 1}`}
                            className="aspect-video w-full object-cover"
                            onError={(e) => {
                              (e.target as HTMLImageElement).src =
                                "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='48' height='48' viewBox='0 0 24 24' fill='none' stroke='%23999' stroke-width='2'%3E%3Cpath d='M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z' /%3E%3C/svg%3E";
                            }}
                          />
                        </a>
                      ) : (
                        <a
                          href={url}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="flex flex-col items-center justify-center gap-1 rounded-lg border border-zinc-200 bg-zinc-50 px-3 py-4 text-xs text-zinc-600 transition hover:border-indigo-300 hover:bg-indigo-50 hover:text-indigo-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-400 dark:hover:border-indigo-700 dark:hover:bg-indigo-950"
                        >
                          <svg className="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                          </svg>
                          <span>File {i + 1}</span>
                        </a>
                      )}
                    </div>
                  );
                })}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

/* ── Helpers ─────────────────────────────────────── */

function shapePost(row: any): Post {
  return {
    id: row.id,
    title: row.title,
    body: row.body,
    coverImageUrl: row.coverImageUrl,
    attachmentsUrls: row.attachmentsUrls,
    attachmentsThumbnailUrls: row.attachmentsThumbnailUrls,
    insertedAt: row.insertedAt,
    updatedAt: row.updatedAt,
  };
}

function formatErrors(errors: AshRpcError[]): string {
  return errors
    .map((e) => `${e.type}: ${e.shortMessage || e.message}`)
    .join("; ");
}
