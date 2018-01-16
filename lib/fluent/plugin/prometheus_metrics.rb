module Fluent::Plugin
  class PromMetricsAggregator
    def initialize
      @known_metrics = []
      @merged_lines = []
    end
    
    def get_metric_name(line)
      metric = ''
      tokens = line.split(' ')
      if line[0] == '#'
        if ['HELP', 'TYPE'].include?(tokens[1])
          metric = tokens[2]
        end
      else
        metric = tokens[0].split('{')[0]
      end
      metric
    end
    
    def is_meta_line(line)
      tokens = line.split(' ')
      line[0] == '#' && ['HELP', 'TYPE'].include?(tokens[1])
    end
    
    def add_metrics(metrics)
      current_metric = ''
      insert_offset = 0
      lines = metrics.split("\n")
      for line in lines
        parsed_metric = get_metric_name(line)
        if parsed_metric == current_metric
          #Known metric, insert at current position
          @merged_lines.insert(insert_offset, line)
          insert_offset += 1
        else
          if parsed_metric == ''
            # Unknown item, insert at current position
            @merged_lines.insert(insert_offset, line)
            insert_offset += 1
          elsif @known_metrics.include?(parsed_metric)
            if is_meta_line(line)
              # Forget about this metric (prevents insertion of existing TYPE / HELP)
              parsed_metric = ''
            else
              #Known metric, need to find insert location
              insert_offset = 0
              found_metric = ''
              for l in @merged_lines
                existing_metric = get_metric_name(l)
                if existing_metric == parsed_metric
                  found_metric = parsed_metric
                  insert_offset += 1
                elsif (found_metric != '' && existing_metric != found_metric)
                  # We found where to insert!
                  break
                else
                  insert_offset += 1
                end
              end
              @merged_lines.insert(insert_offset, line)
              insert_offset += 1
            end
          else
            # New item, add lines to end of content
            @known_metrics += [parsed_metric]
            @merged_lines += [line]
            insert_offset = @merged_lines.length
          end
          current_metric = parsed_metric
        end
      end
    end
    
    def get_metrics
      @merged_lines.join("\n")
    end
  end
end
