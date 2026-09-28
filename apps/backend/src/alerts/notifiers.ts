import type { Alert, AlertSeverity } from '@memeguard/shared';
import type { HttpClient } from '../lib/http';

export interface Notifier {
  readonly name: string;
  send(alert: Alert): Promise<void>;
}

const SEVERITY_ICON: Record<AlertSeverity, string> = { info: 'ℹ️', warning: '⚠️', critical: '🚨' };
const SEVERITY_COLOR: Record<AlertSeverity, number> = {
  info: 0x3b82f6,
  warning: 0xf59e0b,
  critical: 0xef4444,
};

export const escapeHtml = (s: string): string =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

export function formatTelegram(alert: Alert, dashboardUrl: string | null): string {
  const token = alert.symbol ? ` <b>${escapeHtml(alert.symbol)}</b>` : '';
  const lines = [
    `${SEVERITY_ICON[alert.severity]} <b>${escapeHtml(alert.title)}</b>${token}`,
    escapeHtml(alert.message).slice(0, 3000),
  ];
  if (alert.chain && alert.address)
    lines.push(`<code>${escapeHtml(alert.chain)}:${escapeHtml(alert.address)}</code>`);
  if (dashboardUrl && alert.address)
    lines.push(`${escapeHtml(dashboardUrl)}/tokens/${encodeURIComponent(alert.address)}`);
  lines.push(`<i>${alert.type} · ${alert.createdAt}</i>`);
  return lines.join('\n');
}

/** Telegram Bot API: POST /bot<token>/sendMessage. The token lives in the URL path and is scrubbed from logs. */
export class TelegramNotifier implements Notifier {
  readonly name = 'telegram';

  constructor(
    private readonly http: HttpClient,
    private readonly botToken: string,
    private readonly chatId: string,
    private readonly dashboardUrl: string | null = null,
  ) {}

  async send(alert: Alert): Promise<void> {
    await this.http.post(`/bot${this.botToken}/sendMessage`, {
      chat_id: this.chatId,
      text: formatTelegram(alert, this.dashboardUrl),
      parse_mode: 'HTML',
      disable_web_page_preview: true,
    });
  }
}

export function formatDiscord(alert: Alert): Record<string, unknown> {
  const fields: { name: string; value: string; inline: boolean }[] = [];
  if (alert.chain) fields.push({ name: 'Chain', value: alert.chain, inline: true });
  if (alert.address) fields.push({ name: 'Token', value: `\`${alert.address}\``, inline: false });
  for (const [k, v] of Object.entries(alert.data).slice(0, 6)) {
    if (v === null || typeof v === 'object') continue;
    fields.push({ name: k, value: String(v).slice(0, 200), inline: true });
  }
  return {
    username: 'MemeGuard',
    embeds: [
      {
        title:
          `${SEVERITY_ICON[alert.severity]} ${alert.title}${alert.symbol ? ` — ${alert.symbol}` : ''}`.slice(
            0,
            256,
          ),
        description: alert.message.slice(0, 4000),
        color: SEVERITY_COLOR[alert.severity],
        fields,
        footer: { text: alert.type },
        timestamp: alert.createdAt,
      },
    ],
    allowed_mentions: { parse: [] },
  };
}

/** Discord incoming webhook (the webhook URL is a secret and is scrubbed from logs). */
export class DiscordNotifier implements Notifier {
  readonly name = 'discord';

  constructor(private readonly http: HttpClient) {}

  async send(alert: Alert): Promise<void> {
    await this.http.post('', formatDiscord(alert));
  }
}
