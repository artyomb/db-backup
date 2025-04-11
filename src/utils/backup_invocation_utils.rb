def start_backups
  loop do
    system("/bin/bash #{Dir.pwd}/backup#{ENV['DEBUG'].nil? ? '' : '_debug'}.sh")
    garbage_collect
    sleep ENV['BACKUP_INTERVAL'].to_i * 60
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
  # backups_categories[:this_week].each do |day_of_week, backups|
  #   latest_backup = backups.max_by { |backup| backup[:date] }
  #   marked_to_retain.add(latest_backup[:filename]) if latest_backup
  # end
  # backups_categories[:this_month].each do |week_in_year, backups|
  #   latest_backup = backups.max_by { |backup| backup[:date] }
  #   marked_to_retain.add(latest_backup[:filename]) if latest_backup
  # end
  # backups_categories[:other_months].each do |year_month, backups|
  #   latest_backup = backups.max_by { |backup| backup[:date] }
  #   marked_to_retain.add(latest_backup[:filename]) if latest_backup
  # end
end