terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

data "azurerm_client_config" "current" {}

locals {
  project_name = "dotnetappdemo"
  location     = "West Europe"
}

resource "azurerm_resource_group" "rg" {
  name     = "${local.project_name}-rg"
  location = local.location
}

resource "azurerm_service_plan" "plan" {
  name                = "${local.project_name}-plan"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  sku_name = "F1"      # <- np. F1, B1, P1v2 itp.
  os_type  = "Windows" # <- "Linux" or "Windows"
}

resource "azurerm_application_insights" "insights" {
  name                = "${local.project_name}-ai"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.log_workspace.id
}

# SQL Server
resource "azurerm_mssql_server" "sql_server" {
  name                         = "${local.project_name}-sqlsrv"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  version                      = "12.0"
  administrator_login          = "sqladminuser"
  administrator_login_password = var.sql_admin_password

  public_network_access_enabled = true
}

# Adding a firewall rule: Allow Azure Services
resource "azurerm_mssql_firewall_rule" "allow_azure_services" {
  name             = "AllowAllAzureServices"
  server_id        = azurerm_mssql_server.sql_server.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_mssql_database" "sql_db" {
  name           = "${local.project_name}-db"
  server_id      = azurerm_mssql_server.sql_server.id
  sku_name       = "Basic"
  collation      = "SQL_Latin1_General_CP1_CI_AS"
  zone_redundant = false
}

# Key Vault
resource "azurerm_key_vault" "vault" {
  name                       = "${local.project_name}kv"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  purge_protection_enabled   = false
  soft_delete_retention_days = 7

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get", "Set", "List", "Delete"
    ]
  }
}

# Secret with connection string
resource "azurerm_key_vault_secret" "sql_connection_string" {
  name         = "ConnectionStrings--DefaultConnection"
  value        = var.connection_string
  key_vault_id = azurerm_key_vault.vault.id
}

# App Service
resource "azurerm_windows_web_app" "webapp" {
  name                = "${local.project_name}-web"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  service_plan_id     = azurerm_service_plan.plan.id

  site_config {
    always_on = false

    application_stack {
      dotnet_version = "v8.0"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  app_settings = {
    "ConnectionStrings__DefaultConnection" = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.sql_connection_string.id})"
    "APPINSIGHTS_INSTRUMENTATIONKEY"       = azurerm_application_insights.insights.instrumentation_key
    "WEBSITE_RUN_FROM_PACKAGE"             = "1"
  }

  logs {
    http_logs {
      file_system {
        retention_in_days = 2
        retention_in_mb   = 100
      }
    }

    application_logs {
      file_system_level = "Information"
    }

    detailed_error_messages = true
    failed_request_tracing  = true
  }

  depends_on = [azurerm_key_vault_secret.sql_connection_string]
}

# Access policy for App Service managed identity / Grant access to App Service to read secrets
resource "azurerm_key_vault_access_policy" "webapp_access" {
  key_vault_id = azurerm_key_vault.vault.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_windows_web_app.webapp.identity[0].principal_id

  secret_permissions = ["Get", "List"]
}

resource "azurerm_api_management" "apim" {
  name                = "${local.project_name}-apim"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  publisher_name      = "Publisher Name"
  publisher_email     = "publisher.email@test.com"

  sku_name = "Consumption_0"

  identity {
    type = "SystemAssigned"
  }

  tags = {
    environment = "demo"
  }
}

resource "azurerm_api_management_api" "hello_api" {
  name                = "hello-api"
  resource_group_name = azurerm_resource_group.rg.name
  api_management_name = azurerm_api_management.apim.name
  revision            = "1"
  display_name        = "Hello API"
  path                = "api"
  protocols           = ["https"]

  service_url = "https://${azurerm_windows_web_app.webapp.default_hostname}"

  subscription_required = false
}

resource "azurerm_api_management_api_operation" "hello_operation" {
  operation_id        = "get-hello"
  api_name            = azurerm_api_management_api.hello_api.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  display_name        = "Get Hello"
  method              = "GET"
  url_template        = "/hello"

  response {
    status_code = 200
    description = "Successful response"
  }

  request {
    description = "Request to hello endpoint"
  }
}

resource "azurerm_api_management_api_policy" "hello_policy" {
  api_name            = azurerm_api_management_api.hello_api.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name

  xml_content = <<XML
<policies>
  <inbound>
    <base />
    <!-- You can add other light policies here, e.g. rate limit -->
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
</policies>
XML
}

resource "azurerm_log_analytics_workspace" "log_workspace" {
  name                = "${local.project_name}-log"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_monitor_diagnostic_setting" "webapp_diag" {
  name                           = "webapp-diagnostics"
  target_resource_id             = azurerm_windows_web_app.webapp.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.log_workspace.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "AppServiceConsoleLogs"
  }

  enabled_log {
    category = "AppServiceAppLogs"
  }

  enabled_log {
    category = "AppServiceHTTPLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
