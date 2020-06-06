class NilClass
   def dup
      nil
   end
   def method_missing(*args)
      nil
   end
   def split(*val)
      Array.new
   end
   def to_s
      ""
   end
   def strip
      ""
   end
   def +(val)
      val
   end
   def closed?
      true
   end
end

class Numeric
   def as_time
      sprintf("%d:%02d:%02d", (self / 60).truncate, self.truncate % 60, ((self % 1) * 60).truncate)
   end
   def with_commas
      self.to_s.reverse.scan(/(?:\d*\.)?\d{1,3}-?/).join(',').reverse
   end
end

class TrueClass
   def method_missing(*usersave)
      true
   end
end

class FalseClass
   def method_missing(*usersave)
      nil
   end
end

class String
   @@elevated_untaint = proc { |what| what.orig_untaint }
   alias :orig_untaint :untaint
   def untaint
      @@elevated_untaint.call(self)
   end
   def to_s
      self.dup
   end
   def stream
      @stream
   end
   def stream=(val)
      @stream ||= val
   end
end

class StringProc
   def initialize(string)
      @string = string
      @string.untaint
   end
   def kind_of?(type)
      Proc.new {}.kind_of? type
   end
   def class
      Proc
   end
   def call(*a)
      proc { begin; $SAFE = 3; rescue; nil; end; eval(@string) }.call
   end
   def _dump(d=nil)
      @string
   end
   def inspect
      "StringProc.new(#{@string.inspect})"
   end
end

class SynchronizedSocket
   def initialize(o)
      @delegate = o
      @mutex = Mutex.new
      self
   end
   def puts(*args, &block)
      @mutex.synchronize {
         @delegate.puts *args, &block
      }
   end
   def write(*args, &block)
      @mutex.synchronize {
         @delegate.write *args, &block
      }
   end
   def method_missing(method, *args, &block)
      @delegate.__send__ method, *args, &block
   end
end

class LimitedArray < Array
   attr_accessor :max_size
   def initialize(size=0, obj=nil)
      @max_size = 200
      super
   end
   def push(line)
      self.shift while self.length >= @max_size
      super
   end
   def shove(line)
      push(line)
   end
   def history
      Array.new
   end
end

class UpstreamHook
   @@upstream_hooks ||= Hash.new
   def UpstreamHook.add(name, action)
      unless action.class == Proc
         echo "UpstreamHook: not a Proc (#{action})"
         return false
      end
      @@upstream_hooks[name] = action
   end
   def UpstreamHook.run(client_string)
      for key in @@upstream_hooks.keys
         begin
            client_string = @@upstream_hooks[key].call(client_string)
         rescue
            @@upstream_hooks.delete(key)
            respond "--- Lich: UpstreamHook: #{$!}"
            respond $!.backtrace.first
         end
         return nil if client_string.nil?
      end
      return client_string
   end
   def UpstreamHook.remove(name)
      @@upstream_hooks.delete(name)
   end
   def UpstreamHook.list
      @@upstream_hooks.keys.dup
   end
end

class DownstreamHook
   @@downstream_hooks ||= Hash.new
   def DownstreamHook.add(name, action)
      unless action.class == Proc
         echo "DownstreamHook: not a Proc (#{action})"
         return false
      end
      @@downstream_hooks[name] = action
   end
   def DownstreamHook.run(server_string)
      for key in @@downstream_hooks.keys
         begin
            server_string = @@downstream_hooks[key].call(server_string.dup)
         rescue
            @@downstream_hooks.delete(key)
            respond "--- Lich: DownstreamHook: #{$!}"
            respond $!.backtrace.first
         end
         return nil if server_string.nil?
      end
      return server_string
   end
   def DownstreamHook.remove(name)
      @@downstream_hooks.delete(name)
   end
   def DownstreamHook.list
      @@downstream_hooks.keys.dup
   end
end

class Watchfor
   def initialize(line, theproc=nil, &block)
      return nil unless script = Script.current
      if line.class == String
         line = Regexp.new(Regexp.escape(line))
      elsif line.class != Regexp
         echo 'watchfor: no string or regexp given'
         return nil
      end
      if block.nil?
         if theproc.respond_to? :call
            block = theproc
         else
            echo 'watchfor: no block or proc given'
            return nil
         end
      end
      script.watchfor[line] = block
   end
   def Watchfor.clear
      script.watchfor = Hash.new
   end
end