# Bedrock Agent Automation
This repository contains automation for managing AWS Bedrock agent collaborators and their aliases using Terraform and GitHub Actions.

## Repository Structure
bedrock_agent_automation/
├── .github/
│   └── workflows/
│       ├── update-supervisor-collab1.yml
│       └── update-supervisor-collab2.yml
├── event_bridge/
│   ├── main.tf
│   └── terraform.tfvars
├── github_integration/
│   ├── main.tf
│   └── terraform.tfvars
├── supervisor-update-collab-1/
│   └── main.tf
├── supervisor-update-collab-2/
│   └── main.tf
└── README.md

 ### 1. EventBridge Configuration
Located in `event_bridge/`:

-   Monitors creation of new aliases for collaborator agents
-   Separate rules for each collaborator

### 2. GitHub Integration
Located in `github_integration/`:

-   Connects EventBridge to GitHub Actions
-   Manages API destinations and connections
-   Routes events to appropriate workflows

### 3. Supervisor Update Configuration

Located in `supervisor-update-collab-1/` and `supervisor-update-collab-2/`:

-   Manages collaborator associations with supervisor
-   Handles disassociation of old aliases
-   Creates new associations with updated aliases

## Prerequisites

1. GitHub Repository Secrets:
```
AWS_ROLE_ARN              # IAM role ARN for GitHub Actions
TF_STATE_BUCKET           # S3 bucket for Terraform state
SUPERVISOR_ID             # Bedrock supervisor agent ID
COLLABORATOR_1_ID         # First collaborator agent ID
COLLABORATOR_2_ID         # Second collaborator agent ID
```
 
2. GitHub Personal Access Token with:
-   `repo`  scope
-   Stored in AWS Secrets Manager as "github-actions-token"

## Deployment Order
1.  Deploy EventBridge Configuration:
```
cd event_bridge
terraform init
terraform plan
terraform apply
```
2.  Deploy GitHub Integration:
```
cd github_integration
terraform init
terraform plan
terraform apply
```
3.  Push code to GitHub repository to set up workflows

## Usage

Create a new alias for either collaborator:
```
# For Collaborator 1
aws bedrock-agent create-agent-alias \
  --agent-id "COLLABORATOR_1_ID" \
  --agent-alias-name "test-alias-1"

# For Collaborator 2
aws bedrock-agent create-agent-alias \
  --agent-id "COLLABORATOR_2_ID" \
  --agent-alias-name "test-alias-2"
```
The automation will:

1.  Detect new alias creation
2.  Trigger appropriate workflow
3.  Update supervisor's collaborator associations
## Monitoring

1.  Check workflow status:
    
    -   GitHub repository → Actions tab
    -   Filter by workflow name
2.  Verify collaborator associations:
    
    -   AWS Bedrock console
    -   Supervisor agent configuration
    -   List collaborators using AWS CLI:
```
aws bedrock-agent list-agent-collaborators \
  --agent-id SUPERVISOR_ID \
  --agent-version "DRAFT"
```

## Known Issues

-   Intermittent 404 errors during collaborator updates
-   State management challenges with rapid successive updates
-   EventBridge-GitHub integration timing considerations
