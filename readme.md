This service configuration example in .drs file:
```ruby
Service :db_backup, image: 'dtorry/db-backup:latest',
        ingress: [ { host: 'backup.settlements.*', port: 7000, basic_auth: 'admin:admin:i7hdbc9g' }],
        env: { BACKUP_INTERVAL: 60 , TABLES: 'settlements_geometry code_settlements', DB_URL: 'postgres://example_user:example_password@stack_name_db_for_backup:5432/example_db_for_backup',
               BACKUP_TARGET_HOST: '127.0.0.1', BACKUP_TARGET_PATH: '/path/to/backups/directory', BACKUP_TARGET_HOST_PRIVATE_KEY: 'value_of_private_key',
               RESTORE_TARGET_HOST_PORT: 'stack_name_db_for_restoring', RESTORE_TARGET_USER: 'db_for_restoring_admin', RESTORE_TARGET_PASSWORD: 'password' }
```

Necessary environment variables:
* `BACKUP_INTERVAL` - backup interval in minutes
* `TABLES` - comma separated list of tables to backup. If not specified, all tables will be backed up.
* `DB_URL` - database connection string.
* `BACKUP_TARGET_HOST` - host address where backups will be stored.
* `BACKUP_TARGET_PATH` - path to directory where backups will be stored on target host.
* `BACKUP_TARGET_HOST_PRIVATE_KEY` - private key to access target host.
* `RESTORE_TARGET_HOST_PORT` - address of database to restore.
* `RESTORE_TARGET_USER` - user to access database.
* `RESTORE_TARGET_PASSWORD` - password to access database.
