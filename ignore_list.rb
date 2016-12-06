class IgnoreList
  attr_reader :files

	def initialize path
    if path.nil? or path.empty?
      @files = []
    else
      begin
        @files = File.readlines(path)
        @files.each {|f| f.sub! "\n", ""}
      rescue
        Log.log_error "Cannot read ignore list #{path}"
      end
    end
  end

  def include? path
    @files.each do |line|
      next if line.nil? or line.empty?
      return true if path == line
      return true if path.start_with?(line[0..-2]) and line[-1] == '*'
    end
    false
  end
end