const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');

const app = express();
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
  max: Number(process.env.PGPOOL_MAX || 5)
});
const allowedOrigins = (process.env.CORS_ORIGINS || '*').split(',').map(value => value.trim());

app.use(cors({
  origin: (origin, callback) => {
    if (!origin || allowedOrigins.includes('*') || allowedOrigins.includes(origin)) return callback(null, true);
    return callback(new Error('Origin is not allowed'));
  }
}));
app.use(express.json({ limit: '100kb' }));

app.get('/api/health', (req, res) => res.json({ status: 'ok' }));

app.get('/api/tracking/summary', async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT
        (SELECT COUNT(*) FROM devices) AS total_devices,
        (SELECT COUNT(*) FROM devices WHERE status = 'online'
          AND last_seen_at > NOW() - INTERVAL '10 minutes') AS online_devices,
        (SELECT COUNT(*) FROM devices WHERE status = 'offline'
          OR last_seen_at <= NOW() - INTERVAL '10 minutes' OR last_seen_at IS NULL) AS offline_devices,
        (SELECT COUNT(*) FROM trips WHERE ended_at IS NULL) AS active_sessions,
        (SELECT COUNT(*) FROM vehicles) AS total_vehicles,
        (SELECT COUNT(*) FROM trips WHERE started_at::date = CURRENT_DATE) AS today_trips,
        (SELECT COALESCE(SUM(distance_km), 0) FROM trips WHERE started_at::date = CURRENT_DATE) AS distance_today
    `);
    res.json(result.rows[0]);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/tracking/devices', async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT d.id, d.device_id, d.device_name, d.status, d.registered_at, d.last_seen_at,
             v.registration_no AS vehicle_number, v.display_name AS vehicle_name,
             v.driver_name, l.latitude, l.longitude, l.speed_kph, l.recorded_at
      FROM devices d
      LEFT JOIN vehicles v ON v.id = d.vehicle_id
      LEFT JOIN LATERAL (
        SELECT latitude, longitude, speed_kph, recorded_at
        FROM locations WHERE device_id = d.id ORDER BY recorded_at DESC LIMIT 1
      ) l ON TRUE
      ORDER BY d.device_name
    `);
    res.json(result.rows);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.post('/api/tracking/locations', async (req, res) => {
  const { device_id, latitude, longitude, speed_kph = 0, recorded_at } = req.body;
  if (!device_id || !Number.isFinite(Number(latitude)) || !Number.isFinite(Number(longitude))) {
    return res.status(400).json({ error: 'device_id, latitude, and longitude are required' });
  }
  try {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const device = await client.query('SELECT id FROM devices WHERE device_id = $1', [device_id]);
      if (!device.rowCount) {
        await client.query('ROLLBACK');
        return res.status(404).json({ error: 'Device not registered' });
      }
      await client.query(
        `INSERT INTO locations (device_id, latitude, longitude, speed_kph, recorded_at)
         VALUES ($1, $2, $3, $4, COALESCE($5::timestamptz, NOW()))`,
        [device.rows[0].id, latitude, longitude, speed_kph, recorded_at || null]
      );
      await client.query(
        `UPDATE devices SET status = 'online', last_seen_at = COALESCE($2::timestamptz, NOW())
         WHERE id = $1`,
        [device.rows[0].id, recorded_at || null]
      );
      await client.query('COMMIT');
      res.status(201).json({ status: 'accepted' });
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/tracking/history/:deviceId', async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT latitude, longitude, speed_kph, recorded_at
       FROM locations WHERE device_id = $1 ORDER BY recorded_at DESC LIMIT 1000`,
      [req.params.deviceId]
    );
    res.json(result.rows);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

const port = Number(process.env.PORT || 8080);
app.listen(port, '0.0.0.0', () => console.log(`GPS API listening on port ${port}`));
