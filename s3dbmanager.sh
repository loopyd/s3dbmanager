#!/bin/bash

# s3dbmanager.sh - A portable bash script to backup / restore mysql database 
#                  to/from s3 buckets.
#
# Copyright (c) 2023 DeityDurg <https://www.deitydurg.net>

# Setup work environment
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WORK_DIR=$(mktemp -d -p "$DIR")
if [[ ! "$WORK_DIR" || ! -d "$WORK_DIR" ]]; then
    echo "Could not create temporary directory for work" >&2
    exit 1
else
    echo "Work directory $WORK_DIR created successfully" >&2
fi
cleanup() {      
  rm -rf "$WORK_DIR"
  echo "Deleted temp working directory $WORK_DIR" >&2
}
trap cleanup EXIT

# Parse command line arguments
VALID_ARGS=$(getopt -o l:u:p:o:d:f:e:b:r:x:a:k:K:OS:s:w:t:i:hc: --long host:,username:,password:,port:,databases:,tables:,s3endpoint:,s3bucket:,s3region:,s3username:,s3accesskey:,s3secretkey:,backupkeyfile:,backupoverwrite,backupkeysize:,operation:,retentiondays:,date:,help,keep: -- "$@")
if [[ $? -ne 0 ]]; then
    exit 1;
fi
eval set -- "$VALID_ARGS"
while [ : ]; do
  case "$1" in
    -l | --host)
        MYSQL_HOST="$2"
        shift 2
        ;;
    -u | --username)
        MYSQL_USER="$2"
        shift 2
        ;;
    -p | --password)
        MYSQL_PASSWORD="$2" 
        shift 2
        ;;
    -o | --port)
        MYSQL_PORT="$2"
        shift 2
        ;;
    -d | --databases)
        MYSQL_DATABASES="$2"
        shift 2
        ;;
    -f | --tables) 
        MYSQL_TABLES="$2"
        shift 2
        ;;
    -e | --s3endpoint)
        S3_ENDPOINT="$2"
        shift 2
        ;;
    -b | --s3bucket)
        S3_BUCKET="$2"
        shift 2
        ;;
    -r | --s3region)
        S3_REGION="$2"
        shift 2
        ;;
    -x | --s3username)
        S3_USER="$2"
        shift 2
        ;;
    -a | --s3accesskey)
        S3_ACCESSKEY="$2"
        shift 2
        ;;
    -k | --s3secretkey)
        S3_SECRETKEY="$2"
        shift 2
        ;;
    -K | --backupkeyfile)
        BACKUP_KEY_FILE="$2"
        shift 2
        ;;
    -O | --backupoverwrite)
        BACKUP_KEY_OVERWRITE="y"
        shift
        ;;
    -S | --backupkeysize)
        BACKUP_KEY_SIZE="$2"
        shift 2
        ;;
    -s | --operation)
        OPERATION="$2"
        shift 2
        ;;
    -w | --retentiondays)
        S3_RETENTION_DAYS="$2"
        shift 2
        ;;
    -t | --date)
        MYDATE="$2"
        shift 2
        ;;
    -i | --interval)
        DAEMON_WAIT_SECONDS="$2"
        shift 2
        ;;
    -c | --keep)
        S3_KEEP="$2"
        shift 2
        ;;
    -h | --help)
        dousage
        exit 1
        ;;
    --) 
        shift; 
        break 
        ;;
  esac
done

# Validate command line arguments and simultaniously build parameters for
# runtime binaries
S3CMD_PARAMS=''
MYSQL_PARAMS=''
if [ -z "$MYSQL_HOST" ]; then
    echo "-l | --host: MYSQL_HOST option required" >&2
    exit 1
else
    MYSQL_PARAMS="--host=${MYSQL_HOST} ${MYSQL_PARAMS}"
fi
if [ -z "$MYSQL_USER" ]; then
    echo "-u | --user: MYSQL_USER option required" >&2
    exit 1
else
    MYSQL_PARAMS="--user=${MYSQL_USER} ${MYSQL_PARAMS}"
fi
if [ -z "$MYSQL_PASSWORD" ]; then
    echo "-p | --password: MYSQL_PASSWORD option not specified, defaulting to NONE" >&2
else
    MYSQL_PARAMS="--password=${MYSQL_PASSWORD} ${MYSQL_PARAMS}"
fi
if [ -z "$MYSQL_PORT" ]; then
    echo "-o | --port: MYSQL_PORT option not specified, defaulting to 3306" >&2
    MYSQL_PORT='3306'
fi
MYSQL_PARAMS="--port=${MYSQL_PORT} ${MYSQL_PARAMS}"
if [ -z "$MYSQL_DATABASES" ]; then
    echo "-d | --database: MYSQL_DATABASES option not specified, operation will work with the entire database" >&2
else 
    MYSQL_PARAMS="--databases=${MYSQL_DATABASES} ${MYSQL_PARAMS}"
fi
if [ -z "$MYSQL_TABLES" ]; then
    echo "-f | --tables: MYSQL_TABLES option not specified, operation will work with the entire database" >&2
else 
    MYSQL_PARAMS="--tables=${MYSQL_TABLES} ${MYSQL_PARAMS}"
fi
if [ -z "$S3_BUCKET" ]; then
    echo "-b | --s3bucket: S3_BUCKET option required" >&2
    exit 1
fi
if [ -z "$S3_ENDPOINT" ]; then
    echo "-e | --s3endpoint: S3_ENDPOINT option required" >&2
    exit 1
fi
if echo "${S3_ENDPOINT}" | sed 's/.digitaloceanspaces.com$//'; then
    S3CMD_PARAMS="--host-bucket=%(bucket)s.${S3_ENDPOINT} ${S3CMD_PARAMS}"
fi
if [ -z "$S3_REGION" ]; then
    echo "-r | --s3region: S3_REGION option not specified, region will default to NONE" >&2
else
    S3CMD_PARAMS="--region=\"${S3_REGION}\" ${S3CMD_PARAMS}"
fi
if [ -z "$S3_USER" ]; then
    echo "-x | --s3username: S3_USER option not specified, username will default to NONE" >&2
else
    S3CMD_PARAMS="--user=\"${S3_USER}\" ${S3CMD_PARAMS}"
fi
if [ -z "$S3_ACCESSKEY" ]; then
    echo "-a | --s3accesskey: S3_ACCESSKEY option required" >&2
    exit 1
else
    S3CMD_PARAMS="--access_key=\"${S3_ACCESSKEY}\" ${S3CMD_PARAMS}"
fi
if [ -z "$S3_SECRETKEY" ]; then
    echo "-k | --s3secretkey: S3_SECRETKEY option required" >&2
    exit 1
else
    S3CMD_PARAMS="--secret_key=\"${S3_SECRETKEY}\" ${S3CMD_PARAMS}"
fi
if [ -z "$OPERATION" ]; then
    echo "-s | --operation: OPERATION option required" >&2
    exit 1
fi
if [ -z "$S3_RETENTION_DAYS" ] && [ "$OPERATION" == "setlifecycle" ]; then
    echo "-w | --retentiondays: OPERATION=setlifecycle requires RETENTION_DAYS option, it has defaulted to 7 days" >&2
    S3_RETENTION_DAYS="7"
fi
# Ensure backup key file is a valid filename.
if [ -z "${BACKUP_KEY_FILE}" ] && [ "$OPERATION" == "backup" ]; then
    echo "-K | --backupkeyfile: OPERATION=backup requires BACKUP_KEY_FILE option, it has defaulted to $HOME/s3dbmanager_backup.key" >&2
    BACKUP_KEY_FILE="$HOME/s3dbmanager_backup.key"
fi
if [ -z "${BACKUP_KEY_FILE}" ] && [ "$OPERATION" == "restore" ]; then
    echo "-K | --backupkeyfile: OPERATION=restore requires BACKUP_KEY_FILE option, it has defaulted to $HOME/s3dbmanager_backup.key" >&2
    BACKUP_KEY_FILE="$HOME/s3dbmanager_backup.key"
fi
# Ensure backup key size is set correctly.
if [ -z "${BACKUP_KEY_SIZE}" ] && [ "$OPERATION" == "backup" ]; then
    echo "-S | --backupkeysize: OPERATION=backup requires BACKUP_KEY_SIZE option, it has defaulted to 32" >&2
    BACKUP_KEY_SIZE="32"
fi
if [ -z "${BACKUP_KEY_SIZE}" ] && [ "$OPERATION" == "restore" ]; then
    echo "-S | --backupkeysize: OPERATION=backup requires BACKUP_KEY_SIZE option, it has defaulted to 32" >&2
    BACKUP_KEY_SIZE="32"
fi
if [ -z "$MYDATE" ] && [ "$OPERATION" == "backup" ]; then
    echo "-t | --date: OPERATION=backup requires DATE option, it has defaulted to NOW" >&2
    MYDATE="$(date '+%Y%m%d-%H%M')"
fi
if [ -z "$MYDATE" ] && [ "$OPERATION" == "restore" ]; then
    echo "-t | --date: OPERATION=restore requires MYDATE option, it has defaulted to NOW" >&2
    MYDATE="$(date '+%Y%m%d-%H%M%S')"
fi
if [ -z "$DAEMON_WAIT_SECONDS" ] && [ "$OPERATION" == "daemonize" ]; then
    echo "-i | --interval: OPERATION=daemonize requires DAEMON_WAIT_SECONDS option, it has defaulted to 3600 seconds (1 hour)" >&2
    DAEMON_WAIT_SECONDS="3600"
fi
if [ -z "$S3_KEEP" ] && [ "$OPERATION" == "rotate" ]; then
    echo "-c | --keep: OPERATION=rotate requires S3_KEEP option, it has defaulted to 14 backups" >&2
    S3_KEEP="14"
fi

FILENAME="${MYDATE}.xb.bz2"
S3CMD_PARAMS=$(echo ${S3CMD_PARAMS} | sed 's/^[ \t]*//;s/[ \t]*$//')
MYSQL_PARAMS=$(echo ${MYSQL_PARAMS} | sed 's/^[ \t]*//;s/[ \t]*$//')

# The function checks for required prerequisites and installs them if
# nessecary.
docheckprerequisites() {
    if ! command -v g++ &> /dev/null; then
        echo "c++ compiler is not installed, it will be installed now" >&2
        apt-get install build-essential
        if command -v gcc &> /dev/null; then
            echo "installed the c++ compiler successfully" >&2
        else
            echo "c++ compiler failed to install, please check the log" >&2
            exit 1
        fi
    fi
    if ! command -v s3cmd &> /dev/null; then
        echo "s3cmd tool could not be found, it will be installed now" >&2
        wget -qO- 'https://github.com/s3tools/s3cmd/releases/download/v2.3.0/s3cmd-2.3.0.tar.gz' | tar xz -C ${WORK_DIR}/ && cp -R ${WORK_DIR}/s3cmd-2.3.0/s3cmd ${WORK_DIR}/s3cmd-2.3.0/S3 /usr/local/bin
        apt-get install python-dateutil -y
        if command -v s3cmd &> /dev/null; then
            echo "s3cmd tool installed successfully" >&2
        else
            echo "s3cmd tool failed to install successfully, please check the log" >&2
            exit 1
        fi
    fi
    if ! command -v lbzip2 &> /dev/null; then
        echo "lbzip2 tool could not be found, it will be installed now" >&2
        apt-get install lbzip2
        if command -v lbzip2 &> /dev/null; then
            echo "lbzip2 tool installed successfully" >&2
        else
            echo "lbzip2 tool failed to install successfully, please check the log" >&2
            exit 1
        fi
    fi
    return
}

# The function sets the lifecycle policy of the s3 bucket.
dosetlifecycle() {
    echo "Setting bucket lifecycle policy..."
    cat >$WORKDIR/lifecycle.xml <<EOF
<?xml version="1.0" ?>
<LifecycleConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
	<Rule>
		<ID>Expire old backups</ID>
		<Prefix/>
		<Status>Enabled</Status>
		<Expiration>
			<Days>${S3_RETENTION_DAYS}</Days>
		</Expiration>
    <AbortIncompleteMultipartUpload>
      <DaysAfterInitiation>1</DaysAfterInitiation>
    </AbortIncompleteMultipartUpload>
  </Rule>
</LifecycleConfiguration>
EOF
    s3cmd $S3CMD_PARAMS setlifecycle "${WORKDIR}/lifecycle.xml" "s3://${S3_BUCKET}"
    return
}

# Generate a backup key to encrypt the database with
dogeneratekey() {
  if [ -f "${BACKUP_KEY_FILE}" ]; then
    if [ -z "${BACKUP_KEY_OVERWRITE}" ]; then
      read -p "WARNING: backup encryption key file already exists. ARE YOU SURE you want to overwrite it? (THIS WILL MAKE ANY PREVIOUSLY MADE BACKUPS INACCESSABLE WITHOUT THE KEY!  BEWARE)  [y/N] " answer
      if [[ ! "${answer}" =~ ^[Yy]$ ]]; then
        echo "Aborting backup key generation."
        return
      fi
    else
      echo "Using existing backup key file ${BACKUP_KEY_FILE}.".
      return
    fi
  fi
  
  # Generate new backup key and save to file
  openssl rand -out "${BACKUP_KEY_FILE}" ${BACKUP_KEY_SIZE}
  echo "Backup encryption key generated and saved to ${BACKUP_KEY_FILE}."
}

# The function does a backup of the database streamed to the S3 bucket.
dobackup() {
    echo "Taking a backup at ${MYDATE}..."
    mysqldump ${MYSQL_PARAMS} \
    | lbzip2 -c \
    | openssl enc -aes-256-cbc -salt -pass file:${BACKUP_KEY_FILE} \
    | s3cmd $S3CMD_PARAMS put - "s3://${S3_BUCKET}/${FILENAME}"
    return
}

# The function performs a restore from the S3 bucket to the database.
dorestore() {
    systemctl stop mysqld.service
    s3cmd $S3CMD_PARAMS get "s3://${S3_BUCKET}/${FILENAME}" \
    | openssl enc -aes-256-cbc -d -salt -pass file:${BACKUP_KEY_FILE} \
    | lbzip2 -d \
    | mysql ${MYSQL_PARAMS}
    systemctl start mysqld.service
}

dorotate() {
    echo "Rotating backups on S3 (keep $S3_KEEP latest backups)" >&2
    s3cmd ls "s3://$S3_BUCKET" \
    | grep -e bz2$ \
    | awk '{print $4}' \
    | head -n -$S3_KEEP \
    | xargs s3cmd del
    return
}

# The function runs a backup daemon in the foreground at DAEMON_WAIT_SECONDS interval.
dobackupdaemon() {
    while true; do
        echo "Daemon is waiting ${DAEMON_WAIT_SECONDS} seconds until next backup..."
        sleep "${DAEMON_WAIT_SECONDS}s"
        dobackup
    done
    return
}

# Function to display usage information
dousage() {
  echo "s3dbmanager.sh - A portable bash script to backup / restore mysql"
  echo "                 to/from s3 buckets."
  echo
  echo "=== Copyright (c) 2023 DeityDurg <https://www.deitydurg.net> ==="
  echo
  echo "Usage: s3dbmanager.sh [options]"
  echo
  echo "Options:"
  echo "  -l | --host            : MySQL host (default: localhost)"
  echo "  -u | --username        : MySQL username"
  echo "  -p | --password        : MySQL password"
  echo "  -o | --port            : MySQL port (default: 3306)"
  echo "  -d | --databases       : MySQL database(s) to backup/restore"
  echo "  -f | --tables          : MySQL table(s) to backup/restore"
  echo "  -e | --s3endpoint      : S3 endpoint"
  echo "  -b | --s3bucket        : S3 bucket"
  echo "  -r | --s3region        : S3 region"
  echo "  -x | --s3username      : S3 username"
  echo "  -a | --s3accesskey     : S3 access key"
  echo "  -k | --s3secretkey     : S3 secret key"
  echo "  -K | --backupkeyfile   : S3 backup key filename (default: $HOME/s3dbmanager_backup.key)"
  echo "  -S | --backupkeysize   : S3 backup key size (default: 32)"
  echo "  -O | --backupoverwrite : Overwrite the backup key file if it exists."
  echo "  -s | --operation       : Operation to perform"
  echo "  -w | --retentiondays   : Number of days to keep backups"
  echo "  -t | --date            : Backup/restore date (format: YYYY-MM-DD)"
  echo "  -i | --interval        : Time to wait between backups/restores (in seconds)"
  echo "  -c | --keep            : Number of backups to keep in S3 (default: 14)"
  echo "  -h | --help            : Display this script usage information"
  return
}

# Run run functions
docheckprerequisites
case "$OPERATION" in
    setlifecycle)
        dosetlifecycle
        ;;
    backup)
        dogeneratekey
        dobackup
        ;;
    rotate)
        dorotate
        ;;
    daemonize)
        dobackupdaemon
        ;;
    restore)
        dogeneratekey
        dorestore
        ;;
    *)
        echo "-o | --operation: OPERATION=$OPERATION not supported" >&2
        exit 1
        ;;
esac