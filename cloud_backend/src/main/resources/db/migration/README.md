# Flyway migrations

This directory is intentionally free of versioned migrations while every Backend endpoint remains planned.
The first approved persistent feature creates `V1__...sql`; applied migrations are never edited or reordered.

Every migration must document rollout assumptions, use PostgreSQL types deliberately, and include primary keys,
foreign keys, non-null constraints, unique constraints and indexes required for concurrent correctness.
