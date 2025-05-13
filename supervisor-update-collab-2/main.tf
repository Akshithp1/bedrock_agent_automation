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
    new_alias_id = var.new_alias_id
  }

  provisioner "local-exec" {
    command = <<EOT
      #!/bin/bash
      set -e

      COLLAB_NAME="Colab-2"
      echo "Starting disassociation process for $COLLAB_NAME..."
      
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
      else
        echo "No existing association found for $COLLAB_NAME"
      fi
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

# Associate new alias with supervisor
resource "aws_bedrockagent_agent_collaborator" "new_association" {
  agent_id                   = var.supervisor_id
  agent_version              = "DRAFT"
  collaboration_instruction  = "You are collaborator 2. Do what the supervisor tells you to do"
  collaborator_name          = "Colab-2"
  relay_conversation_history = "DISABLED"
  prepare_agent              = false

  agent_descriptor {
    alias_arn = "arn:aws:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:agent-alias/${var.collaborator_id}/${var.new_alias_id}"
  }

  depends_on = [null_resource.disassociate_collaborator]

  lifecycle {
    create_before_destroy = false
  }
}

# Force replacement trigger
resource "null_resource" "force_replacement" {
  triggers = {
    alias_id = var.new_alias_id
  }

  depends_on = [null_resource.disassociate_collaborator]
}
