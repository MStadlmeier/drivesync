require_relative 'src/synchronizer'
require_relative 'src/config_manager'

VERSION = 1.3

def sync
  syncer = Synchronizer.new
  syncer.run
end

def print_version
  puts "DriveSync v#{VERSION}"
end

def print_help
  print_version
  puts "Sync your Google Drive with your Linux machine"
  puts "Project homepage: https://github.com/MStadlmeier/drivesync"
  puts "Config location: #{File.expand_path('~/.drivesync/config.yml')}"
  puts "Usage:"
  puts "  sync / no parameter - Start sync"
  puts "  help / -h - Display this message"
  puts "  -v / version - Display software version"
  puts "  reset - Deletes local Drive folder, manifest and authorization, resetting your install (this should fix any sync problems)"
end

def reset
  syncer = Synchronizer.new
  syncer.reset
end

arg = ARGV.length == 0 ? 'sync' : ARGV.first
case arg.downcase
when 'sync'
  sync
when 'help', '-h', '-help'
  print_help
when 'version', '-v', '-version'
  print_version
when 'reset'
  reset
else
  puts "Unrecognized parameter: '#{arg}' - try -h for usage instructions"
end