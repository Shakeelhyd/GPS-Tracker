const express = require('express');
const cors = require('cors');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

const trackingRoutes = require('./routes/tracking');

const app = express();
const allowedOrigins = (process.env.CORS_ORIGINS || '*').split(',').map(origin => origin.trim());
app.use(cors({
  origin: (origin, callback) => {
    if (!origin || allowedOrigins.includes('*') || allowedOrigins.includes(origin)) return callback(null, true);
    return callback(new Error('Origin is not allowed'));
  }
}));
app.use(express.json());
app.use('/api/tracking', trackingRoutes);
app.get('/api/health', (req, res) => res.json({ status: 'ok' }));

const PORT = Number(process.env.PORT || 4000);
const HOST = process.env.HOST || '0.0.0.0';
app.listen(PORT, HOST, () => console.log(`GPS API server running on http://${HOST}:${PORT}`));
