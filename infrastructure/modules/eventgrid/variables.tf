# =============================================================================
# EVENT GRID MODULE VARIABLES
# File: infrastructure/modules/eventgrid/variables.tf
# =============================================================================

variable "topic_name" {
  description = "Name for the Event Grid custom topic"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "service_bus_queue_id" {
  description = "Resource ID of the Service Bus queue that receives UserRegistered events"
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
