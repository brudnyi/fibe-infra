DO
$do$
BEGIN
   IF NOT EXISTS (
      SELECT FROM pg_catalog.pg_roles WHERE rolname = 'fibe_user'
   ) THEN
      CREATE ROLE fibe_user LOGIN PASSWORD 'change_me';
   END IF;
END
$do$;

DO
$do$
BEGIN
   IF NOT EXISTS (
      SELECT FROM pg_database WHERE datname = 'fibe_db'
   ) THEN
      CREATE DATABASE fibe_db OWNER fibe_user;
   END IF;
END
$do$;
