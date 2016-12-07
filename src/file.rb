class Google::Apis::DriveV3::File
	attr_accessor :path
end

#List of files that are present locally but not remotely and vice-versa
class FileDiff
	#Remote ahead and both are Drive::File list
	#Local ahead is string list
	attr_accessor :remote_ahead, :local_ahead, :both

	def initialize
		@remote_ahead = []
		@local_ahead = []
    @both = []
	end
end