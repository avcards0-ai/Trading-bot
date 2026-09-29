import { Route, Routes } from 'react-router-dom';
import { Layout } from './components/Layout';
import { AlertsPage } from './pages/Alerts';
import { BacktestPage } from './pages/Backtest';
import { DashboardPage } from './pages/Dashboard';
import { LeaderboardPage } from './pages/Leaderboard';
import { PerformancePage } from './pages/Performance';
import { PositionsPage } from './pages/Positions';
import { SettingsPage } from './pages/Settings';
import { SniperPage } from './pages/Sniper';
import { SocialPage } from './pages/Social';
import { SystemPage } from './pages/System';
import { TokenDetailPage } from './pages/TokenDetail';
import { TokensPage } from './pages/Tokens';

export function App() {
  return (
    <Layout>
      <Routes>
        <Route path="/" element={<DashboardPage />} />
        <Route path="/tokens" element={<TokensPage />} />
        <Route path="/tokens/:address" element={<TokenDetailPage />} />
        <Route path="/leaderboard" element={<LeaderboardPage />} />
        <Route path="/positions" element={<PositionsPage />} />
        <Route path="/sniper" element={<SniperPage />} />
        <Route path="/social" element={<SocialPage />} />
        <Route path="/performance" element={<PerformancePage />} />
        <Route path="/backtest" element={<BacktestPage />} />
        <Route path="/alerts" element={<AlertsPage />} />
        <Route path="/system" element={<SystemPage />} />
        <Route path="/settings" element={<SettingsPage />} />
        <Route path="*" element={<div className="text-sm text-muted">Page not found.</div>} />
      </Routes>
    </Layout>
  );
}
