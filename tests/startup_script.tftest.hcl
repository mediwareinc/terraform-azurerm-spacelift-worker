# The worker script is base64-encoded inside custom_data, which is itself
# base64-encoded, so each assertion decodes both layers with:
#   base64decode(regex("echo \"([^\"]+)\" \\| base64 --decode", base64decode(custom_data))[0])

mock_provider "azurerm" {}
mock_provider "azuread" {}

variables {
  configuration  = "export SPACELIFT_TOKEN=test"
  admin_password = "not-a-real-password"
  subnet_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/virtualNetworks/test-vnet/subnets/test-subnet"
  worker_pool_id = "01TESTPOOL"
  resource_group = {
    name     = "test-rg"
    location = "eastus"
  }
}

run "defaults_poll_to_us_endpoint" {
  command = plan

  assert {
    condition     = strcontains(base64decode(regex("echo \"([^\"]+)\" \\| base64 --decode", base64decode(azurerm_linux_virtual_machine_scale_set.this.custom_data))[0]), "export SPACELIFT_WORKER_COMMS_URL=\"https://app.us.spacelift.io\"")
    error_message = "Workers must poll the US endpoint by default; our account is in the US region (EDO-14974)."
  }

  assert {
    condition     = strcontains(base64decode(regex("echo \"([^\"]+)\" \\| base64 --decode", base64decode(azurerm_linux_virtual_machine_scale_set.this.custom_data))[0]), "export SPACELIFT_WORKER_COMMS_PROTOCOL=\"poll\"")
    error_message = "Workers must default to HTTP long-poll."
  }

  assert {
    condition     = strcontains(base64decode(regex("echo \"([^\"]+)\" \\| base64 --decode", base64decode(azurerm_linux_virtual_machine_scale_set.this.custom_data))[0]), "export SPACELIFT_WORKER_COMMS_URL=\"https://app.us.spacelift.io\"\nexport SPACELIFT_TOKEN=test")
    error_message = "Module comms exports must come before var.configuration so the caller can override them."
  }

  assert {
    condition     = strcontains(base64decode(regex("echo \"([^\"]+)\" \\| base64 --decode", base64decode(azurerm_linux_virtual_machine_scale_set.this.custom_data))[0]), "systemctl start spacelift-launcher")
    error_message = "The launcher must run as a systemd service."
  }

  assert {
    condition     = strcontains(base64decode(regex("echo \"([^\"]+)\" \\| base64 --decode", base64decode(azurerm_linux_virtual_machine_scale_set.this.custom_data))[0]), "spacelift () {(\nset -e")
    error_message = "Setup must run in a subshell with set -e so failures stop it."
  }

  assert {
    condition     = !strcontains(base64decode(regex("echo \"([^\"]+)\" \\| base64 --decode", base64decode(azurerm_linux_virtual_machine_scale_set.this.custom_data))[0]), "if ! spacelift")
    error_message = "Calling setup from an if test disables set -e inside it."
  }

  assert {
    condition     = strcontains(base64decode(regex("echo \"([^\"]+)\" \\| base64 --decode", base64decode(azurerm_linux_virtual_machine_scale_set.this.custom_data))[0]), "ExecStopPost=+/bin/sh -c 'systemctl is-system-running | grep -q stopping || { sleep 15; reboot; }'")
    error_message = "The default Reboot behavior must reboot the VM after the launcher stops, but not while the VM is shutting down (Azure waits ~10 minutes, then hard-resets)."
  }

  assert {
    condition     = !strcontains(regex("ExecStopPost=[^\n]*", base64decode(regex("echo \"([^\"]+)\" \\| base64 --decode", base64decode(azurerm_linux_virtual_machine_scale_set.this.custom_data))[0])), "$")
    error_message = "ExecStopPost must not contain $: bash expands it when writing the unit and systemd expands it again."
  }

  assert {
    condition     = azurerm_linux_virtual_machine_scale_set.this.os_disk[0].storage_account_type == "StandardSSD_LRS"
    error_message = "The OS disk default must be StandardSSD_LRS (Standard HDD OS disks retire 2028-09-08). Changing storage_account_type replaces the scale set."
  }

  assert {
    condition     = azurerm_linux_virtual_machine_scale_set.this.upgrade_mode == "Rolling"
    error_message = "The scale set must keep the rolling upgrade mode."
  }

  assert {
    condition     = azurerm_linux_virtual_machine_scale_set.this.name == "sp5ft"
    error_message = "The scale set name must stay name_prefix, without the worker pool ID."
  }
}

run "process_exit_none" {
  command = plan

  variables {
    process_exit_behavior = "None"
  }

  assert {
    condition     = !strcontains(base64decode(regex("echo \"([^\"]+)\" \\| base64 --decode", base64decode(azurerm_linux_virtual_machine_scale_set.this.custom_data))[0]), "ExecStopPost")
    error_message = "process_exit_behavior None must not add an ExecStopPost."
  }

  assert {
    condition     = strcontains(base64decode(regex("echo \"([^\"]+)\" \\| base64 --decode", base64decode(azurerm_linux_virtual_machine_scale_set.this.custom_data))[0]), "if [ $setupStatus -ne 0 ]; then\n  echo \"Spacelift setup failed with status $setupStatus\" >> /var/log/spacelift/error.log\n\nfi")
    error_message = "The setup failure branch must still have a command when process_exit_behavior is None."
  }
}

run "process_exit_shutdown" {
  command = plan

  variables {
    process_exit_behavior = "Shutdown"
  }

  assert {
    condition     = strcontains(base64decode(regex("echo \"([^\"]+)\" \\| base64 --decode", base64decode(azurerm_linux_virtual_machine_scale_set.this.custom_data))[0]), "ExecStopPost=+/bin/sh -c 'systemctl is-system-running | grep -q stopping || { sleep 15; poweroff; }'")
    error_message = "Shutdown behavior must power off the VM after the launcher stops."
  }
}

run "mqtt_omits_url" {
  command = plan

  variables {
    worker_comms_protocol = "mqtt"
    worker_comms_url      = null
  }

  assert {
    condition     = strcontains(base64decode(regex("echo \"([^\"]+)\" \\| base64 --decode", base64decode(azurerm_linux_virtual_machine_scale_set.this.custom_data))[0]), "export SPACELIFT_WORKER_COMMS_PROTOCOL=\"mqtt\"")
    error_message = "MQTT fallback must export the mqtt protocol."
  }

  assert {
    condition     = !strcontains(base64decode(regex("echo \"([^\"]+)\" \\| base64 --decode", base64decode(azurerm_linux_virtual_machine_scale_set.this.custom_data))[0]), "SPACELIFT_WORKER_COMMS_URL")
    error_message = "MQTT fallback must not export a poll URL."
  }
}

run "poll_without_url_fails" {
  command = plan

  variables {
    worker_comms_url = null
  }

  expect_failures = [azurerm_linux_virtual_machine_scale_set.this]
}

run "invalid_url_fails" {
  command = plan

  variables {
    worker_comms_url = "https://app.us.spacelift.io/some/path"
  }

  expect_failures = [var.worker_comms_url]
}

run "invalid_protocol_fails" {
  command = plan

  variables {
    worker_comms_protocol = "websocket"
  }

  expect_failures = [var.worker_comms_protocol]
}
