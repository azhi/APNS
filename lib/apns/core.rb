module APNS
  require 'json'

  @host = 'gateway.sandbox.push.apple.com'
  @port = 2195
  # openssl pkcs12 -in mycert.p12 -out client-cert.pem -nodes -clcerts
  @pem = nil # this should be the path of the pem file not the contentes
  @pass = nil
  @cache_connection = false

  class << self
    attr_accessor :host, :pem, :port, :pass, :cache_connection
  end

  def self.send_notification(device_token, message)
    n = APNS::Notification.new(device_token, message)
    self.send_notifications([n])
  end

  def self.send_notifications(notifications)
    packed_notifications = APNS::Notification.packed_notifications(notifications)
    write_to_connection(:push, packed_notifications)
  end

  def self.feedback
    connection = get_connection(:feedback)

    apns_feedback = []

    while message = connection.read(38)
      timestamp, token_size, token = message.unpack('N1n1H*')
      apns_feedback << [Time.at(timestamp), token]
    end
    connection.close

    return apns_feedback
  end

  def self.close_cached_connection
    @cache_connection && @push_connection &&
      @push_connection.close
  end

  protected
    def self.push_connection_options
      {
        host: self.host,
        port: self.port,
        pem: self.pem,
        pass: self.pass
      }
    end

    def self.feedback_connection_options
      self.push_connection_options.merge(host: self.host.gsub('gateway','feedback'), port: 2196)
    end

    def self.get_connection(type)
      options =
        case type
        when :push
          push_connection_options
        when :feedback
          feedback_connection_options
        else
          raise ArgumentError.new('Wrong type. Expected one of [:push, :feedback]')
        end
      if cache_connection && type == :push
        @push_connection ||= APNS::Connection.open(options)
        @push_connection
      else
        APNS::Connection.open(options)
      end
    end

    def self.write_to_connection(type, data, response_length = nil)
      connection = get_connection(type)
      if response_length
        response = connection.write_and_wait_response(data, response_length)
      else
        connection.write(data)
      end
      connection.close unless cache_connection
      response
    end
end
