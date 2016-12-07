require 'date'

class Time
	def to_datetime
		seconds = sec + Rational(usec, 10**6)
    offset = Rational(utc_offset, 60*60*24)
    DateTime.new year, month, day, hour, min, seconds, offset
  end
end

class DateTime
  #For some reason, the > operator returns true even for 2 identical DateTimes, so I guess this is necessary..
  def is_after? other
    (self - other).to_f >  (1 / (24.0 * 60 * 60))
  end

  def is_before? other
    other.is_after? self
  end
end