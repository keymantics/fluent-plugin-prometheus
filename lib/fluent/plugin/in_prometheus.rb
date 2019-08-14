require 'fluent/plugin/input'
require 'fluent/plugin/prometheus'
require 'fluent/plugin/prometheus_metrics'
require 'webrick'

module Fluent::Plugin
  class PrometheusInput < Fluent::Plugin::Input
    Fluent::Plugin.register_input('prometheus', self)

    helpers :thread

    config_param :bind, :string, default: '0.0.0.0'
    config_param :port, :integer, default: 24231
    config_param :metrics_path, :string, default: '/metrics'
    config_param :metrics_all_path, :string, default: '/metrics_all'

    attr_reader :registry

    attr_reader :num_workers
    attr_reader :base_port
    attr_reader :metrics_path

    def initialize
      super
      @registry = ::Prometheus::Client.registry
    end

    def configure(conf)
      super

      # Get how many workers we have
      sysconf = if self.respond_to?(:owner) && owner.respond_to?(:system_config)
                  owner.system_config
                elsif self.respond_to?(:system_config)
                  self.system_config
                else
                  nil
                end
      @num_workers = sysconf && sysconf.workers ? sysconf.workers : 1

      @base_port = @port
      @port += fluentd_worker_id
    end

    def multi_workers_ready?
      true
    end

    def start
      super

      log.debug "listening prometheus http server on http://#{@bind}:#{@port}/#{@metrics_path} for worker#{fluentd_worker_id}"
      @server = WEBrick::HTTPServer.new(
        BindAddress: @bind,
        Port: @port,
        MaxClients: 5,
        Logger: WEBrick::Log.new(STDERR, WEBrick::Log::FATAL),
        AccessLog: [],
      )
      @server.mount(@metrics_path, MonitorServlet, self)
      @server.mount("#{metrics_all_path}", MonitorServletAll, self)
      thread_create(:in_prometheus) do
        @server.start
      end
    end

    def shutdown
      if @server
        @server.shutdown
        @server = nil
      end
      super
    end

    class MonitorServlet < WEBrick::HTTPServlet::AbstractServlet
      def initialize(server, prometheus)
        @prometheus = prometheus
      end

      def do_GET(req, res)
        res.status = 200
        res['Content-Type'] = ::Prometheus::Client::Formats::Text::CONTENT_TYPE
        res.body = ::Prometheus::Client::Formats::Text.marshal(@prometheus.registry)
      rescue
        res.status = 500
        res['Content-Type'] = 'text/plain'
        res.body = $!.to_s
      end
    end

    class MonitorServletAll < WEBrick::HTTPServlet::AbstractServlet
      def initialize(server, prometheus)
        @prometheus = prometheus
      end

      def do_GET(req, res)
        res.status = 200
        res['Content-Type'] = ::Prometheus::Client::Formats::Text::CONTENT_TYPE

        full_result = PromMetricsAggregator.new
        $current_worker = 0
        while $current_worker < @prometheus.num_workers
          Net::HTTP.start("127.0.0.1", @prometheus.base_port + $current_worker) do |http|
            req = Net::HTTP::Get.new(@prometheus.metrics_path)
            result = http.request(req)
            if result.is_a?(Net::HTTPSuccess)
              full_result.add_metrics(result.body)
            end
          end
          $current_worker += 1
        end
        res.body = full_result.get_metrics
      rescue
        res.status = 500
        res['Content-Type'] = 'text/plain'
        res.body = $!.to_s
      end
    end
  end
end
