# Splunk platform semantics

Read this before you write a `tstats` or `| rest` query.

## `tstats` through MCP

- `by` goes after `where`: `| tstats count where index=os by host`. With `by` before `where`, the search fails.
- `span=` inside a `where` clause fails ("'span' argument is only supported for _time"). Drop it, or use a
  `timechart` pipeline.
- `tstats` must be the first command. For an expression over metadata fields, such as `_indextime-_time`, use
  `| eval … | stats …` instead.

## REST endpoints

- `| rest /services/licenser/pools` reports `used_bytes` for the current day. It resets at midnight; it is not a
  rolling 24 hours and not a running total. A drop at midnight is neither lost data nor a recovery. For a rolling
  24 hours, sum `b` over the last 24 hours of `index=_internal source=*license_usage.log type=Usage`.
- `| rest /services/server/health/splunkd/details` returns one row with nested `features.*.health` fields, such as
  `features.HEC Health.health`. It has no top-level `status` field, so `stats count by status` returns no rows.
  Read the row with `| head 5`, or project the `features.*.health` fields.

## Agent logs

- One logical `hermes:agent` line can arrive more than once: a standard-output copy plus file copies. Raw counts
  run about two to three times the true count. Deduplicate before you count failure signatures:
  `| dedup host _time kind` before `stats`.
