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

# Verify current state and disassociate if needed
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
      
      # Function to check collaborator state
      check_collaborator() {
        aws bedrock-agent list-agent-collaborators \
          --agent-id ${var.supervisor_id} \
          --agent-version "DRAFT" \
          --query "agentCollaboratorSummaries[?collaboratorName=='$COLLAB_NAME'].collaboratorId" \
          --output text
      }

      # Function to verify disassociation
      verify_disassociation() {
        local max_attempts=5
        local attempt=1
        local sleep_time=10

        while [ $attempt -le $max_attempts ]; do
          echo "Verification attempt $attempt of $max_attempts..."
          local check=$(check_collaborator)
          
          if [ -z "$check" ]; then
            echo "Disassociation verified"
            return 0
          fi
          
          echo "Collaborator still exists, waiting..."
          sleep $sleep_time
          attempt=$((attempt + 1))
        done
        
        echo "Failed to verify disassociation after $max_attempts attempts"
        return 1
      }

      # Main process
      echo "Checking current state..."
      CURRENT_COLLAB=$(check_collaborator)
      
      if [ ! -z "$CURRENT_COLLAB" ]; then
        echo "Found existing collaborator: $CURRENT_COLLAB"
        
        # Try disassociation with retries
        MAX_RETRIES=3
        for i in $(seq 1 $MAX_RETRIES); do
          echo "Disassociation attempt $i of $MAX_RETRIES"
          
          aws bedrock-agent disassociate-agent-collaborator \
            --agent-id ${var.supervisor_id} \
            --agent-version "DRAFT" \
            --collaborator-id $CURRENT_COLLAB || true
          
          echo "Waiting for disassociation to complete..."
          sleep 30
          
          if verify_disassociation; then
            echo "Disassociation successful"
            break
          fi
          
          if [ $i -eq $MAX_RETRIES ]; then
            echo "Failed to disassociate after $MAX_RETRIES attempts"
            exit 1
          fi
        done
      else
        echo "No existing association found for $COLLAB_NAME"
      fi

      # Final verification
      FINAL_CHECK=$(check_collaborator)
      if [ ! -z "$FINAL_CHECK" ]; then
        echo "Error: Collaborator still exists after all attempts"
        exit 1
      fi

      echo "Process completed successfully"
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

# Wait after disassociation
resource "time_sleep" "wait_after_disassociate" {
  depends_on = [null_resource.disassociate_collaborator]
  create_duration = "30s"
}

# Associate new alias with supervisor
resource "aws_bedrockagent_agent_collaborator" "new_association" {
  count = var.new_alias_id != "" ? 1 : 0

  agent_id                   = var.supervisor_id
  agent_version              = "DRAFT"
  collaboration_instruction  = "You are collaborator 2. Do what the supervisor tells you to do"
  collaborator_name          = "Colab-2"
  relay_conversation_history = "DISABLED"
  prepare_agent              = false

  agent_descriptor {
    alias_arn = "arn:aws:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:agent-alias/${var.collaborator_id}/${var.new_alias_id}"
  }

  depends_on = [time_sleep.wait_after_disassociate]
}

# Verify association
resource "null_resource" "verify_association" {
  count = var.new_alias_id != "" ? 1 : 0
  
  triggers = {
    association_id = aws_bedrockagent_agent_collaborator.new_association[0].id
  }

  provisioner "local-exec" {
    command = <<EOT
      #!/bin/bash
      set -e
      
      echo "Verifying association..."
      sleep 10
      
      COLLAB_CHECK=$(aws bedrock-agent list-agent-collaborators \
        --agent-id ${var.supervisor_id} \
        --agent-version "DRAFT" \
        --query "agentCollaboratorSummaries[?contains(agentDescriptor.aliasArn, '${var.new_alias_id}')].collaboratorId" \
        --output text)
        
      if [ -z "$COLLAB_CHECK" ]; then
        echo "Error: New association not found"
        exit 1
      fi
      
      echo "Association verified successfully"
    EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [aws_bedrockagent_agent_collaborator.new_association]
}
