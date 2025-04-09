This service configuration example in .drs file:
```ruby
Service :db_backup, image: 'dtorry/db-backup:latest',
        ingress: [ { host: 'backup.settlements.*', port: 7000, basic_auth: 'admin:admin:i7hdbc9g' }],
        env: { BACKUP_INTERVAL: 60 , TABLES: 'settlements_geometry code_settlements', DB_URL: DB_URL}
```

Note:
* `BACKUP_INTERVAL` - backup interval in minutes
* `TABLES` - comma separated list of tables to backup. If not specified, all tables will be backed up.
* `DB_URL` - database connection string.