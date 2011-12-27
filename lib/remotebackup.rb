require 'rubygems'
require 'net/ssh'
require 'net/scp'
require "stringio"
require "fileutils"
require "date"
require 'logger'
require 'yaml'
require 'node'
module Remotebackup
  class BackupInfo
    attr_accessor :file_map,:mod,:last_file
    def initialize(args)
      @mod = false
      @name = args["name"] || args["server"]
      @server = args["server"]
      @user = args["user"]
      @options = {}
      @options[:port] = args["port"].to_i if args["port"]
      @options[:password] = args["password"] if args["password"]
      @options[:passphrase] = args["passphrase"] if args["passphrase"]
      if args["key"]
        @options[:keys] = [File.expand_path(args["key"])] 
      end
      @path = args["path"]
      @ignore_list = args["ignore_list"] || []
      @nowTime = DateTime.now
      @file_map = {"file" => Hash.new,"symbolic" => Hash.new,"directory"=>Array.new}
      Net::SSH.start(@server,@user,@options) { |session|
        make_file_map_list(session,"")
      }
    end
    def ignore_check(target)
      @ignore_list.each do |ignore|
        if target =~ /#{ignore}/
          return false
        end
      end
      return true
    end
    def make_file_map_list(session,target)
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
      if !Node.build(lines[0].chomp)
        @file_map["directory"].push target unless target == ""
        makeFileMap(session,target,lines)
      else
        node = Node.build(lines[0].chomp)
        if node.ftype == :symbolic
          @file_map["symbolic"][File.basename(@path)] = node.make_map.call
        elsif node.ftype == :file
          @file_map["file"][File.basename(@path)] = node.make_map.call
        end
      end
    end
    def makeFileMap(session,target,lines)
      lines.each do |line|
        node = Node.build(line.chomp)
        next unless node
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
          make_file_map_list(session,target_name)
        when :special
          next
        when :file
          @file_map["file"][target_name] = node.make_map.call
        when :symbolic
          @file_map["symbolic"][target_name] = node.make_map.call
        end
      end
    end
    def outputYaml(out_dir)
      output_dir = out_dir + "/" + @name
      f = output_dir + "/" + date_to_filename + ".yml"
      File.open(f,"w") do |f|
        f.write YAML.dump(@file_map)
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
      old_file_info_map = load_last_yaml(output_dir)
      @file_map["directory"].each do |dir|
        unless old_file_info_map["directory"].include?(dir)
          @mod = true
          msg_out "create directory:#{dir}"
          FileUtils.mkdir_p(output_dir + "/" + dir)
        end
      end
      old_file_map = old_file_info_map["symbolic"]
      @file_map["symbolic"].each do |key,val|
        if !old_file_map[key] || old_file_map[key]["source"] != val["source"]
          @mod = true
          if !old_file_map[key]  
            msg_out "create symbolic:#{key}"
          else
            msg_out "modified symbolic:#{key}"
          end
        end
      end
      old_file_map = old_file_info_map["file"]
      Net::SSH.start(@server, @user,@options) do |ssh|
        @file_map["file"].each do |key,val|
          key = key.dup.force_encoding("utf-8")
          if !old_file_map[key] || old_file_map[key]["date"] != val["date"] 
            @mod = true
            file_name = output_dir + "/" + key + date_to_filename
            orig = "#{@path}/#{key}"
            msg_out "scp #{orig} #{file_name}"
            begin
              ssh.scp.download!(orig,file_name)
            rescue
              $log.error("#{orig} can't copy. ignore.")
              next
            end
            val["file_name"] = file_name
            if !old_file_map[key]
              msg_out "create file:#{key}"
            else
              msg_out "modified file:#{key}"
            end
          else
            val["file_name"] = old_file_map[key]["file_name"]
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
      @doc = YAML.load_file(@config_file)
      @conf_backups = Array.new
      @doc.each do |key,val|
        @conf_backups.push(val.merge(:name => key))
      end
    end
    def start
      @conf_backups.each do |conf|
        bkup = BackupInfo.new(conf)
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
