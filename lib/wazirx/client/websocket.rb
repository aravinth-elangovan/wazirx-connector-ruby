require 'faye/websocket'
require 'json'
require 'date'

module Wazirx
  module Client
    # Public: Client with methods mirroring the Wazirx WebSocket API
    class WebSocket
      # Public: String base url for WebSocket client to use
      BASE_URL = 'wss://stream.wazirx.com/stream'.freeze
      SUBSCRIBE = 'subscribe'
      UNSUBSCRIBE = 'unsubscribe'

      def initialize(api_key='', secret_key='')
        @api_key = api_key
        @secret_key = secret_key
      end

      def trades(symbol:, id: 0, action: SUBSCRIBE, methods: {})
        stream = get_mapped_streams(symbol, 'trades')
        create_stream(streams: stream, id: id, action: action, methods: methods)
      end

      def all_market_ticker(id: 0,action: SUBSCRIBE, methods: {})
        stream = "!ticker@arr"
        create_stream(streams: stream, id: id, action: action, methods: methods)
      end

      def depth(symbol:, id: 0, action: SUBSCRIBE, methods: {})
        stream = get_mapped_streams(symbol, 'depth')
        create_stream(streams: stream, id: id, action: action, methods: methods)
      end

      def user_stream(streams:, id: 0, action: SUBSCRIBE, methods: {})
        create_stream(streams: streams, id: id, action: action, methods: methods, auth_key: get_auth_key)
      end

      def multi_stream(streams:, id: 0, action: SUBSCRIBE)
        return "Streams should be an array!" if streams.class != Array
        format_stream = []
        streams.each do | stream |
          format_stream += get_mapped_streams(stream[:symbol], stream[:type]) if stream[:type].to_s == 'trades'
          format_stream += get_mapped_streams(stream[:symbol], stream[:type]) if stream[:type].to_s == 'depth'
          format_stream << "!ticker@arr" if stream[:type].to_s == 'ticker'
        end
        create_stream(streams: format_stream, id: id, action: action)
      end

      def subscribe(streams:[], id:0, auth_key:'')
        puts subscribeEvent(streams, id, auth_key)
      end

      def unsubscribe(streams:[], id:0, auth_key:'')
        puts unsubscribeEvent(streams, id, auth_key)
      end

      private

      def get_mapped_streams(symbols, type)
        symbols.class == Array ? symbols.map { |sym| "#{sym}@#{type.to_s}" } : ["#{symbols}@#{type.to_s}"]
      end

      def get_auth_key
        return @auth_key unless @auth_key.nil?
        client = REST.new(api_key: @api_key, secret_key: @secret_key)
        @auth_key = client.call('create_auth_token!', {timestamp: DateTime.now.strftime('%Q'), recvWindow: 20000})['auth_key']
      end

      def subscribeEvent(streams=[], id=0, auth_key='')
        @ws.send(JSON.dump({'event': SUBSCRIBE, 'streams': streams.flatten, 'id': id, 'auth_key': auth_key}))
      end

      def unsubscribeEvent(streams=[], id=0, auth_key='')
        @ws.send(JSON.dump({'event': UNSUBSCRIBE, 'streams': streams.flatten, 'id': id}))
      end

      def create_stream(streams: streams, id: id, action: action, methods: {}, auth_key:'')
        @ws = Faye::WebSocket::Client.new(BASE_URL)
        @ws.on :open do |event|
          puts [:open]
          if action == SUBSCRIBE
            puts subscribeEvent(streams, id, auth_key)
            methods[:message].call(event)
            EM.add_periodic_timer 300 do
              @ws.send('ping', BASE_URL)
              puts [:message, 'pinged every 5 minutes']
            end
          else
            puts unsubscribeEvent(streams, id, auth_key)
          end
        end

        @ws.on :message do |event|
          puts [:message, JSON.load(event.data)]
          methods[:message].call(event)
        end

        @ws.on :close do |event|
          puts [:close, event.code, event.reason]
          methods[:message].call(event)
          @ws = nil
        end
      end

    end
  end
end
