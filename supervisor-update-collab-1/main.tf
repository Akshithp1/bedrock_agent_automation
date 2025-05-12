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
      version = "~> 0.9"
    }
  }
  backend "s3" {}
}

provider "aws" {
  region = "us-east-1"
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

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
  triggers = {
    collaborator_id = var.collaborator_id
    new_alias_id = var.new_alias_id
  }

  provisioner "local-exec" {
    command = <<EOT
      #!/bin/bash
      set -e

      COLLAB_NAME="Collab-1"  
      echo "Starting disassociation process for $COLLAB_NAME..."
      
      # Get current collaborator by name
      CURRENT_COLLAB=$(aws bedrock-agent list-agent-collaborators \
        --agent-id ${var.supervisor_id} \
        --agent-version "DRAFT" \
        --query "agentCollaboratorSummaries[?collaboratorName=='$COLLAB_NAME'].collaboratorId" \
        --output text)
      
      if [ ! -z "$CURRENT_COLLAB" ]; then
        echo "Found existing collaborator: $CURRENT_COLLAB"
        aws bedrock-agent disassociate-agent-collaborator \
          --agent-id ${var.supervisor_id} \
          --agent-version "DRAFT" \
          --collaborator-id $CURRENT_COLLAB
        
        echo "Waiting for disassociation to complete..."
        sleep 30
        
        # Verify disassociation
        VERIFY=$(aws bedrock-agent list-agent-collaborators \
          --agent-id ${var.supervisor_id} \
          --agent-version "DRAFT" \
          --query "agentCollaboratorSummaries[?collaboratorName=='$COLLAB_NAME'].collaboratorId" \
          --output text)
          
        if [ ! -z "$VERIFY" ]; then
          echo "Error: Disassociation failed"
          exit 1
        fi
      else
        echo "No existing association found for $COLLAB_NAME"
      fi
      
      echo "Current collaborators:"
      aws bedrock-agent list-agent-collaborators \
        --agent-id ${var.supervisor_id} \
        --agent-version "DRAFT"
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

# Associate new alias with supervisor
resource "aws_bedrockagent_agent_collaborator" "new_association" {
  agent_id                   = var.supervisor_id
  agent_version              = "DRAFT"
  collaboration_instruction  = "You are a collaborator. Do what the supervisor tells you to do"
  collaborator_name          = "Collab-1"
  relay_conversation_history = "DISABLED"
  prepare_agent              = false

  agent_descriptor {
    alias_arn = "arn:aws:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:agent-alias/${var.collaborator_id}/${var.new_alias_id}"
  }

  depends_on = [null_resource.disassociate_collaborator]
}
