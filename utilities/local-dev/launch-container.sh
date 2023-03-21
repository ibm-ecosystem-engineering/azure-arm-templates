#!/usr/bin/env bash

CONTAINER_NAME="az-test"
DOCKER_CMD="docker"
DOCKER_IMAGE="mcr.microsoft.com/azure-cli:2.46.0"

displayUsage() {
  echo "Launches and attaches to a container."
  echo
  echo "Usage: $0 -m MODULE_DIR -e ENV_FILE -v MOUNT_PATH [-i IMAGE] [-d DOCKER_CMD]"
  echo " options:"
  echo " v     path to be mounted"
  echo " e     environment file path"
  echo " i     (optional) the container image to be used"
  echo " d     (optional) the docker command to be used"
  echo " h     Print this help"
  echo
}

# Get command line options
while getopts ":m:v:e:i:d:h" option; do
  case $option in
    h) # Display help
      displayUsage
      exit 1;;
    v) # mount path
      MOUNT_PATH=$OPTARG;;
    e) # environment file
      ENV_FILE=$OPTARG;;
    i) # image
      DOCKER_IMAGE=$OPTARG;;
    d) # docker command
      DOCKER_CMD=$OPTARG;;
    \?) # Invalid option
      echo "Error: Invalid option"
      displayUsage
      exit 1;;
  esac
done

# Clean up old container
${DOCKER_CMD} kill ${CONTAINER_NAME} 1> /dev/null 2> /dev/null
${DOCKER_CMD} rm ${CONTAINER_NAME} 1> /dev/null 2> /dev/null

# Pull docker image
echo "Pulling container image: ${DOCKER_IMAGE}"
${DOCKER_CMD} pull "${DOCKER_IMAGE}"

if [[ -n $MOUNT_PATH ]]; then
    if [[ -d $MOUNT_PATH ]]; then
        MOUNT="-v ${MOUNT_PATH}:/mnt"
    else
        echo "ERROR: Request mount $MOUNT_PATH does not exist"
        exit 1
    fi
else
    MOUNT=""
fi

if [[ -n $ENV_FILE ]]; then
    ENV="--env-file ${ENV_FILE}"
else
    ENV=""
fi

# Initialize container
${DOCKER_CMD} run -itd --name ${CONTAINER_NAME} \
  ${MOUNT} ${ENV} -w /workspace \
  ${DOCKER_IMAGE}

# Attach to container
${DOCKER_CMD} attach ${CONTAINER_NAME}