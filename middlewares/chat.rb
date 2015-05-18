# middlewares/chat.rb
require 'faye/websocket'
require 'redis'
require 'json'
require 'erb'

module ChatDemo
  class Chat
    KEEPALIVE_TIME = 15 # in seconds
    CHANNEL        = "chat-demo"

    def initialize(app)
      @app     = app
      @clients = []
      @base_channel = "websockets"
      uri      = URI.parse(ENV["REDISCLOUD_URL"])
      @redis   = Redis.new(host: uri.host, port: uri.port, password: uri.password)

      Thread.new do
        redis_sub = Redis.new(host: uri.host, port: uri.port, password: uri.password)
        redis_sub.psubscribe("#{@base_channel}.*") do |on|
          on.pmessage do |pattern, channel, msg|
            @clients.each do |client| 
              channel_name = channel.gsub("#{@base_channel}.", "")
              if client[:channels].include?(channel_name)
                client[:ws].send(msg)
              end
            end

          end
        end
      end
    end

    def call(env)
    	if Faye::WebSocket.websocket?(env)
    		ws = Faye::WebSocket.new(env, nil, {ping: KEEPALIVE_TIME })
        
        request = Rack::Request.new(env)

        client = { :ws => nil, :channels => [] }
        
        # The list of channels the client is requesting access to
        channels = request.params["channels"]

      	ws.on :open do |event|
          # Assign the websocket object to the client
          client[:ws] = ws

          # For every channel the client wants to subscribe to...
          channels.each do |channel|
            # Ensure they are authorized to listen on this channel. (This is not
            # needed, but useful if you want to add security to specific channels)
            #if WebsocketChannelAuthorizer.can_subscribe?(channel, token)
              # Add the channel to the client
              client[:channels].push(channel)
            #end
          end

          # Add the client to the list of clients
  			  p [:open, ws.object_id]
  			  @clients << client
  			end

  			ws.on :message do |event|
          json = JSON.parse(event.data)
  			  p [:message, event.data]
  			  @redis.publish("#{@base_channel}.#{json['channel']}", sanitize(event.data))
  			end

  			ws.on :close do |event|
  			  p [:close, ws.object_id, event.code, event.reason]
  			  @clients.delete(ws)
  			  ws = nil
  			end
			            
        # Return async Rack response
    		ws.rack_response
    	else
    		@app.call(env)
    	end
    end

    private

    def sanitize(message)
      json = JSON.parse(message)
      json.each {|key, value| json[key] = ERB::Util.html_escape(value) }
      JSON.generate(json)
    end
  end
end