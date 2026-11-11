-- GPS Tracking & Management System - PostgreSQL schema
-- Run against a fresh database: psql gps_tracking -f schema.sql

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DROP TABLE IF EXISTS audit_logs, geofence_events, geofences, locations, trips,
  location_shares, devices, vehicles, app_users CASCADE;

CREATE TABLE app_users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name VARCHAR(150) NOT NULL,
  email VARCHAR(255) UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  role VARCHAR(20) NOT NULL DEFAULT 'user' CHECK (role IN ('admin', 'user')),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE vehicles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  registration_no VARCHAR(40) UNIQUE NOT NULL,
  display_name VARCHAR(150) NOT NULL,
  driver_name VARCHAR(150),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE devices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id VARCHAR(100) UNIQUE NOT NULL,
  device_name VARCHAR(150) NOT NULL,
  vehicle_id UUID REFERENCES vehicles(id) ON DELETE SET NULL,
  assigned_user_id UUID REFERENCES app_users(id) ON DELETE SET NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'offline' CHECK (status IN ('online', 'offline')),
  last_seen_at TIMESTAMPTZ,
  registered_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE locations (
  id BIGSERIAL PRIMARY KEY,
  device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  latitude NUMERIC(10, 7) NOT NULL CHECK (latitude BETWEEN -90 AND 90),
  longitude NUMERIC(10, 7) NOT NULL CHECK (longitude BETWEEN -180 AND 180),
  speed_kph NUMERIC(7, 2) NOT NULL DEFAULT 0 CHECK (speed_kph >= 0),
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_locations_device_time ON locations(device_id, recorded_at DESC);

CREATE TABLE trips (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  started_at TIMESTAMPTZ NOT NULL,
  ended_at TIMESTAMPTZ,
  start_latitude NUMERIC(10, 7),
  start_longitude NUMERIC(10, 7),
  end_latitude NUMERIC(10, 7),
  end_longitude NUMERIC(10, 7),
  distance_km NUMERIC(12, 3) NOT NULL DEFAULT 0
);

CREATE TABLE geofences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(150) NOT NULL,
  latitude NUMERIC(10, 7) NOT NULL,
  longitude NUMERIC(10, 7) NOT NULL,
  radius_m INTEGER NOT NULL CHECK (radius_m > 0),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by UUID REFERENCES app_users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE geofence_events (
  id BIGSERIAL PRIMARY KEY,
  geofence_id UUID NOT NULL REFERENCES geofences(id) ON DELETE CASCADE,
  device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  event_type VARCHAR(10) NOT NULL CHECK (event_type IN ('entry', 'exit')),
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE location_shares (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  can_view_history BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (device_id, user_id)
);

CREATE TABLE audit_logs (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID REFERENCES app_users(id) ON DELETE SET NULL,
  action VARCHAR(100) NOT NULL,
  entity_type VARCHAR(50),
  entity_id TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Development seed data uses valid coordinates in New York and is clearly
-- marked as sample data. Replace it with authorized devices before production.
INSERT INTO vehicles (registration_no, display_name, driver_name) VALUES
  ('NYC-4821', 'Northstar Van', 'Maya Patel'),
  ('NYC-7710', 'Atlas Sedan', 'Ethan Brooks');
INSERT INTO devices (device_id, device_name, vehicle_id, status, last_seen_at)
SELECT 'TRK-1042', 'Northstar tracker', id, 'online', NOW() - INTERVAL '2 minutes'
FROM vehicles WHERE registration_no = 'NYC-4821';
INSERT INTO devices (device_id, device_name, vehicle_id, status, last_seen_at)
SELECT 'TRK-1078', 'Atlas tracker', id, 'offline', NOW() - INTERVAL '2 hours'
FROM vehicles WHERE registration_no = 'NYC-7710';
INSERT INTO locations (device_id, latitude, longitude, speed_kph, recorded_at)
SELECT id, 40.7412, -73.9896, 42.5, NOW() - INTERVAL '2 minutes' FROM devices WHERE device_id = 'TRK-1042';
INSERT INTO locations (device_id, latitude, longitude, speed_kph, recorded_at)
SELECT id, 40.7484, -73.9857, 0, NOW() - INTERVAL '2 hours' FROM devices WHERE device_id = 'TRK-1078';
