$:.unshift(File.dirname(__FILE__)) unless
$:.include?(File.dirname(__FILE__)) || $:.include?(File.expand_path(File.dirname(__FILE__)))
require 'rubygems'
require 'net/ssh'
require 'net/scp'
require "stringio"
require "fileutils"
require "rexml/document"
require "date"
require 'logger'
require 'yaml'
module Remotebackup
  VERSION='0.51.1'
  class Node
    attr_accessor :ftype,:name,:makeMap
    LS_FILE = /([-a-z]*)\s+(\d+)\s+(\S+)\s+(\S+)\s+(\d*)\s+([A-Z][a-z]*)\s+(\d+)\s+([\d:]*)\s+(.*)/
      LS_LINK = /([-a-z]*)\s+(\d+)\s+(\S+)\s+(\S+)\s+(\d*)\s+([A-Z][a-z]*)\s+(\d+)\s+([\d:]*)\s+(.*)\s+->\s+(.*)/
      Result = {:access=>0,:link_num=>1,:user=>2,:group=>3,:size=>4,:month=>5,:day=>6,:yt=>7,:name=>8,:arrow=>9,:source=>10}
    Month = {"Jan" => 1, "Feb" => 2, "Mar" => 3, "Apr" => 4, "May" => 5, "Jun" => 6, "Jul" => 7, "Aug" => 8,
              "Sep" => 9, "Oct" => 10, "Nov" => 11, "Dec" => 12}

    def initialize(out)
      if out =~ /[^\x20-\x7E]/
        $log.error("#{out} includes irregular char. ignore.")
        return
      end
      case out
      when /^-/
        if LS_FILE.match(out)
          @name = $9
          @ftype = :file
          @size = $5.to_i
          month = Month[$6]
          day = $7.to_i
          hour = 0
          minute = 0
          tmpTime = $8
          if tmpTime =~ /(.*):(.*)/
            year = DateTime.now.year
            hour = $1.to_i
            minute = $2.to_i
          else
            year = tmpTime.to_i
          end
          @date = DateTime.new(year,month,day,hour,minute).to_s
          @makeMap = lambda{ return {"size" => @size, "date" => @date}}
        else
          $log.error("#{out} is not recognized. ignore.")
        end
      when /^l/
        if LS_LINK.match(out)
          @name = $9
          @ftype = :symbolic
          @source = $10
          @makeMap = lambda{ return {"source" => @source}}
        end
      when /^d/
        if LS_FILE.match(out)
          @name = $9
          @ftype = :directory
        end
      else
        @ftype = :special
        $log.error("#{out} is not regular file. ignore.")
      end
    end
  end
  class BackupInfo
    attr_accessor :fileMap,:mod,:last_file
    def initialize(name,server,user,password,path,ignore_list)
      @mod = false
      @name = name
      @server = server
      @user = user
      @password = password
      @path = path
      @ignore_list = ignore_list
      @nowTime = DateTime.now
      @fileMap = {"file" => Hash.new,"symbolic" => Hash.new,"directory"=>Array.new}
      Net::SSH.start(@server,@user,:password=>@password) { |session|
        makeFileMapList(session,"")
      }
    end
    def ignore_check(target)
      if @ignore_list
        @ignore_list.each do |ignore|
          if target =~ /#{ignore}/
            return false
          end
        end
      end
      return true
    end
    def makeFileMapList(session,target)
      if target != ""
        target_path = @path +"/"+target
      else
        target_path = @path
      end
      cmd = "export LANG=C;ls -la #{target_path}"
      out = ""
      channel = session.open_channel do |ch|
        ch.exec cmd do |ch,success|
          ch.on_data do |c,data|
            out += data
          end
        end
      end
      channel.wait
      if out =~ /No such file/
        $log.error("can't open path:#{target_path}") 
        return
      end
      if out == ""
        return
      end
      lines = StringIO.new(out).readlines
      if lines[0].split().length < 9
        @fileMap["directory"].push target unless target == ""
        makeFileMap(session,target,lines)
      else
        node = Node.new(lines[0].chomp)
        if node.ftype == :symbolic
          @fileMap["symbolic"][File.basename(@path)] = node.makeMap.call
        elsif node.ftype == :file
          @fileMap["file"][File.basename(@path)] = node.makeMap.call
        end
      end
    end
    def makeFileMap(session,target,lines)
      lines.each do |line|
        if line.split().length < 9
          next
        end
        node = Node.new(line.chomp)
        if  not node.name or node.name == "." or node.name == ".." 
          next
        end
        if target != ""
          target_name = target +"/"+ node.name
        else
          target_name = node.name
        end
        unless ignore_check(target_name)
          next
        end
        case node.ftype
        when :directory
          makeFileMapList(session,target_name)
        when :special
          next
        when :file
          @fileMap["file"][target_name] = node.makeMap.call
        when :symbolic
          @fileMap["symbolic"][target_name] = node.makeMap.call
        end
      end
    end
    def outputYaml(out_dir)
      output_dir = out_dir + "/" + @name
      f = output_dir + "/" + date_to_filename + ".yml"
      File.open(f,"w") do |f|
        f.write YAML.dump(@fileMap)
      end
    end
    def cleanFileInfo()
      FileUtils.touch([@last_file])
    end
    def load_last_yaml(output_dir)
      files = Array.new
      if FileTest.directory?(output_dir)
        dirs = Dir.glob(output_dir+ "/*.yml")
        dirs.each do |file|
          files.push file
        end
      end
      if files.length == 0
        return {"file" => Hash.new,"symbolic" => Hash.new,"directory"=>Array.new}
      end
      @last_file = files.sort.pop
      return YAML.load(File.read(@last_file))
    end
    def differencial_copy(out_dir)
      output_dir = out_dir + "/" + @name
      FileUtils.mkdir_p(output_dir)
      oldFileInfoMap = load_last_yaml(output_dir)
      @fileMap["directory"].each do |dir|
        unless oldFileInfoMap["directory"].include?(dir)
          @mod = true
          msg_out "create directory:#{dir}"
          FileUtils.mkdir_p(output_dir + "/" + dir)
        end
      end
      oldFileMap = oldFileInfoMap["symbolic"]
      @fileMap["symbolic"].each do |key,val|
        if !oldFileMap[key] || oldFileMap[key]["source"] != val["source"]
          @mod = true
          if !oldFileMap[key]  
            msg_out "create symbolic:#{key}"
          else
            msg_out "modified symbolic:#{key}"
          end
        end
      end
      oldFileMap = oldFileInfoMap["file"]
      Net::SSH.start(@server, @user, :password => @password) do |ssh|
        @fileMap["file"].each do |key,val|
          if !oldFileMap[key] || oldFileMap[key]["date"] != val["date"] 
            @mod = true
            file_name = output_dir + "/" + key + date_to_filename
            orig = "#{@path}/#{key}".gsub(/ /,"\\ ").gsub(/\(/,"\\(").gsub(/\)/,"\\)").gsub(/&/,"\\\\&").gsub(/\=/,"\\=")
            msg_out "scp #{orig} #{file_name}"
            begin
              ssh.scp.download!(orig,file_name)
            rescue
              $log.error("#{orig} can't copy. ignore.")
              next
            end
            val["file_name"] = file_name
            if !oldFileMap[key]
              msg_out "create file:#{key}"
            else
              msg_out "modified file:#{key}"
            end
          else
            val["file_name"] = oldFileMap[key]["file_name"]
          end
        end
      end
    end
    def zerosup(i)
      if i < 10
        "0" + i.to_s
      else
        i.to_s
      end
    end
    def date_to_filename()
      @nowTime.year.to_s + "_" + zerosup(@nowTime.month) + "_" + zerosup(@nowTime.day) + "_" + zerosup(@nowTime.hour) + "_" + zerosup(@nowTime.min) 
    end
  end
  class Backup
    def initialize(config_file,config_out_dir)
      @config_file = config_file
      @config_out_dir = config_out_dir
      @doc = REXML::Document.new(File.open(@config_file))
      @top = @doc.elements["/backups"]
      @conf_backups = Array.new
      unless @top
        oops("/backups is not set in #{@config_file}.")
      end
      @top.each_element do |backup|
        bkup_info = Hash.new
        backup.each_element do |elem|
          if elem.name == "ignore_list"
            ignores = Array.new
            elem.each_element do |ignore|
              if ignore.text
                ignores.push(ignore.text)
              end
            end
            bkup_info["ignore_list"] = ignores
          else
            bkup_info[elem.name] = elem.text
          end
        end
        @conf_backups.push(bkup_info)
      end
    end
    def start
      @conf_backups.each do |conf|
        bkup = BackupInfo.new(conf["name"],conf["server"],conf["user"],conf["password"],conf["path"],conf["ignore_list"])
        msg_out "--------------------------------"
        msg_out "Backup start #{conf['name']}"
        msg_out "--------------------------------"
        bkup.differencial_copy(@config_out_dir)
        if bkup.mod
          bkup.outputYaml(@config_out_dir)
        else
          bkup.cleanFileInfo()
        end
      end
    end
  end
  class Restore
    def initialize(config_file,config_out_dir)
      @config_file = config_file
      @file_info_map = YAML.load_file(config_file)
      @config_out_dir = config_out_dir
      FileUtils.mkdir_p(@config_out_dir)
    end
    def start
      msg_out "-------------------------------------------"
      msg_out "Restore start #{File.dirname(@config_file)}"
      msg_out "-------------------------------------------"
      @file_info_map["directory"].each do |dir|
        msg_out "mkdir -p #{@config_out_dir}/#{dir}"
        FileUtils.mkdir_p(@config_out_dir + "/" + dir)
      end
      @file_info_map["symbolic"].each do |key,val|
        FileUtils.rm_r([@config_out_dir + "/" + key],{:force=>true})
        msg_out "link -s  #{val['source']} #{@config_out_dir}/#{key}"
        FileUtils.symlink(val["source"],@config_out_dir + "/" + key)
      end
      @file_info_map["file"].each do |key,val|
        unless val['file_name']
          $log.error("#{key} can't copy. ignore.")
          next
        end
        msg_out "cp #{val['file_name']} #{@config_out_dir}/#{key}"
        FileUtils.cp(val["file_name"],@config_out_dir + "/" + key)
      end
    end
  end
end
