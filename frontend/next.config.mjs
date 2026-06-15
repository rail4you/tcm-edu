/**
 * Next.js configuration tuned for the ash-ts-demo monorepo.
 *
 * The dev server (`pnpm dev`) and the static export (`pnpm build`) need
 * subtly different settings, so we branch on `process.env.NODE_ENV`:
 *
 *   • Development (`next dev`)
 *       - Served at  http://localhost:3000/
 *       - `/api/*` requests are proxied to Phoenix (http://localhost:4011)
 *         through the `rewrites()` config.
 *       - No `basePath` so the dev URLs match what production looks like
 *         after Phoenix mounts the static export under `/app`.
 *
 *   • Production (`next build`)
 *       - `output: "export"` writes a fully-static bundle to `out/`
 *         (Next.js 16+ refuses to write outside the project, so we keep
 *         `distDir` at its default and let the export land in `frontend/out/`).
 *         The Dockerfile copies that directory to `priv/app/` before the
 *         Elixir release is assembled.
 *       - `basePath` / `assetPrefix` are set to `/app` so the generated
 *         HTML/asset URLs match the mount point.
 *       - `images.unoptimized` and `trailingSlash` are required by the
 *         static-export contract.
 *
 * The generated RPC client (in `lib/generated/ash_rpc.ts`) hard-codes the
 * absolute path `/api/rpc/run`. That URL is correct in production (same
 * origin as Phoenix) and is intercepted by the dev rewrite while the
 * Next.js dev server is running.
 */
const isProd = process.env.NODE_ENV === "production";

/** @type {import('next').NextConfig} */
const nextConfig = {
  output: "export",
  trailingSlash: true,
  images: { unoptimized: true },
  reactStrictMode: true,
  // Production export is mounted under `/app/` by Phoenix.
  // Dev server stays at the root for ergonomic developer URLs.
  ...(isProd
    ? {
        basePath: "/app",
        assetPrefix: "/app",
      }
    : {}),
  async rewrites() {
    // Only honored by `next dev` / `next start`. Static exports skip this.
    return [
      {
        source: "/api/:path*",
        destination: "http://localhost:4011/api/:path*",
      },
    ];
  },
};

export default nextConfig;
