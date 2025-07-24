require 'open3'
require 'sequel'

def restore_by_dump(backup_path, database_name)
  message = nil
  puts "Restoring backup at #{Time.now} by dump #{backup_path}"
  default_db_url = ENV['DB_URL'] # postgres://settlements:settlements@settlements_settlements_db/settlements?sslmode=disable
  default_user_password = default_db_url.split('@').first.split('//').last
  default_db_user = default_user_password.split(':').first
  default_db_password = default_user_password.split(':').last
  default_db_name = default_db_url.split('?').first.split('/').last
  default_db_host_port = default_db_url.split('@').last.split('/').first
  db_host_port     = ENV['RESTORE_TARGET_HOST_PORT']
  db_host_port ||= default_db_host_port
  raise "Target database host and port are not specified" if db_host_port.nil?
  db_host = db_host_port.split(':').first
  db_port = db_host_port.split(':').last if db_host_port.split(':').size > 1
  db_user     = ENV['RESTORE_TARGET_USER']
  db_user     ||= default_db_user
  db_password = ENV['RESTORE_TARGET_PASSWORD']
  db_password ||= default_db_password
  db_name     = database_name || default_db_name
  missing_vars = []
  missing_vars << 'RESTORE_TARGET_HOST_PORT' if db_host_port.nil?
  missing_vars << 'RESTORE_TARGET_USER' if db_user.nil?
  missing_vars << 'RESTORE_TARGET_PASSWORD' if db_password.nil?
  missing_vars << 'RESTORE_TARGET_DB_NAME' if db_name.nil?
  exception_message = "Following environment variables are not set: #{missing_vars.join(', ')}" unless missing_vars.empty?
  raise exception_message if exception_message
  pg_path = File.expand_path('~/.pgpass')
  File.write(pg_path, "#{db_host_port}:*:#{db_user}:#{db_password}\n")
  File.chmod(0600, pg_path)
  ENV['PGPASSFILE'] = pg_path
  puts "PGPASSFILE updated: #{File.read(ENV['PGPASSFILE'])}"
  # usr = system("whoami")

  # check_cmd = ['psql', '-h', db_host_port.split(':').first]
  # check_cmd += ['-p', db_host_port.split(':').last] if db_host_port.split(':').size > 1
  # check_cmd += ['-U', db_user, '-tAc', "SELECT 1 FROM pg_database WHERE datname='#{db_name}'"]
  # exists_output, exists_err, exists_status = Open3.capture3(*check_cmd)
  # puts "Database is already exists" if exists_output.strip == '1'
  # unless exists_output.strip == '1'
  #   puts "Database #{db_name} does not exist, creating..."
  #   create_cmd = ['createdb', '-h', db_host_port.split(':').first]
  #   create_cmd += ['-p', db_host_port.split(':').last] if db_host_port.split(':').size > 1
  #   create_cmd += ['-U', db_user, db_name]
  #   create_output, create_err, create_status = Open3.capture3(*create_cmd)
  #   unless create_status.success?
  #     raise 'Database creation failed'
  #   end
  # end

  # Create admin Sequel connection
  if db_port && !db_port.empty?
    db_url = "postgres://#{db_user}:#{db_password}@#{db_host}:#{db_port}/#{db_name}"
    admin_db_url = "postgres://#{db_user}:#{db_password}@#{db_host}:#{db_port}/postgres"
  else
    db_url = "postgres://#{db_user}:#{db_password}@#{db_host}/#{db_name}"
    admin_db_url = "postgres://#{db_user}:#{db_password}@#{db_host}/postgres"
  end
  # Connect to 'postgres' so we can drop the target DB
  puts "Creating sequel connection to #{admin_db_url}"
  sequel_connection = Sequel.connect(admin_db_url)
  puts "Connection created with options #{sequel_connection.opts}"
  begin
    if db_name == default_db_name
      # If the database name is the same as the default database name, we will restore the backup into a new database then rename it to the default database name
      puts "You specified the same database as the origin one. Dump will replace original database"
      # OLD PIPELINE
      # drop_database(db_host, db_port, db_user, db_password, db_name + RESTORE_IN_ORIGIN_DB_SUFFIX)
      # create_and_restore(db_host, db_port, db_user, db_name + RESTORE_IN_ORIGIN_DB_SUFFIX, backup_path)
      # drop_database(db_host, db_port, db_user, db_password, db_name)
      # rename_db(db_host_port, db_user, db_password, db_name + RESTORE_IN_ORIGIN_DB_SUFFIX, db_name)
      # NEW PIPELINE
      drop_database_sequel(sequel_connection, db_name + RESTORE_IN_ORIGIN_DB_SUFFIX)
      create_and_restore_sequel(sequel_connection, db_name + RESTORE_IN_ORIGIN_DB_SUFFIX, db_password, backup_path)
      sequel_connection.transaction do
        rename_db_sequel(sequel_connection, db_name, db_name + OLD_DB_SUFFIX)
        rename_db_sequel(sequel_connection, db_name + RESTORE_IN_ORIGIN_DB_SUFFIX, db_name)
      end
      drop_database_sequel(sequel_connection, db_name + OLD_DB_SUFFIX)
      message = "Successfully restored dump into #{db_name}"
    else
      # OLD PIPELINE
      # Drop database if it exists
      # drop_database(db_host, db_port, db_user, db_password, db_name)
      # create_and_restore(db_host, db_port, db_user, db_name, backup_path) if db_name != default_db_name
      # NEW PIPELINE
      drop_database_sequel(sequel_connection, db_name)
      create_and_restore_sequel(sequel_connection, db_name, db_password, backup_path)
      message = "Successfully restored dump into #{db_name}"
    end
  rescue => e
    message = "Failed to restore #{db_name}:\n#{e.message}"
    raise message
  ensure
    sequel_connection.disconnect
    message
  end
end

# def create_and_restore(db_host, db_port, db_user, db_name, backup_path)
#   # Create database again
#   puts "Creating fresh database #{db_name}..."
#   create_cmd = ['createdb', '-h', db_host, '-U', db_user, db_name]
#   create_cmd += ['-p', db_port] if db_port
#   create_output, create_err, create_status = Open3.capture3(*create_cmd)
#   puts "Database #{db_name} created" if create_status.success?
#   unless create_status.success?
#     raise "Database creation failed: #{create_err}"
#   end
#
#   # Extract SQL file from backup .gz
#   begin
#     gzip_file_path = File.join(BACKUPS_DIR, backup_path)
#     sql_file = File.join(BACKUPS_DIR, File.basename(backup_path, '.gz'))
#     system("gzip -d #{gzip_file_path} -c > #{sql_file}")
#     unless $?.success?
#       raise "Error extracting SQL file from backup"
#     end
#     # Restore SQL file
#     restore_cmd = ['psql', '-h', db_host]
#     restore_cmd += ['-p', db_port] if db_port
#     restore_cmd += ['-U', db_user, '-d', db_name, '-f', sql_file]
#     puts "Restoring database..."
#     restore_out, restore_err, restore_status = Open3.capture3(*restore_cmd)
#
#     if restore_status.success?
#       message = "Database restored successfully"
#       puts message
#       return message
#     else
#       puts "Error restoring database: #{restore_err}"
#       raise 'Error restoring database'
#     end
#   rescue Exception => e
#     puts "Error restoring database: #{e.message}"
#     raise e
#   ensure
#     # Remove the SQL file
#     puts "Temporary SQL file removed"
#     system("rm #{sql_file}")
#   end
# end

def create_and_restore_sequel(sequel_connection, db_name, db_password, backup_path)
  # Create the database using SQL instead of createdb command
  puts "Creating fresh database #{db_name}..."
  begin
    sequel_connection.run("CREATE DATABASE #{db_name};")
    puts "Database #{db_name} created successfully."
  rescue Sequel::DatabaseError => e
    raise "Database creation failed: #{e.message}"
  end

  # Extract and restore the backup
  begin
    gzip_file_path = File.join(BACKUPS_DIR, backup_path)
    sql_file = File.join(BACKUPS_DIR, File.basename(backup_path, '.gz'))

    # Extract .gz file to .sql
    puts "Extracting backup file #{backup_path}..."
    system("gzip -d #{gzip_file_path} -c > #{sql_file}")
    raise "Error extracting SQL file from backup" unless $?.success?

    # Prepare psql restore command
    puts "Restoring database #{db_name} from #{sql_file}..."
    db_opts = sequel_connection.opts
    db_host = db_opts[:host] || 'localhost'
    db_port = db_opts[:port]
    db_user = db_opts[:user]

    restore_cmd = ['psql', '-h', db_host]
    restore_cmd += ['-p', db_port.to_s] if db_port
    restore_cmd += ['-U', db_user, '-d', db_name, '-f', sql_file]
    # Run restore
    env = ENV.to_h.merge('PGPASSWORD' => db_password)
    restore_out, restore_err, restore_status = Open3.capture3(env, *restore_cmd)

    if restore_status.success?
      puts "Database restored successfully."
      return "Database restored successfully."
    else
      puts "Error restoring database: #{restore_err}"
      raise "Restore failed: #{restore_err}"
    end

  rescue => e
    puts "Exception occurred during restore: #{e.message}"
    raise e

  ensure
    # Clean up temp .sql file
    if sql_file && File.exist?(sql_file)
      puts "Removing temporary SQL file #{sql_file}..."
      system("rm #{sql_file}")
    end
  end
end


# def drop_database(db_host, db_port, db_user, db_password, db_name)
#   db_url = nil
#   admin_db_url = nil
#   if db_port && !db_port.empty?
#     db_url = "postgres://#{db_user}:#{db_password}@#{db_host}:#{db_port}/#{db_name}"
#     admin_db_url = "postgres://#{db_user}:#{db_password}@#{db_host}:#{db_port}/postgres"
#   else
#     db_url = "postgres://#{db_user}:#{db_password}@#{db_host}/postgres"
#     admin_db_url = "postgres://#{db_user}:#{db_password}@#{db_host}/#{db_name}"
#   end
#   puts "Dropping database #{db_name}... With options: db_host: #{db_host}, db_port: #{db_port}, db_user: #{db_user}"
#   # Connect to 'postgres' so we can drop the target DB
#   db = Sequel.connect(admin_db_url)
#   begin
#     db.transaction do
#       # Terminate existing sessions
#       puts "Terminating active connections to #{db_name}..."
#       db.run(%Q(
#         SELECT pg_terminate_backend(pid)
#         FROM pg_stat_activity
#         WHERE datname = '#{db_name}' AND pid <> pg_backend_pid();
#       )) rescue nil
#
#       # Drop the database
#       puts "Dropping database #{db_name}..."
#       db.run("DROP DATABASE IF EXISTS #{db_name};")
#     end
#
#     puts "Database #{db_name} dropped successfully."
#   rescue => e
#     raise "Failed to drop database #{db_name}:\n#{e.message}"
#   ensure
#     # Unlock database
#     puts "Unlocking database #{db_name}..."
#     db.run("ALTER DATABASE #{db_name} WITH ALLOW_CONNECTIONS true;") rescue nil
#     db.disconnect
#   end
# end

def drop_database_sequel(sequel_connection, db_name)
  # Terminate existing sessions
  puts "Terminating active connections to #{db_name}..."
  sequel_connection.run(%Q(
    SELECT pg_terminate_backend(pid)
    FROM pg_stat_activity
    WHERE datname = '#{db_name}' AND pid <> pg_backend_pid();
  )) rescue nil

  # Drop the database
  puts "Dropping database #{db_name}..."
  sequel_connection.run("DROP DATABASE IF EXISTS #{db_name};")
end

# def rename_db(db_host_port, db_user, db_password, db_name, db_name_new)
#   db_url = "postgres://#{db_user}:#{db_password}@#{db_host_port}/#{db_name}"
#
#   puts "Renaming database #{db_name} to #{db_name_new}"
#
#   # Connect to the 'postgres' DB to manage the target DB
#   db = Sequel.connect(db_url)
#
#   begin
#     db.transaction do
#       puts "Locking database #{db_name} against new connections..."
#       db.run("ALTER DATABASE #{db_name} WITH ALLOW_CONNECTIONS false;")
#
#       puts "Terminating active connections to #{db_name}..."
#       db.run(%Q(
#         SELECT pg_terminate_backend(pid)
#         FROM pg_stat_activity
#         WHERE datname = '#{db_name}' AND pid <> pg_backend_pid();
#       ))
#
#       puts "Renaming database #{db_name} to #{db_name_new}..."
#       db.run("ALTER DATABASE #{db_name} RENAME TO #{db_name_new};")
#     end
#
#     puts "Database #{db_name} successfully renamed to #{db_name_new}"
#
#   rescue => e
#     raise "Database renaming failed:\n#{e.message}"
#   ensure
#     begin
#       puts "Re-enabling connections to #{db_name_new}..."
#       db.run("ALTER DATABASE #{db_name_new} WITH ALLOW_CONNECTIONS true;")
#     rescue => e
#       raise "Failed to unlock database:\n#{e.message}"
#     ensure
#       db.disconnect
#     end
#   end
# end

def rename_db_sequel(sequel_connection, db_name, db_name_new)
  begin
    puts "Locking database #{db_name} against new connections..."
    sequel_connection.run("ALTER DATABASE #{db_name} WITH ALLOW_CONNECTIONS false;")

    puts "Terminating active connections to #{db_name}..."
    sequel_connection.run(%Q(
      SELECT pg_terminate_backend(pid)
      FROM pg_stat_activity
      WHERE datname = '#{db_name}' AND pid <> pg_backend_pid();
    ))

    puts "Renaming database #{db_name} to #{db_name_new}..."
    sequel_connection.run("ALTER DATABASE #{db_name} RENAME TO #{db_name_new};")
    puts "Database #{db_name} successfully renamed to #{db_name_new}"

  rescue => e
    raise "Database renaming failed:\n#{e.message}"
  ensure
    begin
      puts "Re-enabling connections to #{db_name_new}..."
      sequel_connection.run("ALTER DATABASE #{db_name_new} WITH ALLOW_CONNECTIONS true;")
    rescue => e
      raise "Failed to unlock database:\n#{e.message}"
    end
  end
end