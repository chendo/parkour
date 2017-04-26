# encoding: utf-8
require "parkour/version"
require "paint"

module Parkour
  module_function

  def io
    @io || $stdout
  end

  def columns
    @columns ||= begin
      cols = ENV.fetch('COLUMNS', `tput cols`.strip).to_i
      if !$?.success?
        100
      else
        cols
      end
    end
  end

  INDENT_AMOUNT = 2
  def format_line(time:, line:, path:, line_no:, depth:, event:, return_value: nil)
    str = StringIO.new
    str << "[#{time.rjust(9)}] "
    str << "#{' ' * depth * INDENT_AMOUNT}#{line}"
    return_string = " => #{return_value}" if return_value
    if return_string && columns - str.string.length - return_string.length > 0
      str << return_string 
    end

    spaces = columns - str.string.length
    path = "#{path}:#{line_no}"
    spaces -= path.length
    spaces = 0 if spaces < 0
    str << "#{' ' * spaces}#{path}"
    str.string
  end

  def begin_line(tp)
    line = File.readlines(tp.path, encoding: 'utf-8')[tp.lineno - 1].sub(/^\s+/, '').strip
    @last_line = {
      time: "...",
      line: line,
      path: tp.path,
      event: tp.event,
      line_no: tp.lineno,
      depth: @depths.shift || @depth,
    }
    @time = Time.now.to_f
    io.print Paint[format_line(**@last_line), :yellow]
  rescue Errno::ENOENT
  end

  CLEAR_LINE = "\e[2K"
  def finish_line(event: nil, return_value: nil)
    return unless @last_line
    io.print "\r#{CLEAR_LINE}"
    @last_line[:time] = "#{((Time.now.to_f - @time) * 1000).round}ms"
    @last_line[:return_value] = return_value
    io.puts Paint[format_line(**@last_line), :green]
  end

  at_exit do
    finish_line
  end

  def tracepoint
    @tracepoint ||= begin
      @depths = []
      @depth = 0
      TracePoint.new(:line, :call, :return) do |tp|
        if filters.empty? || filters.any? { |f| tp.path =~ f }
          if tp.event == :call
            @depths = [@depth, @depth + 1]
            @depth += 1
            finish_line
            begin_line(tp)
          elsif tp.event == :return
            @depth -= 1 if @depth > 0
            return_value = tp.return_value.inspect
            finish_line(event: :return, return_value: return_value)
            begin_line(tp)
          else
            finish_line
            begin_line(tp)
          end
        end
      end
    end
  end

  def filters
    @filters ||= []
  end

  def trace(filters: [], output: nil, &block)
    file = ENV['PARKOUR_FILE']
    @filters = filters.clone
    @io = if file == 'stderr'
      $stderr
    elsif file
      # FIXME: don't leak fds
      File.open(file, 'a').tap do |fd|
        fd.sync = true
      end
    else
      $stdout
    end
    tracepoint.enable
    block.call
  ensure 
    tracepoint.disable
  end
end
