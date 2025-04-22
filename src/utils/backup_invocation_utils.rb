require_relative 'common_utils'
def start_backups
  loop do
    latest_backup_time = define_latest_backup_time
    if latest_backup_time.nil? || latest_backup_time < Time.now - 60 * 60
      backup_cmd = ['/bin/bash', "#{Dir.pwd}/backup#{ENV['DEBUG'].nil? ? '' : '_debug'}.sh"]
      puts "Call backups script at #{Time.now}"
      script_out, script_err, script_status = Open3.capture3(*backup_cmd)

      if script_status.exitstatus == 0
        puts "Backups script performed successfully; output:\n#{'*' * 150}\n#{script_out}#{'*' * 150}"
        $last_backup_report = { status_code: script_status.exitstatus, message: script_out , error_message: script_err }
      else
        puts "Backup failed with exit status: #{script_status.exitstatus}"
        puts "Script output:\n#{'*' * 150}\n#{script_out}#{'*' * 150}"
        puts "\e[31mError message:\n#{'*' * 150}\n#{script_err}#{'*' * 150}\e[0m"
        $last_backup_report = { status_code: script_status.exitstatus, message: script_out, error_message: script_err }
      end
      begin
        garbage_collect
      rescue Exception => e
        puts "Error during garbage collection: #{e}"
      end
      if script_status.exitstatus == 0
        begin
          perform_rsync
        rescue Exception => e
          puts "Rsync call error: #{e}"
        end
      end
    else
      puts "Skipping backup because it was performed less than 1 hour ago"
      $last_backup_report = { status_code: 0, message: 'Skipping backup because it was performed less than 1 hour ago', error_message: '' }
    end
    sleep ENV['BACKUP_INTERVAL'].to_i * 60
  end
end

def perform_rsync
  $last_rsync_reports = []
  puts "Starting rsync backup transfer"
  rsync_targets = ENV['RSYNC_TARGETS']
  rsync_targets_private_key = ENV['RSYNC_TARGETS_PRIVATE_KEY']

  if rsync_targets.nil? || rsync_targets.empty?
    puts "No rsync targets specified"
    $last_rsync_reports << { status_code: 1, message: 'No rsync targets specified', error_message: 'No rsync targets specified' }
    raise "No rsync targets specified"
  end
  if rsync_targets_private_key.nil?
    puts "No rsync targets private key specified"
    $last_rsync_reports << { status_code: 1, message: 'No rsync targets private key specified', error_message: 'No rsync targets private key specified' }
    raise "No rsync targets private key specified"
  end

  rsync_targets = rsync_targets.split(',')
  Tempfile.create('rsync_key') do |key_file|
    key_file.write(rsync_targets_private_key)
    key_file.chmod(0600)  # Secure permissions for SSH
    key_file.flush
    rsync_targets.each do |rsync_target|
      rsync_command = "rsync -av --delete -e \"ssh -vvv -i #{key_file.path} -o StrictHostKeyChecking=no -T\" #{BACKUPS_DIR}/ #{rsync_target}/"
      puts "Running: #{rsync_command}"
      rsync_out, rsync_err, rsync_status = Open3.capture3(rsync_command)
      if rsync_status.exitstatus == 0
        puts "Rsync transfer for #{rsync_target} completed successfully"
        $last_rsync_reports << { status_code: rsync_status.exitstatus, message: "Output of rsync with target #{rsync_target}:\n#{rsync_out}", error_message: rsync_err }
      else
        puts "Rsync transfer for #{rsync_target} failed with exit status: #{rsync_status.exitstatus}"
        puts "Rsync output:\n#{'*' * 150}\n#{rsync_out}#{'*' * 150}"
        puts "\e[31mError message:\n#{'*' * 150}\n#{rsync_err}#{'*' * 150}\e[0m"
        $last_rsync_reports << { status_code: rsync_status.exitstatus, message: "Output of rsync with target #{rsync_target}:\n#{rsync_out}", error_message: rsync_err }
      end
    end
    puts "All rsync transfers completed"
  end
end

def garbage_collect
  puts "Garbage collection started"

  backups_categories = { this_week: {}, this_month: {}, other_months: {} }
  marked_to_retain = Set.new

  current_date = Time.now
  current_year, current_month, current_day, current_week_in_year = current_date.year, current_date.month, current_date.day, current_date.strftime('%U').to_i
  puts "Analyzing backups in #{BACKUPS_DIR}"
  Dir.children(BACKUPS_DIR).each do |filename|
    date_time_string = filename.split('_')[-2..-1].join('').split('.').first
    year, month, day, hour, minute, second = date_time_string[0..3], date_time_string[4..5], date_time_string[6..7], date_time_string[8..9], date_time_string[10..11], date_time_string[12..13]
    backup_date = Time.new(year, month, day, hour, minute, second, "+03:00")
    backup_week_in_year = backup_date.strftime('%U').to_i
    backup = { filename: filename, date: backup_date }

    if backup_date.year == current_year && backup_date.month == current_month
      if backup_week_in_year == current_week_in_year # Backups from current week
        if backup_date.day == current_day # Backups from current day
          # backups_categories[:this_day] << backup

          marked_to_retain.add(backup[:filename])
        else # Backups from current month but not from current day
          day_of_week = backup_date.strftime('%A')
          backups_categories[:this_week][day_of_week] ||= Set.new
          backups_categories[:this_week][day_of_week] << backup
        end
      else # Backups from current month but not from current week
        backups_categories[:this_month][backup_week_in_year] ||= Set.new
        backups_categories[:this_month][backup_week_in_year] << backup
      end
    else
      backups_categories[:other_months][year+month] ||= Set.new
      backups_categories[:other_months][year+month] << backup
    end
  end

  puts "Marking backups to retain:"
  marked_to_retain.each { |filename| puts "Marking backup #{filename} for retention" }
  backups_categories.each do |category_key, backups_category|
    backups_category.each do |category_key, backups|
      latest_backup = backups.max_by { |backup| backup[:date] }
      puts "Marking backup #{latest_backup[:filename]} for retention"
      marked_to_retain.add(latest_backup[:filename]) if latest_backup
    end
  end
  puts "Total marked backups: #{marked_to_retain.size}"
  deleted_backups = 0
  puts "Deleting backups:"
  Dir.children(BACKUPS_DIR).each do |filename|
    next if marked_to_retain.include?(filename)
    puts "Deleting backup #{filename}"
    File.delete(File.join(BACKUPS_DIR, filename))
    deleted_backups += 1
  end
  puts "Deleting process completed. Deleted #{deleted_backups} backups."
end

def define_latest_backup_time
  latest_backup_time = nil
  Dir.children(BACKUPS_DIR).each do |filename|
    backup_date = determine_backup_time(filename)
    if latest_backup_time.nil? || backup_date > latest_backup_time
      latest_backup_time = backup_date
    end
  end
  latest_backup_time
end