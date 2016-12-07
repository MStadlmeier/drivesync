include Log
require 'fileutils'

class LocalManager
  attr_accessor :files

  def initialize config
    @root = config['drive_path']
    @root += '/' if @root[-1] != '/'
    @config = config
    FileUtils.mkdir_p @root
  end

  def get_files
    @files = Dir[File.join(@root, '**', '*')].reject{|f| File.directory?(f)}
    @files = @files.collect{|file| file.sub @root, ''}
    @files = @files.reject{|f| file_ignored? f}
  end

  #For consistency's sake..
  #Returns the path if file exists, nil otherwise
  def find_by_path path
    return nil if @files == nil
    @files.select{|file| file == path}.first
  end

  private

  def file_ignored? path
    @config['ignored_files'].each do |ign|
      return true if ign.match path
    end
    false
  end
end