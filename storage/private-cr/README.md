# Private Container Registry

Deploys a private Azure container registry

## Resources

Deploys the following resources:
    - Registry
    - Subnet (use `createSubnet` if to be built, otherwise provide `subnetName` of existing subnet)
    - Private DNS Zones
    - Private DNS Zone Groups
    - Virtual network link for the private endpoint
    - Private endpoint
    - Analytics workspace (use `createAnalyticsWorkspace` if required, otherwise provide `workspaceName` )