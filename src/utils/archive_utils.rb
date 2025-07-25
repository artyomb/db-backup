require 'zlib'

def extract_sql_from_rar(incoming_file)
  # TODO: replace tempdir with actual dir
  temp_dir = Dir.mktmpdir
  system("unrar e -y #{incoming_file.path} #{temp_dir.to_s}")

  extracted_files = Dir.children(temp_dir)
  raise "RAR archive must contain exactly one file" if extracted_files.size != 1
  raise "File in archive must be .sql file" unless extracted_files.first.end_with?('.sql')

  temp_file = Tempfile.new(['extracted', '.sql'])
  File.write(temp_file.path, File.read(File.join(temp_dir, extracted_files.first)))

  FileUtils.remove_entry(temp_dir)
  temp_file
end

def extract_sql_from_gz(incoming_file)
  # Ensure file has .gz extension
  raise "Expected a .gz file" unless File.extname(incoming_file.path) == ".gz"

  # Create a Tempfile to hold the extracted SQL
  temp_file = Tempfile.new(['extracted', '.sql'])

  # Read compressed input and write to temp SQL file
  Zlib::GzipReader.open(incoming_file.path) do |gz|
    File.write(temp_file.path, gz.read)
  end

  # Verify it ends in .sql by content/intent (optional check)
  unless temp_file.path.end_with?(".sql")
    # Or inspect the content, if needed
    first_line = File.open(temp_file.path, &:readline)
    unless first_line.downcase.include?("sql")
      raise "Extracted content does not appear to be SQL"
    end
  end
  temp_file
end

def archive_into_gz(source_file, target_dir)
  # Create .gz file and write compressed data
  Zlib::GzipWriter.open(target_dir) do |gz|
    IO.copy_stream(source_file, gz)
  end

  puts "Compressed file saved to: #{target_dir}"

end