module Funicular
  module Profiler
    class Aggregator
      MAX_GROUPS = 500

      def summarize(buffer)
        groups = {}
        buffer.each_record do |record|
          component = record.attributes["funicular.component.class"]
          key = [record.name, component]
          key = overflow_key(groups) unless groups.key?(key) || groups.length < MAX_GROUPS
          group = groups[key] ||= new_group(key)
          group["count"] += 1
          group["error_count"] += 1 if record.status == "error"
          group["empty_diff_count"] += 1 if record.attributes["funicular.diff.empty"] == true
          group["total_us"] += record.duration_us
          group["max_us"] = record.duration_us if record.duration_us > group["max_us"]
          group["durations"] << record.duration_us
        end
        groups.values.map { |group| finish_group(group) }
      end

      private

      def overflow_key(groups)
        key = ["<other>", nil]
        return key if groups.key?(key)

        group = groups.delete(groups.keys[-1])
        group["name"] = key[0]
        group["component_class"] = key[1]
        groups[key] = group
        key
      end

      def new_group(key)
        {
          "name" => key[0], "component_class" => key[1], "count" => 0,
          "error_count" => 0, "empty_diff_count" => 0, "total_us" => 0,
          "max_us" => 0, "durations" => []
        }
      end

      def finish_group(group)
        durations = group.delete("durations").sort
        group["p50_us"] = percentile(durations, 0.50)
        group["p95_us"] = percentile(durations, 0.95)
        group
      end

      def percentile(values, fraction)
        return 0 if values.empty?
        values[(values.length * fraction).ceil - 1]
      end
    end
  end
end
