-- Extensions needed by the application
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Support 3 app replicas × 35 pool + overhead
ALTER SYSTEM SET max_connections = 200;
