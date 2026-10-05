import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
import { defineConfig } from 'vite';

const backend = process.env.VITE_BACKEND_URL ?? 'http://127.0.0.1:8080';
// In GitHub Codespaces the dashboard is opened through a forwarded <name>-5173.<domain> address,
// which Vite rejects unless allowed. Only that domain is allowed, and only inside a codespace.
const codespacesDomain = process.env.CODESPACES
  ? process.env.GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN
  : undefined;
const allowedHosts = codespacesDomain ? { allowedHosts: [`.${codespacesDomain}`] } : {};

export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    port: 5173,
    host: '127.0.0.1',
    ...allowedHosts,
    proxy: {
      // The backend serves its API at the root (GET /tokens, POST /scan, ...);
      // the dashboard calls /api/* and the proxy strips the prefix.
      '/api': {
        target: backend,
        changeOrigin: true,
        rewrite: (p) => p.replace(/^\/api/, ''),
      },
    },
  },
  preview: {
    port: 4173,
    ...allowedHosts,
    proxy: {
      '/api': { target: backend, changeOrigin: true, rewrite: (p) => p.replace(/^\/api/, '') },
    },
  },
  build: { outDir: 'dist', sourcemap: true, chunkSizeWarningLimit: 1200 },
});
