#!/bin/bash

get_env_vars_by_path() {
    # Get environment parameters from AWS Parameter Store.
    # Returns export KEY1="val1"\n
    local path=$1
    local env_vars=$(
        aws ssm get-parameters-by-path --path $path \
            --region us-west-2 \
            --recursive \
            --with-decryption \
            --output text \
        | sed "s|.*$path/||g" \
        | awk '{ print $1 "=" "\""$3"\""; }'
    )
    echo "$env_vars"
}

set_env_vars() {
    local env_vars=$1

    if [ "$env_vars" == "" ]; then
        exit 1
    fi

    while read -r variable; do
        echo "export $variable"
    done <<< "$env_vars"
}

merge_env_vars() {
    local envs=$@
    local merged=""

    for env in $envs; do
        while read -r variable; do
            local key=$(echo $variable | cut -f1 -d=)
            if ! printenv $key > /dev/null 2>&1; then
                merged="$merged $variable"$'\n'
            fi
        done <<< "$env"
    done
    echo "$merged"
}

main() {
    local environment=$1
    local service=$2

    local shared_constants=$(get_env_vars_by_path /ecs/shared/constants)  # shared across all services and environments.
    local service_constants=$(get_env_vars_by_path /ecs/$service/constants)  # shared across all services and environments.

    local shared_env_vars=$(get_env_vars_by_path /ecs/shared/$environment) # shared across all services within a specific environment.
    local service_env_vars=$(get_env_vars_by_path /ecs/$service/$environment) # scoped to a single service and environment.

    local merged=$(merge_env_vars "$shared_constants" "$service_constants" "$shared_env_vars" "$service_env_vars")
    set_env_vars "$merged"
}

main "$@"