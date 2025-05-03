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
  # Add triggers to ensure it runs when needed
  triggers = {
    collaborator_name = var.collaborator_name
    new_alias_id = var.new_alias_id
    timestamp = timestamp()  # Force run every time
  }

  provisioner "local-exec" {
    command = <<-EOF
      #!/bin/bash
      set -e  # Exit on error
      
      echo "Starting disassociation process for ${var.collaborator_name}..."
      
      # Get current collaborator ID
      CURRENT_COLLAB=$(aws bedrock-agent list-agent-collaborators \
        --agent-id ${var.supervisor_id} \
        --agent-version "DRAFT" \
        --query "agentCollaboratorSummaries[?collaboratorName=='${var.collaborator_name}'].collaboratorId" \
        --output text)
      
      if [ ! -z "$CURRENT_COLLAB" ]; then
        echo "Found existing collaborator: $CURRENT_COLLAB"
        
        # Disassociate
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
          --query "agentCollaboratorSummaries[?collaboratorName=='${var.collaborator_name}'].collaboratorId" \
          --output text)
        
        if [ ! -z "$VERIFY" ]; then
          echo "Error: Collaborator still exists after disassociation"
          exit 1
        else
          echo "Successfully disassociated collaborator"
        fi
      else
        echo "No existing association found for ${var.collaborator_name}"
      fi
    EOF
    interpreter = ["/bin/bash", "-c"]
  }
}


# Wait after disassociation
resource "time_sleep" "wait_after_disassociate" {
  create_duration = "30s"
  depends_on = [null_resource.disassociate_collaborator]
}

# Collaborator 1
resource "aws_bedrockagent_agent_collaborator" "collaborator_1" {
  count = var.collaborator_name == "my-agent-collaborator-1" ? 1 : 0

  agent_id                   = var.supervisor_id
  agent_version              = "DRAFT"
  collaboration_instruction  = "You are collaborator 1. Do what the supervisor tells you to do"
  collaborator_name          = "my-agent-collaborator-1"
  relay_conversation_history = "TO_COLLABORATOR"
  prepare_agent              = false

  agent_descriptor {
    alias_arn = "arn:aws:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:agent-alias/${var.collaborator_id}/${var.new_alias_id}"
  }

  depends_on = [null_resource.disassociate_collaborator]
}

# Collaborator 2
resource "aws_bedrockagent_agent_collaborator" "collaborator_2" {
  count = var.collaborator_name == "my-agent-collaborator-2" ? 1 : 0

  agent_id                   = var.supervisor_id
  agent_version              = "DRAFT"
  collaboration_instruction  = "You are collaborator 2. Do what the supervisor tells you to do"
  collaborator_name          = "my-agent-collaborator-2"
  relay_conversation_history = "TO_COLLABORATOR"
  prepare_agent              = false

  agent_descriptor {
    alias_arn = "arn:aws:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:agent-alias/${var.collaborator_id}/${var.new_alias_id}"
  }

  depends_on = [null_resource.disassociate_collaborator]
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
