#!/bin/bash

# Function to sanitize a string by replacing non-alphanumeric characters with underscores
function sanitize {
    echo "$1" | sed 's/[^a-zA-Z0-9]/_/g'
}
# Function to display usage information
function display_usage {
    echo "Usage: $0 -p PORT -s SERVER_NAME [-r ENABLE_RATE_LIMITING] [-c ENABLE_CACHE] [-C ENABLE_CACHE_CONTROL]"
    exit 1
}

# Function to generate Nginx configuration
function generate_nginx_conf {
    PORT=$1
    SERVER_NAME=$2
    ENABLE_RATE_LIMITING=$3
    ENABLE_CACHE=$4
    ENABLE_CACHE_CONTROL=$5

    # Sanitize server name for use in upstream
    SANITIZED_SERVER_NAME=$(sanitize "$SERVER_NAME")

    RATE_LIMITING=""
    if [ "$ENABLE_RATE_LIMITING" == "true" ]; then
        RATE_LIMITING="limit_req_zone \$binary_remote_addr zone=rate_limiting:10m rate=10r/s;"
    fi

    CACHING=""
    if [ "$ENABLE_CACHE" == "true" ]; then
        CACHING="proxy_cache cache;
        proxy_cache_valid 200 302 10m;
        proxy_cache_valid 404 1m;"
    fi

    CACHE_CONTROL=""
    if [ "$ENABLE_CACHE_CONTROL" == "true" ]; then
        CACHE_CONTROL="add_header Cache-Control \"public, max-age=31536000, immutable\";"
    fi

    cat <<EOL
upstream ${SANITIZED_SERVER_NAME}_loadbalancer {
    server localhost:$PORT;
    # add more servers here if needed
}
server {
    listen  80;
    server_name $SERVER_NAME;
    client_max_body_size 100m;

    # Rate limiting
    $RATE_LIMITING

    location / {
        proxy_pass http://${SANITIZED_SERVER_NAME}_loadbalancer;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;

        # Cache Control
        $CACHE_CONTROL

        # Caching
        $CACHING
    }

    # Custom error pages
    error_page  500 502 503 504  /50x.html;
    location = /50x.html {
        root  /usr/share/nginx/html;
    }
}
EOL
}

# Main function to execute the script
function main {
    # Parse command line arguments
    while getopts ":p:s:r:c:C:" opt; do
        case $opt in
            p)
                PORT=$OPTARG
                ;;
            s)
                SERVER_NAME=$OPTARG
                ;;
            r)
                ENABLE_RATE_LIMITING=$OPTARG
                ;;
            c)
                ENABLE_CACHE=$OPTARG
                ;;
            C)
                ENABLE_CACHE_CONTROL=$OPTARG
                ;;
            \?)
                echo "Invalid option: -$OPTARG" >&2
                display_usage
                ;;
            :)
                echo "Option -$OPTARG requires an argument." >&2
                display_usage
                ;;
        esac
    done

    # Validate mandatory arguments
    if [ -z "$PORT" ] || [ -z "$SERVER_NAME" ]; then
        echo "Missing one or more mandatory arguments."
        display_usage
    fi

    # Generate Nginx configuration
    generate_nginx_conf "$PORT" "$SERVER_NAME" "$ENABLE_RATE_LIMITING" "$ENABLE_CACHE" "$ENABLE_CACHE_CONTROL"
}

# Execute the main function
main "$@"
