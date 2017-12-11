class Helper
  def self.file_ignored? path, config
    if config['inclusion'] == 'whitelist'
      config['whitelist'].each do |entry|
        return false if File.fnmatch entry, path
      end
      return true
    else
      config['blacklist'].each do |entry|
        return true if File.fnmatch entry, path
      end
      return false
    end
  end

  #Returns true if the path looks ok to delete(not empty, root or home directory)
  def self.safe_path? path
    return false if path.nil?
    path = path.strip
    return false if path == ''
    return false if path == '/'
    return false if path == Dir.home
    return false if path == Dir.home + '/'
    true
  end
end