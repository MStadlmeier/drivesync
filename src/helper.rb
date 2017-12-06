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
end