#!/bin/bash
# This script is used to get status of all/specific pipeline instances in the dlstreamer-pipeline-server
# ------------------------------------------------------------------
# 1. Based on argument, get status of all or specific pipeline instance(s)
# ------------------------------------------------------------------

# Default values
SCRIPT_DIR=$(dirname $(readlink -f "$0"))
PIPELINE_ROOT="user_defined_pipelines" # Default root directory for pipelines
DEPLOYMENT_TYPE=""                     # Default deployment type (empty for existing flow)
ENV_FILE="${ENV_FILE:-.env}"           # Default to .env if not set

init() {
    # load environment variables from specified env file if it exists
    if [[ -f "$SCRIPT_DIR/$ENV_FILE" ]]; then
        export $(grep -v -E '^\s*#' "$SCRIPT_DIR/$ENV_FILE" | sed -e 's/#.*$//' -e '/^\s*$/d' | xargs)
        echo "Environment variables loaded from $SCRIPT_DIR/$ENV_FILE"
    else
        err "No $ENV_FILE file found in $SCRIPT_DIR"
        exit 1
    fi

    # check if SAMPLE_APP is set
    if [[ -z "$SAMPLE_APP" ]]; then
        err "SAMPLE_APP environment variable is not set."
        exit 1
    else
        echo "Running sample app: $SAMPLE_APP"
    fi
    # check if APP_DIR is set
    if [[ -z "$APP_DIR" ]]; then
        err "APP_DIR environment variable is not set in $ENV_FILE."
        echo "Please run: ENV_FILE=$ENV_FILE ./setup.sh"
        exit 1
    fi
    # check if APP_DIR directory exists
    if [[ ! -d "$APP_DIR" ]]; then
        err "APP_DIR directory $APP_DIR does not exist."
        exit 1
    fi

    # Set the appropriate HOST_IP with port for curl commands based on deployment type
    if [[ "$DEPLOYMENT_TYPE" == "helm" ]]; then
        # For Helm, use NGINX_HTTPS_PORT if set (for multi-instance), otherwise default to 30443
        CURL_HOST_IP="${HOST_IP}:${NGINX_HTTPS_PORT:-30443}"
        echo "Using Helm deployment - curl commands will use: $CURL_HOST_IP"
    else
        CURL_HOST_IP="${HOST_IP}:${NGINX_HTTPS_PORT:-443}"
        echo "Using default deployment - curl commands will use: $CURL_HOST_IP"
    fi
}

get_status_instance() {
    local instance_id="$1"
    echo "Getting status of pipeline instance with ID: $instance_id"
    # Use curl to get the status of the pipeline instance
    response=$(curl -s -k -w "\n%{http_code}" https://$CURL_HOST_IP/api/pipelines/$instance_id/status)

    # Split response and status
    body=$(echo "$response" | sed '$d')
    status=$(echo "$response" | tail -n1)

    if [[ "$status" -ne 200 ]]; then
        err "Failed to get status of pipeline instance with ID '$instance_id'. HTTP Status Code: $status"
        echo "Response body: $body"
        exit 0
    else
        echo "Response body: $body"
    fi
}

get_status_all() {
    init
    response=$(curl -s -k -w "\n%{http_code}" https://$CURL_HOST_IP/api/pipelines/status)
    # Split response and status
    body=$(echo "$response" | sed '$d')
    status=$(echo "$response" | tail -n1)
    if [[ "$status" -ne 200 ]]; then
        err "Failed to get status of dlstreamer-pipeline-server. HTTP Status Code: $status"
        exit 1
    else
        echo "$body"
    fi
}

err() {
    echo "ERROR: $*" >&2
}

usage() {
    echo "Usage: $0 [helm] [-a | --app <app_name>] [--all] [ -i | --id <instance_id> ] [-h | --help]"
    echo "Arguments:"
    echo "  helm                            For Helm deployment (uses NGINX_HTTPS_PORT env var or defaults to :30443)"
    echo "Options:"
    echo "  -a, --app <app_name>            Specify application (pdd, pcb, wpc, wsg) - sets ENV_FILE to .env.<app_name>"
    echo "  --all                           Get status of all pipelines instances (default)"
    echo "  -i, --id <instance_id>          Get status of a specified pipeline instance(s)"
    echo "  -h, --help                      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --app pdd                    # Get status for pallet-defect-detection"
    echo "  ENV_FILE=.env.pdd $0            # Alternative using ENV_FILE"
}

main() {
    # Check for helm argument first and set DEPLOYMENT_TYPE
    args=("$@")
    for i in "${!args[@]}"; do
        if [[ "${args[i]}" == "helm" ]]; then
            DEPLOYMENT_TYPE="helm"
            # Remove helm from the args array
            unset 'args[i]'
            break
        fi
    done

    # Reconstruct the arguments from the modified array (removing empty elements)
    filtered_args=()
    for arg in "${args[@]}"; do
        [[ -n "$arg" ]] && filtered_args+=("$arg")
    done
    set -- "${filtered_args[@]}"

    # Check for --app argument and set ENV_FILE
    while [[ $# -gt 0 ]]; do
        case "$1" in
        -a | --app)
            shift
            if [[ -z "$1" ]]; then
                err "--app requires an app name (e.g., pdd, pcb, wpc, wsg)"
                usage
                exit 1
            fi
            export ENV_FILE=".env.$1"
            echo "Using application config: $ENV_FILE"
            shift
            ;;
        *)
            break
            ;;
        esac
    done

    # If no arguments provided, fetch status of all pipeline instances
    if [[ -z "$1" ]]; then
        get_status_all
        return
    fi

    case "$1" in
    --all)
        echo "Fetching status for all pipeline instances"
        get_status_all
        ;;
    -i | --id)
        # TODO support multiple instance ids
        # Check if the next argument is provided and not empty, and loop through all instance_ids
        shift
        if [[ -z "$1" ]]; then
            err "--id requires a non-empty argument."
            usage
            exit 1
        else
            # loop over all instance ids
            ids="$@"
            init
            for id in $ids; do
                # get status of the pipeline instance with the given id
                echo "Stopping pipeline instance with ID: $id"
                get_status_instance "$id"
            done
        fi
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        err "Invalid option '$1'."
        usage
        exit 1
        ;;
    esac
}

main "$@"
