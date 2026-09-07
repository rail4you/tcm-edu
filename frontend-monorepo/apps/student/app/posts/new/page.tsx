"use client";

import { useState } from "react";
import { useAuth } from "../../auth-context";
import { createPost, type AshRpcError } from "@tcm-edu/rpc-client";
import Link from "next/link";
import { useRouter } from "next/navigation";

export default function NewPostPage() {
  const { isAuthenticated, token, isAdmin } = useAuth();
  const router = useRouter();

  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [coverFile, setCoverFile] = useState<File | null>(null);
  const [extraFiles, setExtraFiles] = useState<File[]>([]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!isAuthenticated) {
    return (
      <main className="mx-auto flex min-h-screen max-w-md flex-col items-center justify-center gap-4 px-6">
        <h1 className="text-2xl font-semibold">New Post</h1>
        <p className="text-sm text-zinc-500">
          Please{" "}
          <Link href="/" className="text-indigo-500 underline underline-offset-2">
            sign in
          </Link>{" "}
          to create posts.
        </p>
      </main>
    );
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!title.trim()) return;

    setSaving(true);
    setError(null);

    try {
      // 1. Create the post
      const result = await createPost({
        input: { title: title.trim(), body: body.trim() || undefined },
        fields: ["id", "title"],
      });

      if (!result.success) {
        setError(formatErrors(result.errors));
        setSaving(false);
        return;
      }

      const postId = result.data.id;

      // 2. Upload cover image if selected
      if (coverFile && token) {
        const coverForm = new FormData();
        coverForm.append("file", coverFile);

        const coverRes = await fetch(`/api/posts/${postId}/upload/cover_image`, {
          method: "POST",
          headers: { Authorization: `Bearer ${token}` },
          body: coverForm,
        });
        const coverData = await coverRes.json();
        if (!coverData.success) {
          console.warn("Cover upload failed:", coverData.error);
        }
      }

      // 3. Upload extra attachments
      if (extraFiles.length > 0 && token) {
        for (const file of extraFiles) {
          const formData = new FormData();
          formData.append("file", file);

          const res = await fetch(`/api/posts/${postId}/upload/attachments`, {
            method: "POST",
            headers: { Authorization: `Bearer ${token}` },
            body: formData,
          });
          const data = await res.json();
          if (!data.success) {
            console.warn("Attachment upload failed:", data.error);
          }
        }
      }

      // 4. Navigate to posts list
      router.push("/posts");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Unknown error");
      setSaving(false);
    }
  }

  function handleExtraFiles(e: React.ChangeEvent<HTMLInputElement>) {
    if (e.target.files) {
      setExtraFiles(Array.from(e.target.files));
    }
  }

  return (
    <main className="mx-auto flex min-h-screen w-full max-w-2xl flex-col gap-8 px-6 py-12">
      {/* Header */}
      <header className="flex flex-col gap-1">
        <p className="text-xs font-semibold uppercase tracking-widest text-indigo-500">
          TCM Education
        </p>
        <h1 className="text-3xl font-semibold">New Post</h1>
      </header>

      {/* Navigation tabs */}
      <nav className="flex items-center gap-1 border-b border-zinc-200 dark:border-zinc-800">
        <Link
          href="/"
          className="rounded-t-lg border-b-2 border-transparent px-4 py-2 text-sm font-medium text-zinc-500 transition hover:border-zinc-300 hover:text-zinc-700 dark:hover:border-zinc-700 dark:hover:text-zinc-300"
        >
          Todos
        </Link>
        <Link
          href="/posts"
          className="rounded-t-lg border-b-2 border-indigo-500 px-4 py-2 text-sm font-medium text-indigo-600 dark:text-indigo-400"
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

      {/* Form */}
      <form
        onSubmit={handleSubmit}
        className="flex flex-col gap-6 rounded-lg border border-zinc-200 bg-white p-6 dark:border-zinc-800 dark:bg-zinc-900"
      >
        {/* Title */}
        <label className="flex flex-col gap-1.5">
          <span className="text-sm font-medium text-zinc-700 dark:text-zinc-300">
            Title <span className="text-red-500">*</span>
          </span>
          <input
            type="text"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            required
            placeholder="Post title"
            maxLength={200}
            className="rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-2 focus:ring-indigo-200 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-100"
          />
        </label>

        {/* Body */}
        <label className="flex flex-col gap-1.5">
          <span className="text-sm font-medium text-zinc-700 dark:text-zinc-300">
            Body
          </span>
          <textarea
            value={body}
            onChange={(e) => setBody(e.target.value)}
            placeholder="Write something..."
            rows={5}
            className="resize-y rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-2 focus:ring-indigo-200 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-100"
          />
        </label>

        {/* Cover image */}
        <label className="flex flex-col gap-1.5">
          <span className="text-sm font-medium text-zinc-700 dark:text-zinc-300">
            Cover Image
          </span>
          <div className="flex items-center gap-3">
            <input
              type="file"
              accept="image/*"
              onChange={(e) => setCoverFile(e.target.files?.[0] || null)}
              className="block w-full text-sm text-zinc-500 file:mr-3 file:rounded-lg file:border-0 file:bg-indigo-50 file:px-3 file:py-1.5 file:text-sm file:font-medium file:text-indigo-700 hover:file:bg-indigo-100 dark:text-zinc-400 dark:file:bg-indigo-950 dark:file:text-indigo-300"
            />
          </div>
        </label>

        {/* Attachments */}
        <label className="flex flex-col gap-1.5">
          <span className="text-sm font-medium text-zinc-700 dark:text-zinc-300">
            Attachments
          </span>
          <input
            type="file"
            multiple
            onChange={handleExtraFiles}
            className="block w-full text-sm text-zinc-500 file:mr-3 file:rounded-lg file:border-0 file:bg-indigo-50 file:px-3 file:py-1.5 file:text-sm file:font-medium file:text-indigo-700 hover:file:bg-indigo-100 dark:text-zinc-400 dark:file:bg-indigo-950 dark:file:text-indigo-300"
          />
          {extraFiles.length > 0 && (
            <p className="text-xs text-zinc-400">
              {extraFiles.length} file(s) selected
            </p>
          )}
        </label>

        {/* Submit */}
        <div className="flex justify-end gap-3">
          <Link
            href="/posts"
            className="rounded-lg border border-zinc-300 px-4 py-2 text-sm text-zinc-600 transition hover:bg-zinc-100 dark:border-zinc-700 dark:text-zinc-400 dark:hover:bg-zinc-800"
          >
            Cancel
          </Link>
          <button
            type="submit"
            disabled={saving || !title.trim()}
            className="rounded-lg bg-indigo-600 px-6 py-2 text-sm font-medium text-white transition hover:bg-indigo-500 disabled:opacity-50"
          >
            {saving ? "Creating…" : "Create Post"}
          </button>
        </div>
      </form>
    </main>
  );
}

function formatErrors(errors: AshRpcError[]): string {
  return errors
    .map((e) => `${e.type}: ${e.shortMessage || e.message}`)
    .join("; ");
}
