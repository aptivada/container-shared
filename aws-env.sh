#!/bin/bash

get_env_vars_by_path() {
    # Get environment parameters from AWS Parameter Store.
    # Returns KEY1 "val1"\n KEY2 "val2"\n
    local path=$1
    local env_vars=$(
        aws ssm get-parameters-by-path --path $path \
            --region us-west-2 \
            --recursive \
            --with-decryption \
            --output text \
        | sed "s|.*$path/||g" \
        | awk '{ print $1 " " "\""$3"\""; }'
    )
    echo "$env_vars"
}

environment=$1
service=$2

global=$(get_env_vars_by_path /ecs/global)
shared=$(get_env_vars_by_path /ecs/shared/$environment)
service=$(get_env_vars_by_path /ecs/$service/$environment)

echo "$global"
echo "$shared"
echo "$service"
