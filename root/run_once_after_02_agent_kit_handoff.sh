#!/bin/bash
set -euo pipefail

if [ -z "${HOME:-}" ] || [ "$HOME" = "/" ]; then
  echo "HOME is missing or unsafe; refusing agent-kit handoff" >&2
  exit 1
fi

copilot_dir="${HOME}/.copilot"
agents_skills_dir="${HOME}/.agents/skills"

if [ -L "${copilot_dir}" ]; then
  echo "Refusing to migrate through a symlinked .copilot directory" >&2
  exit 1
fi

if [ -L "${HOME}/.agents" ] || [ -L "${agents_skills_dir}" ]; then
  echo "Refusing to migrate through a symlinked .agents skills directory" >&2
  exit 1
fi

legacy_extensions=(
  agent-status
  app-environment-lookup
)

legacy_agents=(
  implementation-runner.agent.md
  workflow-runner.agent.md
)

legacy_copilot_skills=(
  compare-engineering-options
  glb-queue-timeout-investigator
  graph-hopper-service-investigator
  graphql-api-utilization-investigator
  graphql-availability-investigator
  graphql-low-traffic-investigator
  graphql-opaque-alert-investigator
  graphql-review-queue
  grilling
  internal-secondary-rate-limit-mitigator
  lowprio-api-uptime-incident-investigator
  luna-run
  unicorn-utilization-incident-investigator
)

legacy_agents_skills=(
  crabbox
  crabbox-patch-sync
  plannotator
  plannotator-annotate
  plannotator-compound
  plannotator-inbox
  plannotator-last
  plannotator-review
  plannotator-setup-goal
  plannotator-visual-explainer
  scrawl
)

if [ -d "${copilot_dir}/extensions" ] && [ ! -L "${copilot_dir}/extensions" ]; then
  for entry in "${legacy_extensions[@]}"; do
    target_path="${copilot_dir}/extensions/${entry}"
    if [ -d "${target_path}" ] && [ ! -L "${target_path}" ]; then
      rm -rf -- "${target_path}"
    fi
  done
fi

if [ -d "${copilot_dir}/agents" ] && [ ! -L "${copilot_dir}/agents" ]; then
  for entry in "${legacy_agents[@]}"; do
    target_path="${copilot_dir}/agents/${entry}"
    if [ -f "${target_path}" ] && [ ! -L "${target_path}" ]; then
      rm -f -- "${target_path}"
    fi
  done
fi

if [ -d "${copilot_dir}/skills" ] && [ ! -L "${copilot_dir}/skills" ]; then
  for entry in "${legacy_copilot_skills[@]}"; do
    target_path="${copilot_dir}/skills/${entry}"
    if [ -d "${target_path}" ] && [ ! -L "${target_path}" ]; then
      rm -rf -- "${target_path}"
    fi
  done
fi

if [ -d "${agents_skills_dir}" ]; then
  for entry in "${legacy_agents_skills[@]}"; do
    target_path="${agents_skills_dir}/${entry}"
    if [ -d "${target_path}" ] && [ ! -L "${target_path}" ]; then
      rm -rf -- "${target_path}"
    fi
  done
fi
