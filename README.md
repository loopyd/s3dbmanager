# s3dbmanager.sh

## Manage it in the draconic way!

This script backs up MariaDB to s3 bucket and back, with a lot of features in a portable design!

## Caveouts

This script has some limitations, for simplicity's sake:

- does not support incremental backups (that have to construct the final from a master backup followed by the additional slave backups)
- does not support partitioned table backup restore

## Shameless buttplug

Maybe I might remove some of these limitations in the future, if it **GETS ENOUGH GITHUB STARS** (is well recieved by the community as a working solution).

## Usage

### Command line arguments

You have this table to reference for command line options.  You can also run ``-h`` or ``--help`` to see the same list.

* **Short** - The short version of the argument
* **Long** - The long version of the argument
* **Optional** - If the argument is optional, it can default to an internally defined value for shorthand convenience
* **Environment** - The name of the environment variable that is used to store this argument.  Instead of passing arguments directly, you can ``export`` this name to make the script work without passing in arguments
* **Description** - The description of the argument's funciton

| Short | Long | Optional | Environment | Description |
| ----- | ---- | ---- | ---- | ---- |
| ``-h`` | ``--help`` | **YES** | N/A | Just displays the usage and some program information |
| ``-o`` | ``--operation`` | **NO** | ``OPERATION`` | The operation to perform, see below for a complete list of these options |
| ``-l`` | ``--host`` | **NO** | ``MYSQL_HOST`` | The MariaDB host to connect to |
| ``-u`` | ``--username`` | **NO** | ``MYSQL_USER`` | The MariaDB username to connect with |
| ``-p`` | ``--password`` | **NO** | ``MYSQL_PASSWORD`` | The MariaDB password to connect with |
| ``-o`` | ``--port`` | **YES** | ``MYSQL_PORT`` | The port to connect to, if none specified it defaults to 3306 |  
| ``-d`` | ``--databases`` | **YES** | ``MYSQL_DATABASES`` | The database to backup, if none is specified, it backs up all of the databases on the MySQL server |
| ``-f`` | ``--tables`` | **YES** | ``MYSQL_TABLES`` | The tables to backup, if none is specified, it backs up all of the tables on the MySQL server |
| ``-e`` | ``--s3endpoint`` | **NO** | ``S3_ENDPOINT`` | The S3 endpoint to connect to |
| ``-b`` | ``--s3bucket`` | **NO** | ``S3_BUCKET`` | The S3 bucket to connect to |
| ``-r`` | ``--s3region`` | **YES** | ``S3_REGION`` | The S3 region to connect to, if none is specified, this is interpreted from the host specified.  This is not required by all providers, but some may need to have it, so it is provided for compatibility with those providers |
| ``-x`` | ``--s3username`` | **YES** | ``S3_USER`` | The S3 username to connect with.  Depending on your IAM configuration, you may have to specify the username to connect to the bucket with.  This is not required by all providers, but some may need to have it, thus it is provided for compatibility with those providers. |
| ``-a`` | ``--s3accesskey`` | **NO** | ``S3_ACCESSKEY`` | The S3 access key to connect with |
| ``-k`` | ``--s3secretkey`` | **NO** | ``S3_SECRETKEY`` | The S3 secret key to connect with |
| ``-w`` | ``--retentiondays`` | **YES** | ``S3_RETENTION_DAYS`` | When specifying the ``setlifecycle`` operation, this option can be provided to set the retention period of backups in days, otherwise it defaults to 7 days. |
| ``-c`` | ``--keep`` | **YES** | ``S3_KEEP`` | When specifying the ``rotate`` operation, this option can be provided to set the number of backups to keep in the s3 bucket, otherwise it defaults to keeping 14 backup files |

### Operations

This portable script contains the following mariadb / s3 operation modes which are specified by ``-o`` or ``--operation`` parameters:

- ``backup`` - backup the database to the s3 bucket
- ``rotate`` - rotate backups in the s3 bucket
- ``restore`` - restore the database from the s3 bucket
- ``setlifecycle`` - set the lifecycle policy for the s3 bucket
- ``daemonize`` - daemonize the backup part of the script in the foreground (by default), allowing the operation to run verbosely on the terminal for debugging purposes.