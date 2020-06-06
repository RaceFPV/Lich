module Setting
   @@load = proc { |args|
      unless script = Script.current
         respond '--- error: Setting.load: calling script is unknown'
         respond $!.backtrace[0..2]
         next nil
      end
      if script.class == ExecScript
         respond "--- Lich: error: Setting.load: exec scripts can't have settings"
         respond $!.backtrace[0..2]
         exit
      end
      if args.empty?
         respond '--- error: Setting.load: no setting specified'
         respond $!.backtrace[0..2]
         exit
      end
      if args.any? { |a| a.class != String }
         respond "--- Lich: error: Setting.load: non-string given as setting name"
         respond $!.backtrace[0..2]
         exit
      end
      values = Array.new
      for setting in args
         begin
            v = Lich.db.get_first_value('SELECT value FROM script_setting WHERE script=? AND name=?;', script.name.encode('UTF-8'), setting.encode('UTF-8'))
         rescue SQLite3::BusyException
            sleep 0.1
            retry
         end
         if v.nil?
            values.push(v)
         else
            begin
               values.push(Marshal.load(v))
            rescue
               respond "--- Lich: error: Setting.load: #{$!}"
               respond $!.backtrace[0..2]
               exit
            end
         end
      end
      if args.length == 1
         next values[0]
      else
         next values
      end
   }
   @@save = proc { |hash|
      unless script = Script.current
         respond '--- error: Setting.save: calling script is unknown'
         respond $!.backtrace[0..2]
         next nil
      end
      if script.class == ExecScript
         respond "--- Lich: error: Setting.load: exec scripts can't have settings"
         respond $!.backtrace[0..2]
         exit
      end
      if hash.class != Hash
         respond "--- Lich: error: Setting.save: invalid arguments: use Setting.save('setting1' => 'value1', 'setting2' => 'value2')"
         respond $!.backtrace[0..2]
         exit
      end
      if hash.empty?
         next nil
      end
      if hash.keys.any? { |k| k.class != String }
         respond "--- Lich: error: Setting.save: non-string given as a setting name"
         respond $!.backtrace[0..2]
         exit
      end
      if hash.length > 1
         begin
            Lich.db.execute('BEGIN')
         rescue SQLite3::BusyException
            sleep 0.1
            retry
         end
      end
      hash.each { |setting,value|
         begin
            if value.nil?
               begin
                  Lich.db.execute('DELETE FROM script_setting WHERE script=? AND name=?;', script.name.encode('UTF-8'), setting.encode('UTF-8'))
               rescue SQLite3::BusyException
                  sleep 0.1
                  retry
               end
            else
               v = SQLite3::Blob.new(Marshal.dump(value))
               begin
                  Lich.db.execute('INSERT OR REPLACE INTO script_setting(script,name,value) VALUES(?,?,?);', script.name.encode('UTF-8'), setting.encode('UTF-8'), v)
               rescue SQLite3::BusyException
                  sleep 0.1
                  retry
               end
            end
         rescue SQLite3::BusyException
            sleep 0.1
            retry
         end
      }
      if hash.length > 1
         begin
            Lich.db.execute('END')
         rescue SQLite3::BusyException
            sleep 0.1
            retry
         end
      end
      true
   }
   @@list = proc {
      unless script = Script.current
         respond '--- error: Setting: unknown calling script'
         next nil
      end
      if script.class == ExecScript
         respond "--- Lich: error: Setting.load: exec scripts can't have settings"
         respond $!.backtrace[0..2]
         exit
      end
      begin
         rows = Lich.db.execute('SELECT name FROM script_setting WHERE script=?;', script.name.encode('UTF-8'))
      rescue SQLite3::BusyException
         sleep 0.1
         retry
      end
      if rows
         # fixme
         next rows.inspect
      else
         next nil
      end
   }
   def Setting.load(*args)
      @@load.call(args)
   end
   def Setting.save(hash)
      @@save.call(hash)
   end
   def Setting.list
      @@list.call
   end
end

module GameSetting
   def GameSetting.load(*args)
      Setting.load(args.collect { |a| "#{XMLData.game}:#{a}" })
   end
   def GameSetting.save(hash)
      game_hash = Hash.new
      hash.each_pair { |k,v| game_hash["#{XMLData.game}:#{k}"] = v }
      Setting.save(game_hash)
   end
end

module CharSetting
   def CharSetting.load(*args)
      Setting.load(args.collect { |a| "#{XMLData.game}:#{XMLData.name}:#{a}" })
   end
   def CharSetting.save(hash)
      game_hash = Hash.new
      hash.each_pair { |k,v| game_hash["#{XMLData.game}:#{XMLData.name}:#{k}"] = v }
      Setting.save(game_hash)
   end
end

module Settings
   settings    = Hash.new
   md5_at_load = Hash.new
   mutex       = Mutex.new
   @@settings = proc { |scope|
      unless script = Script.current
         respond '--- error: Settings: unknown calling script'
         next nil
      end
      unless scope =~ /^#{XMLData.game}\:#{XMLData.name}$|^#{XMLData.game}$|^\:$/
         respond '--- error: Settings: invalid scope'
         next nil
      end
      mutex.synchronize {
         unless settings[script.name] and settings[script.name][scope]
            begin
               _hash = Lich.db.get_first_value('SELECT hash FROM script_auto_settings WHERE script=? AND scope=?;', script.name.encode('UTF-8'), scope.encode('UTF-8'))
            rescue SQLite3::BusyException
               sleep 0.1
               retry
            end
            settings[script.name] ||= Hash.new
            if _hash.nil?
               settings[script.name][scope] = Hash.new
            else
               begin
                  hash = Marshal.load(_hash)
               rescue
                  respond "--- Lich: error: #{$!}"
                  respond $!.backtrace[0..1]
                  exit
               end
               settings[script.name][scope] = hash
            end
            md5_at_load[script.name] ||= Hash.new
            md5_at_load[script.name][scope] = Digest::MD5.hexdigest(settings[script.name][scope].to_s)
         end
      }
      settings[script.name][scope]
   }
   @@save = proc {
      mutex.synchronize {
         sql_began = false
         settings.each_pair { |script_name,scopedata|
            scopedata.each_pair { |scope,data|
               if Digest::MD5.hexdigest(data.to_s) != md5_at_load[script_name][scope]
                  unless sql_began
                     begin
                        Lich.db.execute('BEGIN')
                     rescue SQLite3::BusyException
                        sleep 0.1
                        retry
                     end
                     sql_began = true
                  end
                  blob = SQLite3::Blob.new(Marshal.dump(data))
                  begin
                     Lich.db.execute('INSERT OR REPLACE INTO script_auto_settings(script,scope,hash) VALUES(?,?,?);', script_name.encode('UTF-8'), scope.encode('UTF-8'), blob)
                  rescue SQLite3::BusyException
                     sleep 0.1
                     retry
                  rescue
                     respond "--- Lich: error: #{$!}"
                     respond $!.backtrace[0..1]
                     next
                  end
               end
            }
            unless Script.running?(script_name)
               settings.delete(script_name)
               md5_at_load.delete(script_name)
            end
         }
         if sql_began
            begin
               Lich.db.execute('END')
            rescue SQLite3::BusyException
               sleep 0.1
               retry
            end
         end
      }
   }
   Thread.new {
      loop {
         sleep 300
         begin
            @@save.call
         rescue
            Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            respond "--- Lich: error: #{$!}\n\t#{$!.backtrace[0..1].join("\n\t")}"
         end
      }
   }
   def Settings.[](name)
      @@settings.call(':')[name]
   end
   def Settings.[]=(name, value)
      @@settings.call(':')[name] = value
   end
   def Settings.to_hash(scope=':')
      @@settings.call(scope)
   end
   def Settings.char
      @@settings.call("#{XMLData.game}:#{XMLData.name}")
   end
   def Settings.save
      @@save.call
   end
end

module GameSettings
   def GameSettings.[](name)
      Settings.to_hash(XMLData.game)[name]
   end
   def GameSettings.[]=(name, value)
      Settings.to_hash(XMLData.game)[name] = value
   end
   def GameSettings.to_hash
      Settings.to_hash(XMLData.game)
   end
end

module CharSettings
   def CharSettings.[](name)
      Settings.to_hash("#{XMLData.game}:#{XMLData.name}")[name]
   end
   def CharSettings.[]=(name, value)
      Settings.to_hash("#{XMLData.game}:#{XMLData.name}")[name] = value
   end
   def CharSettings.to_hash
      Settings.to_hash("#{XMLData.game}:#{XMLData.name}")
   end
end

module Vars
   @@vars   = Hash.new
   md5      = nil
   mutex    = Mutex.new
   @@loaded = false
   @@load = proc {
      mutex.synchronize {
         unless @@loaded
            begin
               h = Lich.db.get_first_value('SELECT hash FROM uservars WHERE scope=?;', "#{XMLData.game}:#{XMLData.name}".encode('UTF-8'))
            rescue SQLite3::BusyException
               sleep 0.1
               retry
            end
            if h
               begin
                  hash = Marshal.load(h)
                  hash.each { |k,v| @@vars[k] = v }
                  md5 = Digest::MD5.hexdigest(hash.to_s)
               rescue
                  respond "--- Lich: error: #{$!}"
                  respond $!.backtrace[0..2]
               end
            end
            @@loaded = true
         end
      }
      nil
   }
   @@save = proc {
      mutex.synchronize {
         if @@loaded
            if Digest::MD5.hexdigest(@@vars.to_s) != md5
               md5 = Digest::MD5.hexdigest(@@vars.to_s)
               blob = SQLite3::Blob.new(Marshal.dump(@@vars))
               begin
                  Lich.db.execute('INSERT OR REPLACE INTO uservars(scope,hash) VALUES(?,?);', "#{XMLData.game}:#{XMLData.name}".encode('UTF-8'), blob)
               rescue SQLite3::BusyException
                  sleep 0.1
                  retry
               end
            end
         end
      }
      nil
   }
   Thread.new {
      loop {
         sleep 300
         begin
            @@save.call
         rescue
            Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            respond "--- Lich: error: #{$!}\n\t#{$!.backtrace[0..1].join("\n\t")}"
         end
      }
   }
   def Vars.[](name)
      @@load.call unless @@loaded
      @@vars[name]
   end
   def Vars.[]=(name, val)
      @@load.call unless @@loaded
      if val.nil?
         @@vars.delete(name)
      else
         @@vars[name] = val
      end
   end
   def Vars.list
      @@load.call unless @@loaded
      @@vars.dup
   end
   def Vars.save
      @@save.call
   end
   def Vars.method_missing(arg1, arg2='')
      @@load.call unless @@loaded
      if arg1[-1,1] == '='
         if arg2.nil?
            @@vars.delete(arg1.to_s.chop)
         else
            @@vars[arg1.to_s.chop] = arg2
         end
      else
         @@vars[arg1.to_s]
      end
   end
end


module Settings
   def Settings.load; end
   def Settings.save_all; end
   def Settings.clear; end
   def Settings.auto=(val); end
   def Settings.auto; end
   def Settings.autoload; end
end

module GameSettings
   def GameSettings.load; end
   def GameSettings.save; end
   def GameSettings.save_all; end
   def GameSettings.clear; end
   def GameSettings.auto=(val); end
   def GameSettings.auto; end
   def GameSettings.autoload; end
end

module CharSettings
   def CharSettings.load; end
   def CharSettings.save; end
   def CharSettings.save_all; end
   def CharSettings.clear; end
   def CharSettings.auto=(val); end
   def CharSettings.auto; end
   def CharSettings.autoload; end
end

module UserVars
   def UserVars.list
      Vars.list
   end
   def UserVars.method_missing(arg1, arg2='')
      Vars.method_missing(arg1, arg2)
   end
   def UserVars.change(var_name, value, t=nil)
      Vars[var_name] = value
   end
   def UserVars.add(var_name, value, t=nil)
      Vars[var_name] = Vars[var_name].split(', ').push(value).join(', ')
   end
   def UserVars.delete(var_name, t=nil)
      Vars[var_name] = nil
   end
   def UserVars.list_global
      Array.new
   end
   def UserVars.list_char
      Vars.list
   end
end

module Setting
   def Setting.[](name)
      Settings[name]
   end
   def Setting.[]=(name, value)
      Settings[name] = value
   end
   def Setting.to_hash(scope=':')
      Settings.to_hash
   end
end
module GameSetting
   def GameSetting.[](name)
      GameSettings[name]
   end
   def GameSetting.[]=(name, value)
      GameSettings[name] = value
   end
   def GameSetting.to_hash(scope=':')
      GameSettings.to_hash
   end
end
module CharSetting
   def CharSetting.[](name)
      CharSettings[name]
   end
   def CharSetting.[]=(name, value)
      CharSettings[name] = value
   end
   def CharSetting.to_hash(scope=':')
      CharSettings.to_hash
   end
end