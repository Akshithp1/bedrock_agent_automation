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

      echo "Starting disassociation process..."
      echo "Attempting to disassociate collaborator ID: Colab-2"
      
      COLLAB=$(aws bedrock-agent list-agent-collaborators \
        --agent-id ${var.supervisor_id} \
        --agent-version DRAFT \
        --query "agentCollaboratorSummaries[?collaboratorName=='Colab-2'].collaboratorId" \
        --output text)

      if [ ! -z "$COLLAB" ]; then
        echo "Found existing collaborator: $COLLAB"
        aws bedrock-agent disassociate-agent-collaborator \
          --agent-id ${var.supervisor_id} \
          --agent-version DRAFT \
          --collaborator-id $COLLAB
        
        echo "Waiting for disassociation to complete..."
        sleep 30
      fi
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
}
