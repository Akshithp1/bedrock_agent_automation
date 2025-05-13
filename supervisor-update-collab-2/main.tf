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
    timestamp = timestamp()  # Force run every time
  }

  provisioner "local-exec" {
    command = <<EOT
      #!/bin/bash
      set -e

      COLLAB_NAME="Colab-2"
      echo "Starting disassociation process for $COLLAB_NAME..."
      
      # List current state
      echo "Current collaborators before disassociation:"
      aws bedrock-agent list-agent-collaborators \
        --agent-id ${var.supervisor_id} \
        --agent-version "DRAFT"
      
      # Get current collaborator by name
      CURRENT_COLLAB=$(aws bedrock-agent list-agent-collaborators \
        --agent-id ${var.supervisor_id} \
        --agent-version "DRAFT" \
        --query "agentCollaboratorSummaries[?collaboratorName=='$COLLAB_NAME'].collaboratorId" \
        --output text)
      
      if [ ! -z "$CURRENT_COLLAB" ]; then
        echo "Found existing collaborator: $CURRENT_COLLAB"
        
        # Try disassociation with retries
        MAX_RETRIES=3
        for i in $(seq 1 $MAX_RETRIES); do
          echo "Attempt $i to disassociate..."
          aws bedrock-agent disassociate-agent-collaborator \
            --agent-id ${var.supervisor_id} \
            --agent-version "DRAFT" \
            --collaborator-id $CURRENT_COLLAB || true
          
          echo "Waiting for disassociation to complete..."
          sleep 30
          
          # Check if still exists
          CHECK=$(aws bedrock-agent list-agent-collaborators \
            --agent-id ${var.supervisor_id} \
            --agent-version "DRAFT" \
            --query "agentCollaboratorSummaries[?collaboratorName=='$COLLAB_NAME'].collaboratorId" \
            --output text)
            
          if [ -z "$CHECK" ]; then
            echo "Successfully disassociated"
            break
          fi
          
          if [ $i -eq $MAX_RETRIES ]; then
            echo "Failed to disassociate after $MAX_RETRIES attempts"
            exit 1
          fi
          
          echo "Retrying..."
          sleep 10
        done
      else
        echo "No existing association found for $COLLAB_NAME"
      fi
      
      echo "Current collaborators after disassociation:"
      aws bedrock-agent list-agent-collaborators \
        --agent-id ${var.supervisor_id} \
        --agent-version "DRAFT"
      
      # Final wait to ensure stability
      sleep 10
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

# Associate new alias with supervisor
resource "aws_bedrockagent_agent_collaborator" "new_association" {
  agent_id                   = var.supervisor_id
  agent_version              = "DRAFT"
  collaboration_instruction  = "You are a collaborator. Do what the supervisor tells you to do"
  collaborator_name          = "Colab-2"
  relay_conversation_history = "DISABLED"
  prepare_agent              = false

  agent_descriptor {
    alias_arn = "arn:aws:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:agent-alias/${var.collaborator_id}/${var.new_alias_id}"
  }

  depends_on = [null_resource.disassociate_collaborator]

  # Add lifecycle block to handle recreation
  lifecycle {
    create_before_destroy = true
  }
}
