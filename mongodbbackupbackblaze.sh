#!/bin/bash

# Function to check and install B2 Command Line Tool
install_b2() {
    # Define installation path in the home directory
    local install_path="$HOME/.local/bin"
    local b2_executable="$install_path/b2-linux"

    # Check if B2 is already installed
    if ! command -v $b2_executable &> /dev/null; then
        echo "Installing Backblaze B2 Command Line Tool in $install_path..."

        # Create installation directory if it doesn't exist
        mkdir -p $install_path

        # Download and install B2 Command Line Tool
        wget -O $b2_executable https://github.com/Backblaze/B2_Command_Line_Tool/releases/latest/download/b2-linux
        chmod +x $b2_executable

        # Optionally add the path to .bashrc or .bash_profile for persistent PATH updates
        echo "export PATH=\"$install_path:\$PATH\"" >> $HOME/.bashrc
        source $HOME/.bashrc

        # Prompt for Backblaze B2 credentials
        read -p "Enter your Backblaze B2 Application Key ID: " b2_account_id
        read -s -p "Enter your Backblaze B2 Application Key: " b2_application_key
        echo

        # Initial authorization
        $b2_executable authorize-account $b2_account_id $b2_application_key
    fi
}

# Function to perform MongoDB backup
backup_mongodb() {
    local db=$1
    local backup_dir="$BACKUP_DIR/mongo_$db-$(date +%Y%m%d)"
    local backup_file="$backup_dir.tar.gz"

    mongodump --host $MONGO_HOST --port $MONGO_PORT --db $db --username $MONGO_USER --password $MONGO_PASSWORD --out "$backup_dir"

    if [ -d "$backup_dir" ]; then
        tar -czf "$backup_file" -C "$BACKUP_DIR" "$(basename $backup_dir)"  # Removed verbose output
        rm -rf "$backup_dir"
    else
        echo "Failed to create backup directory: $backup_dir" >&2
        return 1
    fi

    echo "$backup_file"  # Echo only the path of the tar.gz file
}
# Function to backup a folder
backup_folder() {
    local folder=$1
    local backup_file="$BACKUP_DIR/$(basename $folder)-$(date +%Y%m%d).tar.gz"
    
    tar -czvf "$backup_file" -C "$(dirname $folder)" "$(basename $folder)"
    echo "$backup_file" # Return the path of the backup file
}

# Function to upload backup to B2
upload_backup() {
    local file=$1
    # Extract just the file name from the full path
    local filename=$(basename "$file")

    # Define the path and file name in B2
    local b2_path="backups/$filename"

    echo "Uploading $file to B2 as $b2_path"
    b2-linux upload-file $B2_BUCKET "$file" "$b2_path" &&
    rm "$file"
}
# Check arguments
if [ "$#" -lt 7 ]; then
    echo "Usage: $0 <mongo_user> <mongo_password> <mongo_host> <mongo_port> <database_names/folders> <b2_bucket> <backup_dir> [<is_folder_backup>]"
    exit 1
fi

# Assigning passed arguments to variables
MONGO_USER=$1
MONGO_PASSWORD=$2
MONGO_HOST=$3
MONGO_PORT=$4
TARGETS=($(echo $5 | tr ',' '\n')) # Split comma-separated databases/folders
B2_BUCKET=$6
BACKUP_DIR=$7
IS_FOLDER_BACKUP=${8:-false} # Optional, default is false

# Check and install B2 CLI
install_b2

# Backup and upload each target (database or folder)
for TARGET in "${TARGETS[@]}"; do
    backup_file=""
    if [ "$IS_FOLDER_BACKUP" = true ]; then
        backup_file=$(backup_folder $TARGET)
    else
        backup_file=$(backup_mongodb $TARGET)
    fi

    echo "Expected backup file: $backup_file" # Debugging output

    if [ -f "$backup_file" ]; then
        echo "Uploading backup file: $backup_file"
        upload_backup "$backup_file"
    else
        echo "Backup file not found: $backup_file"
        echo "Backup for target $TARGET failed."
    fi
done