module Timeliness
  module Parser
    class MissingTimezoneSupport < StandardError; end

    class << self

      def parse(value, *args)
        return value unless value.is_a?(String)

        options = args.last.is_a?(Hash) ? args.pop : {}
        type = args.first

        time_array = _parse(value, type, options)
        return nil if time_array.nil?

        override_values_by_type(time_array, type, options) unless type == :datetime
        make_time(time_array[0..6], options[:zone])
      rescue NoMethodError => ex
        raise ex unless ex.message =~ /zone/
        raise MissingTimezoneSupport, "ActiveSupport must be loaded to use timezones other than :utc and :local."
      end

      def make_time(time_array, zone=nil)
        return nil unless fast_date_valid_with_fallback(*time_array[0..2])

        zone ||= Timeliness.default_timezone
        case zone
        when :utc, :local
          time_with_datetime_fallback(zone, *time_array.compact)
        when :current
          Time.zone.local(*time_array)
        else
          Time.use_zone(zone) { Time.zone.local(*time_array) }
        end
      rescue ArgumentError, TypeError
        nil
      end

      def _parse(string, type=nil, options={})
        if options[:strict] && type
          set = Definitions.send("#{type}_format_set")
          set.match(string, options[:format])
        else
          values = nil
          Definitions.format_set(type, string).find {|set| values = set.match(string, options[:format]) }
          values
        end
      rescue
        nil
      end

      private

      def override_values_by_type(values, type, options)
        case type
        when :date
          values[3..7] = nil
        when :time
          values[0..2] = current_date(options)
        when nil
          dummy_date = current_date(options)
          values[0] ||= dummy_date[0]
          values[1] ||= dummy_date[1]
          values[2] ||= dummy_date[2]
        end
      end

      def current_date(options)
        now = if options[:now]
          options[:now]
        elsif options[:zone]
          current_time_in_zone(options[:zone])
        else
          Timeliness.date_for_time_type
        end
        now.is_a?(Array) ? now[0..2] : [now.year, now.month, now.day]
      end

      def current_time_in_zone(zone)
        case zone
        when :utc, :local
          Time.now.send("get#{zone}")
        when :current
          Time.current
        else
          Time.use_zone(zone) { Time.current }
        end
      end

      # Taken from ActiveSupport and simplified
      def time_with_datetime_fallback(utc_or_local, year, month=1, day=1, hour=0, min=0, sec=0, usec=0)
       return nil if hour > 23 || min > 59 || sec > 59
        ::Time.send(utc_or_local, year, month, day, hour, min, sec, usec)
      rescue
        offset = utc_or_local == :local ? (::Time.local(2007).utc_offset.to_r/86400) : 0
        ::DateTime.civil(year, month, day, hour, min, sec, offset)
      end

      # Enforce strict date part validity which the Time class does not.
      # Only does full date check if month and day are possibly invalid.
      def fast_date_valid_with_fallback(year, month, day)
        month < 13 && (day < 29 || Date.valid_civil?(year, month, day))
      end

    end

  end
end
