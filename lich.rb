#!/usr/bin/env ruby
# encoding: US-ASCII
#####
# Copyright (C) 2005-2006 Murray Miron
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
#   Redistributions of source code must retain the above copyright
# notice, this list of conditions and the following disclaimer.
#
#   Redistributions in binary form must reproduce the above copyright
# notice, this list of conditions and the following disclaimer in the
# documentation and/or other materials provided with the distribution.
#
#   Neither the name of the organization nor the names of its contributors
# may be used to endorse or promote products derived from this software
# without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#####

#
# Lich is maintained by Matt Lowe (tillmen@lichproject.org)
#

LICH_VERSION = '4.6.54'
TESTING = false

if RUBY_VERSION !~ /^2/
   if (RUBY_PLATFORM =~ /mingw|win/) and (RUBY_PLATFORM !~ /darwin/i)
      if RUBY_VERSION =~ /^1\.9/
         require 'fiddle'
         Fiddle::Function.new(DL.dlopen('user32.dll')['MessageBox'], [Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_INT).call(0, 'Upgrade Ruby to version 2.0', "Lich v#{LICH_VERSION}", 16)
      else
         # fixme: This message never shows up on Ruby 1.8 because it errors out on negative lookbehind regex later in the file
         require 'dl'
         DL.dlopen('user32.dll')['MessageBox', 'LLPPL'].call(0, 'Upgrade Ruby to version 2.0', "Lich v#{LICH_VERSION}", 16)
      end
   else
      puts "Upgrade Ruby to version 2.0"
   end
   exit
end

require 'time'
require 'socket'
require 'rexml/document'
require 'rexml/streamlistener'
require 'stringio'
require 'zlib'
require 'drb'
require 'resolv'
require 'digest/md5'
require_relative("./data/map")
require_relative("./data/settings_modules")
require_relative("./data/spells")
require_relative("./data/games_module")
require_relative("./data/scripts")
require_relative("./data/xml_parser")
require_relative("./data/lich_module")
require_relative("./data/sockets")

begin
   # stupid workaround for Windows
   # seems to avoid a 10 second lag when starting lnet, without adding a 10 second lag at startup
   require 'openssl'
   OpenSSL::PKey::RSA.new(512)
rescue LoadError
   nil # not required for basic Lich; however, lnet and repository scripts will fail without openssl
rescue
   nil
end
if (RUBY_PLATFORM =~ /mingw|win/i) and (RUBY_PLATFORM !~ /darwin/i)
   #
   # Windows API made slightly less annoying
   #
   require 'fiddle'
   require 'fiddle/import'
   module Win32
      SIZEOF_CHAR = Fiddle::SIZEOF_CHAR
      SIZEOF_LONG = Fiddle::SIZEOF_LONG
      SEE_MASK_NOCLOSEPROCESS = 0x00000040
      MB_OK = 0x00000000
      MB_OKCANCEL = 0x00000001
      MB_YESNO = 0x00000004
      MB_ICONERROR = 0x00000010
      MB_ICONQUESTION = 0x00000020
      MB_ICONWARNING = 0x00000030
      IDIOK = 1
      IDICANCEL = 2
      IDIYES = 6
      IDINO = 7
      KEY_ALL_ACCESS = 0xF003F
      KEY_CREATE_SUB_KEY = 0x0004
      KEY_ENUMERATE_SUB_KEYS = 0x0008
      KEY_EXECUTE = 0x20019
      KEY_NOTIFY = 0x0010
      KEY_QUERY_VALUE = 0x0001
      KEY_READ = 0x20019
      KEY_SET_VALUE = 0x0002
      KEY_WOW64_32KEY = 0x0200
      KEY_WOW64_64KEY = 0x0100
      KEY_WRITE = 0x20006
      TokenElevation = 20
      TOKEN_QUERY = 8
      STILL_ACTIVE = 259
      SW_SHOWNORMAL = 1
      SW_SHOW = 5
      PROCESS_QUERY_INFORMATION = 1024
      PROCESS_VM_READ = 16
      HKEY_LOCAL_MACHINE = -2147483646
      REG_NONE = 0
      REG_SZ = 1
      REG_EXPAND_SZ = 2
      REG_BINARY = 3
      REG_DWORD = 4
      REG_DWORD_LITTLE_ENDIAN = 4
      REG_DWORD_BIG_ENDIAN = 5
      REG_LINK = 6
      REG_MULTI_SZ = 7
      REG_QWORD = 11
      REG_QWORD_LITTLE_ENDIAN = 11

      module Kernel32
         extend Fiddle::Importer
         dlload 'kernel32'
         extern 'int GetCurrentProcess()'
         extern 'int GetExitCodeProcess(int, int*)'
         extern 'int GetModuleFileName(int, void*, int)'
         extern 'int GetVersionEx(void*)'
#         extern 'int OpenProcess(int, int, int)' # fixme
         extern 'int GetLastError()'
         extern 'int CreateProcess(void*, void*, void*, void*, int, int, void*, void*, void*, void*)'
      end
      def Win32.GetLastError
         return Kernel32.GetLastError()
      end
      def Win32.CreateProcess(args)
         if args[:lpCommandLine]
            lpCommandLine = args[:lpCommandLine].dup
         else
            lpCommandLine = nil
         end
         if args[:bInheritHandles] == false
            bInheritHandles = 0
         elsif args[:bInheritHandles] == true
            bInheritHandles = 1
         else
            bInheritHandles = args[:bInheritHandles].to_i
         end
         if args[:lpEnvironment].class == Array
            # fixme
         end
         lpStartupInfo = [ 68, 0, 0, 0,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0 ]
         lpStartupInfo_index = { :lpDesktop => 2, :lpTitle => 3, :dwX => 4, :dwY => 5, :dwXSize => 6, :dwYSize => 7, :dwXCountChars => 8, :dwYCountChars => 9, :dwFillAttribute => 10, :dwFlags => 11, :wShowWindow => 12, :hStdInput => 15, :hStdOutput => 16, :hStdError => 17 }
         for sym in [ :lpDesktop, :lpTitle ]
            if args[sym]
               args[sym] = "#{args[sym]}\0" unless args[sym][-1,1] == "\0"
               lpStartupInfo[lpStartupInfo_index[sym]] = Fiddle::Pointer.to_ptr(args[sym]).to_i
            end
         end
         for sym in [ :dwX, :dwY, :dwXSize, :dwYSize, :dwXCountChars, :dwYCountChars, :dwFillAttribute, :dwFlags, :wShowWindow, :hStdInput, :hStdOutput, :hStdError ]
            if args[sym]
               lpStartupInfo[lpStartupInfo_index[sym]] = args[sym]
            end
         end
         lpStartupInfo = lpStartupInfo.pack('LLLLLLLLLLLLSSLLLL')
         lpProcessInformation = [ 0, 0, 0, 0, ].pack('LLLL')
         r = Kernel32.CreateProcess(args[:lpApplicationName], lpCommandLine, args[:lpProcessAttributes], args[:lpThreadAttributes], bInheritHandles, args[:dwCreationFlags].to_i, args[:lpEnvironment], args[:lpCurrentDirectory], lpStartupInfo, lpProcessInformation)
         lpProcessInformation = lpProcessInformation.unpack('LLLL')
         return :return => (r > 0 ? true : false), :hProcess => lpProcessInformation[0], :hThread => lpProcessInformation[1], :dwProcessId => lpProcessInformation[2], :dwThreadId => lpProcessInformation[3]
      end
#      Win32.CreateProcess(:lpApplicationName => 'Launcher.exe', :lpCommandLine => 'lich2323.sal', :lpCurrentDirectory => 'C:\\PROGRA~1\\SIMU')
#      def Win32.OpenProcess(args={})
#         return Kernel32.OpenProcess(args[:dwDesiredAccess].to_i, args[:bInheritHandle].to_i, args[:dwProcessId].to_i)
#      end
      def Win32.GetCurrentProcess
         return Kernel32.GetCurrentProcess
      end
      def Win32.GetExitCodeProcess(args)
         lpExitCode = [ 0 ].pack('L')
         r = Kernel32.GetExitCodeProcess(args[:hProcess].to_i, lpExitCode)
         return :return => r, :lpExitCode => lpExitCode.unpack('L')[0]
      end
      def Win32.GetModuleFileName(args={})
         args[:nSize] ||= 256
         buffer = "\0" * args[:nSize].to_i
         r = Kernel32.GetModuleFileName(args[:hModule].to_i, buffer, args[:nSize].to_i)
         return :return => r, :lpFilename => buffer.gsub("\0", '')
      end
      def Win32.GetVersionEx
         a = [ 156, 0, 0, 0, 0, ("\0" * 128), 0, 0, 0, 0, 0].pack('LLLLLa128SSSCC')
         r = Kernel32.GetVersionEx(a)
         a = a.unpack('LLLLLa128SSSCC')
         return :return => r, :dwOSVersionInfoSize => a[0], :dwMajorVersion => a[1], :dwMinorVersion => a[2], :dwBuildNumber => a[3], :dwPlatformId => a[4], :szCSDVersion => a[5].strip, :wServicePackMajor => a[6], :wServicePackMinor => a[7], :wSuiteMask => a[8], :wProductType => a[9]
      end

      module User32
         extend Fiddle::Importer
         dlload 'user32'
         extern 'int MessageBox(int, char*, char*, int)'
      end
      def Win32.MessageBox(args)
         args[:lpCaption] ||= "Lich v#{LICH_VERSION}"
         return User32.MessageBox(args[:hWnd].to_i, args[:lpText], args[:lpCaption], args[:uType].to_i)
      end

      module Advapi32
         extend Fiddle::Importer
         dlload 'advapi32'
         extern 'int GetTokenInformation(int, int, void*, int, void*)'
         extern 'int OpenProcessToken(int, int, void*)'
         extern 'int RegOpenKeyEx(int, char*, int, int, void*)'
         extern 'int RegQueryValueEx(int, char*, void*, void*, void*, void*)'
         extern 'int RegSetValueEx(int, char*, int, int, char*, int)'
         extern 'int RegDeleteValue(int, char*)'
         extern 'int RegCloseKey(int)'
      end
      def Win32.GetTokenInformation(args)
         if args[:TokenInformationClass] == TokenElevation
            token_information_length = SIZEOF_LONG
            token_information = [ 0 ].pack('L')
         else
            return nil
         end
         return_length = [ 0 ].pack('L')
         r = Advapi32.GetTokenInformation(args[:TokenHandle].to_i, args[:TokenInformationClass], token_information, token_information_length, return_length)
         if args[:TokenInformationClass] == TokenElevation
            return :return => r, :TokenIsElevated => token_information.unpack('L')[0]
         end
      end
      def Win32.OpenProcessToken(args)
         token_handle = [ 0 ].pack('L')
         r = Advapi32.OpenProcessToken(args[:ProcessHandle].to_i, args[:DesiredAccess].to_i, token_handle)
         return :return => r, :TokenHandle => token_handle.unpack('L')[0]
      end
      def Win32.RegOpenKeyEx(args)
         phkResult = [ 0 ].pack('L')
         r = Advapi32.RegOpenKeyEx(args[:hKey].to_i, args[:lpSubKey].to_s, 0, args[:samDesired].to_i, phkResult)
         return :return => r, :phkResult => phkResult.unpack('L')[0]
      end
      def Win32.RegQueryValueEx(args)
         args[:lpValueName] ||= 0
         lpcbData = [ 0 ].pack('L')
         r = Advapi32.RegQueryValueEx(args[:hKey].to_i, args[:lpValueName], 0, 0, 0, lpcbData)
         if r == 0
            lpcbData = lpcbData.unpack('L')[0]
            lpData = String.new.rjust(lpcbData, "\x00")
            lpcbData = [ lpcbData ].pack('L')
            lpType = [ 0 ].pack('L')
            r = Advapi32.RegQueryValueEx(args[:hKey].to_i, args[:lpValueName], 0, lpType, lpData, lpcbData)
            lpType = lpType.unpack('L')[0]
            lpcbData = lpcbData.unpack('L')[0]
            if [REG_EXPAND_SZ, REG_SZ, REG_LINK].include?(lpType)
               lpData.gsub!("\x00", '')
            elsif lpType == REG_MULTI_SZ
               lpData = lpData.gsub("\x00\x00", '').split("\x00")
            elsif lpType == REG_DWORD
               lpData = lpData.unpack('L')[0]
            elsif lpType == REG_QWORD
               lpData = lpData.unpack('Q')[0]
            elsif lpType == REG_BINARY
               # fixme
            elsif lpType == REG_DWORD_BIG_ENDIAN
               # fixme
            else
               # fixme
            end
            return :return => r, :lpType => lpType, :lpcbData => lpcbData, :lpData => lpData
         else
            return :return => r
         end
      end
      def Win32.RegSetValueEx(args)
         if [REG_EXPAND_SZ, REG_SZ, REG_LINK].include?(args[:dwType]) and (args[:lpData].class == String)
            lpData = args[:lpData].dup
            lpData.concat("\x00")
            cbData = lpData.length
         elsif (args[:dwType] == REG_MULTI_SZ) and (args[:lpData].class == Array)
            lpData = args[:lpData].join("\x00").concat("\x00\x00")
            cbData = lpData.length
         elsif (args[:dwType] == REG_DWORD) and (args[:lpData].class == Fixnum)
            lpData = [args[:lpData]].pack('L')
            cbData = 4
         elsif (args[:dwType] == REG_QWORD) and (args[:lpData].class == Fixnum or args[:lpData].class == Bignum)
            lpData = [args[:lpData]].pack('Q')
            cbData = 8
         elsif args[:dwType] == REG_BINARY
            # fixme
            return false
         elsif args[:dwType] == REG_DWORD_BIG_ENDIAN
            # fixme
            return false
         else
            # fixme
            return false
         end
         args[:lpValueName] ||= 0
         return Advapi32.RegSetValueEx(args[:hKey].to_i, args[:lpValueName], 0, args[:dwType], lpData, cbData)
      end
      def Win32.RegDeleteValue(args)
         args[:lpValueName] ||= 0
         return Advapi32.RegDeleteValue(args[:hKey].to_i, args[:lpValueName])
      end
      def   Win32.RegCloseKey(args)
         return Advapi32.RegCloseKey(args[:hKey])
      end      

      module Shell32
         extend Fiddle::Importer
         dlload 'shell32'
         extern 'int ShellExecuteEx(void*)'
         extern 'int ShellExecute(int, char*, char*, char*, char*, int)'
      end
      def Win32.ShellExecuteEx(args)
#         struct = [ (SIZEOF_LONG * 15), 0, 0, 0, 0, 0, 0, SW_SHOWNORMAL, 0, 0, 0, 0, 0, 0, 0 ]
         struct = [ (SIZEOF_LONG * 15), 0, 0, 0, 0, 0, 0, SW_SHOW, 0, 0, 0, 0, 0, 0, 0 ]
         struct_index = { :cbSize => 0, :fMask => 1, :hwnd => 2, :lpVerb => 3, :lpFile => 4, :lpParameters => 5, :lpDirectory => 6, :nShow => 7, :hInstApp => 8, :lpIDList => 9, :lpClass => 10, :hkeyClass => 11, :dwHotKey => 12, :hIcon => 13, :hMonitor => 13, :hProcess => 14 }
         for sym in [ :lpVerb, :lpFile, :lpParameters, :lpDirectory, :lpIDList, :lpClass ]
            if args[sym]
               args[sym] = "#{args[sym]}\0" unless args[sym][-1,1] == "\0"
               struct[struct_index[sym]] = Fiddle::Pointer.to_ptr(args[sym]).to_i
            end
         end
         for sym in [ :fMask, :hwnd, :nShow, :hkeyClass, :dwHotKey, :hIcon, :hMonitor, :hProcess ]
            if args[sym]
               struct[struct_index[sym]] = args[sym]
            end
         end
         struct = struct.pack('LLLLLLLLLLLLLLL')
         r = Shell32.ShellExecuteEx(struct)
         struct = struct.unpack('LLLLLLLLLLLLLLL')
         return :return => r, :hProcess => struct[struct_index[:hProcess]], :hInstApp => struct[struct_index[:hInstApp]]
      end
      def Win32.ShellExecute(args)
         args[:lpOperation] ||= 0
         args[:lpParameters] ||= 0
         args[:lpDirectory] ||= 0
         args[:nShowCmd] ||= 1
         return Shell32.ShellExecute(args[:hwnd].to_i, args[:lpOperation], args[:lpFile], args[:lpParameters], args[:lpDirectory], args[:nShowCmd])
      end

      begin
         module Kernel32
            extern 'int EnumProcesses(void*, int, void*)'
         end
         def Win32.EnumProcesses(args={})
            args[:cb] ||= 400
            pProcessIds = Array.new((args[:cb]/SIZEOF_LONG), 0).pack(''.rjust((args[:cb]/SIZEOF_LONG), 'L'))
            pBytesReturned = [ 0 ].pack('L')
            r = Kernel32.EnumProcesses(pProcessIds, args[:cb], pBytesReturned)
            pBytesReturned = pBytesReturned.unpack('L')[0]
            return :return => r, :pProcessIds => pProcessIds.unpack(''.rjust((args[:cb]/SIZEOF_LONG), 'L'))[0...(pBytesReturned/SIZEOF_LONG)], :pBytesReturned => pBytesReturned
         end
      rescue
         module Psapi
            extend Fiddle::Importer
            dlload 'psapi'
            extern 'int EnumProcesses(void*, int, void*)'
         end
         def Win32.EnumProcesses(args={})
            args[:cb] ||= 400
            pProcessIds = Array.new((args[:cb]/SIZEOF_LONG), 0).pack(''.rjust((args[:cb]/SIZEOF_LONG), 'L'))
            pBytesReturned = [ 0 ].pack('L')
            r = Psapi.EnumProcesses(pProcessIds, args[:cb], pBytesReturned)
            pBytesReturned = pBytesReturned.unpack('L')[0]
            return :return => r, :pProcessIds => pProcessIds.unpack(''.rjust((args[:cb]/SIZEOF_LONG), 'L'))[0...(pBytesReturned/SIZEOF_LONG)], :pBytesReturned => pBytesReturned
         end
      end

      def Win32.isXP?
         return (Win32.GetVersionEx[:dwMajorVersion] < 6)
      end
      def Win32.admin?
         if Win32.isXP?
            return true
         else
            r = Win32.OpenProcessToken(:ProcessHandle => Win32.GetCurrentProcess, :DesiredAccess => TOKEN_QUERY)
            token_handle = r[:TokenHandle]
            r = Win32.GetTokenInformation(:TokenInformationClass => TokenElevation, :TokenHandle => token_handle)
            return (r[:TokenIsElevated] != 0)
         end
      end
      def Win32.AdminShellExecute(args)
         # open ruby/lich as admin and tell it to open something else
         if not caller.any? { |c| c =~ /eval|run/ }
            r = Win32.GetModuleFileName
            if r[:return] > 0
               if File.exists?(r[:lpFilename])
                  Win32.ShellExecuteEx(:lpVerb => 'runas', :lpFile => r[:lpFilename], :lpParameters => "#{File.expand_path($PROGRAM_NAME)} shellexecute #{[Marshal.dump(args)].pack('m').gsub("\n",'')}")
               end
            end
         end
      end
   end
else
   if arg = ARGV.find { |a| a =~ /^--wine=.+$/i }
      $wine_bin = arg.sub(/^--wine=/, '')
   else
      begin
         $wine_bin = `which wine`.strip
      rescue
         $wine_bin = nil
      end
   end
   if arg = ARGV.find { |a| a =~ /^--wine-prefix=.+$/i }
      $wine_prefix = arg.sub(/^--wine-prefix=/, '')
   elsif ENV['WINEPREFIX']
      $wine_prefix = ENV['WINEPREFIX']
   elsif ENV['HOME']
      $wine_prefix = ENV['HOME'] + '/.wine'
   else
      $wine_prefix = nil
   end
   if $wine_bin and File.exists?($wine_bin) and File.file?($wine_bin) and $wine_prefix and File.exists?($wine_prefix) and File.directory?($wine_prefix)
      module Wine
         BIN = $wine_bin
         PREFIX = $wine_prefix
         def Wine.registry_gets(key)
            hkey, subkey, thingie = /(HKEY_LOCAL_MACHINE|HKEY_CURRENT_USER)\\(.+)\\([^\\]*)/.match(key).captures # fixme: stupid highlights ]/
            if File.exists?(PREFIX + '/system.reg')
               if hkey == 'HKEY_LOCAL_MACHINE'
                  subkey = "[#{subkey.gsub('\\', '\\\\\\')}]"
                  if thingie.nil? or thingie.empty?
                     thingie = '@'
                  else
                     thingie = "\"#{thingie}\""
                  end
                  lookin = result = false
                  File.open(PREFIX + '/system.reg') { |f| f.readlines }.each { |line|
                     if line[0...subkey.length] == subkey
                        lookin = true
                     elsif line =~ /^\[/
                        lookin = false
                     elsif lookin and line =~ /^#{thingie}="(.*)"$/i
                        result = $1.split('\\"').join('"').split('\\\\').join('\\').sub(/\\0$/, '')
                        break
                     end
                  }
                  return result
               else
                  return false
               end
            else
               return false
            end
         end
         def Wine.registry_puts(key, value)
            hkey, subkey, thingie = /(HKEY_LOCAL_MACHINE|HKEY_CURRENT_USER)\\(.+)\\([^\\]*)/.match(key).captures # fixme ]/ 
            if File.exists?(PREFIX)
               if thingie.nil? or thingie.empty?
                  thingie = '@'
               else
                  thingie = "\"#{thingie}\""
               end
               # gsub sucks for this..
               value = value.split('\\').join('\\\\')
               value = value.split('"').join('\"')
               begin
                  regedit_data = "REGEDIT4\n\n[#{hkey}\\#{subkey}]\n#{thingie}=\"#{value}\"\n\n"
                  filename = "#{TEMP_DIR}/wine-#{Time.now.to_i}.reg"
                  File.open(filename, 'w') { |f| f.write(regedit_data) }
                  system("#{BIN} regedit #{filename}")
                  sleep 0.2
                  File.delete(filename)
               rescue
                  return false
               end
               return true
            end
         end
      end
   end
   $wine_bin = nil
   $wine_prefix = nil
end

if ARGV[0] == 'shellexecute'
   args = Marshal.load(ARGV[1].unpack('m')[0])
   Win32.ShellExecute(:lpOperation => args[:op], :lpFile => args[:file], :lpDirectory => args[:dir], :lpParameters => args[:params])
   exit
end

begin
   require 'sqlite3'
rescue LoadError
   if defined?(Win32)
      r = Win32.MessageBox(:lpText => "Lich needs sqlite3 to save settings and data, but it is not installed.\n\nWould you like to install sqlite3 now?", :lpCaption => "Lich v#{LICH_VERSION}", :uType => (Win32::MB_YESNO | Win32::MB_ICONQUESTION))
      if r == Win32::IDIYES
         r = Win32.GetModuleFileName
         if r[:return] > 0
            ruby_bin_dir = File.dirname(r[:lpFilename])
            if File.exists?("#{ruby_bin_dir}\\gem.bat")
               verb = (Win32.isXP? ? 'open' : 'runas')
               # fixme: using --source http://rubygems.org to avoid https because it has been failing to validate the certificate on Windows
               r = Win32.ShellExecuteEx(:fMask => Win32::SEE_MASK_NOCLOSEPROCESS, :lpVerb => verb, :lpFile => "#{ruby_bin_dir}\\#{gem_file}", :lpParameters => 'install sqlite3 --source http://rubygems.org --no-ri --no-rdoc --version 1.3.13')
               if r[:return] > 0
                  pid = r[:hProcess]
                  sleep 1 while Win32.GetExitCodeProcess(:hProcess => pid)[:lpExitCode] == Win32::STILL_ACTIVE
                  r = Win32.MessageBox(:lpText => "Install finished.  Lich will restart now.", :lpCaption => "Lich v#{LICH_VERSION}", :uType => Win32::MB_OKCANCEL)
               else
                  # ShellExecuteEx failed: this seems to happen with an access denied error even while elevated on some random systems
                  r = Win32.ShellExecute(:lpOperation => verb, :lpFile => "#{ruby_bin_dir}\\#{gem_file}", :lpParameters => 'install sqlite3 --source http://rubygems.org --no-ri --no-rdoc --version 1.3.13')
                  if r <= 32
                     Win32.MessageBox(:lpText => "error: failed to start the sqlite3 installer\n\nfailed command: Win32.ShellExecute(:lpOperation => #{verb.inspect}, :lpFile => \"#{ruby_bin_dir}\\#{gem_file}\", :lpParameters => \"install sqlite3 --source http://rubygems.org --no-ri --no-rdoc --version 1.3.13'\")\n\nerror code: #{Win32.GetLastError}", :lpCaption => "Lich v#{LICH_VERSION}", :uType => (Win32::MB_OK | Win32::MB_ICONERROR))
                     exit
                  end
                  r = Win32.MessageBox(:lpText => "When the installer is finished, click OK to restart Lich.", :lpCaption => "Lich v#{LICH_VERSION}", :uType => Win32::MB_OKCANCEL)
               end
               if r == Win32::IDIOK
                  if File.exists?("#{ruby_bin_dir}\\rubyw.exe")
                     Win32.ShellExecute(:lpOperation => 'open', :lpFile => "#{ruby_bin_dir}\\rubyw.exe", :lpParameters => "\"#{File.expand_path($PROGRAM_NAME)}\"")
                  else
                     Win32.MessageBox(:lpText => "error: failed to find rubyw.exe; can't restart Lich for you", :lpCaption => "Lich v#{LICH_VERSION}", :uType => (Win32::MB_OK | Win32::MB_ICONERROR))
                  end
               else
                  # user doesn't want to restart Lich
               end
            else
               Win32.MessageBox(:lpText => "error: Could not find gem.cmd or gem.bat in directory #{ruby_bin_dir}", :lpCaption => "Lich v#{LICH_VERSION}", :uType => (Win32::MB_OK | Win32::MB_ICONERROR))
            end
         else
            Win32.MessageBox(:lpText => "error: GetModuleFileName failed", :lpCaption => "Lich v#{LICH_VERSION}", :uType => (Win32::MB_OK | Win32::MB_ICONERROR))
         end
      else
         # user doesn't want to install sqlite3 gem
      end
   else
      # fixme: no sqlite3 on Linux/Mac
      puts "The sqlite3 gem is not installed (or failed to load), you may need to: sudo gem install sqlite3"
   end
   exit
end

if ((RUBY_PLATFORM =~ /mingw|win/i) and (RUBY_PLATFORM !~ /darwin/i)) or ENV['DISPLAY']
   begin
      require 'gtk2'
      HAVE_GTK = true
   rescue LoadError
      if (ENV['RUN_BY_CRON'].nil? or ENV['RUN_BY_CRON'] == 'false') and ARGV.empty? or ARGV.any? { |arg| arg =~ /^--gui$/ } or not $stdout.isatty
         if defined?(Win32)
            r = Win32.MessageBox(:lpText => "Lich uses gtk2 to create windows, but it is not installed.  You can use Lich from the command line (ruby lich.rbw --help) or you can install gtk2 for a point and click interface.\n\nWould you like to install gtk2 now?", :lpCaption => "Lich v#{LICH_VERSION}", :uType => (Win32::MB_YESNO | Win32::MB_ICONQUESTION))
            if r == Win32::IDIYES
               r = Win32.GetModuleFileName
               if r[:return] > 0
                  ruby_bin_dir = File.dirname(r[:lpFilename])
                  if File.exists?("#{ruby_bin_dir}\\gem.cmd")
                  gem_file = 'gem.cmd'
                  elsif File.exists?("#{ruby_bin_dir}\\gem.bat")
                     gem_file = 'gem.bat'
                  else
                     gem_file = nil
                  end
                  if gem_file
                     verb = (Win32.isXP? ? 'open' : 'runas')
                     r = Win32.ShellExecuteEx(:fMask => Win32::SEE_MASK_NOCLOSEPROCESS, :lpVerb => verb, :lpFile => "#{ruby_bin_dir}\\gem.bat", :lpParameters => 'install cairo:1.14.3 gtk2:2.2.5 --source http://rubygems.org --no-ri --no-rdoc')
                     if r[:return] > 0
                        pid = r[:hProcess]
                        sleep 1 while Win32.GetExitCodeProcess(:hProcess => pid)[:lpExitCode] == Win32::STILL_ACTIVE
                        r = Win32.MessageBox(:lpText => "Install finished.  Lich will restart now.", :lpCaption => "Lich v#{LICH_VERSION}", :uType => Win32::MB_OKCANCEL)
                     else
                        # ShellExecuteEx failed: this seems to happen with an access denied error even while elevated on some random systems
                        r = Win32.ShellExecute(:lpOperation => verb, :lpFile => "#{ruby_bin_dir}\\gem.bat", :lpParameters => 'install cairo:1.14.3 gtk2:2.2.5 --source http://rubygems.org --no-ri --no-rdoc')
                        if r <= 32
                           Win32.MessageBox(:lpText => "error: failed to start the gtk2 installer\n\nfailed command: Win32.ShellExecute(:lpOperation => #{verb.inspect}, :lpFile => \"#{ruby_bin_dir}\\gem.bat\", :lpParameters => \"install cairo:1.14.3 gtk2:2.2.5 --source http://rubygems.org --no-ri --no-rdoc\")\n\nerror code: #{Win32.GetLastError}", :lpCaption => "Lich v#{LICH_VERSION}", :uType => (Win32::MB_OK | Win32::MB_ICONERROR))
                           exit
                        end
                        r = Win32.MessageBox(:lpText => "When the installer is finished, click OK to restart Lich.", :lpCaption => "Lich v#{LICH_VERSION}", :uType => Win32::MB_OKCANCEL)
                     end
                     if r == Win32::IDIOK
                        if File.exists?("#{ruby_bin_dir}\\rubyw.exe")
                           Win32.ShellExecute(:lpOperation => 'open', :lpFile => "#{ruby_bin_dir}\\rubyw.exe", :lpParameters => "\"#{File.expand_path($PROGRAM_NAME)}\"")
                        else
                           Win32.MessageBox(:lpText => "error: failed to find rubyw.exe; can't restart Lich for you", :lpCaption => "Lich v#{LICH_VERSION}", :uType => (Win32::MB_OK | Win32::MB_ICONERROR))
                        end
                     else
                        # user doesn't want to restart Lich
                     end
                  else
                     Win32.MessageBox(:lpText => "error: Could not find gem.bat in directory #{ruby_bin_dir}", :lpCaption => "Lich v#{LICH_VERSION}", :uType => (Win32::MB_OK | Win32::MB_ICONERROR))
                  end
               else
                  Win32.MessageBox(:lpText => "error: GetModuleFileName failed", :lpCaption => "Lich v#{LICH_VERSION}", :uType => (Win32::MB_OK | Win32::MB_ICONERROR))
               end
            else
               # user doesn't want to install gtk2 gem
            end
         else
            # fixme: no gtk2 on Linux/Mac
            puts "The gtk2 gem is not installed (or failed to load), you may need to: sudo gem install gtk2"
         end
         exit
      else
         # gtk is optional if command line arguments are given or started in a terminal
         HAVE_GTK = false
         early_gtk_error = "warning: failed to load GTK\n\t#{$!}\n\t#{$!.backtrace.join("\n\t")}"
      end
   end
else
   HAVE_GTK = false
   early_gtk_error = "info: DISPLAY environment variable is not set; not trying gtk"
end

if defined?(Gtk)
   module Gtk
      # Calling Gtk API in a thread other than the main thread may cause random segfaults
      def Gtk.queue &block
         GLib::Timeout.add(1) {
            begin
               block.call
            rescue
               respond "error in Gtk.queue: #{$!}"
               Lich.log "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            rescue SyntaxError
               respond "error in Gtk.queue: #{$!}"
               Lich.log "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            rescue SystemExit
               nil
            rescue SecurityError
               respond "error in Gtk.queue: #{$!}"
               Lich.log "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            rescue ThreadError
               respond "error in Gtk.queue: #{$!}"
               Lich.log "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            rescue SystemStackError
               respond "error in Gtk.queue: #{$!}"
               Lich.log "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            rescue Exception
               respond "error in Gtk.queue: #{$!}"
               Lich.log "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            rescue ScriptError
               respond "error in Gtk.queue: #{$!}"
               Lich.log "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            rescue LoadError
               respond "error in Gtk.queue: #{$!}"
               Lich.log "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            rescue NoMemoryError
               respond "error in Gtk.queue: #{$!}"
               Lich.log "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            rescue
               respond "error in Gtk.queue: #{$!}"
               Lich.log "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            end
            false # don't repeat timeout
         }
      end
   end
end



class Room < Map
#   private_class_method :new
   def Room.method_missing(*args)
      super(*args)
   end
end

def hide_me
   Script.current.hidden = !Script.current.hidden
end

def no_kill_all
   script = Script.current
   script.no_kill_all = !script.no_kill_all
end

def no_pause_all
   script = Script.current
   script.no_pause_all = !script.no_pause_all
end

def toggle_upstream
   unless script = Script.current then echo 'toggle_upstream: cannot identify calling script.'; return nil; end
   script.want_upstream = !script.want_upstream
end

def silence_me
   unless script = Script.current then echo 'silence_me: cannot identify calling script.'; return nil; end
   if script.safe? then echo("WARNING: 'safe' script attempted to silence itself.  Ignoring the request.")
      sleep 1
      return true
   end
   script.silent = !script.silent
end

def toggle_echo
   unless script = Script.current then respond('--- toggle_echo: Unable to identify calling script.'); return nil; end
   script.no_echo = !script.no_echo
end

def echo_on
   unless script = Script.current then respond('--- echo_on: Unable to identify calling script.'); return nil; end
   script.no_echo = false
end

def echo_off
   unless script = Script.current then respond('--- echo_off: Unable to identify calling script.'); return nil; end
   script.no_echo = true
end

def upstream_get
   unless script = Script.current then echo 'upstream_get: cannot identify calling script.'; return nil; end
   unless script.want_upstream
      echo("This script wants to listen to the upstream, but it isn't set as receiving the upstream! This will cause a permanent hang, aborting (ask for the upstream with 'toggle_upstream' in the script)")
      sleep 0.3
      return false
   end
   script.upstream_gets
end

def upstream_get?
   unless script = Script.current then echo 'upstream_get: cannot identify calling script.'; return nil; end
   unless script.want_upstream
      echo("This script wants to listen to the upstream, but it isn't set as receiving the upstream! This will cause a permanent hang, aborting (ask for the upstream with 'toggle_upstream' in the script)")
      return false
   end
   script.upstream_gets?
end

def echo(*messages)
   respond if messages.empty?
   if script = Script.current 
      unless script.no_echo
         messages.each { |message| respond("[#{script.name}: #{message.to_s.chomp}]") }
      end
   else
      messages.each { |message| respond("[(unknown script): #{message.to_s.chomp}]") }
   end
   nil
end

def _echo(*messages)
   _respond if messages.empty?
   if script = Script.current 
      unless script.no_echo
         messages.each { |message| _respond("[#{script.name}: #{message.to_s.chomp}]") }
      end
   else
      messages.each { |message| _respond("[(unknown script): #{message.to_s.chomp}]") }
   end
   nil
end

def goto(label)
   Script.current.jump_label = label.to_s
   raise JUMP
end

def pause_script(*names)
   names.flatten!
   if names.empty?
      Script.current.pause
      Script.current
   else
      names.each { |scr|
         fnd = Script.list.find { |nm| nm.name =~ /^#{scr}/i }
         fnd.pause unless (fnd.paused || fnd.nil?)
      }
   end
end

def unpause_script(*names)
   names.flatten!
   names.each { |scr| 
      fnd = Script.list.find { |nm| nm.name =~ /^#{scr}/i }
      fnd.unpause if (fnd.paused and not fnd.nil?)
   }
end

def fix_injury_mode
   unless XMLData.injury_mode == 2
      Game._puts '_injury 2'
      150.times { sleep 0.05; break if XMLData.injury_mode == 2 }
   end
end

def hide_script(*args)
   args.flatten!
   args.each { |name|
      if script = Script.running.find { |scr| scr.name == name }
         script.hidden = !script.hidden
      end
   }
end

def parse_list(string)
   string.split_as_list
end

def waitrt
   wait_until { (XMLData.roundtime_end.to_f - Time.now.to_f + XMLData.server_time_offset.to_f) > 0 }
   sleep((XMLData.roundtime_end.to_f - Time.now.to_f + XMLData.server_time_offset.to_f + "0.6".to_f).abs)
end

def waitrt?
   rt = XMLData.roundtime_end.to_f - Time.now.to_f + XMLData.server_time_offset.to_f + "0.6".to_f
   if rt > 0
      sleep rt
   end
end

def waitcastrt
   wait_until { (XMLData.cast_roundtime_end.to_f - Time.now.to_f + XMLData.server_time_offset.to_f) > 0 }
   sleep((XMLData.cast_roundtime_end.to_f - Time.now.to_f + XMLData.server_time_offset.to_f + "0.6".to_f).abs)
end

def waitcastrt?
   rt = XMLData.cast_roundtime_end.to_f - Time.now.to_f + XMLData.server_time_offset.to_f + "0.6".to_f
   if rt > 0
      sleep rt
   end
end

def checkrt
   [XMLData.roundtime_end.to_f - Time.now.to_f + XMLData.server_time_offset.to_f + "0.6".to_f, 0].max
end

def checkcastrt
   [XMLData.cast_roundtime_end.to_f - Time.now.to_f + XMLData.server_time_offset.to_f + "0.6".to_f, 0].max
end

def checkpoison
   XMLData.indicator['IconPOISONED'] == 'y'
end

def checkdisease
   XMLData.indicator['IconDISEASED'] == 'y'
end

def checksitting
   XMLData.indicator['IconSITTING'] == 'y'
end

def checkkneeling
   XMLData.indicator['IconKNEELING'] == 'y'
end

def checkstunned
   XMLData.indicator['IconSTUNNED'] == 'y'
end

def checkbleeding
   XMLData.indicator['IconBLEEDING'] == 'y'
end

def checkgrouped
   XMLData.indicator['IconJOINED'] == 'y'
end

def checkdead
   XMLData.indicator['IconDEAD'] == 'y'
end

def checkreallybleeding
   checkbleeding and !(Spell[9909].active? or Spell[9905].active?)
end

def muckled?
   muckled = checkwebbed or checkdead or checkstunned
   if defined?(checksleeping)
      muckled = muckled or checksleeping
   end
   if defined?(checkbound)
      muckled = muckled or checkbound
   end
   return muckled
end

def checkhidden
   XMLData.indicator['IconHIDDEN'] == 'y'
end

def checkinvisible
   XMLData.indicator['IconINVISIBLE'] == 'y'
end

def checkwebbed
   XMLData.indicator['IconWEBBED'] == 'y'
end

def checkprone
   XMLData.indicator['IconPRONE'] == 'y'
end

def checknotstanding
   XMLData.indicator['IconSTANDING'] == 'n'
end

def checkstanding
   XMLData.indicator['IconSTANDING'] == 'y'
end

def checkname(*strings)
   strings.flatten!
   if strings.empty?
      XMLData.name
   else
      XMLData.name =~ /^(?:#{strings.join('|')})/i
   end
end

def checkloot
   GameObj.loot.collect { |item| item.noun }
end

def i_stand_alone
   unless script = Script.current then echo 'i_stand_alone: cannot identify calling script.'; return nil; end
   script.want_downstream = !script.want_downstream
   return !script.want_downstream
end

def debug(*args)
   if $LICH_DEBUG
      if block_given?
         yield(*args)
      else
         echo(*args)
      end
   end
end

def timetest(*contestants)
   contestants.collect { |code| start = Time.now; 5000.times { code.call }; Time.now - start }
end

def dec2bin(n)
   "0" + [n].pack("N").unpack("B32")[0].sub(/^0+(?=\d)/, '')
end

def bin2dec(n)
   [("0"*32+n.to_s)[-32..-1]].pack("B32").unpack("N")[0]
end

def idle?(time = 60)
   Time.now - $_IDLETIMESTAMP_ >= time
end

def selectput(string, success, failure, timeout = nil)
   timeout = timeout.to_f if timeout and !timeout.kind_of?(Numeric)
   success = [ success ] if success.kind_of? String
   failure = [ failure ] if failure.kind_of? String
   if !string.kind_of?(String) or !success.kind_of?(Array) or !failure.kind_of?(Array) or timeout && !timeout.kind_of?(Numeric)
      raise ArgumentError, "usage is: selectput(game_command,success_array,failure_array[,timeout_in_secs])" 
   end
   success.flatten!
   failure.flatten!
   regex = /#{(success + failure).join('|')}/i
   successre = /#{success.join('|')}/i
   failurere = /#{failure.join('|')}/i
   thr = Thread.current

   timethr = Thread.new {
      timeout -= sleep("0.1".to_f) until timeout <= 0
      thr.raise(StandardError)
   } if timeout

   begin
      loop {
         fput(string)
         response = waitforre(regex)
         if successre.match(response.to_s)
            timethr.kill if timethr.alive?
            break(response.string)
         end
         yield(response.string) if block_given?
      }
   rescue
      nil
   end
end

def toggle_unique
   unless script = Script.current then echo 'toggle_unique: cannot identify calling script.'; return nil; end
   script.want_downstream = !script.want_downstream
end

def die_with_me(*vals)
   unless script = Script.current then echo 'die_with_me: cannot identify calling script.'; return nil; end
   script.die_with.push vals
   script.die_with.flatten!
   echo("The following script(s) will now die when I do: #{script.die_with.join(', ')}") unless script.die_with.empty?
end

def upstream_waitfor(*strings)
   strings.flatten!
   script = Script.current
   unless script.want_upstream then echo("This script wants to listen to the upstream, but it isn't set as receiving the upstream! This will cause a permanent hang, aborting (ask for the upstream with 'toggle_upstream' in the script)") ; return false end
   regexpstr = strings.join('|')
   while line = script.upstream_gets
      if line =~ /#{regexpstr}/i
         return line
      end
   end
end

def send_to_script(*values)
   values.flatten!
   if script = Script.list.find { |val| val.name =~ /^#{values.first}/i }
      if script.want_downstream
         values[1..-1].each { |val| script.downstream_buffer.push(val) }
      else
         values[1..-1].each { |val| script.unique_buffer.push(val) }
      end
      echo("Sent to #{script.name} -- '#{values[1..-1].join(' ; ')}'")
      return true
   else
      echo("'#{values.first}' does not match any active scripts!")
      return false
   end
end

def unique_send_to_script(*values)
   values.flatten!
   if script = Script.list.find { |val| val.name =~ /^#{values.first}/i }
      values[1..-1].each { |val| script.unique_buffer.push(val) }
      echo("sent to #{script}: #{values[1..-1].join(' ; ')}")
      return true
   else
      echo("'#{values.first}' does not match any active scripts!")
      return false
   end
end

def unique_waitfor(*strings)
   unless script = Script.current then echo 'unique_waitfor: cannot identify calling script.'; return nil; end
   strings.flatten!
   regexp = /#{strings.join('|')}/
   while true
      str = script.unique_gets
      if str =~ regexp
         return str
      end
   end
end

def unique_get
   unless script = Script.current then echo 'unique_get: cannot identify calling script.'; return nil; end
   script.unique_gets
end

def unique_get?
   unless script = Script.current then echo 'unique_get: cannot identify calling script.'; return nil; end
   script.unique_gets?
end

def multimove(*dirs)
   dirs.flatten.each { |dir| move(dir) }
end

def n;    'north';     end
def ne;   'northeast'; end
def e;    'east';      end
def se;   'southeast'; end
def s;    'south';     end
def sw;   'southwest'; end
def w;    'west';      end
def nw;   'northwest'; end
def u;    'up';        end
def up;   'up';          end
def down; 'down';      end
def d;    'down';      end
def o;    'out';       end
def out;  'out';       end

def move(dir='none', giveup_seconds=30, giveup_lines=30)
   #[LNet]-[Private]-Casis: "You begin to make your way up the steep headland pathway.  Before traveling very far, however, you lose your footing on the loose stones.  You struggle in vain to maintain your balance, then find yourself falling to the bay below!"  (20:35:36)
   #[LNet]-[Private]-Casis: "You smack into the water with a splash and sink far below the surface."  (20:35:50)
   # You approach the entrance and identify yourself to the guard.  The guard checks over a long scroll of names and says, "I'm sorry, the Guild is open to invitees only.  Please do return at a later date when we will be open to the public."
   if dir == 'none'
      echo 'move: no direction given'
      return false
   end

   need_full_hands = false
   tried_open = false
   tried_fix_drag = false
   line_count = 0
   room_count = XMLData.room_count
   giveup_time = Time.now.to_i + giveup_seconds.to_i
   save_stream = Array.new

   put_dir = proc {
      if XMLData.room_count > room_count
         fill_hands if need_full_hands
         Script.current.downstream_buffer.unshift(save_stream)
         Script.current.downstream_buffer.flatten!
         return true
      end
      waitrt?
      wait_while { stunned? }
      giveup_time = Time.now.to_i + giveup_seconds.to_i
      line_count = 0
      save_stream.push(clear)
      put dir
   }

   put_dir.call

   loop {
      line = get?
      unless line.nil?
         save_stream.push(line)
         line_count += 1
      end
      if line.nil?
         sleep 0.1
      elsif line =~ /^You can't do that while engaged!|^You are engaged to /
         # DragonRealms
         fput 'retreat'
         fput 'retreat'
         put_dir.call
      elsif line =~ /^You can't enter .+ and remain hidden or invisible\.|if he can't see you!$|^You can't enter .+ when you can't be seen\.$|^You can't do that without being seen\.$|^How do you intend to get .*? attention\?  After all, no one can see you right now\.$/
         fput 'unhide'
         put_dir.call
      elsif (line =~ /^You (?:take a few steps toward|trudge up to|limp towards|march up to|sashay gracefully up to|skip happily towards|sneak up to|stumble toward) a rusty doorknob/) and (dir =~ /door/)
         which = [ 'first', 'second', 'third', 'fourth', 'fifth', 'sixth', 'seventh', 'eight', 'ninth', 'tenth', 'eleventh', 'twelfth' ]
         if dir =~ /\b#{which.join('|')}\b/
            dir.sub!(/\b(#{which.join('|')})\b/) { "#{which[which.index($1)+1]}" }
         else
            dir.sub!('door', 'second door')
         end
         put_dir.call
      elsif line =~ /^You can't go there|^You can't (?:go|swim) in that direction\.|^Where are you trying to go\?|^What were you referring to\?|^I could not find what you were referring to\.|^How do you plan to do that here\?|^You take a few steps towards|^You cannot do that\.|^You settle yourself on|^You shouldn't annoy|^You can't go to|^That's probably not a very good idea|^You can't do that|^Maybe you should look|^You are already|^You walk over to|^You step over to|The [\w\s]+ is too far away|You may not pass\.|become impassable\.|prevents you from entering\.|Please leave promptly\.|is too far above you to attempt that\.$|^Uh, yeah\.  Right\.$|^Definitely NOT a good idea\.$|^Your attempt fails|^There doesn't seem to be any way to do that at the moment\.$/
         echo 'move: failed'
         fill_hands if need_full_hands
         Script.current.downstream_buffer.unshift(save_stream)
         Script.current.downstream_buffer.flatten!
         return false
      elsif line =~ /^An unseen force prevents you\.$|^Sorry, you aren't allowed to enter here\.|^That looks like someplace only performers should go\.|^As you climb, your grip gives way and you fall down|^The clerk stops you from entering the partition and says, "I'll need to see your ticket!"$|^The guard stops you, saying, "Only members of registered groups may enter the Meeting Hall\.  If you'd like to visit, ask a group officer for a guest pass\."$|^An? .*? reaches over and grasps [A-Z][a-z]+ by the neck preventing (?:him|her) from being dragged anywhere\.$|^You'll have to wait, [A-Z][a-z]+ .* locker|^As you move toward the gate, you carelessly bump into the guard|^You attempt to enter the back of the shop, but a clerk stops you.  "Your reputation precedes you!|you notice that thick beams are placed across the entry with a small sign that reads, "Abandoned\."$|appears to be closed, perhaps you should try again later\?$/
         echo 'move: failed'
         fill_hands if need_full_hands
         Script.current.downstream_buffer.unshift(save_stream)
         Script.current.downstream_buffer.flatten!
         # return nil instead of false to show the direction shouldn't be removed from the map database
         return nil
      elsif line =~ /^You grab [A-Z][a-z]+ and try to drag h(?:im|er), but s?he (?:is too heavy|doesn't budge)\.$|^Tentatively, you attempt to swim through the nook\.  After only a few feet, you begin to sink!  Your lungs burn from lack of air, and you begin to panic!  You frantically paddle back to safety!$|^Guards(?:wo)?man [A-Z][a-z]+ stops you and says, "(?:Stop\.|Halt!)  You need to make sure you check in|^You step into the root, but can see no way to climb the slippery tendrils inside\.  After a moment, you step back out\.$|^As you start .*? back to safe ground\.$|^You stumble a bit as you try to enter the pool but feel that your persistence will pay off\.$|^A shimmering field of magical crimson and gold energy flows through the area\.$|^You attempt to navigate your way through the fog, but (?:quickly become entangled|get turned around)/
         sleep 1
         waitrt?
         put_dir.call
      elsif line =~ /^Climbing.*(?:plunge|fall)|^Tentatively, you attempt to climb.*(?:fall|slip)|^You start.*but quickly realize|^You.*drop back to the ground|^You leap .* fall unceremoniously to the ground in a heap\.$|^You search for a way to make the climb .*? but without success\.$|^You start to climb .* you fall to the ground|^You attempt to climb .* wrong approach|^You run towards .*? slowly retreat back, reassessing the situation\./
         sleep 1
         waitrt?
         fput 'stand' unless standing?
         waitrt?
         put_dir.call
      elsif line =~ /^You begin to climb up the silvery thread.* you tumble to the ground/
         sleep 0.5
         waitrt?
         fput 'stand' unless standing?
         waitrt?
         if checkleft or checkright
            need_full_hands = true
            empty_hands
         end
         put_dir.call
      elsif line == 'You are too injured to be doing any climbing!'
         if (resolve = Spell[9704]) and resolve.known?
            wait_until { resolve.affordable? }
            resolve.cast
            put_dir.call
         else
            return nil
         end
      elsif line =~ /^You(?:'re going to| will) have to climb that\./
         dir.gsub!('go', 'climb')
         put_dir.call
      elsif line =~ /^You can't climb that\./
         dir.gsub!('climb', 'go')
         put_dir.call
      elsif line =~ /^You can't drag/
         if tried_fix_drag
            fill_hands if need_full_hands
            Script.current.downstream_buffer.unshift(save_stream)
            Script.current.downstream_buffer.flatten!
            return false
         elsif (dir =~ /^(?:go|climb) .+$/) and (drag_line = reget.reverse.find { |l| l =~ /^You grab .*?(?:'s body)? and drag|^You are now automatically attempting to drag .*? when/ })
            tried_fix_drag = true
            name = (/^You grab (.*?)('s body)? and drag/.match(drag_line).captures.first || /^You are now automatically attempting to drag (.*?) when/.match(drag_line).captures.first)
            target = /^(?:go|climb) (.+)$/.match(dir).captures.first
            fput "drag #{name}"
            dir = "drag #{name} #{target}"
            put_dir.call
         else
            tried_fix_drag = true
            dir.sub!(/^climb /, 'go ')
            put_dir.call
         end
      elsif line =~ /^Maybe if your hands were empty|^You figure freeing up both hands might help\.|^You can't .+ with your hands full\.$|^You'll need empty hands to climb that\.$|^It's a bit too difficult to swim holding|^You will need both hands free for such a difficult task\./
         need_full_hands = true
         empty_hands
         put_dir.call
      elsif line =~ /(?:appears|seems) to be closed\.$|^You cannot quite manage to squeeze between the stone doors\.$/
         if tried_open
            fill_hands if need_full_hands
            Script.current.downstream_buffer.unshift(save_stream)
            Script.current.downstream_buffer.flatten!
            return false
         else
            tried_open = true
            fput dir.sub(/go|climb/, 'open')
            put_dir.call
         end
      elsif line =~ /^(\.\.\.w|W)ait ([0-9]+) sec(onds)?\.$/
         if $2.to_i > 1
            sleep ($2.to_i - "0.2".to_f)
         else
            sleep 0.3
         end
         put_dir.call
      elsif line =~ /will have to stand up first|must be standing first|^You'll have to get up first|^But you're already sitting!|^Shouldn't you be standing first|^Try standing up|^Perhaps you should stand up|^Standing up might help|^You should really stand up first/
         fput 'stand'
         waitrt?
         put_dir.call
      elsif line =~ /^Sorry, you may only type ahead/
         sleep 1
         put_dir.call
      elsif line == 'You are still stunned.'
         wait_while { stunned? }
         put_dir.call
      elsif line =~ /you slip (?:on a patch of ice )?and flail uselessly as you land on your rear(?:\.|!)$|You wobble and stumble only for a moment before landing flat on your face!$/
         waitrt?
         fput 'stand' unless standing?
         waitrt?
         put_dir.call
      elsif line =~ /^You flick your hand (?:up|down)wards and focus your aura on your disk, but your disk only wobbles briefly\.$/
         put_dir.call
      elsif line =~ /^You dive into the fast-moving river, but the current catches you and whips you back to shore, wet and battered\.$|^Running through the swampy terrain, you notice a wet patch in the bog/
         waitrt?
         put_dir.call
      elsif line == "You don't seem to be able to move to do that."
         30.times { 
            break if clear.include?('You regain control of your senses!')
            sleep 0.1
         }
         put_dir.call
      end
      if XMLData.room_count > room_count
         fill_hands if need_full_hands
         Script.current.downstream_buffer.unshift(save_stream)
         Script.current.downstream_buffer.flatten!
         return true
      end
      if Time.now.to_i >= giveup_time
         echo "move: no recognized response in #{giveup_seconds} seconds.  giving up."
         fill_hands if need_full_hands
         Script.current.downstream_buffer.unshift(save_stream)
         Script.current.downstream_buffer.flatten!
         return nil
      end
      if line_count >= giveup_lines
         echo "move: no recognized response after #{line_count} lines.  giving up."
         fill_hands if need_full_hands
         Script.current.downstream_buffer.unshift(save_stream)
         Script.current.downstream_buffer.flatten!
         return nil
      end
   }
end

def watchhealth(value, theproc=nil, &block)
   value = value.to_i
   if block.nil?
      if !theproc.respond_to? :call
         respond "`watchhealth' was not given a block or a proc to execute!"
         return nil
      else
         block = theproc
      end
   end
   Thread.new {
      wait_while { health(value) }
      block.call
   }
end

def wait_until(announce=nil)
   priosave = Thread.current.priority
   Thread.current.priority = 0
   unless announce.nil? or yield
      respond(announce)
   end
   until yield
      sleep 0.25
   end
   Thread.current.priority = priosave
end

def wait_while(announce=nil)
   priosave = Thread.current.priority
   Thread.current.priority = 0
   unless announce.nil? or !yield
      respond(announce)
   end
   while yield
      sleep 0.25
   end
   Thread.current.priority = priosave
end

def checkpaths(dir="none")
   if dir == "none"
      if XMLData.room_exits.empty?
         return false
      else
         return XMLData.room_exits.collect { |dir| dir = SHORTDIR[dir] }
      end
   else
      XMLData.room_exits.include?(dir) || XMLData.room_exits.include?(SHORTDIR[dir])
   end
end

def reverse_direction(dir)
   if dir == "n" then 's'
   elsif dir == "ne" then 'sw'
   elsif dir == "e" then 'w'
   elsif dir == "se" then 'nw'
   elsif dir == "s" then 'n'
   elsif dir == "sw" then 'ne'
   elsif dir == "w" then 'e'
   elsif dir == "nw" then 'se'
   elsif dir == "up" then 'down'
   elsif dir == "down" then 'up'
   elsif dir == "out" then 'out'
   elsif dir == 'o' then out
   elsif dir == 'u' then 'down'
   elsif dir == 'd' then up
   elsif dir == n then s
   elsif dir == ne then sw
   elsif dir == e then w
   elsif dir == se then nw
   elsif dir == s then n
   elsif dir == sw then ne
   elsif dir == w then e
   elsif dir == nw then se
   elsif dir == u then d
   elsif dir == d then u
   else echo("Cannot recognize direction to properly reverse it!"); false
   end
end

def walk(*boundaries, &block)
   boundaries.flatten!
   unless block.nil?
      until val = yield
         walk(*boundaries)
      end
      return val
   end
   if $last_dir and !boundaries.empty? and checkroomdescrip =~ /#{boundaries.join('|')}/i
      move($last_dir)
      $last_dir = reverse_direction($last_dir)
      return checknpcs
   end
   dirs = checkpaths
   dirs.delete($last_dir) unless dirs.length < 2
   this_time = rand(dirs.length)
   $last_dir = reverse_direction(dirs[this_time])
   move(dirs[this_time])
   checknpcs
end

def run
   loop { break unless walk }
end

def check_mind(string=nil)
   if string.nil?
      return XMLData.mind_text
   elsif (string.class == String) and (string.to_i == 0)
      if string =~ /#{XMLData.mind_text}/i
         return true
      else
         return false
      end
   elsif string.to_i.between?(0,100)
      return string.to_i <= XMLData.mind_value.to_i
   else
      echo("check_mind error! You must provide an integer ranging from 0-100, the common abbreviation of how full your head is, or provide no input to have check_mind return an abbreviation of how filled your head is.") ; sleep 1
      return false
   end
end

def checkmind(string=nil)
   if string.nil?
      return XMLData.mind_text
   elsif string.class == String and string.to_i == 0
      if string =~ /#{XMLData.mind_text}/i
         return true
      else
         return false
      end
   elsif string.to_i.between?(1,8)
      mind_state = ['clear as a bell','fresh and clear','clear','muddled','becoming numbed','numbed','must rest','saturated']
      if mind_state.index(XMLData.mind_text)
         mind = mind_state.index(XMLData.mind_text) + 1
         return string.to_i <= mind
      else
         echo "Bad string in checkmind: mind_state"
         nil
      end
   else
      echo("Checkmind error! You must provide an integer ranging from 1-8 (7 is fried, 8 is 100% fried), the common abbreviation of how full your head is, or provide no input to have checkmind return an abbreviation of how filled your head is.") ; sleep 1
      return false
   end
end

def percentmind(num=nil)
   if num.nil?
      XMLData.mind_value
   else 
      XMLData.mind_value >= num.to_i
   end
end

def checkfried
   if XMLData.mind_text =~ /must rest|saturated/
      true
   else
      false
   end
end

def checksaturated
   if XMLData.mind_text =~ /saturated/
      true
   else
      false
   end
end

def checkmana(num=nil)
   if num.nil?
      XMLData.mana
   else
      XMLData.mana >= num.to_i
   end
end

def maxmana
   XMLData.max_mana
end

def percentmana(num=nil)
   if XMLData.max_mana == 0
      percent = 100
   else
      percent = ((XMLData.mana.to_f / XMLData.max_mana.to_f) * 100).to_i
   end
   if num.nil?
      percent
   else 
      percent >= num.to_i
   end
end

def checkhealth(num=nil)
   if num.nil?
      XMLData.health
   else
      XMLData.health >= num.to_i
   end
end

def maxhealth
   XMLData.max_health
end

def percenthealth(num=nil)
   if num.nil?
      ((XMLData.health.to_f / XMLData.max_health.to_f) * 100).to_i
   else
      ((XMLData.health.to_f / XMLData.max_health.to_f) * 100).to_i >= num.to_i
   end
end

def checkspirit(num=nil)
   if num.nil?
      XMLData.spirit
   else
      XMLData.spirit >= num.to_i
   end
end

def maxspirit
   XMLData.max_spirit
end

def percentspirit(num=nil)
   if num.nil?
      ((XMLData.spirit.to_f / XMLData.max_spirit.to_f) * 100).to_i
   else
      ((XMLData.spirit.to_f / XMLData.max_spirit.to_f) * 100).to_i >= num.to_i
   end
end

def checkstamina(num=nil)
   if num.nil?
      XMLData.stamina
   else
      XMLData.stamina >= num.to_i
   end
end

def maxstamina()
   XMLData.max_stamina
end

def percentstamina(num=nil)
   if XMLData.max_stamina == 0
      percent = 100
   else
      percent = ((XMLData.stamina.to_f / XMLData.max_stamina.to_f) * 100).to_i
   end
   if num.nil?
      percent
   else
      percent >= num.to_i
   end
end

def checkstance(num=nil)
   if num.nil?
      XMLData.stance_text
   elsif (num.class == String) and (num.to_i == 0)
      if num =~ /off/i
         XMLData.stance_value == 0
      elsif num =~ /adv/i
         XMLData.stance_value.between?(01, 20)
      elsif num =~ /for/i
         XMLData.stance_value.between?(21, 40)
      elsif num =~ /neu/i
         XMLData.stance_value.between?(41, 60)
      elsif num =~ /gua/i
         XMLData.stance_value.between?(61, 80)
      elsif num =~ /def/i
         XMLData.stance_value == 100
      else
         echo "checkstance: invalid argument (#{num}).  Must be off/adv/for/neu/gua/def or 0-100"
         nil
      end
   elsif (num.class == Fixnum) or (num =~ /^[0-9]+$/ and num = num.to_i)
      XMLData.stance_value == num.to_i
   else
      echo "checkstance: invalid argument (#{num}).  Must be off/adv/for/neu/gua/def or 0-100"
      nil
   end
end

def percentstance(num=nil)
   if num.nil?
      XMLData.stance_value
   else
      XMLData.stance_value >= num.to_i
   end
end

def checkencumbrance(string=nil)
   if string.nil?
      XMLData.encumbrance_text
   elsif (string.class == Fixnum) or (string =~ /^[0-9]+$/ and string = string.to_i)
      string <= XMLData.encumbrance_value
   else
      # fixme
      if string =~ /#{XMLData.encumbrance_text}/i
         true
      else
         false
      end
   end
end

def percentencumbrance(num=nil)
   if num.nil?
      XMLData.encumbrance_value
   else
      num.to_i <= XMLData.encumbrance_value
   end
end

def checkarea(*strings)
   strings.flatten!
   if strings.empty?
      XMLData.room_title.split(',').first.sub('[','')
   else
      XMLData.room_title.split(',').first =~ /#{strings.join('|')}/i
   end
end

def checkroom(*strings)
   strings.flatten!
   if strings.empty?
      XMLData.room_title.chomp
   else
      XMLData.room_title =~ /#{strings.join('|')}/i
   end
end

def outside?
   if XMLData.room_exits_string =~ /Obvious paths:/
      true
   else
      false
   end
end

def checkfamarea(*strings)
   strings.flatten!
   if strings.empty? then return XMLData.familiar_room_title.split(',').first.sub('[','') end
   XMLData.familiar_room_title.split(',').first =~ /#{strings.join('|')}/i
end

def checkfampaths(dir="none")
   if dir == "none"
      if XMLData.familiar_room_exits.empty?
         return false
      else
         return XMLData.familiar_room_exits
      end
   else
      XMLData.familiar_room_exits.include?(dir)
   end
end

def checkfamroom(*strings)
   strings.flatten! ; if strings.empty? then return XMLData.familiar_room_title.chomp end
   XMLData.familiar_room_title =~ /#{strings.join('|')}/i
end

def checkfamnpcs(*strings)
   parsed = Array.new
   XMLData.familiar_npcs.each { |val| parsed.push(val.split.last) }
   if strings.empty?
      if parsed.empty?
         return false
      else
         return parsed
      end
   else
      if mtch = strings.find { |lookfor| parsed.find { |critter| critter =~ /#{lookfor}/ } }
         return mtch
      else
         return false
      end
   end
end

def checkfampcs(*strings)
   familiar_pcs = Array.new
   XMLData.familiar_pcs.to_s.gsub(/Lord |Lady |Great |High |Renowned |Grand |Apprentice |Novice |Journeyman /,'').split(',').each { |line| familiar_pcs.push(line.slice(/[A-Z][a-z]+/)) }
   if familiar_pcs.empty?
      return false
   elsif strings.empty?
      return familiar_pcs
   else
      regexpstr = strings.join('|\b')
      peeps = familiar_pcs.find_all { |val| val =~ /\b#{regexpstr}/i }
      if peeps.empty?
         return false
      else
         return peeps
      end
   end
end

def checkpcs(*strings)
   pcs = GameObj.pcs.collect { |pc| pc.noun }
   if pcs.empty?
      if strings.empty? then return nil else return false end
   end
   strings.flatten!
   if strings.empty?
      pcs
   else
      regexpstr = strings.join(' ')
      pcs.find { |pc| regexpstr =~ /\b#{pc}/i }
   end
end

def checknpcs(*strings)
   npcs = GameObj.npcs.collect { |npc| npc.noun }
   if npcs.empty?
      if strings.empty? then return nil else return false end
   end
   strings.flatten!
   if strings.empty?
      npcs
   else
      regexpstr = strings.join(' ')
      npcs.find { |npc| regexpstr =~ /\b#{npc}/i }
   end
end

def count_npcs
   checknpcs.length
end

def checkright(*hand)
   if GameObj.right_hand.nil? then return nil end
   hand.flatten!
   if GameObj.right_hand.name == "Empty" or GameObj.right_hand.name.empty?
      nil
   elsif hand.empty?
      GameObj.right_hand.noun
   else
      hand.find { |instance| GameObj.right_hand.name =~ /#{instance}/i }
   end
end

def checkleft(*hand)
   if GameObj.left_hand.nil? then return nil end
   hand.flatten!
   if GameObj.left_hand.name == "Empty" or GameObj.left_hand.name.empty?
      nil
   elsif hand.empty?
      GameObj.left_hand.noun
   else
      hand.find { |instance| GameObj.left_hand.name =~ /#{instance}/i }
   end
end

def checkroomdescrip(*val)
   val.flatten!
   if val.empty?
      return XMLData.room_description
   else
      return XMLData.room_description =~ /#{val.join('|')}/i
   end
end

def checkfamroomdescrip(*val)
   val.flatten!
   if val.empty?
      return XMLData.familiar_room_description
   else
      return XMLData.familiar_room_description =~ /#{val.join('|')}/i
   end
end

def checkspell(*spells)
   spells.flatten!
   return false if Spell.active.empty?
   spells.each { |spell| return false unless Spell[spell].active? }
   true
end

def checkprep(spell=nil)
   if spell.nil?
      XMLData.prepared_spell
   elsif spell.class != String
      echo("Checkprep error, spell # not implemented!  You must use the spell name")
      false
   else
      XMLData.prepared_spell =~ /^#{spell}/i
   end
end

def setpriority(val=nil)
   if val.nil? then return Thread.current.priority end
   if val.to_i > 3
      echo("You're trying to set a script's priority as being higher than the send/recv threads (this is telling Lich to run the script before it even gets data to give the script, and is useless); the limit is 3")
      return Thread.current.priority
   else
      Thread.current.group.list.each { |thr| thr.priority = val.to_i }
      return Thread.current.priority
   end
end

def checkbounty
   if XMLData.bounty_task
      return XMLData.bounty_task
   else
      return nil
   end
end

def checksleeping
   return $infomon_sleeping
end
def sleeping?
   return $infomon_sleeping
end
def checkbound
   return $infomon_bound
end
def bound?
   return $infomon_bound
end
def checksilenced
   $infomon_silenced
end
def silenced?
   $infomon_silenced
end
def checkcalmed
   $infomon_calmed
end
def calmed?
   $infomon_calmed
end
def checkcutthroat
   $infomon_cutthroat
end
def cutthroat?
   $infomon_cutthroat
end

def variable
   unless script = Script.current then echo 'variable: cannot identify calling script.'; return nil; end
   script.vars
end

def pause(num=1)
   if num =~ /m/
      sleep((num.sub(/m/, '').to_f * 60))
   elsif num =~ /h/
      sleep((num.sub(/h/, '').to_f * 3600))
   elsif num =~ /d/
      sleep((num.sub(/d/, '').to_f * 86400))
   else
      sleep(num.to_f)
   end
end

def cast(spell, target=nil, results_of_interest=nil)
   if spell.class == Spell
      spell.cast(target, results_of_interest)
   elsif ( (spell.class == Fixnum) or (spell.to_s =~ /^[0-9]+$/) ) and (find_spell = Spell[spell.to_i])
      find_spell.cast(target, results_of_interest)
   elsif (spell.class == String) and (find_spell = Spell[spell])
      find_spell.cast(target, results_of_interest)
   else
      echo "cast: invalid spell (#{spell})"
      false
   end
end

def clear(opt=0)
   unless script = Script.current then respond('--- clear: Unable to identify calling script.'); return false; end
   to_return = script.downstream_buffer.dup
   script.downstream_buffer.clear
   to_return
end

def match(label, string)
   strings = [ label, string ]
   strings.flatten!
   unless script = Script.current then echo("An unknown script thread tried to fetch a game line from the queue, but Lich can't process the call without knowing which script is calling! Aborting...") ; Thread.current.kill ; return false end
   if strings.empty? then echo("Error! 'match' was given no strings to look for!") ; sleep 1 ; return false end
   unless strings.length == 2
      while line_in = script.gets
         strings.each { |string|
            if line_in =~ /#{string}/ then return $~.to_s end
         }
      end
   else
      if script.respond_to?(:match_stack_add)
         script.match_stack_add(strings.first.to_s, strings.last)
      else
         script.match_stack_labels.push(strings[0].to_s)
         script.match_stack_strings.push(strings[1])
      end
   end
end

def matchtimeout(secs, *strings)
   unless script = Script.current then echo("An unknown script thread tried to fetch a game line from the queue, but Lich can't process the call without knowing which script is calling! Aborting...") ; Thread.current.kill ; return false end
   unless (secs.class == Float || secs.class == Fixnum)
      echo('matchtimeout error! You appear to have given it a string, not a #! Syntax:  matchtimeout(30, "You stand up")')
      return false
   end
   strings.flatten!
   if strings.empty?
      echo("matchtimeout without any strings to wait for!")
      sleep 1
      return false
   end
   regexpstr = strings.join('|')
   end_time = Time.now.to_f + secs
   loop {
      line = get?
      if line.nil?
         sleep 0.1
      elsif line =~ /#{regexpstr}/i
         return line
      end
      if (Time.now.to_f > end_time)
         return false
      end
   }
end

def matchbefore(*strings)
   strings.flatten!
   unless script = Script.current then echo("An unknown script thread tried to fetch a game line from the queue, but Lich can't process the call without knowing which script is calling! Aborting...") ; Thread.current.kill ; return false end
   if strings.empty? then echo("matchbefore without any strings to wait for!") ; return false end
   regexpstr = strings.join('|')
   loop { if (line_in = script.gets) =~ /#{regexpstr}/ then return $`.to_s end }
end

def matchafter(*strings)
   strings.flatten!
   unless script = Script.current then echo("An unknown script thread tried to fetch a game line from the queue, but Lich can't process the call without knowing which script is calling! Aborting...") ; Thread.current.kill ; return false end
   if strings.empty? then echo("matchafter without any strings to wait for!") ; return end
   regexpstr = strings.join('|')
   loop { if (line_in = script.gets) =~ /#{regexpstr}/ then return $'.to_s end }
end

def matchboth(*strings)
   strings.flatten!
   unless script = Script.current then echo("An unknown script thread tried to fetch a game line from the queue, but Lich can't process the call without knowing which script is calling! Aborting...") ; Thread.current.kill ; return false end
   if strings.empty? then echo("matchboth without any strings to wait for!") ; return end
   regexpstr = strings.join('|')
   loop { if (line_in = script.gets) =~ /#{regexpstr}/ then break end }
   return [ $`.to_s, $'.to_s ]
end

def matchwait(*strings)
   unless script = Script.current then respond('--- matchwait: Unable to identify calling script.'); return false; end
   strings.flatten!
   unless strings.empty?
      regexpstr = strings.collect { |str| str.kind_of?(Regexp) ? str.source : str }.join('|')
      regexobj = /#{regexpstr}/
      while line_in = script.gets
         return line_in if line_in =~ regexobj
      end
   else
      strings = script.match_stack_strings
      labels = script.match_stack_labels
      regexpstr = /#{strings.join('|')}/i
      while line_in = script.gets
         if mdata = regexpstr.match(line_in)
            jmp = labels[strings.index(mdata.to_s) || strings.index(strings.find { |str| line_in =~ /#{str}/i })]
            script.match_stack_clear
            goto jmp
         end
      end
   end
end

def waitforre(regexp)
   unless script = Script.current then respond('--- waitforre: Unable to identify calling script.'); return false; end
   unless regexp.class == Regexp then echo("Script error! You have given 'waitforre' something to wait for, but it isn't a Regular Expression! Use 'waitfor' if you want to wait for a string."); sleep 1; return nil end
   regobj = regexp.match(script.gets) until regobj
end

def waitfor(*strings)
   unless script = Script.current then respond('--- waitfor: Unable to identify calling script.'); return false; end
   strings.flatten!
   if (script.class == WizardScript) and (strings.length == 1) and (strings.first.strip == '>')
      return script.gets
   end
   if strings.empty?
      echo 'waitfor: no string to wait for'
      return false
   end
   regexpstr = strings.join('|')
   while true
      line_in = script.gets
      if (line_in =~ /#{regexpstr}/i) then return line_in end
   end
end

def wait
   unless script = Script.current then respond('--- wait: unable to identify calling script.'); return false; end
   script.clear
   return script.gets
end

def get
   Script.current.gets
end

def get?
   Script.current.gets?
end

def reget(*lines)
   unless script = Script.current then respond('--- reget: Unable to identify calling script.'); return false; end
   lines.flatten!
   if caller.find { |c| c =~ /regetall/ }
      history = ($_SERVERBUFFER_.history + $_SERVERBUFFER_).join("\n")
   else
      history = $_SERVERBUFFER_.dup.join("\n")
   end
   unless script.want_downstream_xml
      history.gsub!(/<pushStream id=["'](?:spellfront|inv|bounty|society)["'][^>]*\/>.*?<popStream[^>]*>/m, '')
      history.gsub!(/<stream id="Spells">.*?<\/stream>/m, '')
      history.gsub!(/<(compDef|inv|component|right|left|spell|prompt)[^>]*>.*?<\/\1>/m, '')
      history.gsub!(/<[^>]+>/, '')
      history.gsub!('&gt;', '>')
      history.gsub!('&lt;', '<')
   end
   history = history.split("\n").delete_if { |line| line.nil? or line.empty? or line =~ /^[\r\n\s\t]*$/ }
   if lines.first.kind_of?(Numeric) or lines.first.to_i.nonzero?
      history = history[-([lines.shift.to_i,history.length].min)..-1]
   end
   unless lines.empty? or lines.nil?
      regex = /#{lines.join('|')}/i
      history = history.find_all { |line| line =~ regex }
   end
   if history.empty?
      nil
   else
      history
   end
end

def regetall(*lines)
   reget(*lines)
end

def multifput(*cmds)
   cmds.flatten.compact.each { |cmd| fput(cmd) }
end

def fput(message, *waitingfor)
   unless script = Script.current then respond('--- waitfor: Unable to identify calling script.'); return false; end
   waitingfor.flatten!
   clear
   put(message)

   while string = get
      if string =~ /(?:\.\.\.wait |Wait )[0-9]+/
         hold_up = string.slice(/[0-9]+/).to_i
         sleep(hold_up) unless hold_up.nil?
         clear
         put(message)
         next
      elsif string =~ /^You.+struggle.+stand/
         clear
         fput 'stand'
         next
      elsif string =~ /stunned|can't do that while|cannot seem|^(?!You rummage).*can't seem|don't seem|Sorry, you may only type ahead/
         if dead?
            echo "You're dead...! You can't do that!"
            sleep 1
            script.downstream_buffer.unshift(string)
            return false
         elsif checkstunned
            while checkstunned
               sleep("0.25".to_f)
            end
         elsif checkwebbed
            while checkwebbed
               sleep("0.25".to_f)
            end
         elsif string =~ /Sorry, you may only type ahead/
            sleep 1
         else
            sleep 0.1
            script.downstream_buffer.unshift(string)
            return false
         end
         clear
         put(message)
         next
      else
         if waitingfor.empty?
            script.downstream_buffer.unshift(string)
            return string
         else
            if foundit = waitingfor.find { |val| string =~ /#{val}/i }
               script.downstream_buffer.unshift(string)
               return foundit
            end
            sleep 1
            clear
            put(message)
            next
         end
      end
   end
end

def put(*messages)
   messages.each { |message| Game.puts(message) }
end

def quiet_exit
   script = Script.current
   script.quiet = !(script.quiet)
end

def matchfindexact(*strings)
   strings.flatten!
     unless script = Script.current then echo("An unknown script thread tried to fetch a game line from the queue, but Lich can't process the call without knowing which script is calling! Aborting...") ; Thread.current.kill ; return false end
   if strings.empty? then echo("error! 'matchfind' with no strings to look for!") ; sleep 1 ; return false end
   looking = Array.new
   strings.each { |str| looking.push(str.gsub('?', '(\b.+\b)')) }
   if looking.empty? then echo("matchfind without any strings to wait for!") ; return false end
   regexpstr = looking.join('|')
   while line_in = script.gets
      if gotit = line_in.slice(/#{regexpstr}/)
         matches = Array.new
         looking.each_with_index { |str,idx|
            if gotit =~ /#{str}/i
               strings[idx].count('?').times { |n| matches.push(eval("$#{n+1}")) }
            end
         }
         break
      end
   end
   if matches.length == 1
      return matches.first
   else
      return matches.compact
   end
end

def matchfind(*strings)
   regex = /#{strings.flatten.join('|').gsub('?', '(.+)')}/i
   unless script = Script.current
      respond "Unknown script is asking to use matchfind!  Cannot process request without identifying the calling script; killing this thread."
      Thread.current.kill
   end
   while true
      if reobj = regex.match(script.gets)
         ret = reobj.captures.compact
         if ret.length < 2
            return ret.first
         else
            return ret
         end
      end
   end
end

def matchfindword(*strings)
   regex = /#{strings.flatten.join('|').gsub('?', '([\w\d]+)')}/i
   unless script = Script.current
      respond "Unknown script is asking to use matchfindword!  Cannot process request without identifying the calling script; killing this thread."
      Thread.current.kill
   end
   while true
      if reobj = regex.match(script.gets)
         ret = reobj.captures.compact
         if ret.length < 2
            return ret.first
         else
            return ret
         end
      end
   end
end

def send_scripts(*messages)
   messages.flatten!
   messages.each { |message|
      Script.new_downstream(message)
   }
   true
end

def status_tags(onoff="none")
   script = Script.current
   if onoff == "on"
      script.want_downstream = false
      script.want_downstream_xml = true
      echo("Status tags will be sent to this script.")
   elsif onoff == "off"
      script.want_downstream = true
      script.want_downstream_xml = false
      echo("Status tags will no longer be sent to this script.")
   elsif script.want_downstream_xml
      script.want_downstream = true
      script.want_downstream_xml = false
   else
      script.want_downstream = false
      script.want_downstream_xml = true
   end
end

def respond(first = "", *messages)
   str = ''
   begin
      if first.class == Array
         first.flatten.each { |ln| str += sprintf("%s\r\n", ln.to_s.chomp) }
      else
         str += sprintf("%s\r\n", first.to_s.chomp)
      end
      messages.flatten.each { |message| str += sprintf("%s\r\n", message.to_s.chomp) }
      str.split(/\r?\n/).each { |line| Script.new_script_output(line); Buffer.update(line, Buffer::SCRIPT_OUTPUT) }
      if $frontend == 'stormfront'
         str = "<output class=\"mono\"/>\r\n#{str.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')}<output class=\"\"/>\r\n"
      elsif $frontend == 'profanity'
         str = str.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
      end
      wait_while { XMLData.in_stream }
      $_CLIENT_.puts(str)
      if $_DETACHABLE_CLIENT_
         $_DETACHABLE_CLIENT_.puts(str) rescue nil
      end
   rescue
      puts $!
      puts $!.backtrace.first
   end
end

def _respond(first = "", *messages)
   str = ''
   begin
      if first.class == Array
         first.flatten.each { |ln| str += sprintf("%s\r\n", ln.to_s.chomp) }
      else
         str += sprintf("%s\r\n", first.to_s.chomp)
      end
      messages.flatten.each { |message| str += sprintf("%s\r\n", message.to_s.chomp) }
      str.split(/\r?\n/).each { |line| Script.new_script_output(line); Buffer.update(line, Buffer::SCRIPT_OUTPUT) } # fixme: strip/separate script output?
      wait_while { XMLData.in_stream }
      $_CLIENT_.puts(str)
      if $_DETACHABLE_CLIENT_
         $_DETACHABLE_CLIENT_.puts(str) rescue nil
      end
   rescue
      puts $!
      puts $!.backtrace.first
   end
end

def noded_pulse
   if Stats.prof =~ /warrior|rogue|sorcerer/i
      stats = [ Skills.smc.to_i, Skills.emc.to_i ]
   elsif Stats.prof =~ /empath|bard/i
      stats = [ Skills.smc.to_i, Skills.mmc.to_i ]
   elsif Stats.prof =~ /wizard/i
      stats = [ Skills.emc.to_i, 0 ]
   elsif Stats.prof =~ /paladin|cleric|ranger/i
      stats = [ Skills.smc.to_i, 0 ]
   else
      stats = [ 0, 0 ]
   end
   return (maxmana * 25 / 100) + (stats.max/10) + (stats.min/20)
end

def unnoded_pulse
   if Stats.prof =~ /warrior|rogue|sorcerer/i
      stats = [ Skills.smc.to_i, Skills.emc.to_i ]
   elsif Stats.prof =~ /empath|bard/i
      stats = [ Skills.smc.to_i, Skills.mmc.to_i ]
   elsif Stats.prof =~ /wizard/i
      stats = [ Skills.emc.to_i, 0 ]
   elsif Stats.prof =~ /paladin|cleric|ranger/i
      stats = [ Skills.smc.to_i, 0 ]
   else
      stats = [ 0, 0 ]
   end
   return (maxmana * 15 / 100) + (stats.max/10) + (stats.min/20)
end

def empty_hands
   $fill_hands_actions ||= Array.new
   actions = Array.new
   right_hand = GameObj.right_hand
   left_hand = GameObj.left_hand
   if UserVars.lootsack.nil? or UserVars.lootsack.empty?
      lootsack = nil
   else
      lootsack = GameObj.inv.find { |obj| obj.name =~ /#{Regexp.escape(UserVars.lootsack.strip)}/i } || GameObj.inv.find { |obj| obj.name =~ /#{Regexp.escape(UserVars.lootsack).sub(' ', ' .*')}/i }
   end
   other_containers_var = nil
   other_containers = proc {
      if other_containers_var.nil?
         Script.current.want_downstream = false
         Script.current.want_downstream_xml = true
         result = dothistimeout 'inventory containers', 5, /^You are wearing/
         Script.current.want_downstream_xml = false
         Script.current.want_downstream = true
         other_containers_ids = result.scan(/exist="(.*?)"/).flatten - [ lootsack.id ]
         other_containers_var = GameObj.inv.find_all { |obj| other_containers_ids.include?(obj.id) }
      end
      other_containers_var
   }
   if left_hand.id
      waitrt?
      if (left_hand.noun =~ /shield|buckler|targe|heater|parma|aegis|scutum|greatshield|mantlet|pavis|arbalest|bow|crossbow|yumi|arbalest/) and (wear_result = dothistimeout("wear ##{left_hand.id}", 8, /^You .*#{left_hand.noun}|^You can only wear \w+ items in that location\.$|^You can't wear that\.$/)) and (wear_result !~ /^You can only wear \w+ items in that location\.$|^You can't wear that\.$/)
         actions.unshift proc {
            dothistimeout "remove ##{left_hand.id}", 3, /^You|^Remove what\?/
            20.times { break if GameObj.left_hand.id == left_hand.id or GameObj.right_hand.id == left_hand.id; sleep 0.1 }
            if GameObj.right_hand.id == left_hand.id
               dothistimeout 'swap', 3, /^You don't have anything to swap!|^You swap/
            end
         }
      else
         actions.unshift proc {
            dothistimeout "get ##{left_hand.id}", 3, /^You (?:shield the opening of .*? from view as you |discreetly |carefully |deftly )?(?:remove|draw|grab|get|reach|slip|tuck|retrieve|already have)|^Get what\?$|^Why don't you leave some for others\?$|^You need a free hand/
            20.times { break if (GameObj.left_hand.id == left_hand.id) or (GameObj.right_hand.id == left_hand.id); sleep 0.1 }
            if GameObj.right_hand.id == left_hand.id
               dothistimeout 'swap', 3, /^You don't have anything to swap!|^You swap/
            end
         }
         if lootsack
            result = dothistimeout "put ##{left_hand.id} in ##{lootsack.id}", 4, /^You (?:attempt to shield .*? from view as you |discreetly |carefully |absent-mindedly )?(?:put|place|slip|tuck|add|drop|untie your|find an incomplete bundle|wipe off .*? and sheathe|secure)|^A sigh of grateful pleasure can be heard as you feed .*? to your|^As you place|^I could not find what you were referring to\.$|^Your bundle would be too large|^The .+ is too large to be bundled\.|^As you place your|^As you prepare to drop|^The .*? is already a bundle|^Your .*? won't fit in .*?\.$|^You can't .+ It's closed!$/
            if result =~ /^You can't .+ It's closed!$/
               actions.push proc { fput "close ##{lootsack.id}" }
               dothistimeout "open ##{lootsack.id}", 3, /^You open|^That is already open\./
               result = dothistimeout "put ##{left_hand.id} in ##{lootsack.id}", 3, /^You (?:attempt to shield .*? from view as you |discreetly |carefully |absent-mindedly )?(?:put|place|slip|tuck|add|drop|untie your|find an incomplete bundle|wipe off .*? and sheathe|secure)|^A sigh of grateful pleasure can be heard as you feed .*? to your|^As you place|^I could not find what you were referring to\.$|^Your bundle would be too large|^The .+ is too large to be bundled\.|^As you place your|^As you prepare to drop|^The .*? is already a bundle|^Your .*? won't fit in .*?\.$|^You can't .+ It's closed!$/
            end
         else
            result = nil
         end
         if result.nil? or result =~ /^Your .*? won't fit in .*?\.$/
            for container in other_containers.call
               result = dothistimeout "put ##{left_hand.id} in ##{container.id}", 4, /^You (?:attempt to shield .*? from view as you |discreetly |carefully |absent-mindedly )?(?:put|place|slip|tuck|add|drop|untie your|find an incomplete bundle|wipe off .*? and sheathe|secure)|^A sigh of grateful pleasure can be heard as you feed .*? to your|^As you place|^I could not find what you were referring to\.$|^Your bundle would be too large|^The .+ is too large to be bundled\.|^As you place your|^As you prepare to drop|^The .*? is already a bundle|^Your .*? won't fit in .*?\.$|^You can't .+ It's closed!$/
               if result =~ /^You can't .+ It's closed!$/
                  actions.push proc { fput "close ##{container.id}" }
                  dothistimeout "open ##{container.id}", 3, /^You open|^That is already open\./
                  result = dothistimeout "put ##{left_hand.id} in ##{container.id}", 3, /^You (?:attempt to shield .*? from view as you |discreetly |carefully |absent-mindedly )?(?:put|place|slip|tuck|add|drop|untie your|find an incomplete bundle|wipe off .*? and sheathe|secure)|^A sigh of grateful pleasure can be heard as you feed .*? to your|^As you place|^I could not find what you were referring to\.$|^Your bundle would be too large|^The .+ is too large to be bundled\.|^As you place your|^As you prepare to drop|^The .*? is already a bundle|^Your .*? won't fit in .*?\.$|^You can't .+ It's closed!$/
               end
               break if result =~ /^You (?:put|absent-mindedly drop|slip)/
            end
         end
      end
   end
   if right_hand.id
      waitrt?
      actions.unshift proc {
         dothistimeout "get ##{right_hand.id}", 3, /^You (?:shield the opening of .*? from view as you |discreetly |carefully |deftly )?(?:remove|draw|grab|get|reach|slip|tuck|retrieve|already have)|^Get what\?$|^Why don't you leave some for others\?$|^You need a free hand/
         20.times { break if GameObj.left_hand.id == right_hand.id or GameObj.right_hand.id == right_hand.id; sleep 0.1 }
         if GameObj.left_hand.id == right_hand.id
            dothistimeout 'swap', 3, /^You don't have anything to swap!|^You swap/
         end
      }
      if UserVars.weapon and UserVars.weaponsack and not UserVars.weapon.empty? and not UserVars.weaponsack.empty? and (right_hand.name =~ /#{Regexp.escape(UserVars.weapon.strip)}/i or right_hand.name =~ /#{Regexp.escape(UserVars.weapon).sub(' ', ' .*')}/i)
         weaponsack = GameObj.inv.find { |obj| obj.name =~ /#{Regexp.escape(UserVars.weaponsack.strip)}/i } || GameObj.inv.find { |obj| obj.name =~ /#{Regexp.escape(UserVars.weaponsack).sub(' ', ' .*')}/i }
      end
      if weaponsack
         result = dothistimeout "put ##{right_hand.id} in ##{weaponsack.id}", 4, /^You (?:attempt to shield .*? from view as you |discreetly |carefully |absent-mindedly )?(?:put|place|slip|tuck|add|drop|untie your|find an incomplete bundle|wipe off .*? and sheathe|secure)|^A sigh of grateful pleasure can be heard as you feed .*? to your|^As you place|^I could not find what you were referring to\.$|^Your bundle would be too large|^The .+ is too large to be bundled\.|^As you place your|^As you prepare to drop|^The .*? is already a bundle|^Your .*? won't fit in .*?\.$|^You can't .+ It's closed!$/
         if result =~ /^You can't .+ It's closed!$/
            actions.push proc { fput "close ##{weaponsack.id}" }
            dothistimeout "open ##{weaponsack.id}", 3, /^You open|^That is already open\./
            result = dothistimeout "put ##{right_hand.id} in ##{weaponsack.id}", 3, /^You (?:attempt to shield .*? from view as you |discreetly |carefully |absent-mindedly )?(?:put|place|slip|tuck|add|drop|untie your|find an incomplete bundle|wipe off .*? and sheathe|secure)|^A sigh of grateful pleasure can be heard as you feed .*? to your|^As you place|^I could not find what you were referring to\.$|^Your bundle would be too large|^The .+ is too large to be bundled\.|^As you place your|^As you prepare to drop|^The .*? is already a bundle|^Your .*? won't fit in .*?\.$|^You can't .+ It's closed!$/
         end
      elsif lootsack
         result = dothistimeout "put ##{right_hand.id} in ##{lootsack.id}", 4, /^You (?:attempt to shield .*? from view as you |discreetly |carefully |absent-mindedly )?(?:put|place|slip|tuck|add|drop|untie your|find an incomplete bundle|wipe off .*? and sheathe|secure)|^A sigh of grateful pleasure can be heard as you feed .*? to your|^As you place|^I could not find what you were referring to\.$|^Your bundle would be too large|^The .+ is too large to be bundled\.|^As you place your|^As you prepare to drop|^The .*? is already a bundle|^Your .*? won't fit in .*?\.$|^You can't .+ It's closed!$/
         if result =~ /^You can't .+ It's closed!$/
            actions.push proc { fput "close ##{lootsack.id}" }
            dothistimeout "open ##{lootsack.id}", 3, /^You open|^That is already open\./
            result = dothistimeout "put ##{right_hand.id} in ##{lootsack.id}", 3, /^You (?:attempt to shield .*? from view as you |discreetly |carefully |absent-mindedly )?(?:put|place|slip|tuck|add|drop|untie your|find an incomplete bundle|wipe off .*? and sheathe|secure)|^A sigh of grateful pleasure can be heard as you feed .*? to your|^As you place|^I could not find what you were referring to\.$|^Your bundle would be too large|^The .+ is too large to be bundled\.|^As you place your|^As you prepare to drop|^The .*? is already a bundle|^Your .*? won't fit in .*?\.$|^You can't .+ It's closed!$/
         end
      else
         result = nil
      end
      if result.nil? or result =~ /^Your .*? won't fit in .*?\.$/
         for container in other_containers.call
            result = dothistimeout "put ##{right_hand.id} in ##{container.id}", 4, /^You (?:attempt to shield .*? from view as you |discreetly |carefully |absent-mindedly )?(?:put|place|slip|tuck|add|drop|untie your|find an incomplete bundle|wipe off .*? and sheathe|secure)|^A sigh of grateful pleasure can be heard as you feed .*? to your|^As you place|^I could not find what you were referring to\.$|^Your bundle would be too large|^The .+ is too large to be bundled\.|^As you place your|^As you prepare to drop|^The .*? is already a bundle|^Your .*? won't fit in .*?\.$|^You can't .+ It's closed!$/
            if result =~ /^You can't .+ It's closed!$/
               actions.push proc { fput "close ##{container.id}" }
               dothistimeout "open ##{container.id}", 3, /^You open|^That is already open\./
               result = dothistimeout "put ##{right_hand.id} in ##{container.id}", 3, /^You (?:attempt to shield .*? from view as you |discreetly |carefully |absent-mindedly )?(?:put|place|slip|tuck|add|drop|untie your|find an incomplete bundle|wipe off .*? and sheathe|secure)|^A sigh of grateful pleasure can be heard as you feed .*? to your|^As you place|^I could not find what you were referring to\.$|^Your bundle would be too large|^The .+ is too large to be bundled\.|^As you place your|^As you prepare to drop|^The .*? is already a bundle|^Your .*? won't fit in .*?\.$|^You can't .+ It's closed!$/
            end
            break if result =~ /^You (?:put|absent-mindedly drop|slip)/
         end
      end
   end
   $fill_hands_actions.push(actions)
end

def fill_hands
   $fill_hands_actions ||= Array.new
   for action in $fill_hands_actions.pop
      action.call
   end
end

def empty_hand
   $fill_hand_actions ||= Array.new
   actions = Array.new
   right_hand = GameObj.right_hand
   left_hand = GameObj.left_hand
   if UserVars.lootsack.nil? or UserVars.lootsack.empty?
      lootsack = nil
   else
      lootsack = GameObj.inv.find { |obj| obj.name =~ /#{Regexp.escape(UserVars.lootsack.strip)}/i } || GameObj.inv.find { |obj| obj.name =~ /#{Regexp.escape(UserVars.lootsack).sub(' ', ' .*')}/i }
   end
   other_containers_var = nil
   other_containers = proc {
      if other_containers_var.nil?
         Script.current.want_downstream = false
         Script.current.want_downstream_xml = true
         result = dothistimeout 'inventory containers', 5, /^You are wearing/
         Script.current.want_downstream_xml = false
         Script.current.want_downstream = true
         other_containers_ids = result.scan(/exist="(.*?)"/).flatten - [ lootsack.id ]
         other_containers_var = GameObj.inv.find_all { |obj| other_containers_ids.include?(obj.id) }
      end
      other_containers_var
   }
   unless (right_hand.id.nil? and ([ Wounds.rightArm, Wounds.rightHand, Scars.rightArm, Scars.rightHand ].max < 3)) or (left_hand.id.nil? and ([ Wounds.leftArm, Wounds.leftHand, Scars.leftArm, Scars.leftHand ].max < 3))
      if right_hand.id and ([ Wounds.rightArm, Wounds.rightHand, Scars.rightArm, Scars.rightHand ].max < 3 or [ Wounds.leftArm, Wounds.leftHand, Scars.leftArm, Scars.leftHand ].max = 3)
         waitrt?
         actions.unshift proc {
            dothistimeout "get ##{right_hand.id}", 3, /^You (?:shield the opening of .*? from view as you |discreetly |carefully |deftly )?(?:remove|draw|grab|get|reach|slip|tuck|retrieve|already have)|^Get what\?$|^Why don't you leave some for others\?$|^You need a free hand/
            20.times { break if GameObj.left_hand.id == right_hand.id or GameObj.right_hand.id == right_hand.id; sleep 0.1 }
            if GameObj.left_hand.id == right_hand.id
               dothistimeout 'swap', 3, /^You don't have anything to swap!|^You swap/
            end
         }
         if UserVars.weapon and UserVars.weaponsack and not UserVars.weapon.empty? and not UserVars.weaponsack.empty? and (right_hand.name =~ /#{Regexp.escape(UserVars.weapon.strip)}/i or right_hand.name =~ /#{Regexp.escape(UserVars.weapon).sub(' ', ' .*')}/i)
            weaponsack = GameObj.inv.find { |obj| obj.name =~ /#{Regexp.escape(UserVars.weaponsack.strip)}/i } || GameObj.inv.find { |obj| obj.name =~ /#{Regexp.escape(UserVars.weaponsack).sub(' ', ' .*')}/i }
         end
         if weaponsack
            result = dothistimeout "put ##{right_hand.id} in ##{weaponsack.id}", 4, /^You (?:attempt to shield .*? from view as you |discreetly |carefully |absent-mindedly )?(?:put|place|slip|tuck|add|drop|untie your|find an incomplete bundle|wipe off .*? and sheathe|secure)|^A sigh of grateful pleasure can be heard as you feed .*? to your|^As you place|^I could not find what you were referring to\.$|^Your bundle would be too large|^The .+ is too large to be bundled\.|^As you place your|^As you prepare to drop|^The .*? is already a bundle|^Your .*? won't fit in .*?\.$|^You can't .+ It's closed!$/
            if result =~ /^You can't .+ It's closed!$/
               actions.push proc { fput "close ##{weaponsack.id}" }
               dothistimeout "open ##{weaponsack.id}", 3, /^You open|^That is already open\./
               result = dothistimeout "put ##{right_hand.id} in ##{weaponsack.id}", 3, /^You (?:attempt to shield .*? from view as you |discreetly |carefully |absent-mindedly )?(?:put|place|slip|tuck|add|drop|untie your|find an incomplete bundle|wipe off .*? and sheathe|secure)|^A sigh of grateful pleasure can be heard as you feed .*? to your|^As you place|^I could not find what you were referring to\.$|^Your bundle would be too large|^The .+ is too large to be bundled\.|^As you place your|^As you prepare to drop|^The .*? is already a bundle|^Your .*? won't fit in .*?\.$|^You can't .+ It's closed!$/
            end
         elsif lootsack
            result = dothistimeout "put ##{right_hand.id} in ##{lootsack.id}", 4, /^You (?:attempt to shield .*? from view as you |discreetly |carefully |absent-mindedly )?(?:put|place|slip|tuck|add|drop|untie your|find an incomplete bundle|wipe off .*? and sheathe|secure)|^A sigh of grateful pleasure can be heard as you feed .*? to your|^As you place|^I could not find what you were referring to\.$|^Your bundle would be too large|^The .+ is too large to be bundled\.|^As you place your|^As you prepare to drop|^The .*? is already a bundle|^Your .*? won't fit in .*?\.$|^You can't .+ It's closed!$/
            if result =~ /^You can't .+ It's closed!$/
               actions.push proc { fput "close ##{lootsack.id}" }
               dothistimeout "open ##{lootsack.id}", 3, /^You open|^That is already open\./
               result = dothistimeout "put ##{right_hand.id} in ##{lootsack.id}", 3, /^You (?:attempt to shield .*? from view as you |discreetly |carefully |absent-mindedly )?(?:put|place|slip|tuck|add|drop|untie your|find an incomplete bundle|wipe off .*? and sheathe|secure)|^A sigh of grateful pleasure can be heard as you feed .*? to your|^As you place|^I could not find what you were referring to\.$|^Your bundle would be too large|^The .+ is too large to be bundled\.|^As you place your|^As you prepare to drop|^The .*? is already a bundle|^Your .*? won't fit in .*?\.$|^You can't .+ It's closed!$/
            end
         else
            result = nil
         end
         if result.nil? or result =~ /^Your .*? won't fit in .*?\.$/
            for container in other_containers.call
               result = dothistimeout "put ##{right_hand.id} in ##{container.id}", 4, /^You (?:attempt to shield .*? from view as you |discreetly |carefully |absent-mindedly )?(?:put|place|slip|tuck|add|drop|untie your|find an incomplete bundle|wipe off .*? and sheathe|secure)|^A sigh of grateful pleasure can be heard as you feed .*? to your|^As you place|^I could not find what you were referring to\.$|^Your bundle would be too large|^The .+ is too large to be bundled\.|^As you place your|^As you prepare to drop|^The .*? is already a bundle|^Your .*? won't fit in .*?\.$|^You can't .+ It's closed!$/
               if result =~ /^You can't .+ It's closed!$/
                  actions.push proc { fput "close ##{container.id}" }
                  dothistimeout "open ##{container.id}", 3, /^You open|^That is already open\./
                  result = dothistimeout "put ##{right_hand.id} in ##{container.id}", 3, /^You (?:attempt to shield .*? from view as you |discreetly |carefully |absent-mindedly )?(?:put|place|slip|tuck|add|drop|untie your|find an incomplete bundle|wipe off .*? and sheathe|secure)|^A sigh of grateful pleasure can be heard as you feed .*? to your|^As you place|^I could not find what you were referring to\.$|^Your bundle would be too large|^The .+ is too large to be bundled\.|^As you place your|^As you prepare to drop|^The .*? is already a bundle|^Your .*? won't fit in .*?\.$|^You can't .+ It's closed!$/
               end
               break if result =~ /^You (?:put|absent-mindedly drop|slip)/
            end
         end
      else
         waitrt?
         if (left_hand.noun =~ /shield|buckler|targe|heater|parma|aegis|scutum|greatshield|mantlet|pavis|arbalest|bow|crossbow|yumi|arbalest/) and (wear_result = dothistimeout("wear ##{left_hand.id}", 8, /^You .*#{left_hand.noun}|^You can only wear \w+ items in that location\.$|^You can't wear that\.$/)) and (wear_result !~ /^You can only wear \w+ items in that location\.$|^You can't wear that\.$/)
            actions.unshift proc {
               dothistimeout "remove ##{left_hand.id}", 3, /^You|^Remove what\?/
               20.times { break if GameObj.left_hand.id == left_hand.id or GameObj.right_hand.id == left_hand.id; sleep 0.1 }
               if GameObj.right_hand.id == left_hand.id
                  dothistimeout 'swap', 3, /^You don't have anything to swap!|^You swap/
               end
            }
         else
            actions.unshift proc {
               dothistimeout "get ##{left_hand.id}", 3, /^You (?:shield the opening of .*? from view as you |discreetly |carefully |deftly )?(?:remove|draw|grab|get|reach|slip|tuck|retrieve|already have)|^Get what\?$|^Why don't you leave some for others\?$|^You need a free hand/
               20.times { break if GameObj.left_hand.id == left_hand.id or GameObj.right_hand.id == left_hand.id; sleep 0.1 }
               if GameObj.right_hand.id == left_hand.id
                  dothistimeout 'swap', 3, /^You don't have anything to swap!|^You swap/
               end
            }
            if lootsack
               result = dothistimeout "put ##{left_hand.id} in ##{lootsack.id}", 4, /^You (?:attempt to shield .*? from view as you |discreetly |carefully |absent-mindedly )?(?:put|place|slip|tuck|add|drop|untie your|find an incomplete bundle|wipe off .*? and sheathe|secure)|^A sigh of grateful pleasure can be heard as you feed .*? to your|^As you place|^I could not find what you were referring to\.$|^Your bundle would be too large|^The .+ is too large to be bundled\.|^As you place your|^As you prepare to drop|^The .*? is already a bundle|^Your .*? won't fit in .*?\.$|^You can't .+ It's closed!$/
               if result =~ /^You can't .+ It's closed!$/
                  actions.push proc { fput "close ##{lootsack.id}" }
                  dothistimeout "open ##{lootsack.id}", 3, /^You open|^That is already open\./
                  result = dothistimeout "put ##{left_hand.id} in ##{lootsack.id}", 3, /^You (?:attempt to shield .*? from view as you |discreetly |carefully |absent-mindedly )?(?:put|place|slip|tuck|add|drop|untie your|find an incomplete bundle|wipe off .*? and sheathe|secure)|^A sigh of grateful pleasure can be heard as you feed .*? to your|^As you place|^I could not find what you were referring to\.$|^Your bundle would be too large|^The .+ is too large to be bundled\.|^As you place your|^As you prepare to drop|^The .*? is already a bundle|^Your .*? won't fit in .*?\.$|^You can't .+ It's closed!$/
               end
            else
               result = nil
            end
            if result.nil? or result =~ /^Your .*? won't fit in .*?\.$/
               for container in other_containers.call
                  result = dothistimeout "put ##{left_hand.id} in ##{container.id}", 4, /^You (?:attempt to shield .*? from view as you |discreetly |carefully |absent-mindedly )?(?:put|place|slip|tuck|add|drop|untie your|find an incomplete bundle|wipe off .*? and sheathe|secure)|^A sigh of grateful pleasure can be heard as you feed .*? to your|^As you place|^I could not find what you were referring to\.$|^Your bundle would be too large|^The .+ is too large to be bundled\.|^As you place your|^As you prepare to drop|^The .*? is already a bundle|^Your .*? won't fit in .*?\.$|^You can't .+ It's closed!$/
                  if result =~ /^You can't .+ It's closed!$/
                     actions.push proc { fput "close ##{container.id}" }
                     dothistimeout "open ##{container.id}", 3, /^You open|^That is already open\./
                     result = dothistimeout "put ##{left_hand.id} in ##{container.id}", 3, /^You (?:attempt to shield .*? from view as you |discreetly |carefully |absent-mindedly )?(?:put|place|slip|tuck|add|drop|untie your|find an incomplete bundle|wipe off .*? and sheathe|secure)|^A sigh of grateful pleasure can be heard as you feed .*? to your|^As you place|^I could not find what you were referring to\.$|^Your bundle would be too large|^The .+ is too large to be bundled\.|^As you place your|^As you prepare to drop|^The .*? is already a bundle|^Your .*? won't fit in .*?\.$|^You can't .+ It's closed!$/
                  end
                  break if result =~ /^You (?:put|absent-mindedly drop|slip)/
               end
            end
         end
      end
   end
   $fill_hand_actions.push(actions)
end

def fill_hand
   $fill_hand_actions ||= Array.new
   for action in $fill_hand_actions.pop
      action.call
   end
end

def empty_right_hand
   $fill_right_hand_actions ||= Array.new
   actions = Array.new
   right_hand = GameObj.right_hand
   if UserVars.lootsack.nil? or UserVars.lootsack.empty?
      lootsack = nil
   else
      lootsack = GameObj.inv.find { |obj| obj.name =~ /#{Regexp.escape(UserVars.lootsack.strip)}/i } || GameObj.inv.find { |obj| obj.name =~ /#{Regexp.escape(UserVars.lootsack).sub(' ', ' .*')}/i }
   end
   other_containers_var = nil
   other_containers = proc {
      if other_containers_var.nil?
         Script.current.want_downstream = false
         Script.current.want_downstream_xml = true
         result = dothistimeout 'inventory containers', 5, /^You are wearing/
         Script.current.want_downstream_xml = false
         Script.current.want_downstream = true
         other_containers_ids = result.scan(/exist="(.*?)"/).flatten - [ lootsack.id ]
         other_containers_var = GameObj.inv.find_all { |obj| other_containers_ids.include?(obj.id) }
      end
      other_containers_var
   }
   if right_hand.id
      waitrt?
      actions.unshift proc {
         dothistimeout "get ##{right_hand.id}", 3, /^You (?:shield the opening of .*? from view as you |discreetly |carefully |deftly )?(?:remove|draw|grab|get|reach|slip|tuck|retrieve|already have)|^Get what\?$|^Why don't you leave some for others\?$|^You need a free hand/
         20.times { break if GameObj.left_hand.id == right_hand.id or GameObj.right_hand.id == right_hand.id; sleep 0.1 }
         if GameObj.left_hand.id == right_hand.id
            dothistimeout 'swap', 3, /^You don't have anything to swap!|^You swap/
         end
      }
      if UserVars.weapon and UserVars.weaponsack and not UserVars.weapon.empty? and not UserVars.weaponsack.empty? and (right_hand.name =~ /#{Regexp.escape(UserVars.weapon.strip)}/i or right_hand.name =~ /#{Regexp.escape(UserVars.weapon).sub(' ', ' .*')}/i)
         weaponsack = GameObj.inv.find { |obj| obj.name =~ /#{Regexp.escape(UserVars.weaponsack.strip)}/i } || GameObj.inv.find { |obj| obj.name =~ /#{Regexp.escape(UserVars.weaponsack).sub(' ', ' .*')}/i }
      end
      if weaponsack
         result = dothistimeout "put ##{right_hand.id} in ##{weaponsack.id}", 4, /^You (?:attempt to shield .*? from view as you |discreetly |carefully |absent-mindedly )?(?:put|place|slip|tuck|add|drop|untie your|find an incomplete bundle|wipe off .*? and sheathe|secure)|^A sigh of grateful pleasure can be heard as you feed .*? to your|^As you place|^I could not find what you were referring to\.$|^Your bundle would be too large|^The .+ is too large to be bundled\.|^As you place your|^As you prepare to drop|^The .*? is already a bundle|^Your .*? won't fit in .*?\.$|^You can't .+ It's closed!$/
         if result =~ /^You can't .+ It's closed!$/
            actions.push proc { fput "close ##{weaponsack.id}" }
            dothistimeout "open ##{weaponsack.id}", 3, /^You open|^That is already open\./
            result = dothistimeout "put ##{right_hand.id} in ##{weaponsack.id}", 3, /^You (?:attempt to shield .*? from view as you |discreetly |carefully |absent-mindedly )?(?:put|place|slip|tuck|add|drop|untie your|find an incomplete bundle|wipe off .*? and sheathe|secure)|^A sigh of grateful pleasure can be heard as you feed .*? to your|^As you place|^I could not find what you were referring to\.$|^Your bundle would be too large|^The .+ is too large to be bundled\.|^As you place your|^As you prepare to drop|^The .*? is already a bundle|^Your .*? won't fit in .*?\.$|^You can't .+ It's closed!$/
         end
      elsif lootsack
         result = dothistimeout "put ##{right_hand.id} in ##{lootsack.id}", 4, /^You (?:attempt to shield .*? from view as you |discreetly |carefully |absent-mindedly )?(?:put|place|slip|tuck|add|drop|untie your|find an incomplete bundle|wipe off .*? and sheathe|secure)|^A sigh of grateful pleasure can be heard as you feed .*? to your|^As you place|^I could not find what you were referring to\.$|^Your bundle would be too large|^The .+ is too large to be bundled\.|^As you place your|^As you prepare to drop|^The .*? is already a bundle|^Your .*? won't fit in .*?\.$|^You can't .+ It's closed!$/
         if result =~ /^You can't .+ It's closed!$/
            actions.push proc { fput "close ##{lootsack.id}" }
            dothistimeout "open ##{lootsack.id}", 3, /^You open|^That is already open\./
            result = dothistimeout "put ##{right_hand.id} in ##{lootsack.id}", 3, /^You (?:attempt to shield .*? from view as you |discreetly |carefully |absent-mindedly )?(?:put|place|slip|tuck|add|drop|untie your|find an incomplete bundle|wipe off .*? and sheathe|secure)|^A sigh of grateful pleasure can be heard as you feed .*? to your|^As you place|^I could not find what you were referring to\.$|^Your bundle would be too large|^The .+ is too large to be bundled\.|^As you place your|^As you prepare to drop|^The .*? is already a bundle|^Your .*? won't fit in .*?\.$|^You can't .+ It's closed!$/
         end
      else
         result = nil
      end
      if result.nil? or result =~ /^Your .*? won't fit in .*?\.$/
         for container in other_containers.call
            result = dothistimeout "put ##{right_hand.id} in ##{container.id}", 4, /^You (?:attempt to shield .*? from view as you |discreetly |carefully |absent-mindedly )?(?:put|place|slip|tuck|add|drop|untie your|find an incomplete bundle|wipe off .*? and sheathe|secure)|^A sigh of grateful pleasure can be heard as you feed .*? to your|^As you place|^I could not find what you were referring to\.$|^Your bundle would be too large|^The .+ is too large to be bundled\.|^As you place your|^As you prepare to drop|^The .*? is already a bundle|^Your .*? won't fit in .*?\.$|^You can't .+ It's closed!$/
            if result =~ /^You can't .+ It's closed!$/
               actions.push proc { fput "close ##{container.id}" }
               dothistimeout "open ##{container.id}", 3, /^You open|^That is already open\./
               result = dothistimeout "put ##{right_hand.id} in ##{container.id}", 3, /^You (?:attempt to shield .*? from view as you |discreetly |carefully |absent-mindedly )?(?:put|place|slip|tuck|add|drop|untie your|find an incomplete bundle|wipe off .*? and sheathe|secure)|^A sigh of grateful pleasure can be heard as you feed .*? to your|^As you place|^I could not find what you were referring to\.$|^Your bundle would be too large|^The .+ is too large to be bundled\.|^As you place your|^As you prepare to drop|^The .*? is already a bundle|^Your .*? won't fit in .*?\.$|^You can't .+ It's closed!$/
            end
            break if result =~ /^You (?:put|absent-mindedly drop|slip)/
         end
      end
   end
   $fill_right_hand_actions.push(actions)
end

def fill_right_hand
   $fill_right_hand_actions ||= Array.new
   for action in $fill_right_hand_actions.pop
      action.call
   end
end

def empty_left_hand
   $fill_left_hand_actions ||= Array.new
   actions = Array.new
   left_hand = GameObj.left_hand
   if UserVars.lootsack.nil? or UserVars.lootsack.empty?
      lootsack = nil
   else
      lootsack = GameObj.inv.find { |obj| obj.name =~ /#{Regexp.escape(UserVars.lootsack.strip)}/i } || GameObj.inv.find { |obj| obj.name =~ /#{Regexp.escape(UserVars.lootsack).sub(' ', ' .*')}/i }
   end
   other_containers_var = nil
   other_containers = proc {
      if other_containers_var.nil?
         Script.current.want_downstream = false
         Script.current.want_downstream_xml = true
         result = dothistimeout 'inventory containers', 5, /^You are wearing/
         Script.current.want_downstream_xml = false
         Script.current.want_downstream = true
         other_containers_ids = result.scan(/exist="(.*?)"/).flatten - [ lootsack.id ]
         other_containers_var = GameObj.inv.find_all { |obj| other_containers_ids.include?(obj.id) }
      end
      other_containers_var
   }
   if left_hand.id
      waitrt?
      if (left_hand.noun =~ /shield|buckler|targe|heater|parma|aegis|scutum|greatshield|mantlet|pavis|arbalest|bow|crossbow|yumi|arbalest/) and (wear_result = dothistimeout("wear ##{left_hand.id}", 8, /^You .*#{left_hand.noun}|^You can only wear \w+ items in that location\.$|^You can't wear that\.$/)) and (wear_result !~ /^You can only wear \w+ items in that location\.$|^You can't wear that\.$/)
         actions.unshift proc {
            dothistimeout "remove ##{left_hand.id}", 3, /^You|^Remove what\?/
            20.times { break if GameObj.left_hand.id == left_hand.id or GameObj.right_hand.id == left_hand.id; sleep 0.1 }
            if GameObj.right_hand.id == left_hand.id
               dothistimeout 'swap', 3, /^You don't have anything to swap!|^You swap/
            end
         }
      else
         actions.unshift proc {
            dothistimeout "get ##{left_hand.id}", 3, /^You (?:shield the opening of .*? from view as you |discreetly |carefully |deftly )?(?:remove|draw|grab|get|reach|slip|tuck|retrieve|already have)|^Get what\?$|^Why don't you leave some for others\?$|^You need a free hand/
            20.times { break if GameObj.left_hand.id == left_hand.id or GameObj.right_hand.id == left_hand.id; sleep 0.1 }
            if GameObj.right_hand.id == left_hand.id
               dothistimeout 'swap', 3, /^You don't have anything to swap!|^You swap/
            end
         }
         if lootsack
            result = dothistimeout "put ##{left_hand.id} in ##{lootsack.id}", 4, /^You (?:attempt to shield .*? from view as you |discreetly |carefully |absent-mindedly )?(?:put|place|slip|tuck|add|drop|untie your|find an incomplete bundle|wipe off .*? and sheathe|secure)|^A sigh of grateful pleasure can be heard as you feed .*? to your|^As you place|^I could not find what you were referring to\.$|^Your bundle would be too large|^The .+ is too large to be bundled\.|^As you place your|^As you prepare to drop|^The .*? is already a bundle|^Your .*? won't fit in .*?\.$|^You can't .+ It's closed!$/
            if result =~ /^You can't .+ It's closed!$/
               actions.push proc { fput "close ##{lootsack.id}" }
               dothistimeout "open ##{lootsack.id}", 3, /^You open|^That is already open\./
               dothistimeout "put ##{left_hand.id} in ##{lootsack.id}", 3, /^You (?:attempt to shield .*? from view as you |discreetly |carefully |absent-mindedly )?(?:put|place|slip|tuck|add|drop|untie your|find an incomplete bundle|wipe off .*? and sheathe|secure)|^A sigh of grateful pleasure can be heard as you feed .*? to your|^As you place|^I could not find what you were referring to\.$|^Your bundle would be too large|^The .+ is too large to be bundled\.|^As you place your|^As you prepare to drop|^The .*? is already a bundle|^Your .*? won't fit in .*?\.$|^You can't .+ It's closed!$/
            end
         else
            result = nil
         end
         if result.nil? or result =~ /^Your .*? won't fit in .*?\.$/
            for container in other_containers.call
               result = dothistimeout "put ##{left_hand.id} in ##{container.id}", 4, /^You (?:attempt to shield .*? from view as you |discreetly |carefully |absent-mindedly )?(?:put|place|slip|tuck|add|drop|untie your|find an incomplete bundle|wipe off .*? and sheathe|secure)|^A sigh of grateful pleasure can be heard as you feed .*? to your|^As you place|^I could not find what you were referring to\.$|^Your bundle would be too large|^The .+ is too large to be bundled\.|^As you place your|^As you prepare to drop|^The .*? is already a bundle|^Your .*? won't fit in .*?\.$|^You can't .+ It's closed!$/
               if result =~ /^You can't .+ It's closed!$/
                  actions.push proc { fput "close ##{container.id}" }
                  dothistimeout "open ##{container.id}", 3, /^You open|^That is already open\./
                  result = dothistimeout "put ##{left_hand.id} in ##{container.id}", 3, /^You (?:attempt to shield .*? from view as you |discreetly |carefully |absent-mindedly )?(?:put|place|slip|tuck|add|drop|untie your|find an incomplete bundle|wipe off .*? and sheathe|secure)|^A sigh of grateful pleasure can be heard as you feed .*? to your|^As you place|^I could not find what you were referring to\.$|^Your bundle would be too large|^The .+ is too large to be bundled\.|^As you place your|^As you prepare to drop|^The .*? is already a bundle|^Your .*? won't fit in .*?\.$|^You can't .+ It's closed!$/
               end
               break if result =~ /^You (?:put|absent-mindedly drop|slip)/
            end
         end
      end
   end
   $fill_left_hand_actions.push(actions)
end

def fill_left_hand
   $fill_left_hand_actions ||= Array.new
   for action in $fill_left_hand_actions.pop
      action.call
   end
end

def dothis (action, success_line)
   loop {
      Script.current.clear
      put action
      loop {
         line = get
         if line =~ success_line
            return line
         elsif line =~ /^(\.\.\.w|W)ait ([0-9]+) sec(onds)?\.$/
            if $2.to_i > 1
               sleep ($2.to_i - "0.5".to_f)
            else
               sleep 0.3
            end
            break
         elsif line == 'Sorry, you may only type ahead 1 command.'
            sleep 1
            break
         elsif line == 'You are still stunned.'
            wait_while { stunned? }
            break
         elsif line == 'That is impossible to do while unconscious!'
            100.times {
               unless line = get?
                  sleep 0.1
               else
                  break if line =~ /Your thoughts slowly come back to you as you find yourself lying on the ground\.  You must have been sleeping\.$|^You wake up from your slumber\.$/
               end
            }
            break
         elsif line == "You don't seem to be able to move to do that."
            100.times {
               unless line = get?
                  sleep 0.1
               else
                  break if line == 'The restricting force that envelops you dissolves away.'
               end
            }
            break
         elsif line == "You can't do that while entangled in a web."
            wait_while { checkwebbed }
            break
         elsif line == 'You find that impossible under the effects of the lullabye.'
            100.times {
               unless line = get?
                  sleep 0.1
               else
                  # fixme
                  break if line == 'You shake off the effects of the lullabye.'
               end
            }
            break
         end
      }
   }
end

def dothistimeout (action, timeout, success_line)
   end_time = Time.now.to_f + timeout
   line = nil
   loop {
      Script.current.clear
      put action unless action.nil?
      loop {
         line = get?
         if line.nil?
            sleep 0.1
         elsif line =~ success_line
            return line
         elsif line =~ /^(\.\.\.w|W)ait ([0-9]+) sec(onds)?\.$/
            if $2.to_i > 1
               sleep ($2.to_i - "0.5".to_f)
            else
               sleep 0.3
            end
            end_time = Time.now.to_f + timeout
            break
         elsif line == 'Sorry, you may only type ahead 1 command.'
            sleep 1
            end_time = Time.now.to_f + timeout
            break
         elsif line == 'You are still stunned.'
            wait_while { stunned? }
            end_time = Time.now.to_f + timeout
            break
         elsif line == 'That is impossible to do while unconscious!'
            100.times {
               unless line = get?
                  sleep 0.1
               else
                  break if line =~ /Your thoughts slowly come back to you as you find yourself lying on the ground\.  You must have been sleeping\.$|^You wake up from your slumber\.$/
               end
            }
            break
         elsif line == "You don't seem to be able to move to do that."
            100.times {
               unless line = get?
                  sleep 0.1
               else
                  break if line == 'The restricting force that envelops you dissolves away.'
               end
            }
            break
         elsif line == "You can't do that while entangled in a web."
            wait_while { checkwebbed }
            break
         elsif line == 'You find that impossible under the effects of the lullabye.'
            100.times {
               unless line = get?
                  sleep 0.1
               else
                  # fixme
                  break if line == 'You shake off the effects of the lullabye.'
               end
            }
            break
         end
         if Time.now.to_f >= end_time
            return nil
         end
      }
   }
end

$link_highlight_start = ''
$link_highlight_end = ''
$speech_highlight_start = ''
$speech_highlight_end = ''

def sf_to_wiz(line)
   begin
      return line if line == "\r\n"

      if $sftowiz_multiline
         $sftowiz_multiline = $sftowiz_multiline + line
         line = $sftowiz_multiline
      end
      if (line.scan(/<pushStream[^>]*\/>/).length > line.scan(/<popStream[^>]*\/>/).length)
         $sftowiz_multiline = line
         return nil
      end
      if (line.scan(/<style id="\w+"[^>]*\/>/).length > line.scan(/<style id=""[^>]*\/>/).length)
         $sftowiz_multiline = line
         return nil
      end
      $sftowiz_multiline = nil
      if line =~ /<LaunchURL src="(.*?)" \/>/
         $_CLIENT_.puts "\034GSw00005\r\nhttps://www.play.net#{$1}\r\n"
      end
      if line =~ /<preset id='speech'>(.*?)<\/preset>/m
         line = line.sub(/<preset id='speech'>.*?<\/preset>/m, "#{$speech_highlight_start}#{$1}#{$speech_highlight_end}")
      end
      if line =~ /<pushStream id="thoughts"[^>]*>(?:<a[^>]*>)?([A-Z][a-z]+)(?:<\/a>)?\s*([\s\[\]\(\)A-z]+)?:(.*?)<popStream\/>/m
         line = line.sub(/<pushStream id="thoughts"[^>]*>(?:<a[^>]*>)?[A-Z][a-z]+(?:<\/a>)?\s*[\s\[\]\(\)A-z]+:.*?<popStream\/>/m, "You hear the faint thoughts of #{$1} echo in your mind:\r\n#{$2}#{$3}")
      end
      if line =~ /<pushStream id="voln"[^>]*>\[Voln \- (?:<a[^>]*>)?([A-Z][a-z]+)(?:<\/a>)?\]\s*(".*")[\r\n]*<popStream\/>/m
         line = line.sub(/<pushStream id="voln"[^>]*>\[Voln \- (?:<a[^>]*>)?([A-Z][a-z]+)(?:<\/a>)?\]\s*(".*")[\r\n]*<popStream\/>/m, "The Symbol of Thought begins to burn in your mind and you hear #{$1} thinking, #{$2}\r\n")
      end
      if line =~ /<stream id="thoughts"[^>]*>([^:]+): (.*?)<\/stream>/m
         line = line.sub(/<stream id="thoughts"[^>]*>.*?<\/stream>/m, "You hear the faint thoughts of #{$1} echo in your mind:\r\n#{$2}")
      end
      if line =~ /<pushStream id="familiar"[^>]*>(.*)<popStream\/>/m
         line = line.sub(/<pushStream id="familiar"[^>]*>.*<popStream\/>/m, "\034GSe\r\n#{$1}\034GSf\r\n")
      end
      if line =~ /<pushStream id="death"\/>(.*?)<popStream\/>/m
         line = line.sub(/<pushStream id="death"\/>.*?<popStream\/>/m, "\034GSw00003\r\n#{$1}\034GSw00004\r\n")
      end
      if line =~ /<style id="roomName" \/>(.*?)<style id=""\/>/m
         line = line.sub(/<style id="roomName" \/>.*?<style id=""\/>/m, "\034GSo\r\n#{$1}\034GSp\r\n")
      end
      line.gsub!(/<style id="roomDesc"\/><style id=""\/>\r?\n/, '')
      if line =~ /<style id="roomDesc"\/>(.*?)<style id=""\/>/m
         desc = $1.gsub(/<a[^>]*>/, $link_highlight_start).gsub("</a>", $link_highlight_end)
         line = line.sub(/<style id="roomDesc"\/>.*?<style id=""\/>/m, "\034GSH\r\n#{desc}\034GSI\r\n")
      end
      line = line.gsub("</prompt>\r\n", "</prompt>")
      line = line.gsub("<pushBold/>", "\034GSL\r\n")
      line = line.gsub("<popBold/>", "\034GSM\r\n")
      line = line.gsub(/<pushStream id=["'](?:spellfront|inv|bounty|society|speech|talk)["'][^>]*\/>.*?<popStream[^>]*>/m, '')
      line = line.gsub(/<stream id="Spells">.*?<\/stream>/m, '')
      line = line.gsub(/<(compDef|inv|component|right|left|spell|prompt)[^>]*>.*?<\/\1>/m, '')
      line = line.gsub(/<[^>]+>/, '')
      line = line.gsub('&gt;', '>')
      line = line.gsub('&lt;', '<')
      return nil if line.gsub("\r\n", '').length < 1
      return line
   rescue
      $_CLIENT_.puts "--- Error: sf_to_wiz: #{$!}"
      $_CLIENT_.puts '$_SERVERSTRING_: ' + $_SERVERSTRING_.to_s
   end
end

def strip_xml(line)
   return line if line == "\r\n"

   if $strip_xml_multiline
      $strip_xml_multiline = $strip_xml_multiline + line
      line = $strip_xml_multiline
   end
   if (line.scan(/<pushStream[^>]*\/>/).length > line.scan(/<popStream[^>]*\/>/).length)
      $strip_xml_multiline = line
      return nil
   end
   $strip_xml_multiline = nil

   line = line.gsub(/<pushStream id=["'](?:spellfront|inv|bounty|society|speech|talk)["'][^>]*\/>.*?<popStream[^>]*>/m, '')
   line = line.gsub(/<stream id="Spells">.*?<\/stream>/m, '')
   line = line.gsub(/<(compDef|inv|component|right|left|spell|prompt)[^>]*>.*?<\/\1>/m, '')
   line = line.gsub(/<[^>]+>/, '')
   line = line.gsub('&gt;', '>')
   line = line.gsub('&lt;', '<')

   return nil if line.gsub("\n", '').gsub("\r", '').gsub(' ', '').length < 1
   return line
end

def monsterbold_start
   if $frontend =~ /^(?:wizard|avalon)$/
      "\034GSL\r\n"
   elsif $frontend == 'stormfront'
      '<pushBold/>'
   elsif $frontend == 'profanity'
      '<b>'
   else
      ''
   end
end

def monsterbold_end
   if $frontend =~ /^(?:wizard|avalon)$/
      "\034GSM\r\n"
   elsif $frontend == 'stormfront'
      '<popBold/>'
   elsif $frontend == 'profanity'
      '</b>'
   else
      ''
   end
end

def do_client(client_string)
   client_string.strip!
#   Buffer.update(client_string, Buffer::UPSTREAM)
   client_string = UpstreamHook.run(client_string)
#   Buffer.update(client_string, Buffer::UPSTREAM_MOD)
   return nil if client_string.nil?
   if client_string =~ /^(?:<c>)?#{$lich_char}(.+)$/
      cmd = $1
      if cmd =~ /^k$|^kill$|^stop$/
         if Script.running.empty?
            respond '--- Lich: no scripts to kill'
         else
            Script.running.last.kill
         end
      elsif cmd =~ /^p$|^pause$/
         if s = Script.running.reverse.find { |s| not s.paused? }
            s.pause
         else
            respond '--- Lich: no scripts to pause'
         end
         s = nil
      elsif cmd =~ /^u$|^unpause$/
         if s = Script.running.reverse.find { |s| s.paused? }
            s.unpause
         else
            respond '--- Lich: no scripts to unpause'
         end
         s = nil
      elsif cmd =~ /^ka$|^kill\s?all$|^stop\s?all$/
         did_something = false
         Script.running.find_all { |s| not s.no_kill_all }.each { |s| s.kill; did_something = true }
         respond('--- Lich: no scripts to kill') unless did_something
      elsif cmd =~ /^pa$|^pause\s?all$/
         did_something = false
         Script.running.find_all { |s| not s.paused? and not s.no_pause_all }.each { |s| s.pause; did_something  = true }
         respond('--- Lich: no scripts to pause') unless did_something
      elsif cmd =~ /^ua$|^unpause\s?all$/
         did_something = false
         Script.running.find_all { |s| s.paused? and not s.no_pause_all }.each { |s| s.unpause; did_something = true }
         respond('--- Lich: no scripts to unpause') unless did_something
      elsif cmd =~ /^(k|kill|stop|p|pause|u|unpause)\s(.+)/
         action = $1
         target = $2
         script = Script.running.find { |s| s.name == target } || Script.hidden.find { |s| s.name == target } || Script.running.find { |s| s.name =~ /^#{target}/i } || Script.hidden.find { |s| s.name =~ /^#{target}/i }
         if script.nil?
            respond "--- Lich: #{target} does not appear to be running! Use ';list' or ';listall' to see what's active."
         elsif action =~ /^(?:k|kill|stop)$/
            script.kill
         elsif action =~/^(?:p|pause)$/
            script.pause
         elsif action =~/^(?:u|unpause)$/
            script.unpause
         end
         action = target = script = nil
      elsif cmd =~ /^list\s?(?:all)?$|^l(?:a)?$/i
         if cmd =~ /a(?:ll)?/i
            list = Script.running + Script.hidden
         else
            list = Script.running
         end
         if list.empty?
            respond '--- Lich: no active scripts'
         else
            respond "--- Lich: #{list.collect { |s| s.paused? ? "#{s.name} (paused)" : s.name }.join(", ")}"
         end
         list = nil
      elsif cmd =~ /^force\s+[^\s]+/
         if cmd =~ /^force\s+([^\s]+)\s+(.+)$/
            Script.start($1, $2, :force => true)
         elsif cmd =~ /^force\s+([^\s]+)/
            Script.start($1, :force => true)
         end
      elsif cmd =~ /^send |^s /
         if cmd.split[1] == "to"
            script = (Script.running + Script.hidden).find { |scr| scr.name == cmd.split[2].chomp.strip } || script = (Script.running + Script.hidden).find { |scr| scr.name =~ /^#{cmd.split[2].chomp.strip}/i }
            if script
               msg = cmd.split[3..-1].join(' ').chomp
               if script.want_downstream
                  script.downstream_buffer.push(msg)
               else
                  script.unique_buffer.push(msg)
               end
               respond "--- sent to '#{script.name}': #{msg}"
            else
               respond "--- Lich: '#{cmd.split[2].chomp.strip}' does not match any active script!"
            end
            script = nil
         else
            if Script.running.empty? and Script.hidden.empty?
               respond('--- Lich: no active scripts to send to.')
            else
               msg = cmd.split[1..-1].join(' ').chomp
               respond("--- sent: #{msg}")
               Script.new_downstream(msg)
            end
         end
      elsif cmd =~ /^(?:exec|e)(q)? (.+)$/
         cmd_data = $2
         if $1.nil?
            ExecScript.start(cmd_data, flags={ :quiet => false, :trusted => true })
         else
            ExecScript.start(cmd_data, flags={ :quiet => true, :trusted => true })
         end
      elsif cmd =~ /^trust\s+(.*)/i
         script_name = $1
         if RUBY_VERSION =~ /^2\.[012]\./
            if File.exists?("#{SCRIPT_DIR}/#{script_name}.lic")
               if Script.trust(script_name)
                  respond "--- Lich: '#{script_name}' is now a trusted script."
               else
                  respond "--- Lich: '#{script_name}' is already trusted."
               end
            else
               respond "--- Lich: could not find script: #{script_name}"
            end
         else
            respond "--- Lich: this feature isn't available in this version of Ruby "
         end
      elsif cmd =~ /^(?:dis|un)trust\s+(.*)/i
         script_name = $1
         if RUBY_VERSION =~ /^2\.[012]\./
            if Script.distrust(script_name)
               respond "--- Lich: '#{script_name}' is no longer a trusted script."
            else
               respond "--- Lich: '#{script_name}' was not found in the trusted script list."
            end
         else
            respond "--- Lich: this feature isn't available in this version of Ruby "
         end
      elsif cmd =~ /^list\s?(?:un)?trust(?:ed)?$|^lt$/i
         if RUBY_VERSION =~ /^2\.[012]\./
            list = Script.list_trusted
            if list.empty?
               respond "--- Lich: no scripts are trusted"
            else
               respond "--- Lich: trusted scripts: #{list.join(', ')}"
            end
            list = nil
         else
            respond "--- Lich: this feature isn't available in this version of Ruby "
         end
      elsif cmd =~ /^help$/i
         respond
         respond "Lich v#{LICH_VERSION}"
         respond
         respond 'built-in commands:'
         respond "   #{$clean_lich_char}<script name>             start a script"
         respond "   #{$clean_lich_char}force <script name>       start a script even if it's already running"
         respond "   #{$clean_lich_char}pause <script name>       pause a script"
         respond "   #{$clean_lich_char}p <script name>           ''"
         respond "   #{$clean_lich_char}unpause <script name>     unpause a script"
         respond "   #{$clean_lich_char}u <script name>           ''"
         respond "   #{$clean_lich_char}kill <script name>        kill a script"
         respond "   #{$clean_lich_char}k <script name>           ''"
         respond "   #{$clean_lich_char}pause                     pause the most recently started script that isn't aready paused"
         respond "   #{$clean_lich_char}p                         ''"
         respond "   #{$clean_lich_char}unpause                   unpause the most recently started script that is paused"
         respond "   #{$clean_lich_char}u                         ''"
         respond "   #{$clean_lich_char}kill                      kill the most recently started script"
         respond "   #{$clean_lich_char}k                         ''"
         respond "   #{$clean_lich_char}list                      show running scripts (except hidden ones)"
         respond "   #{$clean_lich_char}l                         ''"
         respond "   #{$clean_lich_char}pause all                 pause all scripts"
         respond "   #{$clean_lich_char}pa                        ''"
         respond "   #{$clean_lich_char}unpause all               unpause all scripts"
         respond "   #{$clean_lich_char}ua                        ''"
         respond "   #{$clean_lich_char}kill all                  kill all scripts"
         respond "   #{$clean_lich_char}ka                        ''"
         respond "   #{$clean_lich_char}list all                  show all running scripts"
         respond "   #{$clean_lich_char}la                        ''"
         respond
         respond "   #{$clean_lich_char}exec <code>               executes the code as if it was in a script"
         respond "   #{$clean_lich_char}e <code>                  ''"
         respond "   #{$clean_lich_char}execq <code>              same as #{$clean_lich_char}exec but without the script active and exited messages"
         respond "   #{$clean_lich_char}eq <code>                 ''"
         respond
         if (RUBY_VERSION =~ /^2\.[012]\./)
            respond "   #{$clean_lich_char}trust <script name>       let the script do whatever it wants"
            respond "   #{$clean_lich_char}distrust <script name>    restrict the script from doing things that might harm your computer"
            respond "   #{$clean_lich_char}list trusted              show what scripts are trusted"
            respond "   #{$clean_lich_char}lt                        ''"
            respond
         end
         respond "   #{$clean_lich_char}send <line>               send a line to all scripts as if it came from the game"
         respond "   #{$clean_lich_char}send to <script> <line>   send a line to a specific script"
         respond
         respond 'If you liked this help message, you might also enjoy:'
         respond "   #{$clean_lich_char}lnet help"
         respond "   #{$clean_lich_char}magic help     (infomon must be running)"
         respond "   #{$clean_lich_char}go2 help"
         respond "   #{$clean_lich_char}repository help"
         respond "   #{$clean_lich_char}alias help"
         respond "   #{$clean_lich_char}vars help"
         respond "   #{$clean_lich_char}autostart help"
         respond
      else
         if cmd =~ /^([^\s]+)\s+(.+)/
            Script.start($1, $2)
         else
            Script.start(cmd)
         end
      end
   else
      if $offline_mode
         respond "--- Lich: offline mode: ignoring #{client_string}"
      else
         client_string = "#{$cmd_prefix}bbs" if ($frontend =~ /^(?:wizard|avalon)$/) and (client_string == "#{$cmd_prefix}\egbbk\n") # launch forum
         Game._puts client_string
      end
      $_CLIENTBUFFER_.push client_string
   end
   Script.new_upstream(client_string)
end

def report_errors(&block)
   begin
      block.call
   rescue
      respond "--- Lich: error: #{$!}\n\t#{$!.backtrace[0..1].join("\n\t")}"
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
   rescue SyntaxError
      respond "--- Lich: error: #{$!}\n\t#{$!.backtrace[0..1].join("\n\t")}"
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
   rescue SystemExit
      nil
   rescue SecurityError
      respond "--- Lich: error: #{$!}\n\t#{$!.backtrace[0..1].join("\n\t")}"
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
   rescue ThreadError
      respond "--- Lich: error: #{$!}\n\t#{$!.backtrace[0..1].join("\n\t")}"
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
   rescue SystemStackError
      respond "--- Lich: error: #{$!}\n\t#{$!.backtrace[0..1].join("\n\t")}"
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
   rescue Exception
      respond "--- Lich: error: #{$!}\n\t#{$!.backtrace[0..1].join("\n\t")}"
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
   rescue ScriptError
      respond "--- Lich: error: #{$!}\n\t#{$!.backtrace[0..1].join("\n\t")}"
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
   rescue LoadError
      respond "--- Lich: error: #{$!}\n\t#{$!.backtrace[0..1].join("\n\t")}"
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
   rescue NoMemoryError
      respond "--- Lich: error: #{$!}\n\t#{$!.backtrace[0..1].join("\n\t")}"
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
   rescue
      respond "--- Lich: error: #{$!}\n\t#{$!.backtrace[0..1].join("\n\t")}"
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
   end
end

include Games::Gemstone

JUMP = Exception.exception('JUMP')
JUMP_ERROR = Exception.exception('JUMP_ERROR')

DIRMAP = {
   'out' => 'K',
   'ne' => 'B',
   'se' => 'D',
   'sw' => 'F',
   'nw' => 'H',
   'up' => 'I',
   'down' => 'J',
   'n' => 'A',
   'e' => 'C',
   's' => 'E',
   'w' => 'G',
}
SHORTDIR = {
   'out' => 'out',
   'northeast' => 'ne',
   'southeast' => 'se',
   'southwest' => 'sw',
   'northwest' => 'nw',
   'up' => 'up',
   'down' => 'down',
   'north' => 'n',
   'east' => 'e',
   'south' => 's',
   'west' => 'w',
}
LONGDIR = {
   'out' => 'out',
   'ne' => 'northeast',
   'se' => 'southeast',
   'sw' => 'southwest',
   'nw' => 'northwest',
   'up' => 'up',
   'down' => 'down',
   'n' => 'north',
   'e' => 'east',
   's' => 'south',
   'w' => 'west',
}
MINDMAP = {
   'clear as a bell' => 'A',
   'fresh and clear' => 'B',
   'clear' => 'C',
   'muddled' => 'D',
   'becoming numbed' => 'E',
   'numbed' => 'F',
   'must rest' => 'G',
   'saturated' => 'H',
}
ICONMAP = {
   'IconKNEELING' => 'GH',
   'IconPRONE' => 'G',
   'IconSITTING' => 'H',
   'IconSTANDING' => 'T',
   'IconSTUNNED' => 'I',
   'IconHIDDEN' => 'N',
   'IconINVISIBLE' => 'D',
   'IconDEAD' => 'B',
   'IconWEBBED' => 'C',
   'IconJOINED' => 'P',
   'IconBLEEDING' => 'O',
}

XMLData = XMLParser.new

reconnect_if_wanted = proc {
   if ARGV.include?('--reconnect') and ARGV.include?('--login') and not $_CLIENTBUFFER_.any? { |cmd| cmd =~ /^(?:\[.*?\])?(?:<c>)?(?:quit|exit)/i }
      if reconnect_arg = ARGV.find { |arg| arg =~ /^\-\-reconnect\-delay=[0-9]+(?:\+[0-9]+)?$/ }
         reconnect_arg =~ /^\-\-reconnect\-delay=([0-9]+)(\+[0-9]+)?/
         reconnect_delay = $1.to_i
         reconnect_step = $2.to_i
      else
         reconnect_delay = 60
         reconnect_step = 0
      end
      Lich.log "info: waiting #{reconnect_delay} seconds to reconnect..."
      sleep reconnect_delay
      Lich.log 'info: reconnecting...'
      if (RUBY_PLATFORM =~ /mingw|win/i) and (RUBY_PLATFORM !~ /darwin/i)
         if $frontend == 'stormfront'
            system 'taskkill /FI "WINDOWTITLE eq [GSIV: ' + Char.name + '*"' # fixme: window title changing to Gemstone IV: Char.name # name optional
         end
         args = [ 'start rubyw.exe' ]
      else
         args = [ 'ruby' ]
      end
      args.push $PROGRAM_NAME.slice(/[^\\\/]+$/)
      args.concat ARGV
      args.push '--reconnected' unless args.include?('--reconnected')
      if reconnect_step > 0
         args.delete(reconnect_arg)
         args.concat ["--reconnect-delay=#{reconnect_delay+reconnect_step}+#{reconnect_step}"]
      end
      Lich.log "exec args.join(' '): exec #{args.join(' ')}"
      exec args.join(' ')
   end
}

#
# Start deprecated stuff
#

$version = LICH_VERSION
$room_count = 0
$psinet = false
$stormfront = true

module Lich
   @@last_warn_deprecated = 0
   def Lich.method_missing(arg1, arg2='')
      if (Time.now.to_i - @@last_warn_deprecated) > 300
         respond "--- warning: Lich.* variables will stop working in a future version of Lich.  Use Vars.* (offending script: #{Script.current.name || 'unknown'})"
         @@last_warn_deprecated = Time.now.to_i
      end
      Vars.method_missing(arg1, arg2)
   end
end

class Script
   def Script.self
      Script.current
   end
   def Script.running
      list = Array.new
      for script in @@running
         list.push(script) unless script.hidden
      end
      return list
   end
   def Script.index
      Script.running
   end
   def Script.hidden
      list = Array.new
      for script in @@running
         list.push(script) if script.hidden
      end
      return list
   end
   def Script.namescript_incoming(line)
      Script.new_downstream(line)
   end
end

class Spellsong
   def Spellsong.cost
      Spellsong.renew_cost
   end
   def Spellsong.tonisdodgebonus
      thresholds = [1,2,3,5,8,10,14,17,21,26,31,36,42,49,55,63,70,78,87,96]
      bonus = 20
      thresholds.each { |val| if Skills.elair >= val then bonus += 1 end }
      bonus
   end
   def Spellsong.mirrorsdodgebonus
      20 + ((Spells.bard - 19) / 2).round
   end
   def Spellsong.mirrorscost
      [19 + ((Spells.bard - 19) / 5).truncate, 8 + ((Spells.bard - 19) / 10).truncate]
   end
   def Spellsong.sonicbonus
      (Spells.bard / 2).round
   end
   def Spellsong.sonicarmorbonus
      Spellsong.sonicbonus + 15
   end
   def Spellsong.sonicbladebonus
      Spellsong.sonicbonus + 10
   end
   def Spellsong.sonicweaponbonus
      Spellsong.sonicbladebonus
   end
   def Spellsong.sonicshieldbonus
      Spellsong.sonicbonus + 10
   end
   def Spellsong.valorbonus
      10 + (([Spells.bard, Stats.level].min - 10) / 2).round
   end
   def Spellsong.valorcost
      [10 + (Spellsong.valorbonus / 2), 3 + (Spellsong.valorbonus / 5)]
   end
   def Spellsong.luckcost
      [6 + ((Spells.bard - 6) / 4),(6 + ((Spells.bard - 6) / 4) / 2).round]
   end
   def Spellsong.manacost
      [18,15]
   end
   def Spellsong.fortcost
      [3,1]
   end
   def Spellsong.shieldcost
      [9,4]
   end
   def Spellsong.weaponcost
      [12,4]
   end
   def Spellsong.armorcost
      [14,5]
   end
   def Spellsong.swordcost
      [25,15]
   end
end

class Map
   def desc
      @description
   end
   def map_name
      @image
   end
   def map_x
      if @image_coords.nil?
         nil
      else
         ((image_coords[0] + image_coords[2])/2.0).round
      end
   end
   def map_y
      if @image_coords.nil?
         nil
      else
         ((image_coords[1] + image_coords[3])/2.0).round
      end
   end
   def map_roomsize
      if @image_coords.nil?
         nil
      else
         image_coords[2] - image_coords[0]
      end
   end
   def geo
      nil
   end
end

def start_script(script_name, cli_vars=[], flags=Hash.new)
   if flags == true
      flags = { :quiet => true }
   end
   Script.start(script_name, cli_vars.join(' '), flags)
end

def start_scripts(*script_names)
   script_names.flatten.each { |script_name|
      start_script(script_name)
      sleep 0.02
   }
end

def force_start_script(script_name,cli_vars=[], flags={})
   flags = Hash.new unless flags.class == Hash
   flags[:force] = true
   start_script(script_name,cli_vars,flags)
end

def survivepoison?
   echo 'survivepoison? called, but there is no XML for poison rate'
   return true
end

def survivedisease?
   echo 'survivepoison? called, but there is no XML for disease rate'
   return true
end

def before_dying(&code)
   Script.at_exit(&code)
end

def undo_before_dying
   Script.clear_exit_procs
end

def abort!
   Script.exit!
end

def fetchloot(userbagchoice=UserVars.lootsack)
   if GameObj.loot.empty?
      return false
   end
   if UserVars.excludeloot.empty?
      regexpstr = nil
   else
      regexpstr = UserVars.excludeloot.split(', ').join('|')
   end
   if checkright and checkleft
      stowed = GameObj.right_hand.noun
      fput "put my #{stowed} in my #{UserVars.lootsack}"
   else
      stowed = nil
   end
   GameObj.loot.each { |loot|
      unless not regexpstr.nil? and loot.name =~ /#{regexpstr}/
         fput "get #{loot.noun}"
         fput("put my #{loot.noun} in my #{userbagchoice}") if (checkright || checkleft)
      end
   }
   if stowed
      fput "take my #{stowed} from my #{UserVars.lootsack}"
   end
end

def take(*items)
   items.flatten!
   if (righthand? && lefthand?)
      weap = checkright
      fput "put my #{checkright} in my #{UserVars.lootsack}"
      unsh = true
   else
      unsh = false
   end
   items.each { |trinket|
      fput "take #{trinket}"
      fput("put my #{trinket} in my #{UserVars.lootsack}") if (righthand? || lefthand?)
   }
   if unsh then fput("take my #{weap} from my #{UserVars.lootsack}") end
end

def stop_script(*target_names)
   numkilled = 0
   target_names.each { |target_name| 
      condemned = Script.list.find { |s_sock| s_sock.name =~ /^#{target_name}/i }
      if condemned.nil?
         respond("--- Lich: '#{Script.current}' tried to stop '#{target_name}', but it isn't running!")
      else
         if condemned.name =~ /^#{Script.current.name}$/i
            exit
         end
         condemned.kill
         respond("--- Lich: '#{condemned}' has been stopped by #{Script.current}.")
         numkilled += 1
      end
   }
   if numkilled == 0
      return false
   else
      return numkilled
   end
end

def running?(*snames)
   snames.each { |checking| (return false) unless (Script.running.find { |lscr| lscr.name =~ /^#{checking}$/i } || Script.running.find { |lscr| lscr.name =~ /^#{checking}/i } || Script.hidden.find { |lscr| lscr.name =~ /^#{checking}$/i } || Script.hidden.find { |lscr| lscr.name =~ /^#{checking}/i }) }
   true
end

def start_exec_script(cmd_data, options=Hash.new)
   ExecScript.start(cmd_data, options)
end

class StringProc
   def StringProc._load(string)
      StringProc.new(string)
   end
end
class String
   def to_a # for compatibility with Ruby 1.8
      [self]
   end
   def silent
      false
   end
   def split_as_list
      string = self
      string.sub!(/^You (?:also see|notice) |^In the .+ you see /, ',')
      string.sub('.','').sub(/ and (an?|some|the)/, ', \1').split(',').reject { |str| str.strip.empty? }.collect { |str| str.lstrip }
   end
end
#
# End deprecated stuff
#

undef :abort
alias :mana :checkmana
alias :mana? :checkmana
alias :max_mana :maxmana
alias :health :checkhealth
alias :health? :checkhealth
alias :spirit :checkspirit
alias :spirit? :checkspirit
alias :stamina :checkstamina
alias :stamina? :checkstamina
alias :stunned? :checkstunned
alias :bleeding? :checkbleeding
alias :reallybleeding? :checkreallybleeding
alias :dead? :checkdead
alias :hiding? :checkhidden
alias :hidden? :checkhidden
alias :hidden :checkhidden
alias :checkhiding :checkhidden
alias :invisible? :checkinvisible
alias :standing? :checkstanding
alias :kneeling? :checkkneeling
alias :sitting? :checksitting
alias :stance? :checkstance
alias :stance :checkstance
alias :joined? :checkgrouped
alias :checkjoined :checkgrouped
alias :group? :checkgrouped
alias :myname? :checkname
alias :active? :checkspell
alias :righthand? :checkright
alias :lefthand? :checkleft
alias :righthand :checkright
alias :lefthand :checkleft
alias :mind? :checkmind
alias :checkactive :checkspell
alias :forceput :fput
alias :send_script :send_scripts
alias :stop_scripts :stop_script
alias :kill_scripts :stop_script
alias :kill_script :stop_script
alias :fried? :checkfried
alias :saturated? :checksaturated
alias :webbed? :checkwebbed
alias :pause_scripts :pause_script
alias :roomdescription? :checkroomdescrip
alias :prepped? :checkprep
alias :checkprepared :checkprep
alias :unpause_scripts :unpause_script
alias :priority? :setpriority
alias :checkoutside :outside?
alias :toggle_status :status_tags
alias :encumbrance? :checkencumbrance
alias :bounty? :checkbounty



#
# Program start
#

ARGV.delete_if { |arg| arg =~ /launcher\.exe/i } # added by Simutronics Game Entry

argv_options = Hash.new
bad_args = Array.new

for arg in ARGV
   if (arg == '-h') or (arg == '--help')
      puts "
   -h, --help               Display this message and exit
   -v, --version            Display version number and credits and exit

   --home=<directory>      Set home directory for Lich (default: location of this file)
   --scripts=<directory>   Set directory for script files (default: home/scripts)
   --data=<directory>      Set directory for data files (default: home/data)
   --temp=<directory>      Set directory for temp files (default: home/temp)
   --logs=<directory>      Set directory for log files (default: home/logs)
   --maps=<directory>      Set directory for map images (default: home/maps)
   --backup=<directory>    Set directory for backups (default: home/backup)

   --start-scripts=<script1,script2,etc>   Start the specified scripts after login

"
      exit
   elsif (arg == '-v') or (arg == '--version')
      puts "The Lich, version #{LICH_VERSION}"
      puts ' (an implementation of the Ruby interpreter by Yukihiro Matsumoto designed to be a \'script engine\' for text-based MUDs)'
      puts ''
      puts '- The Lich program and all material collectively referred to as "The Lich project" is copyright (C) 2005-2006 Murray Miron.'
      puts '- The Gemstone IV and DragonRealms games are copyright (C) Simutronics Corporation.'
      puts '- The Wizard front-end and the StormFront front-end are also copyrighted by the Simutronics Corporation.'
      puts '- Ruby is (C) Yukihiro \'Matz\' Matsumoto.'
      puts ''
      puts 'Thanks to all those who\'ve reported bugs and helped me track down problems on both Windows and Linux.'
      exit
   elsif arg == '--link-to-sge'
      result = Lich.link_to_sge
      if $stdout.isatty
         if result
            $stdout.puts "Successfully linked to SGE."
         else
            $stdout.puts "Failed to link to SGE."
         end
      end
      exit
   elsif arg == '--unlink-from-sge'
      result = Lich.unlink_from_sge
      if $stdout.isatty
         if result
            $stdout.puts "Successfully unlinked from SGE."
         else
            $stdout.puts "Failed to unlink from SGE."
         end
      end
      exit
   elsif arg == '--link-to-sal'
      result = Lich.link_to_sal
      if $stdout.isatty
         if result
            $stdout.puts "Successfully linked to SAL files."
         else
            $stdout.puts "Failed to link to SAL files."
         end
      end
      exit
   elsif arg == '--unlink-from-sal'
      result = Lich.unlink_from_sal
      if $stdout.isatty
         if result
            $stdout.puts "Successfully unlinked from SAL files."
         else
            $stdout.puts "Failed to unlink from SAL files."
         end
      end
      exit
   elsif arg == '--install' # deprecated
      if Lich.link_to_sge and Lich.link_to_sal
         $stdout.puts 'Install was successful.'
         Lich.log 'Install was successful.'
      else
         $stdout.puts 'Install failed.'
         Lich.log 'Install failed.'
      end
      exit
   elsif arg == '--uninstall' # deprecated
      if Lich.unlink_from_sge and Lich.unlink_from_sal
         $stdout.puts 'Uninstall was successful.'
         Lich.log 'Uninstall was successful.'
      else
         $stdout.puts 'Uninstall failed.'
         Lich.log 'Uninstall failed.'
      end
      exit
   elsif arg =~ /^--(?:home)=(.+)$/i
      LICH_DIR = $1.sub(/[\\\/]$/, '')
   elsif arg =~ /^--temp=(.+)$/i
      TEMP_DIR = $1.sub(/[\\\/]$/, '')
   elsif arg =~ /^--scripts=(.+)$/i
      SCRIPT_DIR = $1.sub(/[\\\/]$/, '')
   elsif arg =~ /^--maps=(.+)$/i
      MAP_DIR = $1.sub(/[\\\/]$/, '')
   elsif arg =~ /^--logs=(.+)$/i
      LOG_DIR = $1.sub(/[\\\/]$/, '')
   elsif arg =~ /^--backup=(.+)$/i
      BACKUP_DIR = $1.sub(/[\\\/]$/, '')
   elsif arg =~ /^--data=(.+)$/i
      DATA_DIR = $1.sub(/[\\\/]$/, '')
   elsif arg =~ /^--start-scripts=(.+)$/i
      argv_options[:start_scripts] = $1
   elsif arg =~ /^--reconnect$/i
      argv_options[:reconnect] = true
   elsif arg =~ /^--reconnect-delay=(.+)$/i
      argv_options[:reconnect_delay] = $1
   elsif arg =~ /^--host=(.+):(.+)$/
      argv_options[:host] = { :domain => $1, :port => $2.to_i }
   elsif arg =~ /^--hosts-file=(.+)$/i
      argv_options[:hosts_file] = $1
   elsif arg =~ /^--gui$/i
      argv_options[:gui] = true
   elsif arg =~ /^--game=(.+)$/i
      argv_options[:game] = $1
   elsif arg =~ /^--account=(.+)$/i
      argv_options[:account] = $1
   elsif arg =~ /^--password=(.+)$/i
      argv_options[:password] = $1
   elsif arg =~ /^--character=(.+)$/i
      argv_options[:character] = $1
   elsif arg =~ /^--frontend=(.+)$/i
      argv_options[:frontend] = $1
   elsif arg =~ /^--frontend-command=(.+)$/i
      argv_options[:frontend_command] = $1
   elsif arg =~ /^--save$/i
      argv_options[:save] = true
   elsif arg =~ /^--wine(?:\-prefix)?=.+$/i
      nil # already used when defining the Wine module
   elsif arg =~ /\.sal$|Gse\.~xt$/i
      argv_options[:sal] = arg
      unless File.exists?(argv_options[:sal])
         if ARGV.join(' ') =~ /([A-Z]:\\.+?\.(?:sal|~xt))/i
            argv_options[:sal] = $1
         end
      end
      unless File.exists?(argv_options[:sal])
         if defined?(Wine)
            argv_options[:sal] = "#{Wine::PREFIX}/drive_c/#{argv_options[:sal][3..-1].split('\\').join('/')}"
         end
      end
      bad_args.clear
   else
      bad_args.push(arg)
   end
end

LICH_DIR   ||= File.dirname(File.expand_path($PROGRAM_NAME))
TEMP_DIR   ||= "#{LICH_DIR}/temp"
DATA_DIR   ||= "#{LICH_DIR}/data"
SCRIPT_DIR ||= "#{LICH_DIR}/scripts"
MAP_DIR    ||= "#{LICH_DIR}/maps"
LOG_DIR    ||= "#{LICH_DIR}/logs"
BACKUP_DIR ||= "#{LICH_DIR}/backup"

unless File.exists?(LICH_DIR)
   begin
      Dir.mkdir(LICH_DIR)
   rescue
      message = "An error occured while attempting to create directory #{LICH_DIR}\n\n"
      if not File.exists?(LICH_DIR.sub(/[\\\/]$/, '').slice(/^.+[\\\/]/).chop)
         message.concat "This was likely because the parent directory (#{LICH_DIR.sub(/[\\\/]$/, '').slice(/^.+[\\\/]/).chop}) doesn't exist."
      elsif defined?(Win32) and (Win32.GetVersionEx[:dwMajorVersion] >= 6) and (dir !~ /^[A-z]\:\\(Users|Documents and Settings)/)
         message.concat "This was likely because Lich doesn't have permission to create files and folders here.  It is recommended to put Lich in your Documents folder."
      else
         message.concat $!
      end
      Lich.msgbox(:message => message, :icon => :error)
      exit
   end
end

Dir.chdir(LICH_DIR)

unless File.exists?(TEMP_DIR)
   begin
      Dir.mkdir(TEMP_DIR)
   rescue
      message = "An error occured while attempting to create directory #{TEMP_DIR}\n\n"
      if not File.exists?(TEMP_DIR.sub(/[\\\/]$/, '').slice(/^.+[\\\/]/).chop)
         message.concat "This was likely because the parent directory (#{TEMP_DIR.sub(/[\\\/]$/, '').slice(/^.+[\\\/]/).chop}) doesn't exist."
      elsif defined?(Win32) and (Win32.GetVersionEx[:dwMajorVersion] >= 6) and (dir !~ /^[A-z]\:\\(Users|Documents and Settings)/)
         message.concat "This was likely because Lich doesn't have permission to create files and folders here.  It is recommended to put Lich in your Documents folder."
      else
         message.concat $!
      end
      Lich.msgbox(:message => message, :icon => :error)
      exit
   end
end

begin
   debug_filename = "#{TEMP_DIR}/debug-#{Time.now.strftime("%Y-%m-%d-%H-%M-%S")}.log"
   $stderr = File.open(debug_filename, 'w')
rescue
   message = "An error occured while attempting to create file #{debug_filename}\n\n"
   if defined?(Win32) and (TEMP_DIR !~ /^[A-z]\:\\(Users|Documents and Settings)/) and not Win32.isXP?
      message.concat "This was likely because Lich doesn't have permission to create files and folders here.  It is recommended to put Lich in your Documents folder."
   else
      message.concat $!
   end
   Lich.msgbox(:message => message, :icon => :error)
   exit
end

$stderr.sync = true
Lich.log "info: Lich #{LICH_VERSION}"
Lich.log "info: Ruby #{RUBY_VERSION}"
Lich.log "info: #{RUBY_PLATFORM}"
Lich.log early_gtk_error if early_gtk_error
early_gtk_error = nil

unless File.exists?(DATA_DIR)
   begin
      Dir.mkdir(DATA_DIR)   
   rescue
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
      Lich.msgbox(:message => "An error occured while attempting to create directory #{DATA_DIR}\n\n#{$!}", :icon => :error)
      exit
   end
end
unless File.exists?(SCRIPT_DIR)
   begin
      Dir.mkdir(SCRIPT_DIR)   
   rescue
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
      Lich.msgbox(:message => "An error occured while attempting to create directory #{SCRIPT_DIR}\n\n#{$!}", :icon => :error)
      exit
   end
end
unless File.exists?(MAP_DIR)
   begin
      Dir.mkdir(MAP_DIR)   
   rescue
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
      Lich.msgbox(:message => "An error occured while attempting to create directory #{MAP_DIR}\n\n#{$!}", :icon => :error)
      exit
   end
end
unless File.exists?(LOG_DIR)
   begin
      Dir.mkdir(LOG_DIR)   
   rescue
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
      Lich.msgbox(:message => "An error occured while attempting to create directory #{LOG_DIR}\n\n#{$!}", :icon => :error)
      exit
   end
end
unless File.exists?(BACKUP_DIR)
   begin
      Dir.mkdir(BACKUP_DIR)   
   rescue
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
      Lich.msgbox(:message => "An error occured while attempting to create directory #{BACKUP_DIR}\n\n#{$!}", :icon => :error)
      exit
   end
end

Lich.init_db

# deprecated
$lich_dir = "#{LICH_DIR}/"
$temp_dir = "#{TEMP_DIR}/"
$script_dir = "#{SCRIPT_DIR}/"
$data_dir = "#{DATA_DIR}/"

#
# only keep the last 20 debug files
#
Dir.entries(TEMP_DIR).find_all { |fn| fn =~ /^debug-\d+-\d+-\d+-\d+-\d+-\d+\.log$/ }.sort.reverse[20..-1].each { |oldfile|
   begin
      File.delete("#{TEMP_DIR}/#{oldfile}")
   rescue
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
   end
}







if (RUBY_VERSION =~ /^2\.[012]\./)
   begin
      did_trusted_defaults = Lich.db.get_first_value("SELECT value FROM lich_settings WHERE name='did_trusted_defaults';")
   rescue SQLite3::BusyException
      sleep 0.1
      retry
   end
   if did_trusted_defaults.nil?
      Script.trust('repository')
      Script.trust('lnet')
      Script.trust('narost')
      begin
         Lich.db.execute("INSERT INTO lich_settings(name,value) VALUES('did_trusted_defaults', 'yes');")
      rescue SQLite3::BusyException
         sleep 0.1
         retry
      end
   end
end

if ARGV.any? { |arg| (arg == '-h') or (arg == '--help') }
   puts 'Usage:  lich [OPTION]'
   puts ''
   puts 'Options are:'
   puts '  -h, --help          Display this list.'
   puts '  -V, --version       Display the program version number and credits.'
   puts ''
   puts '  -d, --directory     Set the main Lich program directory.'
   puts '      --script-dir    Set the directoy where Lich looks for scripts.'
   puts '      --data-dir      Set the directory where Lich will store script data.'
   puts '      --temp-dir      Set the directory where Lich will store temporary files.'
   puts ''
   puts '  -w, --wizard        Run in Wizard mode (default)'
   puts '  -s, --stormfront    Run in StormFront mode.'
   puts '      --avalon        Run in Avalon mode.'
   puts ''
   puts '      --gemstone      Connect to the Gemstone IV Prime server (default).'
   puts '      --dragonrealms  Connect to the DragonRealms server.'
   puts '      --platinum      Connect to the Gemstone IV/DragonRealms Platinum server.'
   puts '  -g, --game          Set the IP address and port of the game.  See example below.'
   puts ''
   puts '      --install       Edits the Windows/WINE registry so that Lich is started when logging in using the website or SGE.'
   puts '      --uninstall     Removes Lich from the registry.'
   puts ''
   puts 'The majority of Lich\'s built-in functionality was designed and implemented with Simutronics MUDs in mind (primarily Gemstone IV): as such, many options/features provided by Lich may not be applicable when it is used with a non-Simutronics MUD.  In nearly every aspect of the program, users who are not playing a Simutronics game should be aware that if the description of a feature/option does not sound applicable and/or compatible with the current game, it should be assumed that the feature/option is not.  This particularly applies to in-script methods (commands) that depend heavily on the data received from the game conforming to specific patterns (for instance, it\'s extremely unlikely Lich will know how much "health" your character has left in a non-Simutronics game, and so the "health" script command will most likely return a value of 0).'
   puts ''
   puts 'The level of increase in efficiency when Lich is run in "bare-bones mode" (i.e. started with the --bare argument) depends on the data stream received from a given game, but on average results in a moderate improvement and it\'s recommended that Lich be run this way for any game that does not send "status information" in a format consistent with Simutronics\' GSL or XML encoding schemas.'
   puts ''
   puts ''
   puts 'Examples:'
   puts '  lich -w -d /usr/bin/lich/          (run Lich in Wizard mode using the dir \'/usr/bin/lich/\' as the program\'s home)'
   puts '  lich -g gs3.simutronics.net:4000   (run Lich using the IP address \'gs3.simutronics.net\' and the port number \'4000\')'
   puts '  lich --script-dir /mydir/scripts   (run Lich with its script directory set to \'/mydir/scripts\')'
   puts '  lich --bare -g skotos.net:5555     (run in bare-bones mode with the IP address and port of the game set to \'skotos.net:5555\')'
   puts ''
   exit
end



if arg = ARGV.find { |a| a == '--hosts-dir' }
   i = ARGV.index(arg)
   ARGV.delete_at(i)
   hosts_dir = ARGV[i]
   ARGV.delete_at(i)
   if hosts_dir and File.exists?(hosts_dir)
      hosts_dir = hosts_dir.tr('\\', '/')
      hosts_dir += '/' unless hosts_dir[-1..-1] == '/'
   else
      $stdout.puts "warning: given hosts directory does not exist: #{hosts_dir}"
      hosts_dir = nil
   end
else
   hosts_dir = nil
end

detachable_client_port = nil
if arg = ARGV.find { |a| a =~ /^\-\-detachable\-client=[0-9]+$/ }
   detachable_client_port = /^\-\-detachable\-client=([0-9]+)$/.match(arg).captures.first
end



#
# import Lich 4.4 settings to Lich 4.6
#
begin
   did_import = Lich.db.get_first_value("SELECT value FROM lich_settings WHERE name='imported_44_data';")
rescue SQLite3::BusyException
   sleep 0.1
   retry
end
if did_import.nil?
   begin
      Lich.db.execute('BEGIN')
   rescue SQLite3::BusyException
      sleep 0.1
      retry
   end
   begin
      Lich.db.execute("INSERT INTO lich_settings(name,value) VALUES('imported_44_data', 'yes');")
   rescue SQLite3::BusyException
      sleep 0.1
      retry
   end
   backup_dir = 'data44/'
   Dir.mkdir(backup_dir) unless File.exists?(backup_dir)
   Dir.entries(DATA_DIR).find_all { |fn| fn =~ /\.sav$/i }.each { |fn|
      next if fn == 'lich.sav'
      s = fn.match(/^(.+)\.sav$/i).captures.first
      data = File.open("#{DATA_DIR}/#{fn}", 'rb') { |f| f.read }
      blob = SQLite3::Blob.new(data)
      begin
         Lich.db.execute("INSERT OR REPLACE INTO script_auto_settings(script,scope,hash) VALUES(?,':',?);", s.encode('UTF-8'), blob)
      rescue SQLite3::BusyException
         sleep 0.1
         retry
      end
      File.rename("#{DATA_DIR}/#{fn}", "#{backup_dir}#{fn}")
      File.rename("#{DATA_DIR}/#{fn}~", "#{backup_dir}#{fn}~") if File.exists?("#{DATA_DIR}/#{fn}~")
   }
   Dir.entries(DATA_DIR).find_all { |fn| File.directory?("#{DATA_DIR}/#{fn}") and fn !~ /^\.\.?$/}.each { |game|
      Dir.mkdir("#{backup_dir}#{game}") unless File.exists?("#{backup_dir}#{game}")
      Dir.entries("#{DATA_DIR}/#{game}").find_all { |fn| fn =~ /\.sav$/i }.each { |fn|
         s = fn.match(/^(.+)\.sav$/i).captures.first
         data = File.open("#{DATA_DIR}/#{game}/#{fn}", 'rb') { |f| f.read }
         blob = SQLite3::Blob.new(data)
         begin
            Lich.db.execute('INSERT OR REPLACE INTO script_auto_settings(script,scope,hash) VALUES(?,?,?);', s.encode('UTF-8'), game.encode('UTF-8'), blob)
         rescue SQLite3::BusyException
            sleep 0.1
            retry
         end
         File.rename("#{DATA_DIR}/#{game}/#{fn}", "#{backup_dir}#{game}/#{fn}")
         File.rename("#{DATA_DIR}/#{game}/#{fn}~", "#{backup_dir}#{game}/#{fn}~") if File.exists?("#{DATA_DIR}/#{game}/#{fn}~")
      }
      Dir.entries("#{DATA_DIR}/#{game}").find_all { |fn| File.directory?("#{DATA_DIR}/#{game}/#{fn}") and fn !~ /^\.\.?$/ }.each { |char|
         Dir.mkdir("#{backup_dir}#{game}/#{char}") unless File.exists?("#{backup_dir}#{game}/#{char}")
         Dir.entries("#{DATA_DIR}/#{game}/#{char}").find_all { |fn| fn =~ /\.sav$/i }.each { |fn|
            s = fn.match(/^(.+)\.sav$/i).captures.first
            data = File.open("#{DATA_DIR}/#{game}/#{char}/#{fn}", 'rb') { |f| f.read }
            blob = SQLite3::Blob.new(data)
            begin
               Lich.db.execute('INSERT OR REPLACE INTO script_auto_settings(script,scope,hash) VALUES(?,?,?);', s.encode('UTF-8'), "#{game}:#{char}".encode('UTF-8'), blob)
            rescue SQLite3::BusyException
               sleep 0.1
               retry
            end
            File.rename("#{DATA_DIR}/#{game}/#{char}/#{fn}", "#{backup_dir}#{game}/#{char}/#{fn}")
            File.rename("#{DATA_DIR}/#{game}/#{char}/#{fn}~", "#{backup_dir}#{game}/#{char}/#{fn}~") if File.exists?("#{DATA_DIR}/#{game}/#{char}/#{fn}~")
         }
         if File.exists?("#{DATA_DIR}/#{game}/#{char}/uservars.dat")
            blob = SQLite3::Blob.new(File.open("#{DATA_DIR}/#{game}/#{char}/uservars.dat", 'rb') { |f| f.read })
            begin
               Lich.db.execute('INSERT OR REPLACE INTO uservars(scope,hash) VALUES(?,?);', "#{game}:#{char}".encode('UTF-8'), blob)
            rescue SQLite3::BusyException
               sleep 0.1
               retry
            end
            blob = nil
            File.rename("#{DATA_DIR}/#{game}/#{char}/uservars.dat", "#{backup_dir}#{game}/#{char}/uservars.dat")
         end
      }
   }
   begin
      Lich.db.execute('END')
   rescue SQLite3::BusyException
      sleep 0.1
      retry
   end
   backup_dir = nil
   characters = Array.new
   begin
      Lich.db.execute("SELECT DISTINCT(scope) FROM script_auto_settings;").each { |row| characters.push(row[0]) if row[0] =~ /^.+:.+$/ }
   rescue SQLite3::BusyException
      sleep 0.1
      retry
   end
   if File.exists?("#{DATA_DIR}/lich.sav")
      data = File.open("#{DATA_DIR}/lich.sav", 'rb') { |f| Marshal.load(f.read) }
      favs = data['favorites']
      aliases = data['alias']
      trusted = data['lichsettings']['trusted_scripts']
      if favs.class == Hash
         begin
            Lich.db.execute('BEGIN')
         rescue SQLite3::BusyException
            sleep 0.1
            retry
         end
         favs.each { |scope,script_list|
            hash = { 'scripts' => Array.new }
            script_list.each { |name,args| hash['scripts'].push(:name => name, :args => args) }
            blob = SQLite3::Blob.new(Marshal.dump(hash))
            if scope == 'global'
               begin
                  Lich.db.execute("INSERT OR REPLACE INTO script_auto_settings(script,scope,hash) VALUES('autostart',':',?);", blob)
               rescue SQLite3::BusyException
                  sleep 0.1
                  retry
               end
            else
               characters.find_all { |c| c =~ /^.+:#{scope}$/ }.each { |c|
                  begin
                     Lich.db.execute("INSERT OR REPLACE INTO script_auto_settings(script,scope,hash) VALUES('autostart',?,?);", c.encode('UTF-8'), blob)
                  rescue SQLite3::BusyException
                     sleep 0.1
                     retry
                  end
               }
            end
         }
         begin
            Lich.db.execute('END')
         rescue SQLite3::BusyException
            sleep 0.1
            retry
         end
      end
      favs = nil   

      db = SQLite3::Database.new("#{DATA_DIR}/alias.db3")
      begin
         db.execute("CREATE TABLE IF NOT EXISTS global (trigger TEXT NOT NULL, target TEXT NOT NULL, UNIQUE(trigger));")
      rescue SQLite3::BusyException
         sleep 0.1
         retry
      end
      begin
         db.execute('BEGIN')
      rescue SQLite3::BusyException
         sleep 0.1
         retry
      end
      if aliases.class == Hash
         aliases.each { |scope,alias_hash|
            if scope == 'global'
               tables = ['global']
            else
               tables = characters.find_all { |c| c =~ /^.+:#{scope}$/ }.collect { |t| t.downcase.sub(':', '_').gsub(/[^a-z_]/, '').encode('UTF-8') }
            end
            tables.each { |t|
               begin
                  db.execute("CREATE TABLE IF NOT EXISTS #{t} (trigger TEXT NOT NULL, target TEXT NOT NULL, UNIQUE(trigger));")
               rescue SQLite3::BusyException
                  sleep 0.1
                  retry
               end
            }
            alias_hash.each { |trigger,target|
               tables.each { |t|
                  begin
                     db.execute("INSERT OR REPLACE INTO #{t} (trigger,target) VALUES(?,?);", trigger.gsub(/\\(.)/) { $1 }.encode('UTF-8'), target.encode('UTF-8'))
                  rescue SQLite3::BusyException
                     sleep 0.1
                     retry
                  end
               }
            }
         }
      end
      begin
         db.execute('END')
      rescue SQLite3::BusyException
         sleep 0.1
         retry
      end

      begin
         Lich.db.execute('BEGIN')
      rescue SQLite3::BusyException
         sleep 0.1
         retry
      end
      trusted.each { |script_name|
         begin
            Lich.db.execute('INSERT OR REPLACE INTO trusted_scripts(name) values(?);', script_name.encode('UTF-8'))
         rescue SQLite3::BusyException
            sleep 0.1
            retry
         end
      }
      begin
         Lich.db.execute('END')
      rescue SQLite3::BusyException
         sleep 0.1
         retry
      end
      db.close rescue nil
      db = nil
      data = nil
      aliases = nil
      characters = nil
      trusted = nil
      File.rename("#{DATA_DIR}/lich.sav", "#{backup_dir}lich.sav")
   end
end

if argv_options[:sal]
   unless File.exists?(argv_options[:sal])
      Lich.log "error: launch file does not exist: #{argv_options[:sal]}"
      Lich.msgbox "error: launch file does not exist: #{argv_options[:sal]}"
      exit
   end
   Lich.log "info: launch file: #{argv_options[:sal]}"
   if argv_options[:sal] =~ /SGE\.sal/i
      unless launcher_cmd = Lich.get_simu_launcher
         $stdout.puts 'error: failed to find the Simutronics launcher'
         Lich.log 'error: failed to find the Simutronics launcher'
         exit
      end
      launcher_cmd.sub!('%1', argv_options[:sal])
      Lich.log "info: launcher_cmd: #{launcher_cmd}"
      if defined?(Win32) and launcher_cmd =~ /^"(.*?)"\s*(.*)$/
         dir_file = $1
         param = $2
         dir = dir_file.slice(/^.*[\\\/]/)
         file = dir_file.sub(/^.*[\\\/]/, '')
         operation = (Win32.isXP? ? 'open' : 'runas')
         Win32.ShellExecute(:lpOperation => operation, :lpFile => file, :lpDirectory => dir, :lpParameters => param)
         if r < 33
            Lich.log "error: Win32.ShellExecute returned #{r}; Win32.GetLastError: #{Win32.GetLastError}"
         end
      elsif defined?(Wine)
         system("#{Wine::BIN} #{launcher_cmd}")
      else
         system(launcher_cmd)
      end
      exit
   end
end

if arg = ARGV.find { |a| (a == '-g') or (a == '--game') }
   game_host, game_port = ARGV[ARGV.index(arg)+1].split(':')
   game_port = game_port.to_i
   if ARGV.any? { |arg| (arg == '-s') or (arg == '--stormfront') }
      $frontend = 'stormfront'
   elsif ARGV.any? { |arg| (arg == '-w') or (arg == '--wizard') }
      $frontend = 'wizard'
   elsif ARGV.any? { |arg| arg == '--avalon' }
      $frontend = 'avalon'
   else
      $frontend = 'unknown'
   end
elsif ARGV.include?('--gemstone')
   if ARGV.include?('--platinum')
      $platinum = true
      if ARGV.any? { |arg| (arg == '-s') or (arg == '--stormfront') }
         game_host = 'storm.gs4.game.play.net'
         game_port = 10124
         $frontend = 'stormfront'
      else
         game_host = 'gs-plat.simutronics.net'
         game_port = 10121
         if ARGV.any? { |arg| arg == '--avalon' }
            $frontend = 'avalon'
         else
            $frontend = 'wizard'
         end
      end
   else
      $platinum = false
      if ARGV.any? { |arg| (arg == '-s') or (arg == '--stormfront') }
         game_host = 'storm.gs4.game.play.net'
         game_port = 10024
         $frontend = 'stormfront'
      else
         game_host = 'gs3.simutronics.net'
         game_port = 4900
         if ARGV.any? { |arg| arg == '--avalon' }
            $frontend = 'avalon'
         else
            $frontend = 'wizard'
         end
      end
   end
elsif ARGV.include?('--shattered')
   $platinum = false
   if ARGV.any? { |arg| (arg == '-s') or (arg == '--stormfront') }
      game_host = 'storm.gs4.game.play.net'
      game_port = 10324
      $frontend = 'stormfront'
   else
      game_host = 'gs4.simutronics.net'
      game_port = 10321
      if ARGV.any? { |arg| arg == '--avalon' }
         $frontend = 'avalon'
      else
         $frontend = 'wizard'
      end
   end
elsif ARGV.include?('--dragonrealms')
   if ARGV.include?('--platinum')
      $platinum = true
      if ARGV.any? { |arg| (arg == '-s') or (arg == '--stormfront') }
         $stdout.puts "fixme"
         Lich.log "fixme"
         exit
         $frontend = 'stormfront'
      else
         $stdout.puts "fixme"
         Lich.log "fixme"
         exit
         $frontend = 'wizard'
      end
   else
      $platinum = false
      if ARGV.any? { |arg| (arg == '-s') or (arg == '--stormfront') }
         $frontend = 'stormfront'
         $stdout.puts "fixme"
         Lich.log "fixme"
         exit
      else
         game_host = 'dr.simutronics.net'
         game_port = 4901
         if ARGV.any? { |arg| arg == '--avalon' }
            $frontend = 'avalon'
         else
            $frontend = 'wizard'
         end
      end
   end
else
   game_host, game_port = nil, nil
   Lich.log "info: no force-mode info given"
end

if defined?(Gtk)
   unless File.exists?('fly64.png')
      File.open('fly64.png', 'wb') { |f| f.write '
         iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAMAAACdt4HsAAAChVBMVEUAAAAA
         AAABAQECAgIDAwMEBAQFBQUGBgYHBwcICAgKCgoLCwsMDAwNDQ0ODg4QEBAR
         ERESEhITExMUFBQWFhYXFxcYGBgZGRkaGhobGxscHBwdHR0eHh4fHx8hISEi
         IiIjIyMkJCQmJiYnJycoKCgpKSksLCwtLS0uLi4vLy8wMDAyMjIzMzM1NTU2
         NjY4ODg6Ojo7Ozs8PDw9PT0+Pj5AQEBBQUFCQkJDQ0NERERFRUVGRkZHR0dJ
         SUlKSkpLS0tMTExNTU1OTk5PT09QUFBRUVFSUlJTU1NUVFRVVVVWVlZXV1dY
         WFhZWVlaWlpcXFxdXV1eXl5gYGBiYmJjY2NkZGRnZ2dpaWlqampra2tsbGxt
         bW1ubm5vb29xcXFycnJ0dHR1dXV2dnZ4eHh5eXl6enp7e3t8fHx9fX1/f3+A
         gICBgYGCgoKDg4OEhISFhYWGhoaHh4eJiYmKioqLi4uMjIyNjY2Ojo6Pj4+Q
         kJCRkZGSkpKTk5OVlZWXl5eYmJiZmZmcnJydnZ2goKChoaGioqKjo6OlpaWm
         pqanp6eoqKipqamqqqqrq6utra2urq6vr6+wsLCxsbGysrKzs7O0tLS1tbW2
         tra3t7e4uLi5ubm6urq7u7u9vb2+vr6/v7/AwMDBwcHCwsLDw8PExMTFxcXH
         x8fIyMjJycnLy8vMzMzPz8/Q0NDR0dHS0tLT09PV1dXW1tbX19fZ2dnc3Nzd
         3d3e3t7f39/g4ODh4eHi4uLj4+Pk5OTl5eXm5ubn5+fo6Ojp6enq6urr6+vs
         7Ozt7e3v7+/w8PDx8fHy8vLz8/P09PT19fX29vb39/f4+Pj5+fn6+vr7+/v8
         /Pz9/f3+/v7////aGP7gAAAAAXRSTlMAQObYZgAABDZJREFUWMOll4tfVEUU
         x+/vxgJlYmUKKZT4KIOgQi3toWA+e1CGEthDEJMwA/KR0UM0X/kow420QMns
         pdVCaka0ApUh0YJF7u/vae7u3d175z4+W3c+n4WZs+d858ycM3NmFcWtcYiK
         p8ZbPAL+KPXoQGOrR8DNHldwPtOjA6sf9+YBU7HRG+GbiZj+kycEt6Tiuf9L
         IIUlh+/D9WeSQ3xIk15o9aTSoIY4dh0WDSczYb2velQJ64MrZ6G149qYd6hI
         xgeG5mLqCW1ODr2KaLtfG+4F1ie3CLahjApf063VnAVbxbAdmJfsPvKaKnK3
         bo+nDx0YZfgMkJl0HIiXybkwtOI+8SfoYiEDdit8DFixMAZQxafTHFzT6Ohn
         JkAQp4VM5G+awYk6GqzbCisCMQa5M2+/2YV2hIT8fZbA1FZ2hCPB+TzqmNrQ
         ow1PrsJmeQW7ovHugqWV7GivSRELemTToz4xvGHrxgxUWvaWz6dGZIvh0HJ7
         tamDb60R/WW/WmPDWT5xAPq6Msxm9e9Vj4320msGoxvA81/ahZYTkGYz71Mi
         my4dnKNGBnk7XJKC0yan2wBU6ofTX5qijZd3Mux8ghnq+vReidCVUPi67Foh
         GLuHbsnJFAlQbdTm4TIhGveSC6FDXsN8Sn7uyhXS8gEnRiWwxgS40xrwwDyR
         FGvtCfThbj5sBNxqo8iLGSoqbGO5H2jgoBFgX5+YpWLATj4FIqHZYiRU2hLe
         BDZZF9czCViidfxGQn6fDeJ7oFYWs1lT/znSPSeF0oIQd+U7UnwGszXdHF3a
         aQ5m1d9m7au3Q7qs+bZQmwjsjN3tN0n5sPhH6neYyNiv8lXJATYCr/D1BJby
         sVYx5tnaZv/Rln2NS7Rxs+RAAT4hs7AqDiiGS8vYIu/Kb5hGpRv4OE6cI9vE
         OtkrNwcsm8omvKuwwbAxnCEBQhzt7fmhe4C0O4y8cYzYojS8mADIXvtdi0o/
         6qn0AmcNEmMTFeoN16I0X0vgbZiecO6wCcDlDhkdNQ8W4Unxf7I4R3HZOqP9
         Q/wI9zgBwlwrquDFyKoNZegBI6BZe3L10978CO5qiXx1CosS8n+0e1x8DhRq
         gCGFH4xD8S82xaC1aL0eFZbDUCv3AbO0SB7hXxXpiNS2tjzr+VMun4gHlbnp
         hhXMBP5UmKP6NNtLurPHszLP0bHEExWKcQtbrirK6ATUmC7l7eIN4RSLYwjE
         9eqAZyKKv0uHlpdnlDgQWIWRWD8APKirZU+Ri3h5gcN1XIALeq8/BTNjzwhU
         WRa9odD+ml2hFkXLoLhRZ8dUuvGdVfPbhbaEC8AT4qAFxUWS2KhWXLGZ6+SI
         rQtNImPG3yYeIKcTCb3N9pXqtI1fjBeIqX4aX8Cz/9sTfbijxxy1uqUef7XU
         bvAIqG/yCNjuEaB0rvMIGHnBm73CfK8/4E+5A/4FccSsAIr2lfUAAAAASUVO
         RK5CYII='.unpack('m')[0] }
   end
   begin
      Gtk.queue {
         Gtk::Window.default_icon = GdkPixbuf::Pixbuf.new(:file => 'fly64.png')
      }
   rescue
      nil # fixme
   end
end

main_thread = Thread.new {
          test_mode = false
    $SEND_CHARACTER = '>'
        $cmd_prefix = '<c>'
   $clean_lich_char = ';' # fixme
   $lich_char = Regexp.escape($clean_lich_char)

   launch_data = nil

   if ARGV.include?('--login')
      if File.exists?("#{DATA_DIR}/entry.dat")
         entry_data = File.open("#{DATA_DIR}/entry.dat", 'r') { |file|
            begin
               Marshal.load(file.read.unpack('m').first)
            rescue
               Array.new
            end
         }
      else
         entry_data = Array.new
      end
      char_name = ARGV[ARGV.index('--login')+1].capitalize
      if ARGV.include?('--gemstone')
         if ARGV.include?('--platinum')
            data = entry_data.find { |d| (d[:char_name] == char_name) and (d[:game_code] == 'GSX') }
         elsif ARGV.include?('--shattered')
            data = entry_data.find { |d| (d[:char_name] == char_name) and (d[:game_code] == 'GSF') }
         else
            data = entry_data.find { |d| (d[:char_name] == char_name) and (d[:game_code] == 'GS3') }
         end
      elsif ARGV.include?('--shattered')
         data = entry_data.find { |d| (d[:char_name] == char_name) and (d[:game_code] == 'GSF') }
      else
         data = entry_data.find { |d| (d[:char_name] == char_name) }
      end
      if data
         Lich.log "info: using quick game entry settings for #{char_name}"
         msgbox = proc { |msg|
            if defined?(Gtk)
               done = false
               Gtk.queue {
                  dialog = Gtk::MessageDialog.new(nil, Gtk::Dialog::DESTROY_WITH_PARENT, Gtk::MessageDialog::QUESTION, Gtk::MessageDialog::BUTTONS_CLOSE, msg)
                  dialog.run
                  dialog.destroy
                  done = true
               }
               sleep 0.1 until done
            else
               $stdout.puts(msg)
               Lich.log(msg)
            end
         }
   
         login_server = nil
         connect_thread = nil
         timeout_thread = Thread.new {
            sleep 30
            $stdout.puts "error: timed out connecting to eaccess.play.net:7900"
            Lich.log "error: timed out connecting to eaccess.play.net:7900"
            connect_thread.kill rescue nil
            login_server = nil
         }
         connect_thread = Thread.new {
            begin
               login_server = TCPSocket.new('eaccess.play.net', 7900)
            rescue
               login_server = nil
               $stdout.puts "error connecting to server: #{$!}"
               Lich.log "error connecting to server: #{$!}"
            end
         }
         connect_thread.join
         timeout_thread.kill rescue nil

         if login_server
            login_server.puts "K\n"
            hashkey = login_server.gets
            if 'test'[0].class == String
               password = data[:password].split('').collect { |c| c.getbyte(0) }
               hashkey = hashkey.split('').collect { |c| c.getbyte(0) }
            else
               password = data[:password].split('').collect { |c| c[0] }
               hashkey = hashkey.split('').collect { |c| c[0] }
            end
            password.each_index { |i| password[i] = ((password[i]-32)^hashkey[i])+32 }
            password = password.collect { |c| c.chr }.join
            login_server.puts "A\t#{data[:user_id]}\t#{password}\n"
            password = nil
            response = login_server.gets
            login_key = /KEY\t([^\t]+)\t/.match(response).captures.first
            if login_key
               login_server.puts "M\n"
               response = login_server.gets
               if response =~ /^M\t/
                  login_server.puts "F\t#{data[:game_code]}\n"
                  response = login_server.gets
                  if response =~ /NORMAL|PREMIUM|TRIAL|INTERNAL|FREE/
                     login_server.puts "G\t#{data[:game_code]}\n"
                     login_server.gets
                     login_server.puts "P\t#{data[:game_code]}\n"
                     login_server.gets
                     login_server.puts "C\n"
                     char_code = login_server.gets.sub(/^C\t[0-9]+\t[0-9]+\t[0-9]+\t[0-9]+[\t\n]/, '').scan(/[^\t]+\t[^\t^\n]+/).find { |c| c.split("\t")[1] == data[:char_name] }.split("\t")[0]
                     login_server.puts "L\t#{char_code}\tSTORM\n"
                     response = login_server.gets
                     if response =~ /^L\t/
                        login_server.close unless login_server.closed?
                        launch_data = response.sub(/^L\tOK\t/, '').split("\t")
                        if data[:frontend] == 'wizard'
                           launch_data.collect! { |line| line.sub(/GAMEFILE=.+/, 'GAMEFILE=WIZARD.EXE').sub(/GAME=.+/, 'GAME=WIZ').sub(/FULLGAMENAME=.+/, 'FULLGAMENAME=Wizard Front End') }
                        elsif data[:frontend] == 'avalon'
                           launch_data.collect! { |line| line.sub(/GAME=.+/, 'GAME=AVALON') }
                        end
                        if data[:custom_launch]
                           launch_data.push "CUSTOMLAUNCH=#{data[:custom_launch]}"
                           if data[:custom_launch_dir]
                              launch_data.push "CUSTOMLAUNCHDIR=#{data[:custom_launch_dir]}"
                           end
                        end
                     else
                        login_server.close unless login_server.closed?
                        $stdout.puts "error: unrecognized response from server. (#{response})"
                        Lich.log "error: unrecognized response from server. (#{response})"
                     end
                  else
                     login_server.close unless login_server.closed?
                     $stdout.puts "error: unrecognized response from server. (#{response})"
                     Lich.log "error: unrecognized response from server. (#{response})"
                  end
               else
                  login_server.close unless login_server.closed?
                  $stdout.puts "error: unrecognized response from server. (#{response})"
                  Lich.log "error: unrecognized response from server. (#{response})"
               end
            else
               login_server.close unless login_server.closed?
               $stdout.puts "Something went wrong... probably invalid user id and/or password.\nserver response: #{response}"
               Lich.log "Something went wrong... probably invalid user id and/or password.\nserver response: #{response}"
               reconnect_if_wanted.call
            end
         else
            $stdout.puts "error: failed to connect to server"
            Lich.log "error: failed to connect to server"
            reconnect_if_wanted.call
            Lich.log "info: exiting..."
            Gtk.queue { Gtk.main_quit } if defined?(Gtk)
            exit
         end
      else
         $stdout.puts "error: failed to find login data for #{char_name}"
         Lich.log "error: failed to find login data for #{char_name}"
      end
   elsif defined?(Gtk) and (ARGV.empty? or argv_options[:gui])
      if File.exists?("#{DATA_DIR}/entry.dat")
         entry_data = File.open("#{DATA_DIR}/entry.dat", 'r') { |file|
            begin
               Marshal.load(file.read.unpack('m').first).sort { |a,b| [a[:user_id].downcase, a[:char_name]] <=> [b[:user_id].downcase, b[:char_name]] }
            rescue
               Array.new
            end
         }
      else
         entry_data = Array.new
      end
      save_entry_data = false
      done = false
      Gtk.queue {

         login_server = nil
         window = nil
         install_tab_loaded = false

         msgbox = proc { |msg|
            dialog = Gtk::MessageDialog.new(window, Gtk::Dialog::DESTROY_WITH_PARENT, Gtk::MessageDialog::QUESTION, Gtk::MessageDialog::BUTTONS_CLOSE, msg)
            dialog.run
            dialog.destroy
         }

         #
         # quick game entry tab
         #
         if entry_data.empty?
            box = Gtk::HBox.new
            box.pack_start(Gtk::Label.new('You have no saved login info.'), true, true, 0)
            quick_game_entry_tab = Gtk::VBox.new
            quick_game_entry_tab.border_width = 5
            quick_game_entry_tab.pack_start(box, true, true, 0)
         else
            quick_box    = Gtk::VBox.new
                last_user_id = nil
            entry_data.each { |login_info|
                    if login_info[:user_id].downcase != last_user_id
                        last_user_id = login_info[:user_id].downcase
                        quick_box.pack_start(Gtk::Label.new("Account: " + last_user_id), false, false, 6)
                    end
                    
               label = Gtk::Label.new("#{login_info[:char_name]} (#{login_info[:game_name]}, #{login_info[:frontend]})")
               play_button = Gtk::Button.new('Play')
               remove_button = Gtk::Button.new('X')
               char_box = Gtk::HBox.new
               char_box.pack_start(label, false, false, 6)
               char_box.pack_end(remove_button, false, false, 0)
               char_box.pack_end(play_button, false, false, 0)
               quick_box.pack_start(char_box, false, false, 0)
               play_button.signal_connect('clicked') {
                  play_button.sensitive = false
                  begin
                     login_server = nil
                     connect_thread = Thread.new {
                        login_server = TCPSocket.new('eaccess.play.net', 7900)
                     }
                     300.times {
                        sleep 0.1
                        break unless connect_thread.status
                     }
                     if connect_thread.status
                        connect_thread.kill rescue nil
                        msgbox.call "error: timed out connecting to eaccess.play.net:7900"
                     end
                  rescue
                     msgbox.call "error connecting to server: #{$!}"
                     play_button.sensitive = true
                  end
                  if login_server
                     login_server.puts "K\n"
                     hashkey = login_server.gets
                     if 'test'[0].class == String
                        password = login_info[:password].split('').collect { |c| c.getbyte(0) }
                        hashkey = hashkey.split('').collect { |c| c.getbyte(0) }
                     else
                        password = login_info[:password].split('').collect { |c| c[0] }
                        hashkey = hashkey.split('').collect { |c| c[0] }
                     end
                     password.each_index { |i| password[i] = ((password[i]-32)^hashkey[i])+32 }
                     password = password.collect { |c| c.chr }.join
                     login_server.puts "A\t#{login_info[:user_id]}\t#{password}\n"
                     password = nil
                     response = login_server.gets
                     login_key = /KEY\t([^\t]+)\t/.match(response).captures.first
                     if login_key
                        login_server.puts "M\n"
                        response = login_server.gets
                        if response =~ /^M\t/
                           login_server.puts "F\t#{login_info[:game_code]}\n"
                           response = login_server.gets
                           if response =~ /NORMAL|PREMIUM|TRIAL|INTERNAL|FREE/
                              login_server.puts "G\t#{login_info[:game_code]}\n"
                              login_server.gets
                              login_server.puts "P\t#{login_info[:game_code]}\n"
                              login_server.gets
                              login_server.puts "C\n"
                              char_code = login_server.gets.sub(/^C\t[0-9]+\t[0-9]+\t[0-9]+\t[0-9]+[\t\n]/, '').scan(/[^\t]+\t[^\t^\n]+/).find { |c| c.split("\t")[1] == login_info[:char_name] }.split("\t")[0]
                              login_server.puts "L\t#{char_code}\tSTORM\n"
                              response = login_server.gets
                              if response =~ /^L\t/
                                 login_server.close unless login_server.closed?
                                 launch_data = response.sub(/^L\tOK\t/, '').split("\t")
                                 if login_info[:frontend] == 'wizard'
                                    launch_data.collect! { |line| line.sub(/GAMEFILE=.+/, 'GAMEFILE=WIZARD.EXE').sub(/GAME=.+/, 'GAME=WIZ').sub(/FULLGAMENAME=.+/, 'FULLGAMENAME=Wizard Front End') }
                                 end
                                 if login_info[:custom_launch]
                                    launch_data.push "CUSTOMLAUNCH=#{login_info[:custom_launch]}"
                                    if login_info[:custom_launch_dir]
                                       launch_data.push "CUSTOMLAUNCHDIR=#{login_info[:custom_launch_dir]}"
                                    end
                                 end
                                 window.destroy
                                 done = true
                              else
                                 login_server.close unless login_server.closed?
                                 msgbox.call("Unrecognized response from server. (#{response})")
                                 play_button.sensitive = true
                              end
                           else
                              login_server.close unless login_server.closed?
                              msgbox.call("Unrecognized response from server. (#{response})")
                              play_button.sensitive = true
                           end
                        else
                           login_server.close unless login_server.closed?
                           msgbox.call("Unrecognized response from server. (#{response})")
                           play_button.sensitive = true
                        end
                     else
                        login_server.close unless login_server.closed?
                        msgbox.call "Something went wrong... probably invalid user id and/or password.\nserver response: #{response}"
                        play_button.sensitive = true
                     end
                  else
                     msgbox.call "error: failed to connect to server"
                     play_button.sensitive = true
                  end
               }
               remove_button.signal_connect('clicked') {
                  entry_data.delete(login_info)
                  save_entry_data = true
                  char_box.visible = false
               }
            }

            adjustment = Gtk::Adjustment.new(0, 0, 1000, 5, 20, 500)
            quick_vp = Gtk::Viewport.new(adjustment, adjustment)
            quick_vp.add(quick_box)

            quick_sw = Gtk::ScrolledWindow.new
            quick_sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_ALWAYS)
            quick_sw.add(quick_vp)

            quick_game_entry_tab = Gtk::VBox.new
            quick_game_entry_tab.border_width = 5
            quick_game_entry_tab.pack_start(quick_sw, true, true, 5)
         end

=begin
         #
         # game entry tab
         #

         checked_frontends = false
         wizard_dir        = nil
         stormfront_dir    = nil
         found_profanity   = false

         account_name_label        = Gtk::Label.new('Account Name:')
         account_name_entry        = Gtk::Entry.new
         password_label            = Gtk::Label.new('Password:')
         password_entry            = Gtk::Entry.new
         password_entry.visibility = false

         account_name_label_box = Gtk::HBox.new
         account_name_label_box.pack_end(account_name_label, false, false, 0)

         password_label_box = Gtk::HBox.new
         password_label_box.pack_end(password_label, false, false, 0)

         login_table = Gtk::Table.new(2, 2, false)
         login_table.attach(account_name_label_box, 0, 1, 0, 1, Gtk::FILL, Gtk::FILL, 5, 5)
         login_table.attach(account_name_entry, 1, 2, 0, 1, Gtk::EXPAND|Gtk::FILL, Gtk::EXPAND|Gtk::FILL, 5, 5)
         login_table.attach(password_label_box, 0, 1, 1, 2, Gtk::FILL, Gtk::FILL, 5, 5)
         login_table.attach(password_entry, 1, 2, 1, 2, Gtk::EXPAND|Gtk::FILL, Gtk::EXPAND|Gtk::FILL, 5, 5)

         disconnect_button = Gtk::Button.new(' Disconnect ')
         disconnect_button.sensitive = false

         connect_button = Gtk::Button.new(' Connect ')

         login_button_box = Gtk::HBox.new
         login_button_box.pack_end(connect_button, false, false, 5)
         login_button_box.pack_end(disconnect_button, false, false, 5)

         liststore = Gtk::ListStore.new(String, String, String, String)
         liststore.set_sort_column_id(1, Gtk::SORT_ASCENDING)

         renderer = Gtk::CellRendererText.new

         treeview = Gtk::TreeView.new(liststore)
         treeview.height_request = 160

         col = Gtk::TreeViewColumn.new("Game", renderer, :text => 1)
         col.resizable = true
         treeview.append_column(col)

         col = Gtk::TreeViewColumn.new("Character", renderer, :text => 3)
         col.resizable = true
         treeview.append_column(col)

         sw = Gtk::ScrolledWindow.new
         sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_ALWAYS)
         sw.add(treeview)

         wizard_option = Gtk::RadioButton.new('WizardFE')
         stormfront_option = Gtk::RadioButton.new(wizard_option, 'Stormfront')
         profanity_option = Gtk::RadioButton.new(wizard_option, 'ProfanityFE')
         other_fe_option = Gtk::RadioButton.new(wizard_option, '(other)')

         frontend_label = Gtk::Label.new('Frontend: ')

         frontend_option = Gtk::ComboBox.new(is_text_only = true)
         frontend_option.append_text('WizardFE')
         frontend_option.append_text('Stormfront')
         frontend_option.append_text('ProfanityFE')
         frontend_option.append_text('(other)')

         frontend_box2 = Gtk::HBox.new(false, 10)
         frontend_box2.pack_start(frontend_label, false, false, 0)
         frontend_box2.pack_start(frontend_option, false, false, 0)

         launch_label = Gtk::Label.new('Launch method: ')

         launch_option = Gtk::ComboBox.new(is_text_only = true)
         launch_option.append_text('ShellExecute')
         launch_option.append_text('spawn')
         launch_option.append_text('system')
         launch_option.active = 0

         launch_box = Gtk::HBox.new(false, 10)
         launch_box.pack_start(launch_label, false, false, 0)
         launch_box.pack_start(launch_option, false, false, 0)

         frontend_box = Gtk::HBox.new(false, 10)
         frontend_box.pack_start(wizard_option, false, false, 0)
         frontend_box.pack_start(stormfront_option, false, false, 0)
         frontend_box.pack_start(profanity_option, false, false, 0)
         frontend_box.pack_start(other_fe_option, false, false, 0)

         use_simu_launcher_option = Gtk::CheckButton.new('Use the Simutronics Launcher')
         use_simu_launcher_option.active = true

         custom_launch_option = Gtk::CheckButton.new('Use a custom launch command')
         custom_launch_entry = Gtk::ComboBoxEntry.new()
         custom_launch_entry.child.text = "(enter custom launch command)"
         custom_launch_entry.append_text("Wizard.Exe /GGS /H127.0.0.1 /P%port% /K%key%")
         custom_launch_entry.append_text("Stormfront.exe /GGS /H127.0.0.1 /P%port% /K%key%")
         custom_launch_dir = Gtk::ComboBoxEntry.new()
         custom_launch_dir.child.text = "(enter working directory for command)"
         custom_launch_dir.append_text("../wizard")
         custom_launch_dir.append_text("../StormFront")

         remember_use_simu_launcher_active = nil 
         revert_custom_launch_active = nil
         frontend_option.signal_connect('changed') {
            if ((frontend_option.active == 0) and not wizard_dir) or ((frontend_option.active == 1) and not stormfront_dir) or (frontend_option.active == 2) or (frontend_option.active == 3)
#            if (frontend_option.active != 0) and (frontend_option.active != 1) # Wizard or Stormfront
               if use_simu_launcher_option.sensitive?
                  remember_use_simu_launcher_active = use_simu_launcher_option.active?
                  use_simu_launcher_option.active = true
                  use_simu_launcher_option.sensitive = false
               end
            elsif not use_simu_launcher_option.sensitive? and not custom_launch_option.active?
               use_simu_launcher_option.sensitive = true
               use_simu_launcher_option.active = remember_use_simu_launcher_active
            end
            if (frontend_option.active == 3) or ((frontend_option.active == 2) and not found_profanity)
               if custom_launch_option.sensitive?
                  if not custom_launch_option.active?
                     revert_custom_launch_active = true
                  else
                     revert_custom_launch_active = false
                  end
                  custom_launch_option.active = true
                  custom_launch_option.sensitive = false
               end
            elsif not custom_launch_option.sensitive?
               custom_launch_option.sensitive = true
               if revert_custom_launch_active
                  revert_custom_launch_active = false
                  custom_launch_option.active = false
               end
            end
         }
         frontend_option.active = 0

         make_quick_option = Gtk::CheckButton.new('Save this info for quick game entry')

         play_button = Gtk::Button.new(' Play ')
         play_button.sensitive = false

         play_button_box = Gtk::HBox.new
         play_button_box.pack_end(play_button, false, false, 5)

         game_entry_tab = Gtk::VBox.new
         game_entry_tab.border_width = 5
         game_entry_tab.pack_start(login_table, false, false, 0)
         game_entry_tab.pack_start(login_button_box, false, false, 0)
         game_entry_tab.pack_start(sw, true, true, 3)
#         game_entry_tab.pack_start(frontend_box, false, false, 3)
         game_entry_tab.pack_start(frontend_box2, false, false, 3)
         game_entry_tab.pack_start(launch_box, false, false, 3)
         game_entry_tab.pack_start(use_simu_launcher_option, false, false, 3)
         game_entry_tab.pack_start(custom_launch_option, false, false, 3)
         game_entry_tab.pack_start(custom_launch_entry, false, false, 3)
         game_entry_tab.pack_start(custom_launch_dir, false, false, 3)
         game_entry_tab.pack_start(make_quick_option, false, false, 3)
         game_entry_tab.pack_start(play_button_box, false, false, 3)

         custom_launch_option.signal_connect('toggled') {
            custom_launch_entry.visible = custom_launch_option.active?
            custom_launch_dir.visible = custom_launch_option.active?
            if custom_launch_option.active?
               if use_simu_launcher_option.sensitive?
                  remember_use_simu_launcher_active = use_simu_launcher_option.active?
                  use_simu_launcher_option.active = false
                  use_simu_launcher_option.sensitive = false
               end
            elsif not use_simu_launcher_option.sensitive? and ((frontend_option.active == 0) or (frontend_option.active == 1) or ((frontend_option.active == 2) and not found_profanity))
               use_simu_launcher_option.sensitive = true
               use_simu_launcher_option.active = remember_use_simu_launcher_active
            end
         }

         connect_button.signal_connect('clicked') {
            connect_button.sensitive = false
            account_name_entry.sensitive = false
            password_entry.sensitive = false
            iter = liststore.append
            iter[1] = 'working...'
            Gtk.queue {
               begin
                  login_server = nil
                  connect_thread = Thread.new {
                     login_server = TCPSocket.new('eaccess.play.net', 7900)
                  }
                  300.times {
                     sleep 0.1
                     break unless connect_thread.status
                  }
                  if connect_thread.status
                     connect_thread.kill rescue nil
                     msgbox.call "error: timed out connecting to eaccess.play.net:7900"
                  end
               rescue
                  msgbox.call "error connecting to server: #{$!}"
                  connect_button.sensitive = true
                  account_name_entry.sensitive = true
                  password_entry.sensitive = true
               end
               disconnect_button.sensitive = true
               if login_server
                  login_server.puts "K\n"
                  hashkey = login_server.gets
                  if 'test'[0].class == String
                     password = password_entry.text.split('').collect { |c| c.getbyte(0) }
                     hashkey = hashkey.split('').collect { |c| c.getbyte(0) }
                  else
                     password = password_entry.text.split('').collect { |c| c[0] }
                     hashkey = hashkey.split('').collect { |c| c[0] }
                  end
                  # password_entry.text = String.new
                  password.each_index { |i| password[i] = ((password[i]-32)^hashkey[i])+32 }
                  password = password.collect { |c| c.chr }.join
                  login_server.puts "A\t#{account_name_entry.text}\t#{password}\n"
                  password = nil
                  response = login_server.gets
                  login_key = /KEY\t([^\t]+)\t/.match(response).captures.first
                  if login_key
                     login_server.puts "M\n"
                     response = login_server.gets
                     if response =~ /^M\t/
                        liststore.clear
                        for game in response.sub(/^M\t/, '').scan(/[^\t]+\t[^\t^\n]+/)
                           game_code, game_name = game.split("\t")
                           login_server.puts "N\t#{game_code}\n"
                           if login_server.gets =~ /STORM/
                              login_server.puts "F\t#{game_code}\n"
                              if login_server.gets =~ /NORMAL|PREMIUM|TRIAL|INTERNAL|FREE/
                                 login_server.puts "G\t#{game_code}\n"
                                 login_server.gets
                                 login_server.puts "P\t#{game_code}\n"
                                 login_server.gets
                                 login_server.puts "C\n"
                                 for code_name in login_server.gets.sub(/^C\t[0-9]+\t[0-9]+\t[0-9]+\t[0-9]+[\t\n]/, '').scan(/[^\t]+\t[^\t^\n]+/)
                                    char_code, char_name = code_name.split("\t")
                                    iter = liststore.append
                                    iter[0] = game_code
                                    iter[1] = game_name
                                    iter[2] = char_code
                                    iter[3] = char_name
                                 end
                              end
                           end
                        end
                        disconnect_button.sensitive = true
                     else
                        login_server.close unless login_server.closed?
                        msgbox.call "Unrecognized response from server (#{response})"
                     end
                  else
                     login_server.close unless login_server.closed?
                     disconnect_button.sensitive = false
                     connect_button.sensitive = true
                     account_name_entry.sensitive = true
                     password_entry.sensitive = true
                     msgbox.call "Something went wrong... probably invalid user id and/or password.\nserver response: #{response}"
                  end
               end
            }
         }
         treeview.signal_connect('cursor-changed') {
            if login_server
               play_button.sensitive = true
            end
         }
         disconnect_button.signal_connect('clicked') {
            disconnect_button.sensitive = false
            play_button.sensitive = false
            liststore.clear
            login_server.close unless login_server.closed?
            connect_button.sensitive = true
            account_name_entry.sensitive = true
            password_entry.sensitive = true
         }
         play_button.signal_connect('clicked') {
            play_button.sensitive = false
            game_code = treeview.selection.selected[0]
            char_code = treeview.selection.selected[2]
            if login_server and not login_server.closed?
               login_server.puts "F\t#{game_code}\n"
               login_server.gets
               login_server.puts "G\t#{game_code}\n"
               login_server.gets
               login_server.puts "P\t#{game_code}\n"
               login_server.gets
               login_server.puts "C\n"
               login_server.gets
               login_server.puts "L\t#{char_code}\tSTORM\n"
               response = login_server.gets
               if response =~ /^L\t/
                  login_server.close unless login_server.closed?
                  port = /GAMEPORT=([0-9]+)/.match(response).captures.first
                  host = /GAMEHOST=([^\t\n]+)/.match(response).captures.first
                  key = /KEY=([^\t\n]+)/.match(response).captures.first
                  launch_data = response.sub(/^L\tOK\t/, '').split("\t")
                  login_server.close unless login_server.closed?
                  if wizard_option.active?
                     launch_data.collect! { |line| line.sub(/GAMEFILE=.+/, "GAMEFILE=WIZARD.EXE").sub(/GAME=.+/, "GAME=WIZ") }
                  elsif suks_option.active?
                     launch_data.collect! { |line| line.sub(/GAMEFILE=.+/, "GAMEFILE=WIZARD.EXE").sub(/GAME=.+/, "GAME=SUKS") }
                  end
                  if custom_launch_option.active?
                     launch_data.push "CUSTOMLAUNCH=#{custom_launch_entry.child.text}"
                     unless custom_launch_dir.child.text.empty? or custom_launch_dir.child.text == "(enter working directory for command)"
                        launch_data.push "CUSTOMLAUNCHDIR=#{custom_launch_dir.child.text}"
                     end
                  end
                  if make_quick_option.active?
                     if wizard_option.active?
                        frontend = 'wizard'
                     else
                        frontend = 'stormfront'
                     end
                     if custom_launch_option.active?
                        custom_launch = custom_launch_entry.child.text
                        if custom_launch_dir.child.text.empty? or custom_launch_dir.child.text == "(enter working directory for command)"
                           custom_launch_dir = nil
                        else
                           custom_launch_dir = custom_launch_dir.child.text
                        end
                     else
                        custom_launch = nil
                        custom_launch_dir = nil
                     end
                     entry_data.push h={ :char_name => treeview.selection.selected[3], :game_code => treeview.selection.selected[0], :game_name => treeview.selection.selected[1], :user_id => account_name_entry.text, :password => password_entry.text, :frontend => frontend, :custom_launch => custom_launch, :custom_launch_dir => custom_launch_dir }
                     save_entry_data = true
                  end
                  account_name_entry.text = String.new
                  password_entry.text = String.new
                  window.destroy
                  done = true
               else
                  login_server.close unless login_server.closed?
                  disconnect_button.sensitive = false
                  play_button.sensitive = false
                  connect_button.sensitive = true
                  account_name_entry.sensitive = true
                  password_entry.sensitive = true
               end
            else
               disconnect_button.sensitive = false
               play_button.sensitive = false
               connect_button.sensitive = true
               account_name_entry.sensitive = true
               password_entry.sensitive = true
            end
         }
         account_name_entry.signal_connect('activate') {
            password_entry.grab_focus
         }
         password_entry.signal_connect('activate') {
            connect_button.clicked
         }
=end

         #
         # old game entry tab
         #

         user_id_entry = Gtk::Entry.new

         pass_entry = Gtk::Entry.new
         pass_entry.visibility = false

         login_table = Gtk::Table.new(2, 2, false)
         login_table.attach(Gtk::Label.new('User ID:'), 0, 1, 0, 1, Gtk::EXPAND|Gtk::FILL, Gtk::EXPAND|Gtk::FILL, 5, 5)
         login_table.attach(user_id_entry, 1, 2, 0, 1, Gtk::EXPAND|Gtk::FILL, Gtk::EXPAND|Gtk::FILL, 5, 5)
         login_table.attach(Gtk::Label.new('Password:'), 0, 1, 1, 2, Gtk::EXPAND|Gtk::FILL, Gtk::EXPAND|Gtk::FILL, 5, 5)
         login_table.attach(pass_entry, 1, 2, 1, 2, Gtk::EXPAND|Gtk::FILL, Gtk::EXPAND|Gtk::FILL, 5, 5)

         disconnect_button = Gtk::Button.new(' Disconnect ')
         disconnect_button.sensitive = false

         connect_button = Gtk::Button.new(' Connect ')

         login_button_box = Gtk::HBox.new
         login_button_box.pack_end(connect_button, false, false, 5)
         login_button_box.pack_end(disconnect_button, false, false, 5)

         liststore = Gtk::ListStore.new(String, String, String, String)
         liststore.set_sort_column_id(1, Gtk::SORT_ASCENDING)

         renderer = Gtk::CellRendererText.new
#         renderer.background = 'white'

         treeview = Gtk::TreeView.new(liststore)
         treeview.height_request = 160

         col = Gtk::TreeViewColumn.new("Game", renderer, :text => 1)
         col.resizable = true
         treeview.append_column(col)

         col = Gtk::TreeViewColumn.new("Character", renderer, :text => 3)
         col.resizable = true
         treeview.append_column(col)

         sw = Gtk::ScrolledWindow.new
         sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_ALWAYS)
         sw.add(treeview)

         wizard_option = Gtk::RadioButton.new('Wizard')
         stormfront_option = Gtk::RadioButton.new(wizard_option, 'Stormfront')
         avalon_option = Gtk::RadioButton.new(wizard_option, 'Avalon')
         suks_option = Gtk::RadioButton.new(wizard_option, 'suks')

         frontend_box = Gtk::HBox.new(false, 10)
         frontend_box.pack_start(wizard_option, false, false, 0)
         frontend_box.pack_start(stormfront_option, false, false, 0)
         if RUBY_PLATFORM =~ /darwin/i
            frontend_box.pack_start(avalon_option, false, false, 0)
         end
         #frontend_box.pack_start(suks_option, false, false, 0)

         custom_launch_option = Gtk::CheckButton.new('Custom launch command')
         custom_launch_entry = Gtk::ComboBoxEntry.new()
         custom_launch_entry.child.text = "(enter custom launch command)"
         custom_launch_entry.append_text("Wizard.Exe /GGS /H127.0.0.1 /P%port% /K%key%")
         custom_launch_entry.append_text("Stormfront.exe /GGS/Hlocalhost/P%port%/K%key%")
         custom_launch_dir = Gtk::ComboBoxEntry.new()
         custom_launch_dir.child.text = "(enter working directory for command)"
         custom_launch_dir.append_text("../wizard")
         custom_launch_dir.append_text("../StormFront")

         make_quick_option = Gtk::CheckButton.new('Save this info for quick game entry')

         play_button = Gtk::Button.new(' Play ')
         play_button.sensitive = false

         play_button_box = Gtk::HBox.new
         play_button_box.pack_end(play_button, false, false, 5)

         game_entry_tab = Gtk::VBox.new
         game_entry_tab.border_width = 5
         game_entry_tab.pack_start(login_table, false, false, 0)
         game_entry_tab.pack_start(login_button_box, false, false, 0)
         game_entry_tab.pack_start(sw, true, true, 3)
         game_entry_tab.pack_start(frontend_box, false, false, 3)
         game_entry_tab.pack_start(custom_launch_option, false, false, 3)
         game_entry_tab.pack_start(custom_launch_entry, false, false, 3)
         game_entry_tab.pack_start(custom_launch_dir, false, false, 3)
         game_entry_tab.pack_start(make_quick_option, false, false, 3)
         game_entry_tab.pack_start(play_button_box, false, false, 3)

         custom_launch_option.signal_connect('toggled') {
            custom_launch_entry.visible = custom_launch_option.active?
            custom_launch_dir.visible = custom_launch_option.active?
         }

         avalon_option.signal_connect('toggled') {
            if avalon_option.active?
               custom_launch_option.active = false
               custom_launch_option.sensitive = false
            else
               custom_launch_option.sensitive = true
            end
         }

         connect_button.signal_connect('clicked') {
            connect_button.sensitive = false
            user_id_entry.sensitive = false
            pass_entry.sensitive = false
            iter = liststore.append
            iter[1] = 'working...'
            Gtk.queue {
               begin
                  login_server = nil
                  connect_thread = Thread.new {
                     login_server = TCPSocket.new('eaccess.play.net', 7900)
                  }
                  300.times {
                     sleep 0.1
                     break unless connect_thread.status
                  }
                  if connect_thread.status
                     connect_thread.kill rescue nil
                     msgbox.call "error: timed out connecting to eaccess.play.net:7900"
                  end
               rescue
                  msgbox.call "error connecting to server: #{$!}"
                  connect_button.sensitive = true
                  user_id_entry.sensitive = true
                  pass_entry.sensitive = true
               end
               disconnect_button.sensitive = true
               if login_server
                  login_server.puts "K\n"
                  hashkey = login_server.gets
                  if 'test'[0].class == String
                     password = pass_entry.text.split('').collect { |c| c.getbyte(0) }
                     hashkey = hashkey.split('').collect { |c| c.getbyte(0) }
                  else
                     password = pass_entry.text.split('').collect { |c| c[0] }
                     hashkey = hashkey.split('').collect { |c| c[0] }
                  end
                  # pass_entry.text = String.new
                  password.each_index { |i| password[i] = ((password[i]-32)^hashkey[i])+32 }
                  password = password.collect { |c| c.chr }.join
                  login_server.puts "A\t#{user_id_entry.text}\t#{password}\n"
                  password = nil
                  response = login_server.gets
                  login_key = /KEY\t([^\t]+)\t/.match(response).captures.first
                  if login_key
                     login_server.puts "M\n"
                     response = login_server.gets
                     if response =~ /^M\t/
                        liststore.clear
                        for game in response.sub(/^M\t/, '').scan(/[^\t]+\t[^\t^\n]+/)
                           game_code, game_name = game.split("\t")
                           login_server.puts "N\t#{game_code}\n"
                           if login_server.gets =~ /STORM/
                              login_server.puts "F\t#{game_code}\n"
                              if login_server.gets =~ /NORMAL|PREMIUM|TRIAL|INTERNAL|FREE/
                                 login_server.puts "G\t#{game_code}\n"
                                 login_server.gets
                                 login_server.puts "P\t#{game_code}\n"
                                 login_server.gets
                                 login_server.puts "C\n"
                                 for code_name in login_server.gets.sub(/^C\t[0-9]+\t[0-9]+\t[0-9]+\t[0-9]+[\t\n]/, '').scan(/[^\t]+\t[^\t^\n]+/)
                                    char_code, char_name = code_name.split("\t")
                                    iter = liststore.append
                                    iter[0] = game_code
                                    iter[1] = game_name
                                    iter[2] = char_code
                                    iter[3] = char_name
                                 end
                              end
                           end
                        end
                        disconnect_button.sensitive = true
                     else
                        login_server.close unless login_server.closed?
                        msgbox.call "Unrecognized response from server (#{response})"
                     end
                  else
                     login_server.close unless login_server.closed?
                     disconnect_button.sensitive = false
                     connect_button.sensitive = true
                     user_id_entry.sensitive = true
                     pass_entry.sensitive = true
                     msgbox.call "Something went wrong... probably invalid user id and/or password.\nserver response: #{response}"
                  end
               end
            }
         }
         treeview.signal_connect('cursor-changed') {
            if login_server
               play_button.sensitive = true
            end
         }
         disconnect_button.signal_connect('clicked') {
            disconnect_button.sensitive = false
            play_button.sensitive = false
            liststore.clear
            login_server.close unless login_server.closed?
            connect_button.sensitive = true
            user_id_entry.sensitive = true
            pass_entry.sensitive = true
         }
         play_button.signal_connect('clicked') {
            play_button.sensitive = false
            game_code = treeview.selection.selected[0]
            char_code = treeview.selection.selected[2]
            if login_server and not login_server.closed?
               login_server.puts "F\t#{game_code}\n"
               login_server.gets
               login_server.puts "G\t#{game_code}\n"
               login_server.gets
               login_server.puts "P\t#{game_code}\n"
               login_server.gets
               login_server.puts "C\n"
               login_server.gets
               login_server.puts "L\t#{char_code}\tSTORM\n"
               response = login_server.gets
               if response =~ /^L\t/
                  login_server.close unless login_server.closed?
                  port = /GAMEPORT=([0-9]+)/.match(response).captures.first
                  host = /GAMEHOST=([^\t\n]+)/.match(response).captures.first
                  key = /KEY=([^\t\n]+)/.match(response).captures.first
                  launch_data = response.sub(/^L\tOK\t/, '').split("\t")
                  login_server.close unless login_server.closed?
                  if wizard_option.active?
                     launch_data.collect! { |line| line.sub(/GAMEFILE=.+/, "GAMEFILE=WIZARD.EXE").sub(/GAME=.+/, "GAME=WIZ") }
                  elsif avalon_option.active?
                     launch_data.collect! { |line| line.sub(/GAME=.+/, "GAME=AVALON") }
                  elsif suks_option.active?
                     launch_data.collect! { |line| line.sub(/GAMEFILE=.+/, "GAMEFILE=WIZARD.EXE").sub(/GAME=.+/, "GAME=SUKS") }
                  end
                  if custom_launch_option.active?
                     launch_data.push "CUSTOMLAUNCH=#{custom_launch_entry.child.text}"
                     unless custom_launch_dir.child.text.empty? or custom_launch_dir.child.text == "(enter working directory for command)"
                        launch_data.push "CUSTOMLAUNCHDIR=#{custom_launch_dir.child.text}"
                     end
                  end
                  if make_quick_option.active?
                     if wizard_option.active?
                        frontend = 'wizard'
                     elsif stormfront_option.active?
                        frontend = 'stormfront'
                     elsif avalon_option.active?
                        frontend = 'avalon'
                     else
                        frontend = 'unkown'
                     end
                     if custom_launch_option.active?
                        custom_launch = custom_launch_entry.child.text
                        if custom_launch_dir.child.text.empty? or custom_launch_dir.child.text == "(enter working directory for command)"
                           custom_launch_dir = nil
                        else
                           custom_launch_dir = custom_launch_dir.child.text
                        end
                     else
                        custom_launch = nil
                        custom_launch_dir = nil
                     end
                     entry_data.push h={ :char_name => treeview.selection.selected[3], :game_code => treeview.selection.selected[0], :game_name => treeview.selection.selected[1], :user_id => user_id_entry.text, :password => pass_entry.text, :frontend => frontend, :custom_launch => custom_launch, :custom_launch_dir => custom_launch_dir }
                     save_entry_data = true
                  end
                  user_id_entry.text = String.new
                  pass_entry.text = String.new
                  window.destroy
                  done = true
               else
                  login_server.close unless login_server.closed?
                  disconnect_button.sensitive = false
                  play_button.sensitive = false
                  connect_button.sensitive = true
                  user_id_entry.sensitive = true
                  pass_entry.sensitive = true
               end
            else
               disconnect_button.sensitive = false
               play_button.sensitive = false
               connect_button.sensitive = true
               user_id_entry.sensitive = true
               pass_entry.sensitive = true
            end
         }
         user_id_entry.signal_connect('activate') {
            pass_entry.grab_focus
         }
         pass_entry.signal_connect('activate') {
            connect_button.clicked
         }

         #
         # link tab
         #

         link_to_web_button = Gtk::Button.new('Link to Website')
         unlink_from_web_button = Gtk::Button.new('Unlink from Website')
         web_button_box = Gtk::HBox.new
         web_button_box.pack_start(link_to_web_button, true, true, 5)
         web_button_box.pack_start(unlink_from_web_button, true, true, 5)
         
         web_order_label = Gtk::Label.new
         web_order_label.text = "Unknown"

         web_box = Gtk::VBox.new
         web_box.pack_start(web_order_label, true, true, 5)
         web_box.pack_start(web_button_box, true, true, 5)

         web_frame = Gtk::Frame.new('Website Launch Chain')
         web_frame.add(web_box)

         link_to_sge_button = Gtk::Button.new('Link to SGE')
         unlink_from_sge_button = Gtk::Button.new('Unlink from SGE')
         sge_button_box = Gtk::HBox.new
         sge_button_box.pack_start(link_to_sge_button, true, true, 5)
         sge_button_box.pack_start(unlink_from_sge_button, true, true, 5)
         
         sge_order_label = Gtk::Label.new
         sge_order_label.text = "Unknown"

         sge_box = Gtk::VBox.new
         sge_box.pack_start(sge_order_label, true, true, 5)
         sge_box.pack_start(sge_button_box, true, true, 5)

         sge_frame = Gtk::Frame.new('SGE Launch Chain')
         sge_frame.add(sge_box)


         refresh_button = Gtk::Button.new(' Refresh ')

         refresh_box = Gtk::HBox.new
         refresh_box.pack_end(refresh_button, false, false, 5)

         install_tab = Gtk::VBox.new
         install_tab.border_width = 5
         install_tab.pack_start(web_frame, false, false, 5)
         install_tab.pack_start(sge_frame, false, false, 5)
         install_tab.pack_start(refresh_box, false, false, 5)

         refresh_button.signal_connect('clicked') {
            install_tab_loaded = true
            if defined?(Win32)
               begin
                  key = Win32.RegOpenKeyEx(:hKey => Win32::HKEY_LOCAL_MACHINE, :lpSubKey => 'Software\\Classes\\Simutronics.Autolaunch\\Shell\\Open\\command', :samDesired => (Win32::KEY_ALL_ACCESS|Win32::KEY_WOW64_32KEY))[:phkResult]
                  web_launch_cmd = Win32.RegQueryValueEx(:hKey => key)[:lpData]
                  real_web_launch_cmd = Win32.RegQueryValueEx(:hKey => key, :lpValueName => 'RealCommand')[:lpData]
               rescue
                  web_launch_cmd = String.new
                  real_web_launch_cmd = String.new
               ensure
                  Win32.RegCloseKey(:hKey => key) rescue nil
               end
               begin
                  key = Win32.RegOpenKeyEx(:hKey => Win32::HKEY_LOCAL_MACHINE, :lpSubKey => 'Software\\Simutronics\\Launcher', :samDesired => (Win32::KEY_ALL_ACCESS|Win32::KEY_WOW64_32KEY))[:phkResult]
                  sge_launch_cmd = Win32.RegQueryValueEx(:hKey => key, :lpValueName => 'Directory')[:lpData]
                  real_sge_launch_cmd = Win32.RegQueryValueEx(:hKey => key, :lpValueName => 'RealDirectory')[:lpData]
               rescue
                  sge_launch_cmd = String.new
                  real_launch_cmd = String.new
               ensure
                  Win32.RegCloseKey(:hKey => key) rescue nil
               end
            elsif defined?(Wine)
               web_launch_cmd = Wine.registry_gets('HKEY_LOCAL_MACHINE\\Software\\Classes\\Simutronics.Autolaunch\\Shell\\Open\\command\\').to_s
               real_web_launch_cmd = Wine.registry_gets('HKEY_LOCAL_MACHINE\\Software\\Classes\\Simutronics.Autolaunch\\Shell\\Open\\command\\RealCommand').to_s
               sge_launch_cmd = Wine.registry_gets('HKEY_LOCAL_MACHINE\\Software\\Simutronics\\Launcher\\Directory').to_s
               real_sge_launch_cmd = Wine.registry_gets('HKEY_LOCAL_MACHINE\\Software\\Simutronics\\Launcher\\RealDirectory').to_s
            else
               web_launch_cmd = String.new
               sge_launch_cmd = String.new
            end
            if web_launch_cmd =~ /lich/i
               link_to_web_button.sensitive = false
               unlink_from_web_button.sensitive = true
               if real_web_launch_cmd =~ /launcher.exe/i
                  web_order_label.text = "Website => Lich => Simu Launcher => Frontend"
               else
                  web_order_label.text = "Website => Lich => Unknown"
               end
            elsif web_launch_cmd =~ /launcher.exe/i
               web_order_label.text = "Website => Simu Launcher => Frontend"
               link_to_web_button.sensitive = true
               unlink_from_web_button.sensitive = false
            else
               web_order_label.text = "Website => Unknown"
               link_to_web_button.sensitive = false
               unlink_from_web_button.sensitive = false
            end
            if sge_launch_cmd =~ /lich/i
               link_to_sge_button.sensitive = false
               unlink_from_sge_button.sensitive = true
               if real_sge_launch_cmd and (defined?(Wine) or File.exists?("#{real_sge_launch_cmd}\\launcher.exe"))
                  sge_order_label.text = "SGE => Lich => Simu Launcher => Frontend"
               else
                  sge_order_label.text = "SGE => Lich => Unknown"
               end
            elsif sge_launch_cmd and (defined?(Wine) or File.exists?("#{sge_launch_cmd}\\launcher.exe"))
               sge_order_label.text = "SGE => Simu Launcher => Frontend"
               link_to_sge_button.sensitive = true
               unlink_from_sge_button.sensitive = false
            else
               sge_order_label.text = "SGE => Unknown"
               link_to_sge_button.sensitive = false
               unlink_from_sge_button.sensitive = false
            end
         }
         link_to_web_button.signal_connect('clicked') {
            link_to_web_button.sensitive = false
            Lich.link_to_sal
            if defined?(Win32)
               refresh_button.clicked
            else
               Lich.msgbox(:message => 'WINE will take 5-30 seconds to update the registry.  Wait a while and click the refresh button.')
            end
         }
         unlink_from_web_button.signal_connect('clicked') {
            unlink_from_web_button.sensitive = false
            Lich.unlink_from_sal
            if defined?(Win32)
               refresh_button.clicked
            else
               Lich.msgbox(:message => 'WINE will take 5-30 seconds to update the registry.  Wait a while and click the refresh button.')
            end
         }
         link_to_sge_button.signal_connect('clicked') {
            link_to_sge_button.sensitive = false
            Lich.link_to_sge
            if defined?(Win32)
               refresh_button.clicked
            else
               Lich.msgbox(:message => 'WINE will take 5-30 seconds to update the registry.  Wait a while and click the refresh button.')
            end
         }
         unlink_from_sge_button.signal_connect('clicked') {
            unlink_from_sge_button.sensitive = false
            Lich.unlink_from_sge
            if defined?(Win32)
               refresh_button.clicked
            else
               Lich.msgbox(:message => 'WINE will take 5-30 seconds to update the registry.  Wait a while and click the refresh button.')
            end
         }

=begin
         #
         # options tab
         #

         lich_char_label = Gtk::Label.new('Lich char:')
         lich_char_label.xalign = 1
         lich_char_entry = Gtk::Entry.new
         lich_char_entry.text = ';' # fixme LichSettings['lich_char'].to_s
         lich_box = Gtk::HBox.new
         lich_box.pack_end(lich_char_entry, true, true, 5)
         lich_box.pack_end(lich_char_label, true, true, 5)

         cache_serverbuffer_button = Gtk::CheckButton.new('Cache to disk')
         cache_serverbuffer_button.active = LichSettings['cache_serverbuffer']

         serverbuffer_max_label = Gtk::Label.new('Maximum lines in memory:')
         serverbuffer_max_entry = Gtk::Entry.new
         serverbuffer_max_entry.text = LichSettings['serverbuffer_max_size'].to_s
         serverbuffer_min_label = Gtk::Label.new('Minumum lines in memory:')
         serverbuffer_min_entry = Gtk::Entry.new
         serverbuffer_min_entry.text = LichSettings['serverbuffer_min_size'].to_s
         serverbuffer_min_entry.sensitive = cache_serverbuffer_button.active?

         serverbuffer_table = Gtk::Table.new(2, 2, false)
         serverbuffer_table.attach(serverbuffer_max_label, 0, 1, 0, 1, Gtk::EXPAND|Gtk::FILL, Gtk::EXPAND|Gtk::FILL, 5, 5)
         serverbuffer_table.attach(serverbuffer_max_entry, 1, 2, 0, 1, Gtk::EXPAND|Gtk::FILL, Gtk::EXPAND|Gtk::FILL, 5, 5)
         serverbuffer_table.attach(serverbuffer_min_label, 0, 1, 1, 2, Gtk::EXPAND|Gtk::FILL, Gtk::EXPAND|Gtk::FILL, 5, 5)
         serverbuffer_table.attach(serverbuffer_min_entry, 1, 2, 1, 2, Gtk::EXPAND|Gtk::FILL, Gtk::EXPAND|Gtk::FILL, 5, 5)

         serverbuffer_box = Gtk::VBox.new
         serverbuffer_box.pack_start(cache_serverbuffer_button, false, false, 5)
         serverbuffer_box.pack_start(serverbuffer_table, false, false, 5)

         serverbuffer_frame = Gtk::Frame.new('Server Buffer')
         serverbuffer_frame.add(serverbuffer_box)

         cache_clientbuffer_button = Gtk::CheckButton.new('Cache to disk')
         cache_clientbuffer_button.active = LichSettings['cache_clientbuffer']

         clientbuffer_max_label = Gtk::Label.new('Maximum lines in memory:')
         clientbuffer_max_entry = Gtk::Entry.new
         clientbuffer_max_entry.text = LichSettings['clientbuffer_max_size'].to_s
         clientbuffer_min_label = Gtk::Label.new('Minumum lines in memory:')
         clientbuffer_min_entry = Gtk::Entry.new
         clientbuffer_min_entry.text = LichSettings['clientbuffer_min_size'].to_s
         clientbuffer_min_entry.sensitive = cache_clientbuffer_button.active?

         clientbuffer_table = Gtk::Table.new(2, 2, false)
         clientbuffer_table.attach(clientbuffer_max_label, 0, 1, 0, 1, Gtk::EXPAND|Gtk::FILL, Gtk::EXPAND|Gtk::FILL, 5, 5)
         clientbuffer_table.attach(clientbuffer_max_entry, 1, 2, 0, 1, Gtk::EXPAND|Gtk::FILL, Gtk::EXPAND|Gtk::FILL, 5, 5)
         clientbuffer_table.attach(clientbuffer_min_label, 0, 1, 1, 2, Gtk::EXPAND|Gtk::FILL, Gtk::EXPAND|Gtk::FILL, 5, 5)
         clientbuffer_table.attach(clientbuffer_min_entry, 1, 2, 1, 2, Gtk::EXPAND|Gtk::FILL, Gtk::EXPAND|Gtk::FILL, 5, 5)

         clientbuffer_box = Gtk::VBox.new
         clientbuffer_box.pack_start(cache_clientbuffer_button, false, false, 5)
         clientbuffer_box.pack_start(clientbuffer_table, false, false, 5)

         clientbuffer_frame = Gtk::Frame.new('Client Buffer')
         clientbuffer_frame.add(clientbuffer_box)

         save_button = Gtk::Button.new(' Save ')
         save_button.sensitive = false

         save_button_box = Gtk::HBox.new
         save_button_box.pack_end(save_button, false, false, 5)

         options_tab = Gtk::VBox.new
         options_tab.border_width = 5
         options_tab.pack_start(lich_box, false, false, 5)
         options_tab.pack_start(serverbuffer_frame, false, false, 5)
         options_tab.pack_start(clientbuffer_frame, false, false, 5)
         options_tab.pack_start(save_button_box, false, false, 5)

         check_changed = proc {
            Gtk.queue {
               if (LichSettings['lich_char'] == lich_char_entry.text) and (LichSettings['cache_serverbuffer'] == cache_serverbuffer_button.active?) and (LichSettings['serverbuffer_max_size'] == serverbuffer_max_entry.text.to_i) and (LichSettings['serverbuffer_min_size'] == serverbuffer_min_entry.text.to_i) and (LichSettings['cache_clientbuffer'] == cache_clientbuffer_button.active?) and (LichSettings['clientbuffer_max_size'] == clientbuffer_max_entry.text.to_i) and (LichSettings['clientbuffer_min_size'] == clientbuffer_min_entry.text.to_i)
                  save_button.sensitive = false
               else
                  save_button.sensitive = true
               end
            }
         }

         lich_char_entry.signal_connect('key-press-event') {
            check_changed.call
            false
         }
         serverbuffer_max_entry.signal_connect('key-press-event') {
            check_changed.call
            false
         }
         serverbuffer_min_entry.signal_connect('key-press-event') {
            check_changed.call
            false
         }
         clientbuffer_max_entry.signal_connect('key-press-event') {
            check_changed.call
            false
         }
         clientbuffer_min_entry.signal_connect('key-press-event') {
            check_changed.call
            false
         }
         cache_serverbuffer_button.signal_connect('clicked') {
            serverbuffer_min_entry.sensitive = cache_serverbuffer_button.active?
            check_changed.call
         }
         cache_clientbuffer_button.signal_connect('clicked') {
            clientbuffer_min_entry.sensitive = cache_clientbuffer_button.active?
            check_changed.call
         }
         save_button.signal_connect('clicked') {
            LichSettings['lich_char']             = lich_char_entry.text
            LichSettings['cache_serverbuffer']    = cache_serverbuffer_button.active?
            LichSettings['serverbuffer_max_size'] = serverbuffer_max_entry.text.to_i
            LichSettings['serverbuffer_min_size'] = serverbuffer_min_entry.text.to_i
            LichSettings['cache_clientbuffer']    = cache_clientbuffer_button.active?
            LichSettings['clientbuffer_max_size'] = clientbuffer_max_entry.text.to_i
            LichSettings['clientbuffer_min_size'] = clientbuffer_min_entry.text.to_i
            LichSettings.save
            save_button.sensitive = false
         }
=end

         #
         # put it together and show the window
         #

         notebook = Gtk::Notebook.new
         notebook.append_page(quick_game_entry_tab, Gtk::Label.new('Quick Game Entry'))
         notebook.append_page(game_entry_tab, Gtk::Label.new('Game Entry'))
         notebook.append_page(install_tab, Gtk::Label.new('Link'))
#         notebook.append_page(options_tab, Gtk::Label.new('Options'))
         notebook.signal_connect('switch-page') { |who,page,page_num|
            if (page_num == 2) and not install_tab_loaded
               refresh_button.clicked
=begin
            elsif (page_num == 1) and not checked_frontends
               checked_frontends = true
               found_profanity = File.exists?("#{LICH_DIR}/profanity.rb")
               if defined?(Win32)
                  begin
                     key = Win32.RegOpenKeyEx(:hKey => Win32::HKEY_LOCAL_MACHINE, :lpSubKey => 'Software\\Simutronics\\STORM32', :samDesired => (Win32::KEY_ALL_ACCESS|Win32::KEY_WOW64_32KEY))[:phkResult]
                     stormfront_dir = Win32.RegQueryValueEx(:hKey => key, :lpValueName => 'Directory')[:lpData]
                  rescue
                     stormfront_dir = nil
                  ensure
                     Win32.RegCloseKey(:hKey => key) rescue nil
                  end
                  begin
                     key = Win32.RegOpenKeyEx(:hKey => Win32::HKEY_LOCAL_MACHINE, :lpSubKey => 'Software\\Simutronics\\WIZ32', :samDesired => (Win32::KEY_ALL_ACCESS|Win32::KEY_WOW64_32KEY))[:phkResult]
                     wizard_dir = Win32.RegQueryValueEx(:hKey => key, :lpValueName => 'Directory')[:lpData]
                  rescue
                     wizard_dir = nil
                  ensure
                     Win32.RegCloseKey(:hKey => key) rescue nil
                  end
               elsif defined?(Wine)
                  stormfront_dir = Wine.registry_gets('HKEY_LOCAL_MACHINE\\Software\\Simutronics\\STORM32\\Directory').gsub("\\", "/")
                  wizard_dir = Wine.registry_gets('HKEY_LOCAL_MACHINE\\Software\\Simutronics\\WIZ32\\Directory').gsub("\\", "/")
               else
                  stormfront_dir = nil
                  wizard_dir = nil
               end
               Lich.log "wizard_dir: #{wizard_dir}"
               Lich.log "stormfront_dir: #{stormfront_dir}"
               unless File.exists?("#{stormfront_dir}\\Stormfront.exe")
                  Lich.log "stormfront doesn't exist"
                  stormfront_dir = nil
               end
               unless File.exists?("#{wizard_dir}\\Wizard.Exe")
                  Lich.log "wizard doesn't exist"
                  wizard_dir = nil
               end
=end
            end
         }

         window = Gtk::Window.new
         window.title = "Lich v#{LICH_VERSION}"
         window.border_width = 5
         window.add(notebook)
         window.signal_connect('delete_event') { window.destroy; done = true }
         window.default_width = 400

         window.show_all

         custom_launch_entry.visible = false
         custom_launch_dir.visible = false

         notebook.set_page(1) if entry_data.empty?
      }

      wait_until { done }

      if save_entry_data
         File.open("#{DATA_DIR}/entry.dat", 'w') { |file|
            file.write([Marshal.dump(entry_data)].pack('m'))
         }
      end
      entry_data = nil

      unless launch_data
         Gtk.queue { Gtk.main_quit }
         Thread.kill
      end
   end
   $_SERVERBUFFER_ = LimitedArray.new
   $_SERVERBUFFER_.max_size = 400
   $_CLIENTBUFFER_ = LimitedArray.new
   $_CLIENTBUFFER_.max_size = 100

   Socket.do_not_reverse_lookup = true

   #
   # open the client and have it connect to us
   #
   if argv_options[:sal]
      begin
         launch_data = File.open(argv_options[:sal]) { |file| file.readlines }.collect { |line| line.chomp }
      rescue
         $stdout.puts "error: failed to read launch_file: #{$!}"
         Lich.log "info: launch_file: #{argv_options[:sal]}"
         Lich.log "error: failed to read launch_file: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
         exit
      end
   end
   if launch_data
      unless gamecode = launch_data.find { |line| line =~ /GAMECODE=/ }
         $stdout.puts "error: launch_data contains no GAMECODE info"
         Lich.log "error: launch_data contains no GAMECODE info"
         exit(1)
      end
      unless gameport = launch_data.find { |line| line =~ /GAMEPORT=/ }
         $stdout.puts "error: launch_data contains no GAMEPORT info"
         Lich.log "error: launch_data contains no GAMEPORT info"
         exit(1)
      end
      unless gamehost = launch_data.find { |opt| opt =~ /GAMEHOST=/ }
         $stdout.puts "error: launch_data contains no GAMEHOST info"
         Lich.log "error: launch_data contains no GAMEHOST info"
         exit(1)
      end
      unless game = launch_data.find { |opt| opt =~ /GAME=/ }
         $stdout.puts "error: launch_data contains no GAME info"
         Lich.log "error: launch_data contains no GAME info"
         exit(1)
      end
      if custom_launch = launch_data.find { |opt| opt =~ /CUSTOMLAUNCH=/ }
         custom_launch.sub!(/^.*?\=/, '')
         Lich.log "info: using custom launch command: #{custom_launch}"
      end
      if custom_launch_dir = launch_data.find { |opt| opt =~ /CUSTOMLAUNCHDIR=/ }
         custom_launch_dir.sub!(/^.*?\=/, '')
         Lich.log "info: using working directory for custom launch command: #{custom_launch_dir}"
      end
      if ARGV.include?('--without-frontend')
         $frontend = 'unknown'
         unless (game_key = launch_data.find { |opt| opt =~ /KEY=/ }) && (game_key = game_key.split('=').last.chomp)
            $stdout.puts "error: launch_data contains no KEY info"
            Lich.log "error: launch_data contains no KEY info"
            exit(1)
         end
      elsif game =~ /SUKS/i
         $frontend = 'suks'
         unless (game_key = launch_data.find { |opt| opt =~ /KEY=/ }) && (game_key = game_key.split('=').last.chomp)
            $stdout.puts "error: launch_data contains no KEY info"
            Lich.log "error: launch_data contains no KEY info"
            exit(1)
         end
      elsif game =~ /AVALON/i
         launcher_cmd = "open -n -b Avalon \"%1\""
      elsif custom_launch
         unless (game_key = launch_data.find { |opt| opt =~ /KEY=/ }) && (game_key = game_key.split('=').last.chomp)
            $stdout.puts "error: launch_data contains no KEY info"
            Lich.log "error: launch_data contains no KEY info"
            exit(1)
         end
      else
         unless launcher_cmd = Lich.get_simu_launcher
            $stdout.puts 'error: failed to find the Simutronics launcher'
            Lich.log 'error: failed to find the Simutronics launcher'
            exit(1)
         end
      end
      gamecode = gamecode.split('=').last
      gameport = gameport.split('=').last
      gamehost = gamehost.split('=').last
      game     = game.split('=').last

      if (gameport == '10121') or (gameport == '10124')
         $platinum = true
      else
         $platinum = false
      end
      Lich.log "info: gamehost: #{gamehost}"
      Lich.log "info: gameport: #{gameport}"
      Lich.log "info: game: #{game}"
      if ARGV.include?('--without-frontend')
         $_CLIENT_ = nil
      elsif $frontend == 'suks'
         nil
      else
         if game =~ /WIZ/i
            $frontend = 'wizard'
         elsif game =~ /STORM/i
            $frontend = 'stormfront'
         elsif game =~ /AVALON/i
            $frontend = 'avalon'
         else
            $frontend = 'unknown'
         end
         begin
            listener = TCPServer.new('127.0.0.1', nil)
         rescue
            $stdout.puts "--- error: cannot bind listen socket to local port: #{$!}"
            Lich.log "error: cannot bind listen socket to local port: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            exit(1)
         end
         accept_thread = Thread.new { $_CLIENT_ = SynchronizedSocket.new(listener.accept) }
         localport = listener.addr[1]
         if custom_launch
            sal_filename = nil
            launcher_cmd = custom_launch.sub(/\%port\%/, localport.to_s).sub(/\%key\%/, game_key.to_s)
            scrubbed_launcher_cmd = custom_launch.sub(/\%port\%/, localport.to_s).sub(/\%key\%/, '[scrubbed key]')
            Lich.log "info: launcher_cmd: #{scrubbed_launcher_cmd}"
         else
            if RUBY_PLATFORM =~ /darwin/i
               localhost = "127.0.0.1"
            else
               localhost = "localhost"
            end
            launch_data.collect! { |line| line.sub(/GAMEPORT=.+/, "GAMEPORT=#{localport}").sub(/GAMEHOST=.+/, "GAMEHOST=#{localhost}") }
            sal_filename = "#{TEMP_DIR}/lich#{rand(10000)}.sal"
            while File.exists?(sal_filename)
               sal_filename = "#{TEMP_DIR}/lich#{rand(10000)}.sal"
            end
            File.open(sal_filename, 'w') { |f| f.puts launch_data }
            launcher_cmd = launcher_cmd.sub('%1', sal_filename)
            launcher_cmd = launcher_cmd.tr('/', "\\") if (RUBY_PLATFORM =~ /mingw|win/i) and (RUBY_PLATFORM !~ /darwin/i)
         end
         begin
            if custom_launch_dir
               Dir.chdir(custom_launch_dir)
            end
            if defined?(Win32)
               launcher_cmd =~ /^"(.*?)"\s*(.*)$/
               dir_file = $1
               param = $2
               dir = dir_file.slice(/^.*[\\\/]/)
               file = dir_file.sub(/^.*[\\\/]/, '')
               if Lich.win32_launch_method and Lich.win32_launch_method =~ /^(\d+):(.+)$/
                  method_num = $1.to_i
                  if $2 == 'fail'
                     method_num = (method_num + 1) % 6 
                  end
               else
                  method_num = 5
               end
               if method_num == 5
                  begin
                     key = Win32.RegOpenKeyEx(:hKey => Win32::HKEY_LOCAL_MACHINE, :lpSubKey => 'Software\\Classes\\Simutronics.Autolaunch\\Shell\\Open\\command', :samDesired => (Win32::KEY_ALL_ACCESS|Win32::KEY_WOW64_32KEY))[:phkResult]
                     if Win32.RegQueryValueEx(:hKey => key)[:lpData] =~ /Launcher\.exe/i
                        associated = true
                     else
                        associated = false
                     end
                  rescue
                     associated = false
                  ensure
                     Win32.RegCloseKey(:hKey => key) rescue nil
                  end
                  unless associated
                     Lich.log "warning: skipping launch method #{method_num + 1} because .sal files are not associated with the Simutronics Launcher"
                     method_num = (method_num + 1) % 6 
                  end
               end
               Lich.win32_launch_method = "#{method_num}:fail"
               if method_num == 0
                  Lich.log "info: launcher_cmd: #{launcher_cmd}"
                  spawn launcher_cmd
               elsif method_num == 1
                  Lich.log "info: launcher_cmd: Win32.ShellExecute(:lpOperation => \"open\", :lpFile => #{file.inspect}, :lpDirectory => #{dir.inspect}, :lpParameters => #{param.inspect})"
                  Win32.ShellExecute(:lpOperation => 'open', :lpFile => file, :lpDirectory => dir, :lpParameters => param)
               elsif method_num == 2
                  Lich.log "info: launcher_cmd: Win32.ShellExecuteEx(:lpOperation => \"runas\", :lpFile => #{file.inspect}, :lpDirectory => #{dir.inspect}, :lpParameters => #{param.inspect})"
                  Win32.ShellExecuteEx(:lpOperation => 'runas', :lpFile => file, :lpDirectory => dir, :lpParameters => param)
               elsif method_num == 3
                  Lich.log "info: launcher_cmd: Win32.AdminShellExecute(:op => \"open\", :file => #{file.inspect}, :dir => #{dir.inspect}, :params => #{param.inspect})"
                  Win32.AdminShellExecute(:op => 'open', :file => file, :dir => dir, :params => param)
               elsif method_num == 4
                  Lich.log "info: launcher_cmd: Win32.AdminShellExecute(:op => \"runas\", :file => #{file.inspect}, :dir => #{dir.inspect}, :params => #{param.inspect})"
                  Win32.AdminShellExecute(:op => 'runas', :file => file, :dir => dir, :params => param)
               else # method_num == 5
                  file = File.expand_path(sal_filename).tr('/', "\\")
                  dir = File.expand_path(File.dirname(sal_filename)).tr('/', "\\")
                  Lich.log "info: launcher_cmd: Win32.ShellExecute(:lpOperation => \"open\", :lpFile => #{file.inspect}, :lpDirectory => #{dir.inspect})"
                  Win32.ShellExecute(:lpOperation => 'open', :lpFile => file, :lpDirectory => dir)
               end
            elsif defined?(Wine) and (game != 'AVALON')
               Lich.log "info: launcher_cmd: #{Wine::BIN} #{launcher_cmd}"
               spawn "#{Wine::BIN} #{launcher_cmd}"
            else
               Lich.log "info: launcher_cmd: #{launcher_cmd}"
               spawn launcher_cmd
            end
         rescue
            Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            Lich.msgbox(:message => "error: #{$!}", :icon => :error)
         end
         Lich.log 'info: waiting for client to connect...'
         300.times { sleep 0.1; break unless accept_thread.status }
         accept_thread.kill if accept_thread.status
         Dir.chdir(LICH_DIR)
         unless $_CLIENT_
            Lich.log "error: timeout waiting for client to connect"
            if defined?(Win32)
               Lich.msgbox(:message => "error: launch method #{method_num + 1} timed out waiting for the client to connect\n\nTry again and another method will be used.", :icon => :error)
            else
               Lich.msgbox(:message => "error: timeout waiting for client to connect", :icon => :error)
            end
            if sal_filename
               File.delete(sal_filename) rescue()
            end
            listener.close rescue()
            $_CLIENT_.close rescue()
            reconnect_if_wanted.call
            Lich.log "info: exiting..."
            Gtk.queue { Gtk.main_quit } if defined?(Gtk)
            exit
         end
         if defined?(Win32)
            Lich.win32_launch_method = "#{method_num}:success"
         end
         Lich.log 'info: connected'
         listener.close rescue nil
         if sal_filename
            File.delete(sal_filename) rescue nil
         end
      end
      gamehost, gameport = Lich.fix_game_host_port(gamehost, gameport)
      Lich.log "info: connecting to game server (#{gamehost}:#{gameport})"
      begin
         connect_thread = Thread.new {
            Game.open(gamehost, gameport)
         }
         300.times {
            sleep 0.1
            break unless connect_thread.status
         }
         if connect_thread.status
            connect_thread.kill rescue nil
            raise "error: timed out connecting to #{gamehost}:#{gameport}"
         end
      rescue
         Lich.log "error: #{$!}"
         gamehost, gameport = Lich.break_game_host_port(gamehost, gameport)
         Lich.log "info: connecting to game server (#{gamehost}:#{gameport})"
         begin
            connect_thread = Thread.new {
               Game.open(gamehost, gameport)
            }
            300.times {
               sleep 0.1
               break unless connect_thread.status
            }
            if connect_thread.status
               connect_thread.kill rescue nil
               raise "error: timed out connecting to #{gamehost}:#{gameport}"
            end
         rescue
            Lich.log "error: #{$!}"
            $_CLIENT_.close rescue nil
            reconnect_if_wanted.call
            Lich.log "info: exiting..."
            Gtk.queue { Gtk.main_quit } if defined?(Gtk)
            exit
         end
      end
      Lich.log 'info: connected'
   elsif game_host and game_port
      unless Lich.hosts_file
         Lich.log "error: cannot find hosts file"
         $stdout.puts "error: cannot find hosts file"
         exit
      end
      game_quad_ip = IPSocket.getaddress(game_host)
      error_count = 0
      begin
         listener = TCPServer.new('127.0.0.1', game_port)
         begin
            listener.setsockopt(Socket::SOL_SOCKET,Socket::SO_REUSEADDR,1)
         rescue
            Lich.log "warning: setsockopt with SO_REUSEADDR failed: #{$!}"
         end
      rescue
         sleep 1
         if (error_count += 1) >= 30
            $stdout.puts 'error: failed to bind to the proper port'
            Lich.log 'error: failed to bind to the proper port'
            exit!
         else
            retry
         end
      end
      Lich.modify_hosts(game_host)

      $stdout.puts "Pretending to be #{game_host}"
      $stdout.puts "Listening on port #{game_port}"
      $stdout.puts "Waiting for the client to connect..."
      Lich.log "info: pretending to be #{game_host}"
      Lich.log "info: listening on port #{game_port}"
      Lich.log "info: waiting for the client to connect..."

      timeout_thread = Thread.new {
         sleep 120
         listener.close rescue nil
         $stdout.puts 'error: timed out waiting for client to connect'
         Lich.log 'error: timed out waiting for client to connect'
         Lich.restore_hosts
         exit
      }
#      $_CLIENT_ = listener.accept
      $_CLIENT_ = SynchronizedSocket.new(listener.accept)
      listener.close rescue nil
      timeout_thread.kill
      $stdout.puts "Connection with the local game client is open."
      Lich.log "info: connection with the game client is open"
      Lich.restore_hosts
      if test_mode
         $_SERVER_ = $stdin # fixme
         $_CLIENT_.puts "Running in test mode: host socket set to stdin."
      else
         Lich.log 'info: connecting to the real game host...'
         game_host, game_port = Lich.fix_game_host_port(game_host, game_port)
         begin
            timeout_thread = Thread.new {
               sleep 30
               Lich.log "error: timed out connecting to #{game_host}:#{game_port}"
               $stdout.puts "error: timed out connecting to #{game_host}:#{game_port}"
               exit
            }
            begin
               Game.open(game_host, game_port)
            rescue
               Lich.log "error: #{$!}"
               $stdout.puts "error: #{$!}"
               exit
            end
            timeout_thread.kill rescue nil
            Lich.log 'info: connection with the game host is open'
         end
      end
   else
      # offline mode removed
      Lich.log "error: don't know what to do"
      exit
   end

   listener = timeout_thr = nil

   #
   # drop superuser privileges
   #
   unless (RUBY_PLATFORM =~ /mingw|win/i) and (RUBY_PLATFORM !~ /darwin/i)
      Lich.log "info: dropping superuser privileges..."
      begin
         Process.uid = `id -ru`.strip.to_i
         Process.gid = `id -rg`.strip.to_i
         Process.egid = `id -rg`.strip.to_i
         Process.euid = `id -ru`.strip.to_i
      rescue SecurityError
         Lich.log "error: failed to drop superuser privileges: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
      rescue SystemCallError
         Lich.log "error: failed to drop superuser privileges: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
      rescue
         Lich.log "error: failed to drop superuser privileges: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
      end
   end

   # backward compatibility
   if $frontend =~ /^(?:wizard|avalon)$/
      $fake_stormfront = true
   else
      $fake_stormfront = false
   end

   undef :exit!

   if ARGV.include?('--without-frontend')
      Thread.new {
         client_thread = nil
         #
         # send the login key
         #
         Game._puts(game_key)
         game_key = nil
         #
         # send version string
         #
         client_string = "/FE:WIZARD /VERSION:1.0.1.22 /P:#{RUBY_PLATFORM} /XML"
         $_CLIENTBUFFER_.push(client_string.dup)
         Game._puts(client_string)
         #
         # tell the server we're ready
         #
         2.times {
            sleep 0.3
            $_CLIENTBUFFER_.push("<c>\r\n")
            Game._puts("<c>")
         }
         $login_time = Time.now
      }
   else
      #
      # shutdown listening socket
      #
      error_count = 0
      begin
         # Somehow... for some ridiculous reason... Windows doesn't let us close the socket if we shut it down first...
         # listener.shutdown
         listener.close unless listener.closed?
      rescue
         Lich.log "warning: failed to close listener socket: #{$!}"
         if (error_count += 1) > 20
            Lich.log 'warning: giving up...'
         else
            sleep 0.05
            retry
         end
      end

      $stdout = $_CLIENT_
      $_CLIENT_.sync = true

      client_thread = Thread.new {
         $login_time = Time.now

         if $offline_mode
            nil
         elsif $frontend =~ /^(?:wizard|avalon)$/
            #
            # send the login key
            #
            client_string = $_CLIENT_.gets
            Game._puts(client_string)
            #
            # take the version string from the client, ignore it, and ask the server for xml
            #
            $_CLIENT_.gets
            client_string = "/FE:STORMFRONT /VERSION:1.0.1.26 /P:#{RUBY_PLATFORM} /XML"
            $_CLIENTBUFFER_.push(client_string.dup)
            Game._puts(client_string)
            #
            # tell the server we're ready
            #
            2.times {
               sleep 0.3
               $_CLIENTBUFFER_.push("#{$cmd_prefix}\r\n")
               Game._puts($cmd_prefix)
            }
            #
            # set up some stuff
            #
            for client_string in [ "#{$cmd_prefix}_injury 2", "#{$cmd_prefix}_flag Display Inventory Boxes 1", "#{$cmd_prefix}_flag Display Dialog Boxes 0" ]
               $_CLIENTBUFFER_.push(client_string)
               Game._puts(client_string)
            end
            #
            # client wants to send "GOOD", xml server won't recognize it
            #
            $_CLIENT_.gets
         else
            inv_off_proc = proc { |server_string|
               if server_string =~ /^<(?:container|clearContainer|exposeContainer)/
                  server_string.gsub!(/<(?:container|clearContainer|exposeContainer)[^>]*>|<inv.+\/inv>/, '')
                  if server_string.empty?
                     nil
                  else
                     server_string
                  end
               elsif server_string =~ /^<flag id="Display Inventory Boxes" status='on' desc="Display all inventory and container windows."\/>/
                  server_string.sub("status='on'", "status='off'")
               elsif server_string =~ /^\s*<d cmd="flag Inventory off">Inventory<\/d>\s+ON/
                  server_string.sub("flag Inventory off", "flag Inventory on").sub('ON', 'OFF')
               else
                  server_string
               end
            }
            DownstreamHook.add('inventory_boxes_off', inv_off_proc)
            inv_toggle_proc = proc { |client_string|
               if client_string =~ /^(?:<c>)?_flag Display Inventory Boxes ([01])/
                  if $1 == '1'
                     DownstreamHook.remove('inventory_boxes_off')
                     Lich.set_inventory_boxes(XMLData.player_id, true)
                  else
                     DownstreamHook.add('inventory_boxes_off', inv_off_proc)
                     Lich.set_inventory_boxes(XMLData.player_id, false)
                  end
                  nil
               elsif client_string =~ /^(?:<c>)?\s*(?:set|flag)\s+inv(?:e|en|ent|ento|entor|entory)?\s+(on|off)/i
                  if $1.downcase == 'on'
                     DownstreamHook.remove('inventory_boxes_off')
                     respond 'You have enabled viewing of inventory and container windows.'
                     Lich.set_inventory_boxes(XMLData.player_id, true)
                  else
                     DownstreamHook.add('inventory_boxes_off', inv_off_proc)
                     respond 'You have disabled viewing of inventory and container windows.'
                     Lich.set_inventory_boxes(XMLData.player_id, false)
                  end
                  nil
               else
                  client_string
               end
            }
            UpstreamHook.add('inventory_boxes_toggle', inv_toggle_proc)

            unless $offline_mode
               client_string = $_CLIENT_.gets
               Game._puts(client_string)
               client_string = $_CLIENT_.gets
               $_CLIENTBUFFER_.push(client_string.dup)
               Game._puts(client_string)
            end
         end

         begin
            while client_string = $_CLIENT_.gets
               client_string = "#{$cmd_prefix}#{client_string}" if $frontend =~ /^(?:wizard|avalon)$/
               begin
                  $_IDLETIMESTAMP_ = Time.now
                  do_client(client_string)
               rescue
                  respond "--- Lich: error: client_thread: #{$!}"
                  respond $!.backtrace.first
                  Lich.log "error: client_thread: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
               end
            end
         rescue
            respond "--- Lich: error: client_thread: #{$!}"
            respond $!.backtrace.first
            Lich.log "error: client_thread: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            sleep 0.2
            retry unless $_CLIENT_.closed? or Game.closed? or !Game.thread.alive? or ($!.to_s =~ /invalid argument|A connection attempt failed|An existing connection was forcibly closed/i)
         end
         Game.close
      }
   end

   if detachable_client_port
      detachable_client_thread = Thread.new {
         loop {
            begin
               server = TCPServer.new('127.0.0.1', detachable_client_port)
               $_DETACHABLE_CLIENT_ = SynchronizedSocket.new(server.accept)
               $_DETACHABLE_CLIENT_.sync = true
            rescue
               Lich.log "#{$!}\n\t#{$!.backtrace.join("\n\t")}"
               server.close rescue nil
               $_DETACHABLE_CLIENT_.close rescue nil
               $_DETACHABLE_CLIENT_ = nil
               sleep 5
               next
            ensure
               server.close rescue nil
            end
            if $_DETACHABLE_CLIENT_
               begin
                  $frontend = 'profanity'
                  Thread.new {
                     100.times { sleep 0.1; break if XMLData.indicator['IconJOINED'] }
                     init_str = "<progressBar id='mana' value='0' text='mana #{XMLData.mana}/#{XMLData.max_mana}'/>"
                     init_str.concat "<progressBar id='health' value='0' text='health #{XMLData.health}/#{XMLData.max_health}'/>"
                     init_str.concat "<progressBar id='spirit' value='0' text='spirit #{XMLData.spirit}/#{XMLData.max_spirit}'/>"
                     init_str.concat "<progressBar id='stamina' value='0' text='stamina #{XMLData.stamina}/#{XMLData.max_stamina}'/>"
                     init_str.concat "<progressBar id='encumlevel' value='#{XMLData.encumbrance_value}' text='#{XMLData.encumbrance_text}'/>"
                     init_str.concat "<progressBar id='pbarStance' value='#{XMLData.stance_value}'/>"
                     init_str.concat "<progressBar id='mindState' value='#{XMLData.mind_value}' text='#{XMLData.mind_text}'/>"
                     init_str.concat "<spell>#{XMLData.prepared_spell}</spell>"
                     init_str.concat "<right>#{GameObj.right_hand.name}</right>"
                     init_str.concat "<left>#{GameObj.left_hand.name}</left>"
                     for indicator in [ 'IconBLEEDING', 'IconPOISONED', 'IconDISEASED', 'IconSTANDING', 'IconKNEELING', 'IconSITTING', 'IconPRONE' ]
                        init_str.concat "<indicator id='#{indicator}' visible='#{XMLData.indicator[indicator]}'/>"
                     end
                     for area in [ 'back', 'leftHand', 'rightHand', 'head', 'rightArm', 'abdomen', 'leftEye', 'leftArm', 'chest', 'rightLeg', 'neck', 'leftLeg', 'nsys', 'rightEye' ]
                        if Wounds.send(area) > 0
                           init_str.concat "<image id=\"#{area}\" name=\"Injury#{Wounds.send(area)}\"/>"
                        elsif Scars.send(area) > 0
                           init_str.concat "<image id=\"#{area}\" name=\"Scar#{Scars.send(area)}\"/>"
                        end
                     end
                     init_str.concat '<compass>'
                     shorten_dir = { 'north' => 'n', 'northeast' => 'ne', 'east' => 'e', 'southeast' => 'se', 'south' => 's', 'southwest' => 'sw', 'west' => 'w', 'northwest' => 'nw', 'up' => 'up', 'down' => 'down', 'out' => 'out' }
                     for dir in XMLData.room_exits
                        if short_dir = shorten_dir[dir]
                           init_str.concat "<dir value='#{short_dir}'/>"
                        end
                     end
                     init_str.concat '</compass>'
                     $_DETACHABLE_CLIENT_.puts init_str
                     init_str = nil
                  }
                  while client_string = $_DETACHABLE_CLIENT_.gets
                     client_string = "#{$cmd_prefix}#{client_string}" # if $frontend =~ /^(?:wizard|avalon)$/
                     begin
                        $_IDLETIMESTAMP_ = Time.now
                        do_client(client_string)
                     rescue
                        respond "--- Lich: error: client_thread: #{$!}"
                        respond $!.backtrace.first
                        Lich.log "error: client_thread: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
                     end
                  end
               rescue
                  respond "--- Lich: error: client_thread: #{$!}"
                  respond $!.backtrace.first
                  Lich.log "error: client_thread: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
                  $_DETACHABLE_CLIENT_.close rescue nil
                  $_DETACHABLE_CLIENT_ = nil
               ensure 
                  $_DETACHABLE_CLIENT_.close rescue nil
                  $_DETACHABLE_CLIENT_ = nil
               end
            end
            sleep 0.1
         }
      }
   else
      detachable_client_thread = nil
   end

   wait_while { $offline_mode }

   if $frontend == 'wizard'
      $link_highlight_start = "\207"
      $link_highlight_end = "\240"
      $speech_highlight_start = "\212"
      $speech_highlight_end = "\240"
   end

   client_thread.priority = 3

   $_CLIENT_.puts "\n--- Lich v#{LICH_VERSION} is active.  Type #{$clean_lich_char}help for usage info.\n\n"

   Game.thread.join
   client_thread.kill rescue nil
   detachable_client_thread.kill rescue nil

   Lich.log 'info: stopping scripts...'
   Script.running.each { |script| script.kill }
   Script.hidden.each { |script| script.kill }
   200.times { sleep 0.1; break if Script.running.empty? and Script.hidden.empty? }
   Lich.log 'info: saving script settings...'
   Settings.save
   Vars.save
   Lich.log 'info: closing connections...'
   Game.close
   $_CLIENT_.close rescue nil
#   Lich.db.close rescue nil
   reconnect_if_wanted.call
   Lich.log "info: exiting..."
   Gtk.queue { Gtk.main_quit } if defined?(Gtk)
   exit
}

if defined?(Gtk)
   Thread.current.priority = -10
   Gtk.main
else
   main_thread.join
end
exit
