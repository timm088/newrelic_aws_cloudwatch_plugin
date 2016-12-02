module NewRelicAWS
  module Collectors
    class CFD < Base
      def cloudfront_distributions
        cfd = Aws::CloudFront::Client.new(
          :access_key_id => @aws_access_key,
          :secret_access_key => @aws_secret_key,
          :region => @aws_region,
          :http_proxy => @aws_proxy_uri
        )
        cfd.list_distributions.distribution_list.items.map { |name| name.id }
      end

      def metric_list
        [
          ["Requests", "Sum", "Count", 0],
          ["BytesDownloaded", "Sum", "Bytes", 0],
          ["BytesUploaded", "Sum", "Bytes", 0],
          ["TotalErrorRate", "Average", "Percent", 0],
          ["4xxErrorRate", "Average", "Percent", 0],
          ["5xxErrorRate", "Average", "Percent", 0]
        ]
      end

      def get_us_data_point(options)
        # We need to have a different version for cloudfront
        # as it uses the global region for monitoring
        @cloudwatch = Aws::CloudWatch::Resource.new(
          :access_key_id     => @aws_access_key,
          :secret_access_key => @aws_secret_key,
          :region            => "us-east-1",
          :http_proxy => @aws_proxy_uri
        )
        @cloudwatch_delay = options[:cloudwatch_delay] || 60

        options[:period]     ||= 60
        options[:start_time] ||= (Time.now.utc - (@cloudwatch_delay + options[:period])).iso8601
        options[:end_time]   ||= (Time.now.utc - @cloudwatch_delay).iso8601
        options[:dimensions] ||= [options[:dimension]]
        NewRelic::PlatformLogger.debug("Retrieving statistics: " + options.inspect)
        begin
          statistics = @cloudwatch.client.get_metric_statistics(
            :namespace   => options[:namespace],
            :metric_name => options[:metric_name],
            :unit        => options[:unit],
            :statistics  => [options[:statistic]],
            :period      => options[:period],
            :start_time  => options[:start_time],
            :end_time    => options[:end_time],
            :dimensions  => options[:dimensions]
          )
        rescue => error
          NewRelic::PlatformLogger.error("Unexpected error: " + error.message)
          NewRelic::PlatformLogger.debug("Backtrace: " + error.backtrace.join("\n "))
          raise error
        end
        NewRelic::PlatformLogger.error("Retrieved statistics: #{statistics.inspect}")

        point = statistics[:datapoints].last
        value = get_value(point, options)
        return if value.nil?

        component_name = get_component_name(options)
        [component_name, options[:metric_name], options[:unit].downcase, value]
      end

      def collect
        data_points = []
        cloudfront_distributions.each do | distribution_id |
          metric_list.each do |(metric_name, statistic, unit, default_value)|
            data_point = get_us_data_point(
              :namespace     => "AWS/CloudFront",
              :metric_name   => metric_name,
              :statistic     => statistic,
              :unit          => unit,
              :default_value => default_value,
              :dimensions    => [
                {
                  :name  => "DistributionId",
                  :value => distribution_id
                },
                {
                  :name  => "Region",
                  :value => "Global"
                }
              ]
	    )
            NewRelic::PlatformLogger.debug("metric_name: #{metric_name}, statistic: #{statistic}, unit: #{unit}, response: #{data_point.inspect}")
            unless data_point.nil?
              data_points << data_point
            end
          end
        end
        data_points
      end
    end
  end
end
