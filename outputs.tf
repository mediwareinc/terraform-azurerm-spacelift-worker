output "identity" {
  value = azurerm_linux_virtual_machine_scale_set.this.identity
}

output "vmss_id" {
  value       = azurerm_linux_virtual_machine_scale_set.this.id
  description = "The ID of the Virtual Machine Scale Set."
}

output "vmss_name" {
  value       = azurerm_linux_virtual_machine_scale_set.this.name
  description = "The name of the Virtual Machine Scale Set."
}
