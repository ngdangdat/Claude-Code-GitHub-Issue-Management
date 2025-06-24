#!/bin/bash

# 🚀 GitHub Issue Management System Environment Setup

set -e  # Stop on error

# Help option handling
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "🤖 GitHub Issue Management System Environment Setup"
    echo "============================================="
    echo ""
    echo "Usage:"
    echo "  $0 [worker_count]"
    echo ""
    echo "Arguments:"
    echo "  worker_count    Number of Workers to create (1-10, default: 3)"
    echo ""
    echo "Environment Variables:"
    echo "  ISSUE_MANAGER_ARGS    Claude arguments for Issue Manager (default: --dangerously-skip-permissions)"
    echo "  WORKER_ARGS           Claude arguments for Workers (default: --dangerously-skip-permissions)"
    echo ""
    echo "Examples:"
    echo "  $0                                                        # Create 3 Workers with default settings"
    echo "  $0 5                                                      # Create 5 Workers"
    echo "  ISSUE_MANAGER_ARGS='' WORKER_ARGS='' $0                   # Run without Claude arguments"
    echo "  ISSUE_MANAGER_ARGS='--model claude-3-5-sonnet-20241022' \\"
    echo "  WORKER_ARGS='--model claude-3-5-sonnet-20241022' $0       # Specify a particular model"
    echo ""
    exit 0
fi

# Worker count setting (default: 3)
WORKER_COUNT=${1:-3}

# Claude arguments setting (obtained from environment variables, default maintains existing behavior)
ISSUE_MANAGER_ARGS=${ISSUE_MANAGER_ARGS:-"--dangerously-skip-permissions"}
WORKER_ARGS=${WORKER_ARGS:-"--dangerously-skip-permissions"}

# Export environment variables (make available within tmux session)
export ISSUE_MANAGER_ARGS
export WORKER_ARGS

# Worker count validity check
if ! [[ "$WORKER_COUNT" =~ ^[1-9][0-9]*$ ]] || [ "$WORKER_COUNT" -gt 10 ]; then
    echo "❌ Error: Worker count must be specified in the range 1-10"
    echo "Usage: $0 [worker_count]"
    echo "Example: $0 3  # Create 3 Workers (default)"
    echo "Example: $0 5  # Create 5 Workers"
    echo "Help: $0 --help"
    exit 1
fi

# Colored log functions
log_info() {
    echo -e "\033[1;32m[INFO]\033[0m $1"
}

log_success() {
    echo -e "\033[1;34m[SUCCESS]\033[0m $1"
}

echo "🤖 GitHub Issue Management System Environment Setup"
echo "============================================="
echo "📊 Configuration: Worker count = $WORKER_COUNT"
echo "🔧 Claude arguments configuration:"
echo "   Issue Manager: ${ISSUE_MANAGER_ARGS:-"(no arguments)"}"
echo "   Workers: ${WORKER_ARGS:-"(no arguments)"}"
echo ""

# STEP 1: Cleanup existing sessions
log_info "🧹 Starting cleanup of existing sessions..."

tmux kill-session -t multiagent 2>/dev/null && log_info "multiagent session deletion completed" || log_info "multiagent session did not exist"

# Clear completion files
mkdir -p ./tmp/worker-status
rm -f ./tmp/worker*_done.txt 2>/dev/null && log_info "Cleared existing completion files" || log_info "Completion files did not exist"
rm -f ./tmp/worker-status/worker*_busy.txt 2>/dev/null && log_info "Cleared existing worker status files" || log_info "Worker status files did not exist"

# Add worktree entry to .gitignore
log_info "Adding worktree entry to .gitignore..."
if [ ! -f ".gitignore" ]; then
    touch .gitignore
    log_info ".gitignore file created"
fi

if ! grep -q "^worktree/$" .gitignore; then
    echo "worktree/" >> .gitignore
    log_info "Added worktree/ to .gitignore"
else
    log_info "worktree/ already exists in .gitignore"
fi

# Execute worktree cleanup
log_info "🧹 Executing worktree cleanup..."
if [ -f "./claude/cleanup-worktrees.sh" ]; then
    ./claude/cleanup-worktrees.sh
    log_info "✅ Worktree cleanup completed"
else
    log_info "⚠️  cleanup-worktrees.sh not found (skipping)"
fi

# Prepare worktree directory
mkdir -p worktree
log_info "Worktree directory created"

log_success "✅ Cleanup completed"
echo ""

# STEP 2: Create multiagent session (dynamic pane count: issue-manager + workers)
TOTAL_PANES=$((WORKER_COUNT + 1))
log_info "📺 Starting multiagent session creation (${TOTAL_PANES} panes: issue-manager + ${WORKER_COUNT} workers)..."

# Create first pane
tmux new-session -d -s multiagent -n "agents"

# Dynamic pane splitting (based on worker count)
if [ "$WORKER_COUNT" -eq 1 ]; then
    # 1 worker: horizontal split
    tmux split-window -h -t "multiagent:0"
elif [ "$WORKER_COUNT" -eq 2 ]; then
    # 2 workers: horizontal split then vertical split on right
    tmux split-window -h -t "multiagent:0"
    tmux select-pane -t "multiagent:0.1"
    tmux split-window -v
elif [ "$WORKER_COUNT" -eq 3 ]; then
    # 3 workers: 2x2 grid
    tmux split-window -h -t "multiagent:0"
    tmux select-pane -t "multiagent:0.0"
    tmux split-window -v
    tmux select-pane -t "multiagent:0.2"
    tmux split-window -v
else
    # 4+ workers: horizontal split then vertical splits on both sides
    tmux split-window -h -t "multiagent:0"

    # Vertical split on left (issue-manager + first worker)
    tmux select-pane -t "multiagent:0.0"
    tmux split-window -v

    # Vertical splits on right (remaining workers)
    tmux select-pane -t "multiagent:0.2"
    for ((i=3; i<=WORKER_COUNT; i++)); do
        tmux split-window -v
    done
fi

# Set pane titles
log_info "Setting pane titles..."

# issue-manager
tmux select-pane -t "multiagent:0.0" -T "issue-manager"

# workers
for ((i=1; i<=WORKER_COUNT; i++)); do
    tmux select-pane -t "multiagent:0.$i" -T "worker$i"
done

# Initial setup for each pane
for ((i=0; i<=WORKER_COUNT; i++)); do
    # Set working directory
    tmux send-keys -t "multiagent:0.$i" "cd $(pwd)" C-m

    # Set Claude argument environment variables for each pane
    tmux send-keys -t "multiagent:0.$i" "export ISSUE_MANAGER_ARGS='${ISSUE_MANAGER_ARGS}'" C-m
    tmux send-keys -t "multiagent:0.$i" "export WORKER_ARGS='${WORKER_ARGS}'" C-m

    # Get pane title
    if [ $i -eq 0 ]; then
        PANE_TITLE="issue-manager"
        # issue-manager: green color
        tmux send-keys -t "multiagent:0.$i" "export PS1='(\[\033[1;32m\]${PANE_TITLE}\[\033[0m\]) \[\033[1;32m\]\w\[\033[0m\]\$ '" C-m
    else
        PANE_TITLE="worker$i"
        # workers: blue color
        tmux send-keys -t "multiagent:0.$i" "export PS1='(\[\033[1;34m\]${PANE_TITLE}\[\033[0m\]) \[\033[1;32m\]\w\[\033[0m\]\$ '" C-m
    fi

    # Welcome message
    tmux send-keys -t "multiagent:0.$i" "echo '=== ${PANE_TITLE} agent ==='" C-m
done

# Start Claude Code (issue-manager only)
log_info "🤖 Starting Claude Code for issue-manager..."
tmux send-keys -t "multiagent:0.0" "claude ${ISSUE_MANAGER_ARGS}" C-m

# Standby messages for workers
for ((i=1; i<=WORKER_COUNT; i++)); do
    tmux send-keys -t "multiagent:0.$i" "echo '=== worker$i waiting ==='" C-m
    tmux send-keys -t "multiagent:0.$i" "echo 'Please wait for assignment from Issue Manager'" C-m
    tmux send-keys -t "multiagent:0.$i" "echo 'Claude will be started automatically when assigned'" C-m
done

# Wait time for Claude startup
sleep 3

log_success "✅ Claude Code startup for issue-manager completed"
log_success "✅ multiagent session creation completed"
echo ""

# STEP 3: Environment verification and display
log_info "🔍 Verifying environment..."

echo ""
echo "📊 Setup Results:"
echo "==================="

# Check tmux sessions
echo "📺 Tmux Sessions:"
tmux list-sessions
echo ""

# Display pane configuration
echo "📋 Pane Configuration:"
echo "  multiagent session (${TOTAL_PANES} panes):"
echo "    Pane 0: issue-manager (GitHub Issue Manager)"
for ((i=1; i<=WORKER_COUNT; i++)); do
    echo "    Pane $i: worker$i       (Issue Resolution Worker #$i)"
done

echo ""
log_success "🎉 GitHub Issue Management System environment setup completed!"
echo ""
echo "📋 Next Steps:"
echo "  1. 🔗 Attach to session:"
echo "     tmux attach-session -t multiagent   # Check GitHub Issue Management System"
echo "     ※ Claude Code is started only in the issue-manager pane"
echo "     ※ Worker Claude will be started automatically when issues are assigned"
echo ""
echo "  2. 📜 Check instructions:"
echo "     Issue Manager: instructions/issue-manager.md"
echo "     worker1-${WORKER_COUNT}: instructions/worker.md"
echo "     System structure: CLAUDE.md"
echo ""
echo "  3. 🎯 Start system: Enter the following message to Issue Manager:"
echo "     \"You are the issue-manager. Please start monitoring GitHub Issues according to the instructions\""
echo ""
echo "  4. 📋 Check GitHub configuration:"
echo "     gh auth status  # Check GitHub CLI authentication"
echo "     gh repo view     # Check repository"