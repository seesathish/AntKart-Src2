# =============================================================================
# DEV EVENT GRID — TERRAGRUNT WIRING
# File: infrastructure/environments/dev/eventgrid/terragrunt.hcl
#
# PURPOSE:
#   Creates the Event Grid custom topic for the dev environment and wires
#   UserRegistered events → Service Bus queue 'user-registered-events'.
#
# TO DEPLOY:
#   cd infrastructure/environments/dev/eventgrid
#   terragrunt init
#   terragrunt plan
#   terragrunt apply
#
# PREREQUISITES:
#   The Service Bus module must have been applied first to create the
#   'user-registered-events' queue (added to the servicebus module in Week 6).
# =============================================================================

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path           = find_in_parent_folders("env.hcl")
  expose         = true
  merge_strategy = "no_merge"
}

terraform {
  source = "../../../modules/eventgrid"
}

dependency "resource_group" {
  config_path = "../resource-group"

  mock_outputs = {
    name     = "mock-rg-antkart-dev-eastus"
    location = "eastus"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "servicebus" {
  config_path = "../servicebus"

  mock_outputs = {
    user_registered_queue_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.ServiceBus/namespaces/mock-sb/queues/user-registered-events"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  topic_name           = "egt-antkart-${include.env.locals.environment}"
  location             = include.env.locals.location
  resource_group_name  = dependency.resource_group.outputs.name
  service_bus_queue_id = dependency.servicebus.outputs.user_registered_queue_id
  tags                 = include.env.locals.common_tags
}
