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

variable "collaborator_1_id" {
  type        = string
  description = "ID of the first collaborator agent"
}

variable "collaborator_2_id" {
  type        = string
  description = "ID of the second collaborator agent"
}

# EventBridge Rule for Collaborator 1
resource "aws_cloudwatch_event_rule" "collaborator_1_alias_created" {
  name        = "detect-collaborator1-alias-creation"
  description = "Detect when Collaborator 1 creates a new alias"

  event_pattern = jsonencode({
    source      = ["aws.bedrock"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["bedrock.amazonaws.com"]
      eventName   = ["CreateAgentAlias"]
      requestParameters = {
        agentId = [var.collaborator_1_id]
      }
    }
  })
}

# EventBridge Rule for Collaborator 2
resource "aws_cloudwatch_event_rule" "collaborator_2_alias_created" {
  name        = "detect-collaborator2-alias-creation"
  description = "Detect when Collaborator 2 creates a new alias"

  event_pattern = jsonencode({
    source      = ["aws.bedrock"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["bedrock.amazonaws.com"]
      eventName   = ["CreateAgentAlias"]
      requestParameters = {
        agentId = [var.collaborator_2_id]
      }
    }
  })
}

output "rule_1_arn" {
  value = aws_cloudwatch_event_rule.collaborator_1_alias_created.arn
}

output "rule_2_arn" {
  value = aws_cloudwatch_event_rule.collaborator_2_alias_created.arn
}
