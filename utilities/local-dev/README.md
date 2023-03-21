# Launch a local deployment script developer container

## Prerequisites

- docker or equivalent runtime

## Instructions

1. Create a file with the environment variables that will be passed to the container
    This file needs to be of the following format with no quotes around value and one variable per line.
    ```
    LOCATION=australiaeast
    RESOURCE_GROUP=my-group
    KEY=123456789abcdef
    ```

2. Run the script to pull the image and launch the container
    ```shell
    ./launch-container.sh -e <ENV_FILE> -v <VOL_MOUNT> -i <IMAGE> -d <DOCKER_CMD>
    ```
    where:
        - `<ENV_FILE>` is the path and filename of the file containing the environment variables previously created
        - `<VOL_MOUNT>` is the mount path for a volume to mount into the container in the `/mnt` directory
        - `<IMAGE>` (optional) is the name of the container image to use (default is `mcr.microsoft.com/azure-cli:2.9.1`)
        - `<DOCKER_CMD>` (optional) is the container runtime command (default is `docker`)

