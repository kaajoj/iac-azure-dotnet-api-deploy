# Deploying .NET Web API to Azure with Terraform & GitHub Actions

This project demonstrates how to deploy a .NET Web API application to Microsoft Azure using **Terraform** for infrastructure provisioning and **GitHub Actions** for CI/CD, providing an end-to-end example setup.

## Project Structure

```
.
├── infra/              # Terraform code
├── src/MyWebApp/       # .NET Web API project
└── .github/workflows/  # CI/CD workflows
    ├── infra.yml
    ├── deploy.yml
    └── destroy.yml
```

## Infrastructure/Services overview (via Terraform)

The following Azure services are provisioned:

- **Resource Group**
- **App Service Plan** (Free F1)
- **App Service** (.NET 8.0, app reads connection string from Key Vault)
- **Key Vault** (stores SQL connection string, identity-based access)
- **SQL Server & Database**
- **Application Insights** (with Log Analytics)
- **Log Analytics Workspace**
- **API Management** (routes traffic from `/api/hello` to App Service)

## GitHub Actions CI/CD

### `.github/workflows/infra.yml`

- Deploys all infrastructure using Terraform

### `.github/workflows/deploy.yml`

- Builds and publishes the .NET app
- Deploys it to the Azure Web App
- Tests the `/hello` endpoint after deployment

## Requirements

- Azure Subscription
- GitHub Secrets:
  - `AZURE_CREDENTIALS`: JSON generated via:

      ```bash
      az ad sp create-for-rbac --name "github-deploy" --role contributor --scopes /subscriptions/<your-subscription-id> --sdk-auth
      ```
  - `TF_VAR_subscription_id`: your Azure subscription ID
  
    Example: `12345678-abcd-1234-ef00-0123456789ab`
  - `TF_VAR_sql_admin_password`: password for SQL Server admin user
 
    Example: `MySecureP@ssw0rd!`
  - `TF_VAR_connection_string`: full connection string stored in Key Vault

    Example:
    ```
    Server=tcp:dotnetappdemo-sqlsrv.database.windows.net,1433;
    Initial Catalog=dotnetappdemo-db;
    Persist Security Info=False;
    User ID=sqladminuser;
    Password=MySecureP@ssw0rd!;
    MultipleActiveResultSets=False;
    Encrypt=True;
    TrustServerCertificate=False;
    Connection Timeout=30;
    ```
    > ⚠️ **Make sure to replace** `dotnetappdemo-sqlsrv` and `dotnetappdemo-db` with the actual names used in your `main.tf`:
    >
    > - SQL Server name → from `azurerm_mssql_server.sql_server.name`  
    > - Database name → from `azurerm_mssql_database.sql_db.name`

> These secrets are automatically passed as Terraform variables during execution in GitHub Actions.

<img width="599" height="548" alt="image" src="https://github.com/user-attachments/assets/56c498ad-59d4-441e-b341-9c3a069ecf72" />

## Usage

1. **Clone the repository**.
2. **Set up GitHub Secrets**:
   
    In your repository, go to:
   
    `Settings → Secrets and variables → Actions → New repository secret`

   Add the following secrets:
    - `AZURE_CREDENTIALS` using `az ad sp create-for-rbac` as described above
    - `TF_VAR_subscription_id`
    - `TF_VAR_sql_admin_password`
    - `TF_VAR_connection_string`

3. **Trigger workflows manually** via the **Actions** tab on GitHub:

   - `infra.yml` — provisions infrastructure
   - `deploy.yml` — builds and deploys the application

4. Once deployed, access/test app using the APIs:
- https://dotnetappdemo-web.azurewebsites.net/ (example/demo URL – not an active environment)
- https://dotnetappdemo-web.azurewebsites.net/hello
- https://dotnetappdemo-web.azurewebsites.net/swagger
- https://dotnetappdemo-web.azurewebsites.net/swagger/v1/swagger.json
- https://dotnetappdemo-apim.azure-api.net/api/hello (via API Management)

5. Push to **main** branch to automatically trigger deployment via GitHub Actions (deploy.yml).

## Troubleshooting & Known Issues

### Purging deleted Key Vault secrets (after terraform destroy)

If you destroy infrastructure and get an error like:

> A resource with the ID ".../secrets/ConnectionStrings--DefaultConnection/..." already exists...

Purge it manually:

```bash
az keyvault list-deleted --output table
az keyvault purge --name dotnetappdemokv
```

### Diagnostic Settings conflict

If Terraform fails with:

> A resource with the ID "...apim-diagnostics..." already exists...

List and delete it:

```bash
az monitor diagnostic-settings list --resource ...
az monitor diagnostic-settings delete --name ...
```

Example:
```bash
`az monitor diagnostic-settings list --resource "dotnetappdemo-apim" --resource-group "dotnetappdemo-rg" --resource-type "Microsoft.ApiManagement/service"`

`az monitor diagnostic-settings delete --name apim-monitor-diagnostics --resource "dotnetappdemo-apim" --resource-group "dotnetappdemo-rg" --resource-type "Microsoft.ApiManagement/service"`
```

# Notes
- Resource names are examples; adapt them for your environment.
- The infrastructure is minimal and intended for demo/testing purposes.
- The sample passwords, logins, demo URLs are placeholders and should never be used in production. Use GitHub Secrets to store sensitive values.
