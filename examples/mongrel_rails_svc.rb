###############################################
# mongrel_rails_svc.rb
#
# This is where Win32::Daemon resides.
###############################################
require 'rubygems'
require 'mongrel'

require 'optparse'

require 'win32/service'

DEBUG_LOG_FILE = File.expand_path(File.dirname(__FILE__) + '/debug.log') 
#STDERR.reopen(DEBUG_LOG_FILE)

# There are need for SimpleHandler
require 'yaml'
require 'zlib'

class RailsHandler < Mongrel::HttpHandler

  def initialize(dir, mime_map = {})
    @files = Mongrel::DirHandler.new(dir,false)
    @guard = Mutex.new
    
    # register the requested mime types
    mime_map.each {|k,v| Mongrel::DirHandler::add_mime_type(k,v) }
  end
  
  def process(request, response)
    # not static, need to talk to rails
    return if response.socket.closed?

    if @files.can_serve(request.params["PATH_INFO"])
      @files.process(request,response)
    else
      cgi = Mongrel::CGIWrapper.new(request, response)

      begin
        @guard.synchronize do
          # Rails is not thread safe so must be run entirely within synchronize 
          Dispatcher.dispatch(cgi, ActionController::CgiRequest::DEFAULT_SESSION_OPTIONS, response.body)
        end

        # This finalizes the output using the proper HttpResponse way
        cgi.out {""}
      rescue Object => rails_error
        STDERR.puts "calling Dispatcher.dispatch #{rails_error}"
        STDERR.puts rails_error.backtrace.join("\n")
      end
    end
  end

end

class SimpleHandler < Mongrel::HttpHandler
    def process(request, response)
      response.start do |head,out|
        head["Content-Type"] = "text/html"
        results = "<html><body>Your request:<br /><pre>#{request.params.to_yaml}</pre><a href=\"/files\">View the files.</a></body></html>"
        if request.params["HTTP_ACCEPT_ENCODING"] == "gzip,deflate"
          head["Content-Encoding"] = "deflate"
          # send it back deflated
          out << Zlib::Deflate.deflate(results)
        else
          # no gzip supported, send it back normal
          out << results
        end
      end
    end
end

class RailsDaemon < Win32::Daemon
  def initialize(ip, port, rails_root, docroot, environment, mime_map, num_procs, timeout)
    File.open(DEBUG_LOG_FILE,"a+") { |f| f.puts("#{Time.now} - daemon_initialize entered") }

    @ip = ip
    @port = port
    @rails_root = rails_root
    @docroot = docroot
    @environment = environment
    @mime_map = mime_map
    @num_procs = num_procs
    @timeout = timeout

    File.open(DEBUG_LOG_FILE,"a+") { |f| f.puts("#{Time.now} - daemon_initialize left") }
  end

  def load_mime_map
    File.open(DEBUG_LOG_FILE,"a+") { |f| f.puts("#{Time.now} - load_mime_map entered") }

    mime = {}

    # configure any requested mime map
    if @mime_map
      puts "Loading additional MIME types from #@mime_map"
      mime.merge!(YAML.load_file(@mime_map))

      # check all the mime types to make sure they are the right format
      mime.each {|k,v| puts "WARNING: MIME type #{k} must start with '.'" if k.index(".") != 0 }
    end

    File.open(DEBUG_LOG_FILE,"a+") { |f| f.puts("#{Time.now} - load_mime_map left") }
    
    return mime
  end

  def configure_rails
    File.open(DEBUG_LOG_FILE,"a+") { |f| f.puts("#{Time.now} - configure_rails entered") }

    Dir.chdir(@rails_root)

    ENV['RAILS_ENV'] = @environment
    require File.join(@rails_root, 'config/environment')

    # configure the rails handler
    rails = RailsHandler.new(@docroot, load_mime_map)
    
    File.open(DEBUG_LOG_FILE,"a+") { |f| f.puts("#{Time.now} - configure_rails left") }

    return rails
  end

  def service_init
    File.open(DEBUG_LOG_FILE,"a+") { |f| f.puts("#{Time.now} - service_init entered") }
    
    @rails = configure_rails
    #@rails = SimpleHandler.new
    
    # start up mongrel with the right configurations
    @server = Mongrel::HttpServer.new(@ip, @port, @num_procs.to_i, @timeout.to_i)
    @server.register("/", @rails)
    
    File.open(DEBUG_LOG_FILE,"a+") { |f| f.puts("#{Time.now} - service_init left") }    
  end
  
  def service_main
    File.open(DEBUG_LOG_FILE,"a+") { |f| f.puts("#{Time.now} - service_main entered") }

    File.open(DEBUG_LOG_FILE,"a+") { |f| f.puts("#{Time.now} - server.run") }
    @server.run
    
    File.open(DEBUG_LOG_FILE,"a+") { |f| f.puts("#{Time.now} - while RUNNING") }
    while state == RUNNING
      sleep 1
    end

    File.open(DEBUG_LOG_FILE,"a+") { |f| f.puts("#{Time.now} - service_main left") }
  end

  def service_stop
    File.open(DEBUG_LOG_FILE,"a+") { |f| f.puts("#{Time.now} - service_stop entered") }

    #File.open(DEBUG_LOG_FILE,"a+") { |f| f.puts("#{Time.now} - server.stop") }
    #@server.stop

    File.open(DEBUG_LOG_FILE,"a+") { |f| f.puts("#{Time.now} - service_stop left") }
  end
end


if ARGV[0] == 'service'
  ARGV.shift

  # default options
  OPTIONS = {
    :rails_root   => Dir.pwd,
    :environment  => 'production',
    :ip           => '0.0.0.0',
    :port         => 3000,
    :mime_map     => nil,
    :num_procs    => 20,
    :timeout      => 120
  }
  
  ARGV.options do |opts|
    opts.on('-r', '--root PATH', "Set the root path where your rails app resides.") { |OPTIONS[:rails_root]| }
    opts.on('-e', '--environment ENV', "Rails environment to run as.") { |OPTIONS[:environment]| }
    opts.on('-b', '--binding ADDR', "Address to bind to") { |OPTIONS[:ip]| }
    opts.on('-p', '--port PORT', "Which port to bind to") { |OPTIONS[:port]| }
    opts.on('-m', '--mime PATH', "A YAML file that lists additional MIME types") { |OPTIONS[:mime_map]| }
    opts.on('-P', '--num-procs INT', "Number of processor threads to use") { |OPTIONS[:num_procs]| }
    opts.on('-t', '--timeout SECONDS', "Timeout all requests after SECONDS time") { |OPTIONS[:timeout]| }
    
    opts.parse!
  end

  OPTIONS[:docroot] = File.expand_path(OPTIONS[:rails_root] + '/public')

  rails_svc = RailsDaemon.new(OPTIONS[:ip], OPTIONS[:port], OPTIONS[:rails_root], OPTIONS[:docroot], OPTIONS[:environment], OPTIONS[:mime_map], OPTIONS[:num_procs].to_i, OPTIONS[:timeout].to_i)
  rails_svc.mainloop

end
