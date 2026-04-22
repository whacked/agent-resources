---
id: adr-0042
status: proposed
date: 2026-04-23
owner: data-platform
tags:
  - analytics
  - streaming
  - metrics
supersedes: adr-0031
---

# Replace Legacy Metrics Pipeline with Event Stream Ingestion

Move from nightly batch metric generation to near-real-time event ingestion to reduce reporting latency and improve operational visibility.

# Background

The current metrics system runs once per night. Internal dashboards lag by up to 24 hours. Operations teams cannot reliably detect same-day anomalies. Several downstream reports depend on stale aggregates, creating manual rechecks during incidents.

# Analysis

The existing batch process is stable but slow. The primary issue is freshness rather than correctness. Replacing the full analytics stack would introduce unnecessary migration risk. A streaming ingestion layer can improve timeliness while preserving current downstream consumers.

# Plan

Implement a lightweight event collector that receives application events continuously, writes them to a durable queue, and updates incremental aggregates every five minutes. Keep the nightly batch process during migration as fallback. Transition dashboards in phases.

# Results

- Define event schemas and validation rules.
- Deploy queue infrastructure in staging.
- Mirror production traffic for comparison testing.
- Run batch and streaming outputs in parallel for two weeks.
- Cut dashboards over to streaming aggregates.
- Keep nightly batch as rollback path for one release cycle.
- Review latency, cost, and data quality after 30 days.
