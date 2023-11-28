#!/bin/bash

# Function to display usage information
function display_usage {
    echo "Usage: $0 -e ENV_NAME -p PROJECT_NAME -t TYPE -d WORKING_DIRECTORY -P PORT -s SERVER_NAME [-r ENABLE_RATE_LIMITING] [-b RATE_BURST] [-c ENABLE_CACHE] [-C ENABLE_CACHE_CONTROL] [-v VERBOSE]"
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
    NODE_ENV_OPTION=""

    # Determine NODE_ENV based on ENV_NAME
    if [[ "$ENV_NAME" == "dev" || "$ENV_NAME" == "development" ]]; then
        NODE_ENV_OPTION="NODE_ENV=development"
    elif [[ "$ENV_NAME" == "prod" || "$ENV_NAME" == "production" ]]; then
        NODE_ENV_OPTION="NODE_ENV=production"
    fi

    if [ "$TYPE" == "frontend" ]; then
        if [ -f "package.json" ]; then
            COMMAND="npm start"
        else
            exit_on_error "package.json not found in directory $DEST_DIR"
        fi
    elif [ "$TYPE" == "backend" ]; then
        if [ ! -f "package.json" ]; then
        exit_on_error "package.json not found in directory $DEST_DIR"
        fi

        # Check if a start script is defined in package.json
        if jq -e .scripts.start package.json > /dev/null; then
            COMMAND="npm start"
        else
            # Look for index.js in multiple directories
            INDEX_JS_PATH=$(find "$DEST_DIR/build" "$DEST_DIR/dist" "$DEST_DIR/output" -type f -name 'index.js' -print -quit)
            if [[ -n $INDEX_JS_PATH ]]; then
                COMMAND="$INDEX_JS_PATH"
                OPTIONS="-i max"
            else
                exit_on_error "No start script in package.json and no index.js found in build, dist, or output directories. Exiting."
            fi
        fi
    fi
    
    export NODE_ENV
    export PORT
    if [ -z "$OPTIONS" ]; then
        pm2 start "$COMMAND" --name "$PM2_NAME"|| exit_on_error "Failed to start PM2 process"
    else
        pm2 start "$COMMAND" --name "$PM2_NAME" "$OPTIONS"|| exit_on_error "Failed to start PM2 process"
    fi
}

# Function to perform common operations
function common_operations {
    log_message "Performing common operations..."

     # Check if pnpm is installed
    if ! command -v $PKG_MANAGER &> /dev/null; then
        exit_on_error "$PKG_MANAGER not found, please install it first."
    fi

     # Check if the destination directory exists, create it if not
    if [ ! -d "$DEST_DIR" ]; then
        mkdir -p "$DEST_DIR" || exit_on_error "Failed to create directory $DEST_DIR"
    fi
    cp "$SOURCE_ENV" "$DEST_ENV" || exit_on_error "Failed to copy .env file"
    cd "$DEST_DIR" || exit_on_error "Failed to change to directory $DEST_DIR"

    # check nvmrc file
    if [ -f ".nvmrc" ]; then
        # Load NVM
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
        
        # Install and use the specified Node.js version in .nvmrc
        nvm install || exit_on_error "Failed to install Node.js version specified in .nvmrc"
        nvm use || exit_on_error "Failed to switch to Node.js version specified in .nvmrc"
    else
        log_message ".nvmrc file not found. Skipping NVM operations."
    fi

    $PKG_MANAGER install || exit_on_error "Failed to install dependencies"
    $PKG_MANAGER lint:fix || log_message "Lint auto-fix script not found or failed to execute"
    $PKG_MANAGER build || exit_on_error "Failed to build the project"
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
    [[ -z "$WORKING_DIRECTORY" || -z "$ENV_NAME" || -z "$PROJECT_NAME" || -z "$TYPE" || -z "$SERVER_NAME" ]] && {
        log_message "Missing one or more mandatory arguments."
        display_usage
    }

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
: ${PKG_MANAGER:=pnpm}
# Parse arguments

while getopts ":e:p:d:t:P:s:r:b:c:C:v:m:" opt; do
    case $opt in
        e) ENV_NAME="$OPTARG";;
        p) PROJECT_NAME="$OPTARG";;
        t) TYPE="$OPTARG";;
        P) PORT="$OPTARG";;
        s) SERVER_NAME="$OPTARG";;
        d) WORKING_DIRECTORY="$OPTARG";;
        r) ENABLE_RATE_LIMITING="$OPTARG";;
        b) RATE_BURST="$OPTARG";;
        c) ENABLE_CACHE="$OPTARG";;
        C) ENABLE_CACHE_CONTROL="$OPTARG";;
        v) VERBOSE="$OPTARG";;
        m) PKG_MANAGER="$OPTARG";;
        *) log_message "Invalid option: -$OPTARG"; display_usage ;;
    esac
done



# Initialize the associative array
# Validation
declare -A boolean_vars=(
    ["VERBOSE"]=$VERBOSE
    ["ENABLE_CACHE"]=$ENABLE_CACHE
    ["ENABLE_CACHE_CONTROL"]=$ENABLE_CACHE_CONTROL
    ["ENABLE_RATE_LIMITING"]=$ENABLE_RATE_LIMITING
)

for var_name in "${!boolean_vars[@]}"; do
    [[ "${boolean_vars[$var_name]}" != "true" && "${boolean_vars[$var_name]}" != "false" ]] && {
        log_message "Invalid boolean value for $var_name: ${boolean_vars[$var_name]}. Should be 'true' or 'false'."
        display_usage
    }
done


# Variables (based on the parsed options)
SOURCE_ENV="/home/dev/envs/${PROJECT_NAME}_${ENV_NAME}_${WORKING_DIRECTORY}.env"
DEST_DIR="/home/dev/sites/$PROJECT_NAME/${ENV_NAME}/${WORKING_DIRECTORY}"
DEST_ENV="$DEST_DIR/.env"
PM2_NAME="${PROJECT_NAME}_${ENV_NAME}_${WORKING_DIRECTORY}"
NGINX_CONF="/etc/nginx/sites-available/${PROJECT_NAME}_${ENV_NAME}_${WORKING_DIRECTORY}.conf"
NGINX_LINK="/etc/nginx/sites-enabled/${PROJECT_NAME}_${ENV_NAME}_${WORKING_DIRECTORY}.conf"

# Create source .env file if needed
if [ ! -f "$SOURCE_ENV" ]; then
    echo -e "KEY=DEFAULT_VALUE\nPORT=$PORT" > "$SOURCE_ENV" || exit_on_error "Failed to create $SOURCE_ENV"
fi

if [[ "$PKG_MANAGER" != "pnpm" && "$PKG_MANAGER" != "yarn" ]]; then
    log_message "Invalid package manager: $PKG_MANAGER. Should be 'pnpm' or 'yarn'."
    display_usage
fi
# Run the main function
log_script_call "$@"

main