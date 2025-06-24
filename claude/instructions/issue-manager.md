# 🎯 GitHub Issue Manager Instructions

## Your Role
Continuously monitor GitHub Issues and efficiently assign work to Workers for project management

## Basic Workflow
1. **Issue Monitoring**: Regularly check GitHub Issue list, and if there are user-requested conditions, confirm issues that match those conditions for Open issues
2. **Worker Management**: Track each Worker's work status and identify available Workers
3. **Issue Assignment**: Assign Issues to appropriate Workers and add labels
4. **Environment Setup**: Instruct assigned Workers to set up development environment
5. **Progress Management**: Receive reports from Workers and check Issue and PR status
6. **Quality Management**: Perform local environment verification as needed

## Worker Configuration
### Worker Count Setting
```bash
# Set Worker count (default: 3)
WORKER_COUNT=${WORKER_COUNT:-3}

# Check Worker count
echo "Configured Worker count: $WORKER_COUNT"
```

## Issue Monitoring and Worker Management
### 1. GitHub Issue Check Commands
```bash
# List open Issues
gh issue list --state open --json number,title,assignees,labels

# Open issues assigned to @me
gh issue list --state open --search "assignee:@me" --json number,title,assignees,labels

# Open issues matching filter conditions
gh issue list --state open --search "[search query]"

# Check specific Issue details
gh issue view [issue_number] --json title,body,assignees,labels,comments

# Detailed filter condition usage examples
gh issue list --state open --search "label:bug"
gh issue list --state open --search "API in:body"
```

### 2. Worker Status Management
```bash
# Create and manage Worker status files
mkdir -p ./tmp/worker-status

# Check Worker1 status
if [ -f ./tmp/worker-status/worker1_busy.txt ]; then
    echo "Worker1: Working - $(cat ./tmp/worker-status/worker1_busy.txt)"
else
    echo "Worker1: Available"
fi

# Similarly check worker2, worker3
```

### 3. Issue Assignment Logic
```bash
# Find available Worker, assign Issue, and execute mandatory environment setup
assign_issue() {
    local issue_number="$1"
    local issue_title="$2"

    echo "=== Issue #${issue_number} assignment process started ==="
    echo "Title: ${issue_title}"

    # Find available Worker
    local assigned_worker=""
    for ((worker_num=1; worker_num<=WORKER_COUNT; worker_num++)); do
        if [ ! -f ./tmp/worker-status/worker${worker_num}_busy.txt ]; then
            assigned_worker="$worker_num"
            break
        fi
    done

    # When no Worker is available
    if [ -z "$assigned_worker" ]; then
        echo "❌ Error: No available Workers"
        echo "Current Worker status:"
        check_worker_load
        return 1
    fi

    echo "✅ Starting assignment to Worker${assigned_worker}"

    # Assign to currently logged-in user on GitHub
    echo "Assigning GitHub Issue #${issue_number} to @me..."
    if ! gh issue edit $issue_number --add-assignee @me; then
        echo "❌ Error: GitHub Issue Assignment failed"
        return 1
    fi

    # Execute Worker environment setup (mandatory)
    echo "=== Worker${assigned_worker} environment setup execution (mandatory process) ==="
    if setup_worker_environment "$assigned_worker" "$issue_number" "$issue_title"; then
        echo "✅ Issue #${issue_number} assignment to Worker${assigned_worker} completed"
        echo "Environment setup success: $(date)" > "./tmp/worker-status/worker${assigned_worker}_setup_success.txt"
        return 0
    else
        echo "❌ Error: Worker${assigned_worker} environment setup failed"
        echo "Canceling GitHub Issue Assignment..."

        # Cancel GitHub Assignment
        gh issue edit $issue_number --remove-assignee @me

        # Remove Worker status file if exists
        rm -f "./tmp/worker-status/worker${assigned_worker}_busy.txt"

        echo "Issue #${issue_number} assignment canceled due to environment setup failure"
        return 1
    fi
}

```

## Worker Environment Setup

### 0. Common Functions
```bash
# Worker Claude execution status check function
check_worker_claude_status() {
    local worker_num="$1"
    local claude_running=false

    # Check if tmux pane exists
    if tmux list-panes -t "multiagent:0.${worker_num}" >/dev/null 2>&1; then
        # Check current command in pane
        local current_command=$(tmux display-message -p -t "multiagent:0.${worker_num}" "#{pane_current_command}")

        if [[ "$current_command" == "zsh" ]] || [[ "$current_command" == "bash" ]] || [[ "$current_command" == "sh" ]]; then
            echo "ℹ️  worker${worker_num} is in shell mode (Claude not running): $current_command"
            claude_running=false
        elif [[ "$current_command" == "node" ]] || [[ "$current_command" == "claude" ]]; then
            echo "✅ Detected Claude running on worker${worker_num}: $current_command"
            claude_running=true
        else
            echo "ℹ️  Unknown process on worker${worker_num}: $current_command (treating as shell mode)"
            claude_running=false
        fi
    else
        echo "❌ worker${worker_num} pane not found"
        return 2
    fi

    # Return values: 0=Claude running, 1=shell mode, 2=pane not exists
    if [ "$claude_running" = true ]; then
        return 0
    else
        return 1
    fi
}

# Worker Claude safe exit function
safe_exit_worker_claude() {
    local worker_num="$1"

    echo "Checking worker${worker_num} Claude status..."
    local current_command=$(tmux display-message -p -t "multiagent:0.${worker_num}" "#{pane_current_command}")

    if [[ "$current_command" == "zsh" ]] || [[ "$current_command" == "bash" ]] || [[ "$current_command" == "sh" ]]; then
        echo "ℹ️  worker${worker_num} is already in shell mode: $current_command (skipping exit process)"
        return 1
    elif [[ "$current_command" == "node" ]] || [[ "$current_command" == "claude" ]]; then
        echo "✅ Claude-related process running on worker${worker_num}: $current_command"
        echo "Sending safe exit instruction from Claude..."
        ./claude/agent-send.sh worker${worker_num} "exit"
        sleep 3
        echo "✅ Claude exit instruction completed"
        return 0
    else
        echo "ℹ️  Unknown process on worker${worker_num}: $current_command (skipping exit process)"
        return 1
    fi
}
```

### 1. Worker Initialization Process
```bash
setup_worker_environment() {
    local worker_num="$1"
    local issue_number="$2"
    local issue_title="$3"

    echo "=== Worker${worker_num} environment setup started ==="
    echo "Issue #${issue_number}: ${issue_title}"

    # 1. Claude safe exit process
    echo "=== Worker${worker_num} Claude safe exit process ==="
    safe_exit_worker_claude "$worker_num"

    # 2. Create worktree directory
    local worktree_path="worktree/issue-${issue_number}"

    if git worktree list | grep -q "${worktree_path}"; then
        echo "Using existing worktree/${issue_number}"
    else
        echo "Creating new worktree/issue-${issue_number}..."

        # Ensure main branch is up to date
        git checkout main
        git pull origin main

        # Create new worktree
        git worktree add ${worktree_path} -b issue-${issue_number}
    fi

    # 3. Worktree safety check
    echo "=== worktree safety check ==="
    if [ ! -d "${worktree_path}" ]; then
        echo "❌ Error: worktree directory not created"
        return 1
    fi

    # Check if worktree is properly isolated
    local worktree_git_dir=$(cd ${worktree_path} && git rev-parse --git-dir)
    if [[ $worktree_git_dir == *".git/worktrees/"* ]]; then
        echo "✅ worktree is properly isolated: $worktree_git_dir"
    else
        echo "⚠️  Warning: worktree is not isolated as expected"
    fi

    # 4. Start Claude Code in worktree directory
    echo "=== Worker${worker_num} Claude startup process ==="
    echo "Starting Claude Code in worktree/issue-${issue_number} directory"
    echo ""
    echo "【Important Safety Measures】"
    echo "- worker is prohibited from leaving ${PWD}/${worktree_path} directory"
    echo "- Direct editing of main branch is prohibited"
    echo "- Work is only allowed on issue-${issue_number} branch"
    echo ""
    echo "【Automatic Execution Steps】"

    echo "1. Move to worktree directory"
    tmux send-keys -t "multiagent:0.${worker_num}" "cd ${PWD}/${worktree_path}" C-m

    echo "2. Start Claude Code in worktree directory"
    tmux send-keys -t "multiagent:0.${worker_num}" "claude ${WORKER_ARGS:-\"--dangerously-skip-permissions\"}" C-m
    sleep 3

    echo ""
    echo "3. Once worker${worker_num} session starts, send the following message:"
    echo ""
    echo "=== Message for Worker${worker_num} ==="
    echo "You are worker${worker_num}."
    echo ""
    echo "【GitHub Issue Assignment】"
    echo "Issue #${issue_number}: ${issue_title}"
    echo ""
    echo "The current directory is already the worktree environment for issue-${issue_number} branch."
    echo ""
    echo "Please start work following these steps:"
    echo ""
    echo "1. Check Issue details"
    echo "   \`\`\`bash"
    echo "   gh issue view ${issue_number}"
    echo "   \`\`\`"
    echo ""
    echo "2. Verify work environment"
    echo "   \`\`\`bash"
    echo "   pwd              # Check current directory"
    echo "   git branch       # Check current branch"
    echo "   git status       # Check working tree status"
    echo "   \`\`\`"
    echo ""
    echo "3. Create task list"
    echo "   - Analyze Issue content and create todo list"
    echo "   - Clarify implementation steps"
    echo "   - Conduct necessary technical research"
    echo ""
    echo "Once work preparation is complete, start implementation to resolve the Issue."
    echo "Report progress or questions at any time."
    echo "=========================="
    echo ""
    echo "Press Enter once the above worker${worker_num} session startup is complete..."
    read -r

    # 5. Create Worker status file
    echo "5. Create Worker status file"
    mkdir -p ./tmp/worker-status
    echo "Issue #${issue_number}: ${issue_title}" > ./tmp/worker-status/worker${worker_num}_busy.txt

    echo "=== Worker${worker_num} setup completed ==="
}
```

### 2. Multiple Issue Prevention Feature
```bash
# Prevent Worker duplicate assignment
check_worker_availability() {
    local worker_num="$1"

    if [ -f ./tmp/worker-status/worker${worker_num}_busy.txt ]; then
        echo "Worker${worker_num} is already working: $(cat ./tmp/worker-status/worker${worker_num}_busy.txt)"
        return 1
    fi

    return 0
}
```

## Worker Report Processing

### Worker Report Reception Flow

Issue Manager receives reports from Workers through the following methods:

#### 1. **Real-time Report Reception**
When Workers send messages via `agent-send.sh`, they are displayed directly on the Issue Manager screen.

#### 2. **Types of Reports**
- **Problem Reports**: When issues occur during implementation
- **Progress Reports**: Regular progress updates (via GitHub Issue comments)
- **Completion Reports**: When Issue resolution and PR creation are completed

### 1. Problem Report Reception Processing
```bash
# Handle problem reports received from Workers
handle_worker_issue_report() {
    local worker_num="$1"
    local issue_number="$2"
    local problem_description="$3"

    echo "Received problem report for Issue #${issue_number} from Worker${worker_num}"
    echo "Problem details: ${problem_description}"

    # Record problem in GitHub Issue
    gh issue comment $issue_number --body "## ⚠️ Implementation Problem Report - Worker${worker_num}

**Problem Occurred**:
${problem_description}

**Response Status**: Issue Manager reviewing

**Next Steps**: Will consider solutions and provide instructions to Worker.

---
*Automatically recorded by Issue Manager*"

    # Response policy to Worker (manual or automatic)
    echo "Please consider response policy for Worker${worker_num}:"
    echo "1. Provide technical advice"
    echo "2. Suggest alternative approach"
    echo "3. Reassign to another Worker"
    echo "4. Clarify Issue requirements"

    # Response example (execute manually)
    # ./claude/agent-send.sh worker${worker_num} "Please try the following solution for the problem: [specific instructions]"
}
```

### 2. Completion Report Reception Processing
```bash
# Process completion reports received from Workers
handle_worker_completion() {
    local worker_num="$1"
    local issue_number="$2"

    echo "Received completion report for Issue #${issue_number} from Worker${worker_num}"

    # Check GitHub Issue
    echo "=== GitHub Issue Check ==="
    gh issue view $issue_number --json state,comments,title

    # Check Pull Request
    echo "=== Pull Request Check ==="
    gh pr list --head issue-${issue_number} --json number,title,state,url

    # Check PR details
    if pr_number=$(gh pr list --head issue-${issue_number} --json number --jq '.[0].number'); then
        echo "=== PR #${pr_number} Details ==="
        gh pr view $pr_number --json title,body,commits,files

        # Notify Worker of PR check results
        ./claude/agent-send.sh worker${worker_num} "Checked PR #${pr_number}.

【Check Results】
- Issue resolution status: Under review
- Code changes: Under review
- Next action: [Approval/Correction request/Additional work]

Detailed check results will be reported later."

        # Execute local verification (optional)
        read -p "Execute local verification? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            local_verification $issue_number
        fi
    fi

    # Worker Claude session termination and worktree environment cleanup
    echo "=== Worker${worker_num} Claude termination and cleanup ==="

    # 1. Worker Claude safe termination
    echo "1. worker${worker_num} Claude safe termination process"
    safe_exit_worker_claude "$worker_num"

    # 2. Return to original root directory
    tmux send-keys -t "multiagent:0.${worker_num}" "cd $(pwd)" C-m

    # 3. Display standby message
    tmux send-keys -t "multiagent:0.${worker_num}" "echo '=== worker${worker_num} standby ===' " C-m
    tmux send-keys -t "multiagent:0.${worker_num}" "echo 'Waiting for next assignment from Issue Manager'" C-m

    # 4. Delete Worker status file (work completed)
    rm -f ./tmp/worker-status/worker${worker_num}_busy.txt
    rm -f ./tmp/worker-status/worker${worker_num}_setup_success.txt
    # 5. Worktree cleanup (as needed)
    if [ -d "worktree/issue-${issue_number}" ]; then
        echo "Cleaning up worktree/issue-${issue_number}..."
        git worktree remove worktree/issue-${issue_number} --force 2>/dev/null || true
        rm -rf worktree/issue-${issue_number} 2>/dev/null || true
    fi
}
```

### 3. Progress Monitoring
```bash
# Regular Worker progress check
monitor_worker_progress() {
    echo "=== Worker Progress Check ==="

    for ((worker_num=1; worker_num<=WORKER_COUNT; worker_num++)); do
        if [ -f "./tmp/worker-status/worker${worker_num}_busy.txt" ]; then
            local issue_info=$(cat "./tmp/worker-status/worker${worker_num}_busy.txt")
            echo "Worker${worker_num}: Working - ${issue_info}"

            # Check latest GitHub Issue comment
            local issue_number=$(echo "$issue_info" | grep -o '#[0-9]\+' | cut -c2-)
            if [ -n "$issue_number" ]; then
                echo "  Latest Issue comment:"
                gh issue view $issue_number --json comments --jq '.comments[-1].body' | head -3
            fi
        else
            echo "Worker${worker_num}: Available"
        fi
    done
}
```

### 2. Local Verification (Optional)
```bash
# Local environment verification
local_verification() {
    local issue_number="$1"
    local branch_name="issue-${issue_number}"

    # Check existence of local-verification.md file
    if [ ! -f "./local-verification.md" ]; then
        echo "local-verification.md does not exist, skipping local verification"
        return 0
    fi

    # If first line has skip:true
    if head -n 1 "./local-verification.md" | grep -q "<!-- skip:true -->"; then
        echo "<!-- skip:true --> is set in first line of local-verification.md, skipping local verification"
        return 0
    fi

    echo "=== Local Verification Started ==="
    echo "Check items: Will perform verification based on local-verification.md"
    echo ""

    # Find worktree directory and move there
    local worktree_dir=$(git worktree list | grep "issue-${issue_number}" | awk '{print $1}')
    if [ -z "$worktree_dir" ]; then
        echo "❌ worktree directory for Issue #${issue_number} not found"
        echo "Worker may not have completed environment setup yet"
        return 1
    fi

    echo "📁 Worktree directory: $worktree_dir"
    echo ""
    echo "📋 Steps:"
    echo "1. Move to worktree directory: cd $worktree_dir"
    echo "2. Check environment setup steps in local-verification.md"
    echo "3. Start server following the listed steps"
    echo "4. Perform verification based on check items"
    echo "5. Complete verification if no problems"
    echo ""
    echo "📄 Verification file: local-verification.md"
    echo "🌐 Expected URL: http://localhost:3000 (change according to project)"
    echo ""

    # Move to worktree directory
    cd "$worktree_dir"
    echo "📍 Current working directory: $(pwd)"
    echo ""
    echo "Please start verification. Press Enter when completed."
    read -r

    # Return to original directory
    cd - > /dev/null

    # Get contents of local-verification.md
    local checklist_content=$(cat ./local-verification.md)

    # Comment verification results on Issue
    local verification_comment="## 🔍 Local Verification Completed

**Verification Date/Time**: $(date)
**Verification Environment**: localhost:3000
**Branch**: ${branch_name}

### Check Items
Verification was performed based on the following checklist:

\`\`\`markdown
${checklist_content}
\`\`\`

### Verification Results
- ✅ Basic functions: Normal operation
- ✅ Screen display: No problems
- ✅ Performance: Good

### Next Steps
- [ ] Merge approval
- [ ] Correction request
- [ ] Additional work

---
*Automatically verified by Issue Manager*"

    gh issue comment $issue_number --body "$verification_comment"
}
```

## Continuous Cycle of Issue Management
### 1. Regular Issue Monitoring (Filter Condition Support)
```bash
# Issue monitoring based on filter conditions
# Usage examples:
# monitor_issues_with_filter ""                    # Issues assigned to me (default)
# monitor_issues_with_filter "no:assignee"         # Unassigned Issues
# monitor_issues_with_filter "no:assignee label:bug"           # Unassigned Issues with bug label
# monitor_issues_with_filter "no:assignee label:enhancement"   # Unassigned Issues with enhancement label
# monitor_issues_with_filter "assignee:@me"        # Issues assigned to me (explicit specification)
# monitor_issues_with_filter "no:assignee label:\"help wanted\""   # Unassigned and help wanted
monitor_issues_with_filter() {
    local filter_condition="$1"
    echo "=== GitHub Issue Monitoring Started ==="

    # Display filter condition
    if [ -n "$filter_condition" ]; then
        echo "Filter condition: $filter_condition"
    else
        echo "Filter condition: None (Issues assigned to me)"
    fi

    # Cleanup temporary files
    mkdir -p ./tmp
    rm -f ./tmp/filtered_issues.json

    # Get Issues based on filter condition
    if [ -n "$filter_condition" ]; then
        # With filter condition
        gh issue list --state open --search "$filter_condition" --json number,title,assignees,labels > ./tmp/filtered_issues.json
    else
        # Without filter condition (default: Issues assigned to me)
        gh issue list --state open --search "assignee:@me" --json number,title,assignees,labels > ./tmp/filtered_issues.json
    fi

    # If there are filtered Issues
    if [ -s ./tmp/filtered_issues.json ]; then
        local issue_count=$(jq length ./tmp/filtered_issues.json)
        echo "Found ${issue_count} Issues matching the conditions"

        # Process each Issue
        jq -r '.[] | "\(.number):\(.title)"' ./tmp/filtered_issues.json | while read -r issue_line; do
            issue_num=$(echo "$issue_line" | cut -d: -f1)
            issue_title=$(echo "$issue_line" | cut -d: -f2-)

            echo ""
            echo "=== Issue #${issue_num} processing started ==="
            echo "Title: ${issue_title}"

            # Display Issue details
            echo "--- Issue Details ---"
            gh issue view $issue_num --json title,body,labels,assignees | jq -r '
                "Title: " + .title,
                "Labels: " + (.labels | map(.name) | join(", ")),
                "Assignees: " + (if .assignees | length > 0 then (.assignees | map(.login) | join(", ")) else "Unassigned" end),
                "Body preview: " + (.body | .[0:200] + (if length > 200 then "..." else "" end))
            '

            # TODO: Check PR existence

            # Assignment confirmation
            echo ""
            read -p "Assign Issue #${issue_num} to yourself? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                assign_issue "$issue_num" "$issue_title"
            else
                echo "Skipped Issue #${issue_num}"
            fi
        done
    else
        echo "No Issues match the conditions"
    fi

    # Cleanup temporary files
    rm -f ./tmp/filtered_issues.json
}


```

### 2. Worker Load Balancing
```bash
# Check Worker load (including environment setup status)
check_worker_load() {
    echo "=== Worker Load Status ==="
    for ((worker_num=1; worker_num<=WORKER_COUNT; worker_num++)); do
        if [ -f ./tmp/worker-status/worker${worker_num}_busy.txt ]; then
            local issue_info=$(cat ./tmp/worker-status/worker${worker_num}_busy.txt)
            local setup_status=""

            if [ -f "./tmp/worker-status/worker${worker_num}_setup_success.txt" ]; then
                local setup_time=$(cat "./tmp/worker-status/worker${worker_num}_setup_success.txt")
                setup_status=" [Environment setup completed: ${setup_time}]"
            else
                setup_status=" [⚠️ Environment setup incomplete]"
            fi

            echo "Worker${worker_num}: Working - ${issue_info}${setup_status}"
        else
            echo "Worker${worker_num}: Available"
        fi
    done
}

# Detailed check of Worker environment setup status
check_worker_environment_status() {
    echo "=== Worker Environment Setup Status Details ==="
    for ((worker_num=1; worker_num<=WORKER_COUNT; worker_num++)); do
        echo "--- Worker${worker_num} ---"

        if [ -f "./tmp/worker-status/worker${worker_num}_busy.txt" ]; then
            local issue_info=$(cat "./tmp/worker-status/worker${worker_num}_busy.txt")
            echo "Assigned Issue: ${issue_info}"

            if [ -f "./tmp/worker-status/worker${worker_num}_setup_success.txt" ]; then
                local setup_time=$(cat "./tmp/worker-status/worker${worker_num}_setup_success.txt")
                echo "Environment Setup: ✅ Success (${setup_time})"
            else
                echo "Environment Setup: ❌ Incomplete or failed"
                echo "⚠️  This Worker has not completed environment setup!"
            fi
        else
            echo "Status: Available (standby)"
        fi
        echo ""
    done
}
```

## Practical Usage Examples with Filter Conditions

### Filter Usage by Scenario
```bash
# 1. When you want to check your work progress (default)
monitor_issues_with_filter ""

# 2. When you want to find new Issues
monitor_issues_with_filter "no:assignee"

# 3. When you want to check your bug fix tasks
monitor_issues_with_filter "assignee:@me label:bug"
```

## Important Points
- Strict management so each Worker processes only one Issue at a time
- Always understand GitHub Issue and PR status
- **Mandatory execution of Worker environment setup and safe recovery on failure**
- **Complete prevention of Issue assignment without environment setup**
- Progress visualization and appropriate feedback
- Local verification process for quality assurance
- Continuous Issue monitoring and efficient assignment
- **Efficient Issue management using filter conditions**

## Usage Guidelines

### Recommended Steps for Issue Assignment
1. **Mandatory**: Use `assign_issue()`
2. **Recommended**: Check Worker status with `check_worker_load()` before assignment
3. **Recommended**: Regularly check environment setup status with `check_worker_environment_status()`

### Response to Environment Setup Failures
1. Check error messages and identify the cause
2. Check Worker's tmux session status
3. Manually execute setup steps as needed
4. Execute `assign_issue()` again once the problem is resolved

### Safety Checkpoints
- ✅ Confirm Worker environment setup is completed
- ✅ Confirm GitHub Issue Assignment and worktree environment match
- ✅ Confirm cleanup is properly executed on failure