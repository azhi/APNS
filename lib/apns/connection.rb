module APNS
  require 'socket'
  require 'openssl'

  class Connection
    attr_reader :host, :port, :pem, :pass, :ssl, :sock

    def initialize(options)
      @host, @port, @pem, @pass = [:host, :port, :pem, :pass].map{ |option| options.delete(option) }
    end

    def connect
      reconnect if closed?
      open unless opened?
      true
    end

    def close
      return false if closed?
      @ssl.close
      @sock.close
      true
    end

    def reconnect
      close
      open
    end

    def opened?
      @ssl && @sock && !closed?
    end

    def closed?
      @ssl && @sock && @ssl.closed?
    end

    def write_and_wait_response(data, read_bytes)
      write(data)
      read(read_bytes)
    end

    def write(data)
      connect
      @ssl.write(data)
    end

    def read(bytes)
      read_socket, _ = IO.select([@ssl], [@ssl], [@ssl], nil)
      if (read_socket && read_socket[0])
        response = @ssl.read(bytes)
      end
      response
    end

    def self.open(options, &block)
      retries = 0
      begin
        connection = self.new(options)
        connection.connect
        yield connection if block_given?

      rescue Errno::ECONNABORTED, Errno::EPIPE, Errno::ECONNRESET
        if (retries += 1) < 5
          connection.close if connection.opened?
          retry
        else
          # too-many retries, re-raise
          raise
        end
      ensure
        connection.close if block_given?
      end
      return connection unless block_given?
    end

    private

      def open
        raise "The path to your pem file is not set. (APNS.pem = /path/to/cert.pem)" unless self.pem
        raise "The path to your pem file does not exist!" unless File.exist?(self.pem)

        context      = OpenSSL::SSL::SSLContext.new
        context.cert = OpenSSL::X509::Certificate.new(File.read(self.pem))
        context.key  = OpenSSL::PKey::RSA.new(File.read(self.pem), self.pass)

        retries = 0
        begin
          @sock         = TCPSocket.new(host, port)
          @ssl          = OpenSSL::SSL::SSLSocket.new(sock, context)
          @ssl.connect
          return @ssl, @sock
        rescue SystemCallError
          if (retries += 1) < 5
            sleep 1
            retry
          else
            # Too many retries, re-raise this exception
            raise
          end
        end
      end
  end
end
