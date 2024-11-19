#!/bin/sh
# SPDX-License-Identifier: MIT

# Copy the contents of .envrc.example to .envrc
cd script/berps
cp .envrc.example .envrc
cp /app/dependency/values.yaml /app/contracts/script/berps/dependency/values.yaml

# Loop through each line in the .envrc file
while IFS= read -r line || [ -n "$line" ]; do
    if [ -n "$line" ] && [ "${line#\#}" = "$line" ]; then
        # Extract the key from the line
        key=$(echo "$line" | sed 's/^export //; s/=.*//')
        # Find the corresponding value in values.yaml
        value=$(grep -m 1 "^${key}:" dependency/values.yaml | sed 's/^.*: //;s/^ *//;s/ *$//')
        # If the value is found, replace it in .envrc
        if [ -n "$value" ]; then
            sed -i "s|^export $key=.*|export $key=$value|" .envrc
        fi
    fi
done < .envrc

echo ".envrc file has been configured."
