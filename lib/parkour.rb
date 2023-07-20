# encoding: utf-8
require "parkour/version"
require "parkour/lru"
require "paint"

module Parkour
  module_function

  def io
    @io || $stdout
  end

  def columns
    @columns ||= begin
      if ENV['BUILDKITE']
        # force to 145 which is the the widest viewport
        140
      else
        cols = ENV.fetch('COLUMNS', `tput cols`.strip).to_i
        if !$?.success?
          120
        else
          cols
        end
      end
    end
  end

  def columns=(value)
    @columns = value
  end

  INDENT_AMOUNT = 2
  def format_line(time:, line:, path:, line_no:, depth:, event:, return_value: nil)
    str = StringIO.new
    str << "#{line_no.to_s.rjust(4)} "
    str << line.slice(0, columns - 20)

    time = "#{time.rjust(9)}"
    spaces = columns - str.string.length
    spaces -= time.length
    spaces = 1 if spaces < 1 # Minimum one space
    str << "#{' ' * spaces}#{time}"
    str.string
  end

  def lines_for_file(path)
    @cache ||= LRU.new(100)
    lines = @cache.get(path)
    return lines if lines

    File.readlines(path, encoding: 'utf-8').tap do |lines|
      @cache.put(path, lines)
    end
  end

  def begin_line(tp)
    line = lines_for_file(tp.path)[tp.lineno - 1]&.chomp
    return if line.nil? # This can happen due to slim/erb etc cause the compiled line is different to the source line
    @last_line = {
      time: "...",
      line: line,
      path: path_filter.call(tp.path),
      event: tp.event,
      line_no: tp.lineno,
      depth: @depths.shift || @depth,
    }
    if @current_path != @last_line[:path]
      @current_path = @last_line[:path]
      io.puts
      io.puts Paint["#{@current_path}:", :blue]
    end
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

  def flush
    finish_line
    @last_line = nil
  end

  IGNORED_CLASSES = ['Capybara::Node::Element']
  def tracepoint
    @tracepoint ||= begin
      @depths = []
      @depth = 0
      TracePoint.new(:line) do |tp|
        @line_events += 1
        if filters.empty? || filters.any? { |f| tp.path =~ f }
          finish_line
          begin_line(tp)
          @lines_processed += 1
        end
      end
    end
  end

  def filters
    @filters ||= []
  end

  def path_filter
    @path_filter ||= -> (path) { path }
  end

  def trace(filters: nil, output: nil, path_filter: nil, &block)
    file = ENV['PARKOUR_FILE']
    @filters = filters ? filters.clone : [Regexp.new(caller.first.split(':').first)]
    @path_filter = path_filter
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

    @line_events = 0
    @lines_processed = 0
    tracepoint.enable
    block.call
  ensure
    tracepoint.disable
    finish_line
    if ENV['PARKOUR_DEBUG']
      @io.puts Paint["[PARKOUR] Lines: #{@lines_processed}/#{@line_events}", :blue]
    end
  end
end
