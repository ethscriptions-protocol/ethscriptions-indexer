class ImportProfiler
  include Singleton

  def self.start(label)
    instance.start(label)
  end

  def self.stop(label)
    instance.stop(label)
  end


  def self.report
    instance.report
  end

  def self.reset
    instance.reset
  end

  def self.enabled?
    instance.enabled?
  end

  def initialize
    @enabled = ENV['PROFILE_IMPORT'] == 'true'
    reset
  end

  def enabled?
    @enabled
  end

  def start(label)
    return unless @enabled

    # Support nested timing by using a per-thread stack
    thread_id = Thread.current.object_id
    @start_stack[thread_id] ||= Concurrent::Map.new
    @start_stack[thread_id][label] ||= Concurrent::Array.new
    @start_stack[thread_id][label].push(Time.current)
  end

  def stop(label)
    return nil unless @enabled

    thread_id = Thread.current.object_id
    return nil unless @start_stack[thread_id] && @start_stack[thread_id][label] && !@start_stack[thread_id][label].empty?

    start_time = @start_stack[thread_id][label].pop
    elapsed = Time.current - start_time

    @timings[label] ||= Concurrent::Array.new
    @timings[label] << elapsed

    # Clean up empty stacks
    if @start_stack[thread_id][label].empty?
      @start_stack[thread_id].delete(label)
      @start_stack.delete(thread_id) if @start_stack[thread_id].empty?
    end

    elapsed
  end


  def report
    return unless @enabled
    return if @timings.empty?

    Rails.logger.info "=" * 100
    Rails.logger.info "IMPORT PROFILE REPORT"
    Rails.logger.info "=" * 100

    # Calculate totals and averages
    report_data = @timings.each_pair.map do |label, times|
      {
        label: label,
        count: times.size,
        total: times.sum.round(3),
        avg: (times.sum / times.size).round(3),
        min: times.min.round(3),
        max: times.max.round(3),
        total_ms: (times.sum * 1000).round(1)
      }
    end

    # Sort by total time descending
    report_data.sort_by! { |d| -d[:total] }

    # Find the grand total
    grand_total = report_data.sum { |d| d[:total] }

    # Print table header
    Rails.logger.info sprintf("%-45s %8s %10s %8s %8s %8s %10s %6s",
                              "Operation", "Count", "Total(ms)", "Avg(ms)", "Min(ms)", "Max(ms)", "Total(s)", "Pct%")
    Rails.logger.info "-" * 110

    # Print each timing
    report_data.each do |data|
      pct = grand_total > 0 ? ((data[:total] / grand_total) * 100).round(1) : 0
      Rails.logger.info sprintf("%-45s %8d %10.1f %8.1f %8.1f %8.1f %10.3f %6.1f%%",
                                data[:label],
                                data[:count],
                                data[:total_ms],
                                data[:avg] * 1000,
                                data[:min] * 1000,
                                data[:max] * 1000,
                                data[:total],
                                pct)
    end

    Rails.logger.info "-" * 110
    Rails.logger.info sprintf("%-45s %8s %10.1f %8s %8s %8s %10.3f",
                              "TOTAL", "", grand_total * 1000, "", "", "", grand_total)
    Rails.logger.info "=" * 100

    # Also print a summary of top time consumers
    Rails.logger.info "\nTop 5 Time Consumers:"
    report_data.first(5).each_with_index do |data, i|
      pct = grand_total > 0 ? ((data[:total] / grand_total) * 100).round(1) : 0
      Rails.logger.info "  #{i+1}. #{data[:label]}: #{data[:total_ms].round(1)}ms (#{pct}%)"
    end
  end

  def reset
    @timings = Concurrent::Map.new
    @start_stack = Concurrent::Map.new
  end
end

