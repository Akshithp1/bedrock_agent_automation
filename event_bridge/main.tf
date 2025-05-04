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

variable "collaborator_agent_ids" {
  type        = list(string)
  description = "List of collaborator agent IDs to monitor"
}

# EventBridge Rule
resource "aws_cloudwatch_event_rule" "collaborator_alias_created" {
  name        = "detect-collaborator-alias-creation"
  description = "Detect when a new collaborator agent alias is created"

  event_pattern = jsonencode({
    source      = ["aws.bedrock"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["bedrock.amazonaws.com"]
      eventName   = ["CreateAgentAlias"]
      requestParameters = {
        agentId = var.collaborator_agent_ids
      }
    }
  })
}

output "rule_arn" {
  value = aws_cloudwatch_event_rule.collaborator_alias_created.arn
}
