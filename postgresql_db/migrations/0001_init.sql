-- initial migration: create application schema and sample table
CREATE SCHEMA IF NOT EXISTS app_schema;
CREATE TABLE IF NOT EXISTS app_schema.example (
  id serial PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT now()
);
