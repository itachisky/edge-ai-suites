#!/bin/bash
# This script is used to list all loaded pipelines in the dlstreamer-pipeline-server
# ------------------------------------------------------------------
# 1. Check if DLSPS server is reachable- status API
# 2. List all loaded pipelines
# ------------------------------------------------------------------

# Default values
SCRIPT_DIR=$(dirname $(readlink -f "$0"))
DEPLOYMENT_TYPE=""                     # Default deployment type (empty for existing flow)
APP_NAME=""                            # Application name (e.g., pdd, pcb)
ENV_FILE="${ENV_FILE:-.env}"           # Default to .env if not set

init() {
    # If APP_NAME is set, override ENV_FILE
    if [[ -n "$APP_NAME" ]]; then
        ENV_FILE=".env.$APP_NAME"
    fi
    
    # load environment variables from specified env file if it exists
    if [[ -f "$SCRIPT_DIR/$ENV_FILE" ]]; then
        export $(grep -v -E '^\s*#' "$SCRIPT_DIR/$ENV_FILE" | sed -e 's/#.*$//' -e '/^\s*$/d' | xargs)
        echo "Environment variables loaded from $SCRIPT_DIR/$ENV_FILE"
    else
        err "No $ENV_FILE file found in $SCRIPT_DIR"
        exit 1
    fi

    # Set the appropriate HOST_IP with port for curl commands based on deployment type
    if [[ "$DEPLOYMENT_TYPE" == "helm" ]]; then
        CURL_HOST_IP="${HOST_IP}:${NGINX_HTTPS_PORT:-30443}"
        echo "Using Helm deployment - curl commands will use: $CURL_HOST_IP"
    else
        CURL_HOST_IP="${HOST_IP}:${NGINX_HTTPS_PORT:-443}"
        echo "Using default deployment - curl commands will use: $CURL_HOST_IP"
    fi
}

list_pipelines() {
    # Initialize the environment
    init
    
    # Check if server is reachable
    response=$(curl -s -k -w "\n%{http_code}" https://$CURL_HOST_IP/api/pipelines/status 2>/dev/null)
    status=$(echo "$response" | tail -n1)
    
    if [[ "$status" -ne 200 ]]; then
        err "Server not reachable at https://$CURL_HOST_IP"
        exit 1
    fi
    
    echo "Server reachable. HTTP Status Code: $status"
    
    # Get loaded pipelines
    response=$(curl -s -k -w "\n%{http_code}" https://$CURL_HOST_IP/api/pipelines)
    body=$(echo "$response" | sed '$d')
    status=$(echo "$response" | tail -n1)
    
    if [[ "$status" -ne 200 ]]; then
        err "Failed to get pipelines (HTTP $status)"
        exit 1
    else
        echo "Loaded pipelines:"
        echo "$body" | python3 -m json.tool 2>/dev/null || echo "$body"
    fi
}

err() {
    echo "ERROR: $*" >&2
}

usage() {
    echo "Usage: $0 [helm] [OPTIONS]"
    echo "Arguments:"
    echo "  helm                            For Helm deployment (uses NGINX_HTTPS_PORT or :30443)"
    echo "Options:"
    echo "  --app <app_name>                Application name (e.g., pdd, pcb) - loads .env.<app_name>"
    echo "  -h, --help                      Show this help message"
    echo ""
    echo "Examples:"
    echo "  Single application:"
    echo "    ./sample_list.sh"
    echo ""
    echo "  Specific application (using --app):"
    echo "    ./sample_list.sh --app pdd"
    echo "    ./sample_list.sh --app pcb"
    echo ""
    echo "  Specific application (using ENV_FILE):"
    echo "    ENV_FILE=.env.pdd ./sample_list.sh"
    echo "    ENV_FILE=.env.pcb ./sample_list.sh"
}

main() {

    # Check for --app argument and set APP_NAME
    args=("$@")
    for i in "${!args[@]}"; do
        if [[ "${args[i]}" == "--app" ]]; then
            if [[ -z "${args[((i + 1))]}" ]]; then
                err "--app requires a non-empty argument."
                usage
                exit 1
            else
                APP_NAME="${args[((i + 1))]}"
                echo "Application: $APP_NAME (using .env.$APP_NAME)"
                # Remove --app and the next argument from the args array
                unset 'args[i]'
                unset 'args[i+1]'
                break
            fi
        fi
    done

    # Reconstruct the arguments from the modified array (removing empty elements)
    filtered_args=()
    for arg in "${args[@]}"; do
        [[ -n "$arg" ]] && filtered_args+=("$arg")
    done
    set -- "${filtered_args[@]}"

    # Check for helm argument and set DEPLOYMENT_TYPE
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

    # Parse remaining arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
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
    done

    # List pipelines for the specified (or default) application
    list_pipelines
}

main "$@"
