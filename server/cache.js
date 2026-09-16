const Redis = require('ioredis');

const redis = new Redis({
  host: process.env.REDIS_HOST,
  port: Number(process.env.REDIS_PORT || 6379),
  password: process.env.REDIS_PASSWORD || undefined,
  lazyConnect: false,
  maxRetriesPerRequest: 2,
  retryStrategy: (times) => Math.min(times * 200, 2000),
});

redis.on('error', (err) => {
  console.error('[redis] connection error:', err.message);
});

module.exports = { redis };
