import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { Writable } from 'node:stream';
import pino from 'pino';
import { REDACT_PATHS, type SecretRedactor } from './redact';

export type Logger = pino.Logger;

export interface LoggerOptions {
  level: string;
  file?: string | null;
  pretty?: boolean;
  redactor: SecretRedactor;
  /** Test hook: capture every (already scrubbed) line. */
  sink?: (line: string) => void;
}

/**
 * Structured JSON logger. Two independent layers keep secrets out of logs:
 *  1. key-path redaction (e.g. any `privateKey`, `authorization`, `apiKey` field), and
 *  2. value scrubbing of every configured secret right before the line hits a sink.
 */
export function createLogger(opts: LoggerOptions): Logger {
  const streams: pino.StreamEntry[] = [];

  const scrubbing = (target: (line: string) => void): Writable =>
    new Writable({
      write(chunk: Buffer | string, _enc, cb) {
        try {
          target(opts.redactor.scrub(chunk.toString()));
          cb();
        } catch (err) {
          cb(err as Error);
        }
      },
    });

  if (opts.sink) {
    streams.push({ level: opts.level as pino.Level, stream: scrubbing(opts.sink) });
  } else if (opts.pretty) {
    // pino-pretty is a dev dependency; load lazily and fall back to JSON when absent.
    let prettyStream: NodeJS.WritableStream | null;
    try {
      const req = createRequire(import.meta.url);
      const pretty = req('pino-pretty') as (o: object) => NodeJS.WritableStream;
      prettyStream = pretty({ colorize: true, translateTime: 'SYS:HH:MM:ss.l' });
    } catch {
      prettyStream = null;
    }
    const out = prettyStream ?? process.stdout;
    streams.push({ level: opts.level as pino.Level, stream: scrubbing((l) => out.write(l)) });
  } else {
    streams.push({ level: opts.level as pino.Level, stream: scrubbing((l) => process.stdout.write(l)) });
  }

  if (opts.file) {
    fs.mkdirSync(path.dirname(path.resolve(opts.file)), { recursive: true });
    const fileStream = pino.destination({ dest: opts.file, sync: false, mkdir: true });
    streams.push({ level: opts.level as pino.Level, stream: scrubbing((l) => fileStream.write(l)) });
  }

  return pino(
    {
      level: opts.level,
      base: { service: 'memeguard' },
      timestamp: pino.stdTimeFunctions.isoTime,
      redact: { paths: REDACT_PATHS, censor: '[REDACTED]' },
      serializers: { err: pino.stdSerializers.err, error: pino.stdSerializers.err },
      formatters: { level: (label) => ({ level: label }) },
    },
    pino.multistream(streams),
  );
}

/** A silent logger for tests and library usage. */
export function createNullLogger(): Logger {
  return pino({ level: 'silent' });
}
