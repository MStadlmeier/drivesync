require_relative 'src/synchronizer'
require_relative 'src/config_manager'
require 'open-uri'

VERSION = '1.4.0'
CHANGELOG_URL = 'https://raw.githubusercontent.com/MStadlmeier/drivesync/master/CHANGELOG'

def check_for_update
  #Not at all hacky way of checking for updates
  begin
    changelog = open(CHANGELOG_URL).read
    version = changelog.split("\n").first.split(' ')[1].strip
    if version != VERSION
      puts "New version available - latest version is: #{version}"
      puts "Get the latest version by running 'git pull' in DriveSync folder or by going to the project website (https://github.com/MStadlmeier/drivesync) and downloading the latest version"
    end
  rescue StandardError
  end
end

def sync
  syncer = Synchronizer.new
  syncer.run
  check_for_update
end

def diff
  syncer = Synchronizer.new
  syncer.print_diff
end

def print_version
  puts "DriveSync v#{VERSION}"
  check_for_update
end

def print_help
  print_version
  puts "Sync your Google Drive with your Linux machine"
  puts "Project homepage: https://github.com/MStadlmeier/drivesync"
  puts "Config location: #{File.expand_path('~/.drivesync/config.yml')}"
  puts "Usage:"
  puts "  sync / no parameter - Start sync"
  puts "  config / -c - Opens the config file in your default text editor"
  puts "  diff - Prints a diff without syncing anything"
  puts "  reset - Deletes local Drive folder, manifest and authorization, resetting your install (this should fix any sync problems)"
  puts "  -v / version - Display software version"
  puts "  help / -h - Display this message"
end

def reset
  check_for_update
  syncer = Synchronizer.new
  syncer.reset
end

def config
  system("\"${EDITOR:-vi}\" #{File.expand_path('~/.drivesync/config.yml')}")
end

arg = ARGV.length == 0 ? 'sync' : ARGV.first
case arg.downcase
when 'sync'
  sync
when 'diff'
  diff
when 'help', '-h', '-help'
  print_help
when 'version', '-v', '-version'
  print_version
when 'reset'
  reset
when 'config', '-c'
  config
else
  puts "Unrecognized parameter: '#{arg}' - try -h for usage instructions"
end
