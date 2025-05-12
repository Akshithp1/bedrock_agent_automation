# main.tf

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

variable "collaborator_name" {
  type = string
}

variable "collaborator_1_id" {
  type = string
  default = ""
}

variable "collaborator_2_id" {
  type = string
  default = ""
}

variable "collaborator_1_alias_id" {
  type = string
  default = ""
}

variable "collaborator_2_alias_id" {
  type = string
  default = ""
}

resource "null_resource" "disassociate_collaborator" {
  triggers = {
    collaborator_name = var.collaborator_name
    timestamp = timestamp()
  }

  provisioner "local-exec" {
    command = <<EOT
      #!/bin/bash
      set -e

      echo "Starting disassociation for ${var.collaborator_name}"

      case "${var.collaborator_name}" in
        "my-agent-collaborator-1")
          TARGET_ID=${var.collaborator_1_id}
          ;;
        "my-agent-collaborator-2")
          TARGET_ID=${var.collaborator_2_id}
          ;;
        *)
          echo "Unknown collaborator name"
          exit 1
          ;;
      esac

      COLLAB=$(aws bedrock-agent list-agent-collaborators \
        --agent-id ${var.supervisor_id} \
        --agent-version DRAFT \
        --query "agentCollaboratorSummaries[?contains(agentDescriptor.aliasArn, '\${TARGET_ID}')].collaboratorId" \
        --output text)

      if [ ! -z "$COLLAB" ]; then
        echo "Disassociating $COLLAB"
        aws bedrock-agent disassociate-agent-collaborator \
          --agent-id ${var.supervisor_id} \
          --agent-version DRAFT \
          --collaborator-id $COLLAB
      fi
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

resource "time_sleep" "wait_after_disassociate" {
  create_duration = "30s"
  depends_on = [null_resource.disassociate_collaborator]
}

resource "aws_bedrockagent_agent_collaborator" "collaborator_1" {
  count = var.collaborator_name == "my-agent-collaborator-1" ? 1 : 0

  agent_id                   = var.supervisor_id
  agent_version              = "DRAFT"
  collaboration_instruction  = "You are collaborator 1. Follow supervisor."
  collaborator_name          = "my-agent-collaborator-1"
  relay_conversation_history = "TO_COLLABORATOR"
  prepare_agent              = false

  agent_descriptor {
    alias_arn = "arn:aws:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:agent-alias/${var.collaborator_1_id}/${var.collaborator_1_alias_id}"
  }

  depends_on = [time_sleep.wait_after_disassociate]
}

resource "aws_bedrockagent_agent_collaborator" "collaborator_2" {
  count = var.collaborator_name == "my-agent-collaborator-2" ? 1 : 0

  agent_id                   = var.supervisor_id
  agent_version              = "DRAFT"
  collaboration_instruction  = "You are collaborator 2. Follow supervisor."
  collaborator_name          = "my-agent-collaborator-2"
  relay_conversation_history = "TO_COLLABORATOR"
  prepare_agent              = false

  agent_descriptor {
    alias_arn = "arn:aws:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:agent-alias/${var.collaborator_2_id}/${var.collaborator_2_alias_id}"
  }

  depends_on = [time_sleep.wait_after_disassociate]
}
