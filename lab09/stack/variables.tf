variable "resource_group_name" {
  description = "Existing resource group created by the bootstrap - the only scope the pipeline can change"
  type        = string
  default     = "rg-lab09"
}

variable "prefix" {
  type    = string
  default = "lab09"
}

variable "tags" {
  type = map(string)
  default = {
    environment = "lab"
    owner       = "az104-practice"
    managed_by  = "terraform-pipeline"
  }
}
