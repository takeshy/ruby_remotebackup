module Remotebackup
  class Node
    attr_accessor :ftype,:name,:make_map
    Month = {"Jan" => 1, "Feb" => 2, "Mar" => 3, "Apr" => 4, "May" => 5, "Jun" => 6, "Jul" => 7, "Aug" => 8,
              "Sep" => 9, "Oct" => 10, "Nov" => 11, "Dec" => 12}
    LS_INFO = {
      :redhat => {
        :ls_file => /([-a-z]*)\s+(\d+)\s+(\S+)\s+(\S+)\s+(\d*)\s+([A-Z][a-z]*)\s+(\d+)\s+([\d:]*)\s+(.*)/,
        :ls_link => /([-a-z]*)\s+(\d+)\s+(\S+)\s+(\S+)\s+(\d*)\s+([A-Z][a-z]*)\s+(\d+)\s+([\d:]*)\s+(.*)\s+->\s+(.*)/,
        :position => 
          {:access=>1,:link_num=>2,:user=>3,:group=>4,:size=>5,:month=>6,:day=>7,:yt=>8,:name=>9,:arrow=>10,:source=>11}
      },
      :debian => {
        :ls_file => /([-a-z]*)\s+(\d+)\s+(\S+)\s+(\S+)\s+(\d*)\s+([-0-9]*)\s+([\d:]*)\s+(.*)/,
        :ls_link => /([-a-z]*)\s+(\d+)\s+(\S+)\s+(\S+)\s+(\d*)\s+([-0-9]*)\s+([\d:]*)\s+(.*)\s+->\s+(.*)/,
        :position => 
          {:access=>1,:link_num=>2,:user=>3,:group=>4,:size=>5,:day =>6,:time =>7,:name=>8,:arrow=>9,:source=>10}
      }
    }

    def self.build(out)
      LS_INFO.each do|key,val|
        if val[:ls_file].match(out)
          return Node.new(key,out)
        end
      end
      nil
    end

    def to_date_time(match)
      if @type == :redhat
        month = Month[match[position[:month]]]
        day = match[position[:day]].to_i
        hour = 0
        minute = 0
        tmp_time = match[position[:yt]]
        if t = /(.*):(.*)/.match(tmp_time)
          year = DateTime.now.year
          hour = t[1].to_i
          minute = t[2].to_i
        else
          year = tmp_time.to_i
        end
        DateTime.new(year,month,day,hour,minute).to_s
      else
        DateTime.parse(match[position[:time]]).to_s
      end
    end

    def ls_file
      LS_INFO[@type][:ls_file]
    end

    def ls_link
      LS_INFO[@type][:ls_link]
    end

    def position
      LS_INFO[@type][:position]
    end

    def initialize(type,out)
      @type = type
      case out
      when /^-/
        if m = ls_file.match(out)
          @ftype = :file
          @name = m[position[:name]]
          @size = m[position[:size]].to_i
          @date = to_date_time(m)
          @make_map = lambda{ return {"size" => @size, "date" => @date}}
        end
      when /^l/
        if m = ls_link.match(out)
          @ftype = :symbolic
          @name = m[position[:name]]
          @source = m[position[:source]]
          @make_map = lambda{ return {"source" => @source}}
        end
      when /^d/
        if m = ls_file.match(out)
          @ftype = :directory
          @name = m[position[:name]]
        end
      else
        @ftype = :special
        $log.error("#{out} is not regular file. ignore.")
      end
    end
  end
end
