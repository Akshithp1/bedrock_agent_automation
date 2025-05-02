terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source = "hashicorp/null"
      version = "~> 3.0"
    }
    time = {
      source = "hashicorp/time"
      version = "~> 0.9.0"
    }
  }
  
  backend "s3" {}
}

provider "aws" {
  region = "us-east-1"
}

variable "supervisor_id" {
  type = string
}

variable "collaborator_id" {
  type = string
}

variable "new_alias_id" {
  type = string
}

# Disassociate existing collaborator
resource "null_resource" "disassociate_collaborator" {
  provisioner "local-exec" {
    command = <<-EOF
      aws bedrock-agent disassociate-agent-collaborator \
        --agent-id ${var.supervisor_id} \
        --agent-version DRAFT \
        --collaborator-id ${var.collaborator_id}
    EOF
  }
}

# Wait after disassociation
resource "time_sleep" "wait_after_disassociate" {
  create_duration = "30s"
  depends_on = [null_resource.disassociate_collaborator]
}

# Associate new alias with supervisor
resource "aws_bedrockagent_agent_collaborator" "new_association" {
  agent_id                   = var.supervisor_id
  collaboration_instruction  = "You are a collaborator. Do what the supervisor tells you to do"
  collaborator_name          = "my-agent-collaborator-1"
  relay_conversation_history = "TO_COLLABORATOR"
  prepare_agent              = false

  agent_descriptor {
    alias_arn = "arn:aws:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:agent-alias/${var.collaborator_id}/${var.new_alias_id}"
  }

  depends_on = [time_sleep.wait_after_disassociate]
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
