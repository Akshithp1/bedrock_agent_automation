terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Get GitHub token
data "aws_secretsmanager_secret" "github_token" {
  name = "github-actions-token"
}

data "aws_secretsmanager_secret_version" "github_token" {
  secret_id = data.aws_secretsmanager_secret.github_token.id
}

# Add variable for role ARN
variable "eventbridge_role_arn" {
  type        = string
  description = "ARN of the IAM role for EventBridge"
}

# GitHub connection
resource "aws_cloudwatch_event_connection" "github" {
  name               = "github-connection"
  authorization_type = "API_KEY"

  auth_parameters {
    api_key {
      key   = "Authorization"
      value = "Bearer ${data.aws_secretsmanager_secret_version.github_token.secret_string}"
    }
  }
}

# GitHub API destination
resource "aws_cloudwatch_event_api_destination" "github" {
  name                               = "github-actions-destination"
  invocation_endpoint               = "https://api.github.com/repos/${var.github_org}/${var.github_repo}/dispatches"
  http_method                       = "POST"
  connection_arn                    = aws_cloudwatch_event_connection.github.arn
  invocation_rate_limit_per_second = 1
}

# Add GitHub target for Collaborator 1
resource "aws_cloudwatch_event_target" "github_actions_collab1" {
  rule      = "detect-collaborator1-alias-creation"
  target_id = "TriggerGitHubActionCollab1"
  arn       = aws_cloudwatch_event_api_destination.github.arn
  role_arn  = var.eventbridge_role_arn

  input_transformer {
    input_paths = {
      agentId  = "$.detail.requestParameters.agentId"
      aliasId  = "$.detail.responseElements.agentAlias.agentAliasId"
    }
    input_template = <<EOF
{
  "event_type": "update_supervisor_collab1",
  "client_payload": {
    "agent_id": <agentId>,
    "new_alias_id": <aliasId>
  }
}
EOF
  }
}

# Add GitHub target for Collaborator 2
resource "aws_cloudwatch_event_target" "github_actions_collab2" {
  rule      = "detect-collaborator2-alias-creation"
  target_id = "TriggerGitHubActionCollab2"
  arn       = aws_cloudwatch_event_api_destination.github.arn
  role_arn  = var.eventbridge_role_arn

  input_transformer {
    input_paths = {
      agentId  = "$.detail.requestParameters.agentId"
      aliasId  = "$.detail.responseElements.agentAlias.agentAliasId"
    }
    input_template = <<EOF
{
  "event_type": "update_supervisor_collab2",
  "client_payload": {
    "agent_id": <agentId>,
    "new_alias_id": <aliasId>
  }
}
EOF
  }
}

variable "github_org" {
  type        = string
  description = "GitHub organization name"
}

variable "github_repo" {
  type        = string
  description = "GitHub repository name"
}

# Add some outputs for verification
output "connection_arn" {
  value = aws_cloudwatch_event_connection.github.arn
}

output "api_destination_arn" {
  value = aws_cloudwatch_event_api_destination.github.arn
}
