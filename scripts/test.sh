#!/bin/bash

# Function to display usage information
function display_usage {
    echo "Usage: $0 -e ENV_NAME -p PROJECT_NAME -t TYPE -P PORT -s SERVER_NAME [-r ENABLE_RATE_LIMITING] [-b RATE_BURST] [-c ENABLE_CACHE] [-C ENABLE_CACHE_CONTROL] [-v VERBOSE]"
    exit 1
}
# Function to sanitize a string by replacing non-alphanumeric characters with underscores
function sanitize {
    echo "$1" | sed 's/[^a-zA-Z0-9]/_/g'
}
# Function to log script call
function log_script_call {
    log_message "Logging script call..."
    LOG_STRING="$0 $@"
    # Check if execution.txt exists, create if not
    [ ! -f execution.txt ] && touch execution.txt
    if ! grep -Fxq "$LOG_STRING" execution.txt; then
        echo "$LOG_STRING" >> execution.txt
    fi
}
# Function to log messages
function log_message {
    if [ "$VERBOSE" == "true" ]; then
        echo "[LOG] $1"
    fi
}

# Function to exit script on error
function exit_on_error {
    log_message "$1"
    exit 1
}

# Function to manage PM2 process
function manage_pm2_process {
    log_message "Managing PM2 process..."
    pm2 delete "$PM2_NAME" 2>/dev/null
    COMMAND=""
    OPTIONS=""
    if [ "$TYPE" == "frontend" ]; then
        if [ -f "package.json" ]; then
            COMMAND="npm start"
        else
            exit_on_error "package.json not found in directory $DEST_DIR"
        fi
    elif [ "$TYPE" == "backend" ]; then
        if [ -f "build/src/index.js" ]; then
            COMMAND="build/src/index.js"
        elif [ -f "build/index.js" ]; then
            COMMAND="build/index.js"
        else
            exit_on_error "Neither build/src/index.js nor build/index.js found. Exiting."
        fi
        OPTIONS="-i max"
    fi

    if [ -z "$OPTIONS" ]; then
        PORT=$PORT pm2 start "$COMMAND" --name "$PM2_NAME"|| exit_on_error "Failed to start PM2 process"
    else
        PORT=$PORT pm2 start "$COMMAND" --name "$PM2_NAME" "$OPTIONS"|| exit_on_error "Failed to start PM2 process"
    fi
}

# Function to perform common operations
function common_operations {
    log_message "Performing common operations..."

     # Check if pnpm is installed
    if ! command -v pnpm &> /dev/null; then
        exit_on_error "pnpm not found, please install it first."
    fi

     # Check if the destination directory exists, create it if not
    if [ ! -d "$DEST_DIR" ]; then
        mkdir -p "$DEST_DIR" || exit_on_error "Failed to create directory $DEST_DIR"
    fi
    cp "$SOURCE_ENV" "$DEST_ENV" || exit_on_error "Failed to copy .env file"
    cd "$DEST_DIR" || exit_on_error "Failed to change to directory $DEST_DIR"
    pnpm install || exit_on_error "Failed to install dependencies"
    pnpm lint:fix || log_message "Lint auto-fix script not found or failed to execute"
    pnpm build || exit_on_error "Failed to build the project"
}
# Function to set up Nginx
function setup_nginx {
    log_message "Setting up Nginx..."
    
    # Sanitize server name for use in upstream
    SANITIZED_SERVER_NAME=$(sanitize "$SERVER_NAME")

    if [ ! -f "$NGINX_CONF" ] || [ ! -L "$NGINX_LINK" ]; then
        log_message "Creating Nginx configuration..."
        log_message "Creating Nginx configuration..."
        sudo bash -c "cat <<EOL > $NGINX_CONF
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
        proxy_set_header Upgrade \\\$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \\\$host;
        proxy_cache_bypass \\\$http_upgrade;

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
EOL"
        # Check if the symbolic link already exists
        if [ -L "$NGINX_LINK" ]; then
            log_message "Nginx symbolic link already exists. Overwriting..."
            sudo ln -sf "$NGINX_CONF" "$NGINX_LINK" || exit_on_error "Failed to create Nginx symbolic link"
        else
            sudo ln -s "$NGINX_CONF" "$NGINX_LINK" || exit_on_error "Failed to create Nginx symbolic link"
        fi
        sudo nginx -s reload || exit_on_error "Failed to reload Nginx"
    else
        log_message "Nginx configuration already exists."
    fi
}

# Main function to execute the script
function main {
    # Validate mandatory arguments
    if [ -z "$ENV_NAME" ] || [ -z "$PROJECT_NAME" ] || [ -z "$TYPE" ] || [ -z "$SERVER_NAME" ]; then
        log_message "Missing one or more mandatory arguments."
        display_usage  # Using display_usage instead of exit 1
    fi

    # Validate TYPE argument
    if [ "$TYPE" != "frontend" ] && [ "$TYPE" != "backend" ]; then
        log_message "Invalid type: $TYPE. Should be 'frontend' or 'backend'."
        display_usage  # Using display_usage instead of exit 1
    fi

    # Cache Control
    CACHE_CONTROL=""
    if [ "$ENABLE_CACHE_CONTROL" == "true" ]; then
        if [ "$TYPE" == "frontend" ]; then
            CACHE_CONTROL='add_header Cache-Control "public, max-age=31536000, immutable";'
        elif [ "$TYPE" == "backend" ]; then
            CACHE_CONTROL='add_header Cache-Control "no-cache, no-store, must-revalidate";'
        fi
    fi

    # Rate limiting
    RATE_LIMITING=""
    if [ "$ENABLE_RATE_LIMITING" == "true" ]; then
        : ${RATE_BURST:=5}
        RATE_LIMITING="limit_req_zone \$binary_remote_addr zone=mylimit:1m rate=${RATE_BURST}r/s; limit_req zone=mylimit;"
    fi

    # Caching
    CACHING=""
    if [ "$ENABLE_CACHE" == "true" ]; then
        CACHING="proxy_cache my_cache;"
    fi
    # Nginx
    # setup_nginx

    # Common operations
    common_operations

    # Manage PM2 process
    manage_pm2_process
}

# Declare an associative array for storing boolean values
# Set default values
: ${PORT:=3603}
: ${VERBOSE:=false}
: ${ENABLE_CACHE:=false}
: ${ENABLE_CACHE_CONTROL:=false}
: ${ENABLE_RATE_LIMITING:=false}
: ${RATE_BURST:=5}

# Parse command line arguments
while getopts ":e:p:t:P:s:r:b:c:C:v:" opt; do
  case $opt in
    e) ENV_NAME="$OPTARG" ;;
    p) PROJECT_NAME="$OPTARG" ;;
    t) TYPE="$OPTARG" ;;
    P) PORT="$OPTARG" ;;
    s) SERVER_NAME="$OPTARG" ;;
    r) ENABLE_RATE_LIMITING="$OPTARG" ;;
    b) RATE_BURST="$OPTARG" ;;
    c) ENABLE_CACHE="$OPTARG" ;;
    C) ENABLE_CACHE_CONTROL="$OPTARG" ;;
    v) VERBOSE="$OPTARG" ;;
    *) log_message "Invalid option: -$OPTARG"; display_usage ;;
  esac
done

declare -A boolean_vars

# Initialize the associative array
boolean_vars["VERBOSE"]=$VERBOSE
boolean_vars["ENABLE_CACHE"]=$ENABLE_CACHE
boolean_vars["ENABLE_CACHE_CONTROL"]=$ENABLE_CACHE_CONTROL
boolean_vars["ENABLE_RATE_LIMITING"]=$ENABLE_RATE_LIMITING
# Validate boolean values
for var_name in "${!boolean_vars[@]}"; do
    var_value=${boolean_vars[$var_name]}
    # log_message "Validating boolean for $var_name: $var_value"
    if [ "$var_value" != "true" ] && [ "$var_value" != "false" ]; then
        log_message "Invalid boolean value for $var_name: $var_value. Should be 'true' or 'false'."
        display_usage
    fi
done

# Validate mandatory arguments
if [ -z "$ENV_NAME" ] || [ -z "$PROJECT_NAME" ] || [ -z "$TYPE" ] || [ -z "$SERVER_NAME" ]; then
    log_message "Missing one or more mandatory arguments."
    display_usage
fi


# Variables (based on the parsed options)
SOURCE_ENV="/home/dev/envs/${PROJECT_NAME}_${ENV_NAME}_${TYPE:0:1}.env"
DEST_DIR="/home/dev/sites/$PROJECT_NAME/${ENV_NAME}/${TYPE}"
DEST_ENV="$DEST_DIR/.env"
PM2_NAME="${PROJECT_NAME}_${ENV_NAME}_${TYPE:0:1}"
NGINX_CONF="/etc/nginx/sites-available/${PROJECT_NAME}_${ENV_NAME}_${TYPE}.conf"
NGINX_LINK="/etc/nginx/sites-enabled/${PROJECT_NAME}_${ENV_NAME}_${TYPE}.conf"

# Create source .env file if needed
if [ ! -f "$SOURCE_ENV" ]; then
    echo -e "KEY=DEFAULT_VALUE\nPORT=$PORT" > "$SOURCE_ENV" || exit_on_error "Failed to create $SOURCE_ENV"
fi

# Run the main function
log_script_call "$@"

main