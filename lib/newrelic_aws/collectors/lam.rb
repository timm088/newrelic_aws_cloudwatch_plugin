module NewRelicAWS
  module Collectors
    class LAM < Base
      def lambda_functions
        lambda = Aws::Lambda::Client.new(
          :access_key_id => @aws_access_key,
          :secret_access_key => @aws_secret_key,
          :region => @aws_region,
          :http_proxy => @aws_proxy_uri
        )
        lambda.list_functions.functions.map { |name| name.function_name }
      end

      def metric_list
        [
          ["Duration", "Average", "Milliseconds"],
          ["Errors", "Average", "Count"],
          ["Invocations" , "Average", "Count"],
          ["Throttles", "Average", "Count"]
        ]
      end

      def collect
        data_points = []
        lambda_functions.each do |function_name|
          metric_list.each do |(metric_name, statistic, unit)|
            data_point = get_data_point(
              :namespace     => "AWS/Lambda",
              :metric_name   => metric_name,
              :statistic     => statistic,
              :unit          => unit,
              :dimension     => {
                :name  => "FunctionName",
                :value => function_name
              }
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
