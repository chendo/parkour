require "parkour/version"
require "paint"

module Parkour
  module_function

  def io
    @io ||= begin
      file = ENV['PARKOUR_FILE']
      if file == 'stderr'
        $stderr
      elsif file
        File.open(file, 'a').tap do |fd|
          fd.sync = true
        end
      else
        $stdout
      end
    end
  end

  def format_line(time:, line:, path:, line_no:, event: '', depth:)
    str = StringIO.new
    str << "[#{time.rjust(9)}] "
    str << "#{' ' * depth}#{line}"

    spaces = ENV.fetch('COLUMNS', `tput cols`.strip).to_i - str.string.length
    path = "#{path}:#{line_no}"
    spaces -= path.length
    str << "#{' ' * spaces}#{path}"
    str.string
  end

  CLEAR_LINE = "\e[2K"
  def begin_line(tp)
    if @last_line
      finish_line
    end

    line = File.readlines(tp.path)[tp.lineno - 1].sub(/^\s+/, '').strip
    @last_line = {
      time: "...",
      line: line,
      path: tp.path,
      event: tp.event,
      line_no: tp.lineno,
      depth: @depths.shift || @depth,
    }
    io.print Paint[format_line(**@last_line), :yellow]
    @time = Time.now.to_f
  end

  def finish_line
    io.print "\r#{CLEAR_LINE}"
    @last_line[:time] = "#{((Time.now.to_f - @time) * 1000).round}ms"
    io.puts Paint[format_line(**@last_line), :green]
  end

  at_exit do
    finish_line if @last_line
  end

  def tracepoint
    @tracepoint ||= begin
      @depths = []
      @depth = 0
      TracePoint.new(:line, :call, :return) do |tp|
        if filters.empty? || filters.any? { |f| f.call(tp) }
          if tp.event == :call
            @depths = [@depth, @depth + 1]
            @depth += 1
            begin_line(tp)
          elsif tp.event == :return
            @depth -= 1
            begin_line(tp)
          else
            begin_line(tp)
          end
        end
      end
    end
  end

  def filters
    @filters = []
  end

  def trace(filters: [], &block)
    tracepoint.enable
    block.call
  ensure 
    tracepoint.disable
  end
end