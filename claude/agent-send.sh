#!/bin/bash

# 🚀 Inter-agent Message Sending Script

# Agent→tmux target mapping
get_agent_target() {
    case "$1" in
        "issue-manager") echo "multiagent:0.0" ;;
        worker[0-9]|worker[1-9][0-9])
            # For workerN format, extract N and calculate pane number
            local worker_num="${1#worker}"
            echo "multiagent:0.$worker_num"
            ;;
        *) echo "" ;;
    esac
}

show_usage() {
    cat << EOF
🤖 Inter-agent Message Sending

Usage:
  $0 [agent_name] [message]
  $0 --list

Available Agents:
  issue-manager - GitHub Issue Manager
  worker1-N     - Issue Resolution Workers (N up to configured worker count)

Examples:
  $0 issue-manager "Please check GitHub Issues"
  $0 worker1 "Assigned Issue #123"
  $0 worker5 "Issue resolution completed"
EOF
}

# Display agent list
show_agents() {
    echo "📋 Available Agents:"
    echo "=========================="
    echo "  issue-manager → multiagent:0.0  (GitHub Issue Manager)"

    # tmuxセッションから実際のpane数を取得して表示
    if tmux has-session -t multiagent 2>/dev/null; then
        local pane_count=$(tmux list-panes -t multiagent:0 -F "#{pane_index}" | wc -l)
        local worker_count=$((pane_count - 1))

        for ((i=1; i<=worker_count; i++)); do
            printf "  worker%-7s → multiagent:0.%-2s (Issue Resolution Worker #%s)\n" "$i" "$i" "$i"
        done
    else
        echo "  (multiagent session not found - please run setup.sh)"
    fi
}

# Log recording
log_send() {
    local agent="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    mkdir -p logs
    echo "[$timestamp] $agent: SENT - \"$message\"" >> logs/send_log.txt
}

# Send message
send_message() {
    local target="$1"
    local message="$2"

    echo "📤 Sending: $target ← '$message'"

    # Clear Claude Code prompt once
    tmux send-keys -t "$target" C-c
    sleep 0.3

    # Send message
    tmux send-keys -t "$target" "$message"
    sleep 0.1

    # Press Enter
    tmux send-keys -t "$target" C-m
    sleep 0.5
}

# Check target existence
check_target() {
    local target="$1"
    local session_name="${target%%:*}"

    if ! tmux has-session -t "$session_name" 2>/dev/null; then
        echo "❌ Session '$session_name' not found"
        return 1
    fi

    return 0
}

# Main processing
main() {
    if [[ $# -eq 0 ]]; then
        show_usage
        exit 1
    fi

    # --list option
    if [[ "$1" == "--list" ]]; then
        show_agents
        exit 0
    fi

    if [[ $# -lt 2 ]]; then
        show_usage
        exit 1
    fi

    local agent_name="$1"
    local message="$2"

    # Get agent target
    local target
    target=$(get_agent_target "$agent_name")

    if [[ -z "$target" ]]; then
        echo "❌ Error: Unknown agent '$agent_name'"
        echo "Available agents: $0 --list"
        exit 1
    fi

    # Check target
    if ! check_target "$target"; then
        exit 1
    fi

    # Send message
    send_message "$target" "$message"

    # Record log
    log_send "$agent_name" "$message"

    echo "✅ Send completed: $agent_name with '$message'"

    return 0
}

main "$@"
