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

variable "collaborator_name" {
  type        = string
  description = "Name of the collaborator (my-agent-collaborator-1 or my-agent-collaborator-2)"
}

# Disassociate existing collaborator
resource "null_resource" "disassociate_collaborator" {
  triggers = {
    collaborator_name = var.collaborator_name
    new_alias_id = var.new_alias_id
  }

  provisioner "local-exec" {
    command = <<-EOF
      #!/bin/bash
      set -e
      
      echo "Starting disassociation process for ${var.collaborator_name}..."
      
      # Get only the collaborator with exact name match
      CURRENT_COLLAB=$(aws bedrock-agent list-agent-collaborators \
        --agent-id ${var.supervisor_id} \
        --agent-version "DRAFT" \
        --query "agentCollaboratorSummaries[?collaboratorName=='${var.collaborator_name}'].collaboratorId" \
        --output text)
      
      if [ ! -z "$CURRENT_COLLAB" ]; then
        echo "Found existing collaborator with name ${var.collaborator_name}: $CURRENT_COLLAB"
        
        # Disassociate only this specific collaborator
        aws bedrock-agent disassociate-agent-collaborator \
          --agent-id ${var.supervisor_id} \
          --agent-version "DRAFT" \
          --collaborator-id $CURRENT_COLLAB
        
        echo "Waiting for disassociation to complete..."
        sleep 30
      else
        echo "No existing association found for ${var.collaborator_name}"
      fi
    EOF
    interpreter = ["/bin/bash", "-c"]
  }
}

# Separate resources for each collaborator with for_each
resource "aws_bedrockagent_agent_collaborator" "collaborators" {
  for_each = {
    "my-agent-collaborator-1" = var.collaborator_name == "my-agent-collaborator-1"
    "my-agent-collaborator-2" = var.collaborator_name == "my-agent-collaborator-2"
  }

  count = each.value ? 1 : 0

  agent_id                   = var.supervisor_id
  agent_version              = "DRAFT"
  collaboration_instruction  = "You are ${each.key}. Do what the supervisor tells you to do"
  collaborator_name          = each.key
  relay_conversation_history = "TO_COLLABORATOR"
  prepare_agent              = false

  agent_descriptor {
    alias_arn = "arn:aws:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:agent-alias/${var.collaborator_id}/${var.new_alias_id}"
  }

  depends_on = [time_sleep.wait_after_disassociate]
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
