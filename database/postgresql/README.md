# Azure PostgreSQL server

Deploys an Azure PostgreSQL server instance with a private link.

## Resources

Deploys the following resources:
    - Subnet (if not provided)
    - Private DNS Zone
    - Virtual network link for private DNS zone
    - Diagnostics Workspace (if required)
    - Diagnostic Analytics (if required)