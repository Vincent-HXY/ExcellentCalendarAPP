#!/bin/bash
curl -X POST http://localhost:8080/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: test-200" \
  -d @/root/register.json
