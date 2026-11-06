import type { IncomingMessage, ServerResponse } from 'node:http';
export type Row = Record<string, unknown>;
export interface Database {
    query(sql: string, values?: unknown[]): Promise<{
        rows: Row[];
        changes?: number;
    }>;
    transaction<T>(work: (db: Database) => Promise<T>): Promise<T>;
}
export interface CurrentUser {
    id: string;
    tokenHash: string;
}
export interface ExperienceDependencies {
    database: Database;
    readJson(request: IncomingMessage, maximum?: number): Promise<unknown>;
    respond(response: ServerResponse, status: number, data: unknown): void;
    limit(key: string, maximum: number): Promise<void>;
    usersByIds(ids: string[], viewer: string, db?: Database): Promise<Map<string, Row>>;
    getPost(id: string, viewer: string): Promise<unknown>;
    invalidateSession(hash: string): void;
    afterRevoke(): Promise<void>;
}
export interface SessionView {
    id: string;
    label: string;
    platform: string;
    createdAt: string;
    lastSeenAt: string;
    expiresAt: string;
    current: boolean;
}
export interface ClientMetric {
    kind: 'flutter_error' | 'api_latency' | 'slow_frame';
    area: 'ui' | 'chat' | 'feed' | 'games' | 'calling' | 'live';
    bucket: number;
    count: number;
    build: number;
}
