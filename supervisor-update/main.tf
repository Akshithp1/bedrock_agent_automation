terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    time = {
      source  = "hashicorp/time"
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

variable "collaborator_name" {
  type        = string
  description = "Name of the collaborator (my-agent-collaborator-1 or my-agent-collaborator-2)"
}

variable "collaborator_1_id" {
  type = string
}

variable "collaborator_1_alias_id" {
  type = string
}

variable "collaborator_2_id" {
  type = string
}

variable "collaborator_2_alias_id" {
  type = string
}

resource "null_resource" "disassociate_collaborator" {
  triggers = {
    timestamp = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOF
      #!/bin/bash
      set -e

      echo "Starting disassociation process for agent ${ var.collaborator_name }..."

      TARGET_ID=""
      if [ "${var.collaborator_name}" = "my-agent-collaborator-1" ]; then
        TARGET_ID="${var.collaborator_1_id}"
      elif [ "${var.collaborator_name}" = "my-agent-collaborator-2" ]; then
        TARGET_ID="${var.collaborator_2_id}"
      fi

      if [ -z "$TARGET_ID" ]; then
        echo "No collaborator ID found for ${var.collaborator_name}"
        exit 0
      fi

      CURRENT_COLLAB=$(aws bedrock-agent list-agent-collaborators \
        --agent-id ${var.supervisor_id} \
        --agent-version "DRAFT" \
        --query "agentCollaboratorSummaries[?contains(agentDescriptor.aliasArn, '$TARGET_ID')].collaboratorId" \
        --output text)

      if [ ! -z "$CURRENT_COLLAB" ]; then
        echo "Disassociating: $CURRENT_COLLAB"
        aws bedrock-agent disassociate-agent-collaborator \
          --agent-id ${var.supervisor_id} \
          --agent-version "DRAFT" \
          --collaborator-id $CURRENT_COLLAB
        sleep 30
      fi
    EOF
    interpreter = ["/bin/bash", "-c"]
  }
}

resource "time_sleep" "wait_after_disassociate" {
  create_duration = "30s"
  depends_on      = [null_resource.disassociate_collaborator]
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_bedrockagent_agent_collaborator" "collaborator_1" {
  count = var.collaborator_name == "my-agent-collaborator-1" ? 1 : 0

  agent_id                   = var.supervisor_id
  agent_version              = "DRAFT"
  collaboration_instruction  = "You are collaborator 1. Do what the supervisor tells you to do."
  collaborator_name          = "my-agent-collaborator-1"
  relay_conversation_history = "TO_COLLABORATOR"
  prepare_agent              = false

  agent_descriptor {
    alias_arn = "arn:aws:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:agent-alias/${var.collaborator_1_id}/${var.collaborator_1_alias_id}"
  }

  depends_on = [null_resource.disassociate_collaborator]
}

resource "aws_bedrockagent_agent_collaborator" "collaborator_2" {
  count = var.collaborator_name == "my-agent-collaborator-2" ? 1 : 0

  agent_id                   = var.supervisor_id
  agent_version              = "DRAFT"
  collaboration_instruction  = "You are collaborator 2. Do what the supervisor tells you to do."
  collaborator_name          = "my-agent-collaborator-2"
  relay_conversation_history = "TO_COLLABORATOR"
  prepare_agent              = false

  agent_descriptor {
    alias_arn = "arn:aws:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:agent-alias/${var.collaborator_2_id}/${var.collaborator_2_alias_id}"
  }

  depends_on = [null_resource.disassociate_collaborator]
}
