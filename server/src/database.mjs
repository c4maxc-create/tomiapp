import { readFile } from 'node:fs/promises';
import {portableSchema,postgresSchema,migrateSQLite} from './schema_migrations.mjs';

const schemaUrl = new URL('../schema.sql', import.meta.url);

// Local tests use real SQLite. Hosted builds use persistent PostgreSQL only.
export async function openDatabase({ connectionString, sqliteFile, production = false } = {}) {
  const schema = await readFile(schemaUrl, 'utf8');
  if (connectionString) {
    const { Pool } = await import('pg');
    const url = new URL(connectionString);
    if (!['postgres:', 'postgresql:'].includes(url.protocol)) throw new Error('Invalid database protocol');
    const localTest = !production && ['localhost', '127.0.0.1'].includes(url.hostname);
    // Enforce certificate verification; URL sslmode must not override this.
    for (const key of ['sslmode', 'sslcert', 'sslkey', 'sslrootcert']) url.searchParams.delete(key);
    const pool = new Pool({
      connectionString: url.toString(),
      ssl: localTest ? false : { rejectUnauthorized: true },
      // This service runs short OLTP queries. PostgreSQL JIT can spend over
      // a second compiling the rich profile joins on every live table refresh.
      options: '-c jit=off',
      max: 5,
      connectionTimeoutMillis: 10000,
      statement_timeout: 10000,
      query_timeout: 15000,
    });
    pool.on('error', (error) => console.error('Database connection error:', error.code || error.name));
    try{await pool.query(postgresSchema(schema));}
    catch(error){await pool.end().catch(()=>{});throw error;}
    const adapt = (executor) => async (sql, values = []) => {
      let index = 0;
      const text = sql.replace(/\?/g, () => `$${++index}`);
      const result = await executor.query(text, values);
      return { rows: result.rows, changes: result.rowCount };
    };
    return {
      dialect: 'postgres',
      query: adapt(pool),
      async transaction(work) {
        const client = await pool.connect();
        try {
          await client.query('BEGIN');
          const result = await work({ query: adapt(client) });
          await client.query('COMMIT');
          return result;
        } catch (error) {
          await client.query('ROLLBACK');
          throw error;
        } finally {
          client.release();
        }
      },
      close: () => pool.end(),
    };
  }
  if (production) throw new Error('DATABASE_URL is required in production; local storage is refused.');
  if (!sqliteFile) throw new Error('A database connection or explicit SQLite file is required.');
  const { DatabaseSync } = await import('node:sqlite');
  const db = new DatabaseSync(sqliteFile);
  try{
    db.exec('PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL; PRAGMA busy_timeout = 5000;');
    db.exec(portableSchema(schema));migrateSQLite(db);
  }catch(error){db.close();throw error;}
  let queue = Promise.resolve();
  const serialized = (work) => {
    const result = queue.then(work);
    queue = result.catch(() => {});
    return result;
  };
  const query = async (sql, values = []) => {
    const statement = db.prepare(sql);
    if (statement.columns().length > 0) {
      return { rows: statement.all(...values), changes: 0 };
    }
    return { rows: [], changes: statement.run(...values).changes };
  };
  return {
    dialect: 'sqlite',
    query: (sql, values) => serialized(() => query(sql, values)),
    transaction: (work) => serialized(async () => {
      db.exec('BEGIN IMMEDIATE');
      try {
        const result = await work({ query });
        db.exec('COMMIT');
        return result;
      } catch (error) {
        db.exec('ROLLBACK');
        throw error;
      }
    }),
    close: () => serialized(() => db.close()),
  };
}
