require('dotenv').config();
const path = require('path');
const express = require('express');
const { pool } = require('./db');
const { redis } = require('./cache');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());
app.use(express.static(path.join(__dirname, '..', 'public')));

// Load-balancer / uptime-check target: reports whether both backing
// workloads (db tier, cache tier) are actually reachable, not just that
// the app-server process is up.
app.get('/healthz', async (req, res) => {
  const status = { app: 'ok', db: 'unknown', cache: 'unknown' };
  let healthy = true;

  try {
    await pool.query('SELECT 1');
    status.db = 'ok';
  } catch (err) {
    status.db = `error: ${err.message}`;
    healthy = false;
  }

  try {
    await redis.ping();
    status.cache = 'ok';
  } catch (err) {
    status.cache = `error: ${err.message}`;
    healthy = false;
  }

  res.status(healthy ? 200 : 503).json(status);
});

app.get('/api/messages', async (req, res) => {
  try {
    const { rows } = await pool.query(
      'SELECT id, name, message, created_at FROM messages ORDER BY created_at DESC LIMIT 50'
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: 'db_unavailable', detail: err.message });
  }
});

app.post('/api/messages', async (req, res) => {
  const { name, message } = req.body || {};
  if (typeof name !== 'string' || typeof message !== 'string' || !name.trim() || !message.trim()) {
    return res.status(400).json({ error: 'name and message are required' });
  }
  if (name.length > 80 || message.length > 500) {
    return res.status(400).json({ error: 'name or message too long' });
  }

  try {
    const { rows } = await pool.query(
      'INSERT INTO messages (name, message) VALUES ($1, $2) RETURNING id, name, message, created_at',
      [name.trim(), message.trim()]
    );
    res.status(201).json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'db_unavailable', detail: err.message });
  }
});

// Visit counter lives in the cache tier (Redis), not the database, to
// show a workload that's fast/ephemeral rather than durable.
app.post('/api/visit', async (req, res) => {
  try {
    const count = await redis.incr('visits');
    res.json({ visits: count });
  } catch (err) {
    res.status(500).json({ error: 'cache_unavailable', detail: err.message });
  }
});

app.get('/api/visit', async (req, res) => {
  try {
    const count = await redis.get('visits');
    res.json({ visits: Number(count || 0) });
  } catch (err) {
    res.status(500).json({ error: 'cache_unavailable', detail: err.message });
  }
});

app.listen(PORT, () => {
  console.log(`cloud-lab-app listening on :${PORT}`);
});
