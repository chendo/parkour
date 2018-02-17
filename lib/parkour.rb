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
      if ENV['BUILDKITE']
        # force to 120 cause tput cols reports 80
        120
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
    str << line

    time = "#{time.rjust(9)}"
    spaces = columns - str.string.length
    spaces -= time.length
    spaces = 1 if spaces < 1 # Minimum one space
    str << "#{' ' * spaces}#{time}"
    str.string
  end

  def begin_line(tp)
    line = File.readlines(tp.path, encoding: 'utf-8')[tp.lineno - 1].chomp
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

  IGNORED_CLASSES = ['Capybara::Node::Element']
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
            return_value = if IGNORED_CLASSES.include?(tp.return_value.class.to_s)
              "#<#{tp.return_value.class.to_s}>"
            else
              tp.return_value.inspect rescue "#<#{tp.return_value.class.to_s}>"
            end
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
    tracepoint.enable
    block.call
  ensure
    finish_line
    tracepoint.disable
  end
end
