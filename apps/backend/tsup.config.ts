import { defineConfig } from 'tsup';

export default defineConfig({
  entry: {
    index: 'src/index.ts',
    'cli/migrate': 'src/cli/migrate.ts',
    'cli/scan': 'src/cli/scan.ts',
    'cli/backtest': 'src/cli/backtest.ts',
  },
  format: ['esm'],
  platform: 'node',
  target: 'node22',
  outDir: 'dist',
  clean: true,
  sourcemap: true,
  splitting: true,
  // Keep runtime deps external; they are installed in the image.
  skipNodeModulesBundle: true,
});
