const { Pool } = require('pg');

const pool = new Pool({
  host: process.env.PGHOST,
  port: Number(process.env.PGPORT || 5432),
  user: process.env.PGUSER,
  password: process.env.PGPASSWORD,
  database: process.env.PGDATABASE,
  max: 5,
  // Managed Postgres (e.g. Azure Database for PostgreSQL) requires TLS by
  // default and presents a cert not in Node's trust store; self-hosted
  // Postgres on a private subnet (Acronis, AWS RDS default) doesn't need it.
  ssl: process.env.PGSSLMODE === 'require' ? { rejectUnauthorized: false } : false,
});

module.exports = { pool };
