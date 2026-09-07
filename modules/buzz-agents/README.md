# buzz-agents

Runs Buzz agents headless as systemd services: one Unix user (`buzz-<name>`),
one home under `/srv/agents/<name>` and one `buzz-agent-<name>.service` per
agent. The service runs the `buzz-acp` harness from `packages/buzz` and drives
`claude-agent-acp` (Claude Code) from `llm-agents.nix`, i.e. the same stack
Buzz Desktop spawns locally, minus the desktop.

## Secrets (manual, on purpose)

This repo has no agenix/sops, so secrets are plain root-only EnvironmentFiles
that you create by hand once per agent. A service whose file is missing stays
inactive (`ConditionPathExists`), so a rebuild never fails because of them.

```sh
sudo install -d -m 0750 -o root -g root /var/lib/buzz-agents
sudo install -m 0600 /dev/stdin /var/lib/buzz-agents/pollen.env <<'EOF'
BUZZ_PRIVATE_KEY=<64-char hex agent key from Buzz Desktop managed-agents.json>
BUZZ_AUTH_TAG='["auth","<owner-hex>","","<sig>"]'
# Optional. Without it, log Claude Code in once for this user:
#   sudo -u buzz-pollen -H claude login
ANTHROPIC_API_KEY=sk-ant-...
EOF
sudo systemctl start buzz-agent-pollen
```

The auth tag is single-line JSON; wrap it in single quotes so systemd keeps the
inner double quotes. Export both values from
`~/.local/share/xyz.block.buzz.app/agents/managed-agents.json` on the machine
that currently runs the agent (`private_key`/`auth_tag` fields of that agent's
entry).

## Cut-over checklist

1. Stop the agent in Buzz Desktop first — the same key running twice answers
   twice.
2. Drop the `.env` file, start the unit, watch `journalctl -fu buzz-agent-<name>`.
3. Mention the agent in a channel; it should reply from the new host.

## Where things live

| Path | Purpose |
|------|---------|
| `/srv/agents/<name>/` | the agent's nest (RESEARCH, PLANS, GUIDES, WORK_LOGS, OUTBOX, REPOS, .scratch) |
| `/srv/agents/<name>/.claude/` | Claude Code state and OAuth credentials for that agent |
| `/var/lib/buzz-agents/<name>.env` | secrets (root-only) |
| `journalctl -u buzz-agent-<name>` | harness + agent logs |

Members of group `buzz-agents` can read the nests; add yourself with
`users.users.<you>.extraGroups = [ "buzz-agents" ]` if you want to poke around
without sudo.

## Options

See `options` in `default.nix`. The important knobs are `respondTo`
(`allowlist` by default: owner plus `respondToAllowlist`) and `agents.<name>`
(`displayName`, `systemPrompt`, `model`, `parallelism`, `extraEnvironment`).
