# Deploys sterling OMS onto an Azure environment

## Prerequisites

- Azure Red Hat OpenShift (ARO)
- PostgreSQL flexible server


## Database configuration

1. Install the psql client onto a VM in the environment
    1. sudo apt update
    1. sudo apt install -y postgresql-client
2. Set the connection string
    ```shell
    export PSQL_HOST="<postgressql FQDN>"
    export PSQL_PASSWORD="<postgresql admin password>"
    export SCHEMA_NAME="<schema_name>"
    export DB_NAME="<db_name>"
    export CONNECTION_STRING="host=$PSQL_HOST port=5432 dbname=postgres user=azureuser password=$PSQL_PASSWORD sslmode=require"
    ```
    An example host would be,
    <namePrefix>-postgresql.postgres.database.azure.com
3. Create database
    ```shell
    psql -d "host=$PSQL_HOST port=5432 dbname=postgres user=azureuser password=$PSQL_PASSWORD sslmode=require" -c "CREATE DATABASE $DB_NAME"
    ```
4. Create schema
    ```shell
    psql -d "host=$PSQL_HOST port=5432 dbname=$DB_NAME user=azureuser password=$PSQL_PASSWORD sslmode=require" -c "CREATE SCHEMA $SCHEMA_NAME"

## Post deployment confirmation

Once OMS is deployed, you can check the status of the database by connecting to it and listing the created tables in the schema as follows.
    ```shell
    psql -d "host=$PSQL_HOST port=5432 dbname=$DB_NAME user=azureuser password=$PSQL_PASSWORD sslmode=require"

    => \dt <schema_name>.*
    ```

where <schema_name> is the name of the schema you previously created.

For example,
    `\dt oms.yfs*`

To list all databases, `\l oms.*`

Check the logs in the `<instance_name>-data-manager-xxxx` pod. This pod is used to create the database structure in postgres. 

