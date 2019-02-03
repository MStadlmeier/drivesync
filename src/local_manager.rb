include Log
require 'fileutils'
require_relative './helper'

class LocalManager
  attr_accessor :files

  def initialize config
    @root = config['drive_path']
    @root += '/' if @root[-1] != '/'
    @config = config
  end

  def get_files
    @files = Helper.dir_glob(File.join(@root, '**', '*'), @config['follow_symlinks']).reject{|f| File.directory?(f)}
    @files = @files.collect{|file| file.sub @root, ''}
    @files = @files.reject{|f| Helper.file_ignored?(f, @config) || too_large?(f)}
  end

  #For consistency's sake..
  #Returns the path if file exists, nil otherwise
  def find_by_path path
    return nil if @files == nil
    @files.find{|file| file == path}
  end

  private

  def too_large? path
    return false if @config['max_file_size'].nil?
    begin
      return File.size(@root + path).to_f / 2**20 > @config['max_file_size']
    rescue SystemCallError
      true
    end
  end
end