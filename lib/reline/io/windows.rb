require 'fiddle/import'

class Reline::Windows < Reline::IO
  def initialize
    @input_buf = []
    @output_buf = []

    @input = STDIN
    @output = STDOUT
    @hsg = nil
    @kbhit = Win32API.new('msvcrt', '_kbhit', [], 'I')
    @GetStdHandle = Win32API.new('kernel32', 'GetStdHandle', ['L'], 'L')
    @hConsoleHandle = @GetStdHandle.call(STD_OUTPUT_HANDLE)
    @hConsoleInputHandle = @GetStdHandle.call(STD_INPUT_HANDLE)
    @GetNumberOfConsoleInputEvents = Win32API.new('kernel32', 'GetNumberOfConsoleInputEvents', ['L', 'P'], 'L')
    @ReadConsoleInputW = Win32API.new('kernel32', 'ReadConsoleInputW', ['L', 'P', 'L', 'P'], 'L')

    @WaitForSingleObject = Win32API.new('kernel32', 'WaitForSingleObject', ['L', 'L'], 'L')
  end

  def encoding
    Encoding::UTF_8
  end

  def win?
    true
  end

  def win_legacy_console?
    @legacy_console
  end

  def set_default_key_bindings(config)
    {
      [224, 72] => :ed_prev_history, # ↑
      [224, 80] => :ed_next_history, # ↓
      [224, 77] => :ed_next_char,    # →
      [224, 75] => :ed_prev_char,    # ←
      [224, 83] => :key_delete,      # Del
      [224, 71] => :ed_move_to_beg,  # Home
      [224, 79] => :ed_move_to_end,  # End
      [  0, 41] => :ed_unassigned,   # input method on/off
      [  0, 72] => :ed_prev_history, # ↑
      [  0, 80] => :ed_next_history, # ↓
      [  0, 77] => :ed_next_char,    # →
      [  0, 75] => :ed_prev_char,    # ←
      [  0, 83] => :key_delete,      # Del
      [  0, 71] => :ed_move_to_beg,  # Home
      [  0, 79] => :ed_move_to_end   # End
    }.each_pair do |key, func|
      config.add_default_key_binding_by_keymap(:emacs, key, func)
      config.add_default_key_binding_by_keymap(:vi_insert, key, func)
      config.add_default_key_binding_by_keymap(:vi_command, key, func)
    end

    {
      [27, 32] => :em_set_mark,             # M-<space>
      [24, 24] => :em_exchange_mark,        # C-x C-x
    }.each_pair do |key, func|
      config.add_default_key_binding_by_keymap(:emacs, key, func)
    end

    # Emulate ANSI key sequence.
    {
      [27, 91, 90] => :completion_journey_up, # S-Tab
    }.each_pair do |key, func|
      config.add_default_key_binding_by_keymap(:emacs, key, func)
      config.add_default_key_binding_by_keymap(:vi_insert, key, func)
    end
  end

  if defined? JRUBY_VERSION
    require 'win32api'
  else
    class Win32API
      DLL = {}
      TYPEMAP = {"0" => Fiddle::TYPE_VOID, "S" => Fiddle::TYPE_VOIDP, "I" => Fiddle::TYPE_LONG}
      POINTER_TYPE = Fiddle::SIZEOF_VOIDP == Fiddle::SIZEOF_LONG_LONG ? 'q*' : 'l!*'

      WIN32_TYPES = "VPpNnLlIi"
      DL_TYPES = "0SSI"

      def initialize(dllname, func, import, export = "0", calltype = :stdcall)
        @proto = [import].join.tr(WIN32_TYPES, DL_TYPES).sub(/^(.)0*$/, '\1')
        import = @proto.chars.map {|win_type| TYPEMAP[win_type.tr(WIN32_TYPES, DL_TYPES)]}
        export = TYPEMAP[export.tr(WIN32_TYPES, DL_TYPES)]
        calltype = Fiddle::Importer.const_get(:CALL_TYPE_TO_ABI)[calltype]

        handle = DLL[dllname] ||=
                 begin
                   Fiddle.dlopen(dllname)
                 rescue Fiddle::DLError
                   raise unless File.extname(dllname).empty?
                   Fiddle.dlopen(dllname + ".dll")
                 end

        @func = Fiddle::Function.new(handle[func], import, export, calltype)
      rescue Fiddle::DLError => e
        raise LoadError, e.message, e.backtrace
      end

      def call(*args)
        import = @proto.split("")
        args.each_with_index do |x, i|
          args[i], = [x == 0 ? nil : +x].pack("p").unpack(POINTER_TYPE) if import[i] == "S"
          args[i], = [x].pack("I").unpack("i") if import[i] == "I"
        end
        ret, = @func.call(*args)
        return ret || 0
      end
    end
  end

  VK_RETURN = 0x0D
  VK_MENU = 0x12 # ALT key
  VK_LMENU = 0xA4
  VK_CONTROL = 0x11
  VK_SHIFT = 0x10
  VK_DIVIDE = 0x6F

  KEY_EVENT = 0x01
  WINDOW_BUFFER_SIZE_EVENT = 0x04

  CAPSLOCK_ON = 0x0080
  ENHANCED_KEY = 0x0100
  LEFT_ALT_PRESSED = 0x0002
  LEFT_CTRL_PRESSED = 0x0008
  NUMLOCK_ON = 0x0020
  RIGHT_ALT_PRESSED = 0x0001
  RIGHT_CTRL_PRESSED = 0x0004
  SCROLLLOCK_ON = 0x0040
  SHIFT_PRESSED = 0x0010

  VK_TAB = 0x09
  VK_END = 0x23
  VK_HOME = 0x24
  VK_LEFT = 0x25
  VK_UP = 0x26
  VK_RIGHT = 0x27
  VK_DOWN = 0x28
  VK_DELETE = 0x2E

  STD_INPUT_HANDLE = -10
  STD_OUTPUT_HANDLE = -11
  FILE_TYPE_PIPE = 0x0003
  FILE_NAME_INFO = 2
  ENABLE_WRAP_AT_EOL_OUTPUT = 2
  ENABLE_VIRTUAL_TERMINAL_PROCESSING = 4

  # Calling Win32API with console handle is reported to fail after executing some external command.
  # We need to refresh console handle and retry the call again.
  private def call_with_console_handle(win32func, *args)
    val = win32func.call(@hConsoleHandle, *args)
    return val if val != 0

    @hConsoleHandle = @GetStdHandle.call(STD_OUTPUT_HANDLE)
    win32func.call(@hConsoleHandle, *args)
  end

  private def getconsolemode
    mode = +"\0\0\0\0"
    call_with_console_handle(@GetConsoleMode, mode)
    mode.unpack1('L')
  end

  def msys_tty?(io = @hConsoleInputHandle)
    false # not supported
  end

  KEY_MAP = [
    # It's treated as Meta+Enter on Windows.
    [ { control_keys: :CTRL,  virtual_key_code: 0x0D }, "\e\r".bytes ],
    [ { control_keys: :SHIFT, virtual_key_code: 0x0D }, "\e\r".bytes ],

    # It's treated as Meta+Space on Windows.
    [ { control_keys: :CTRL,  char_code: 0x20 }, "\e ".bytes ],

    # Emulate getwch() key sequences.
    [ { control_keys: [], virtual_key_code: VK_UP },     [0, 72] ],
    [ { control_keys: [], virtual_key_code: VK_DOWN },   [0, 80] ],
    [ { control_keys: [], virtual_key_code: VK_RIGHT },  [0, 77] ],
    [ { control_keys: [], virtual_key_code: VK_LEFT },   [0, 75] ],
    [ { control_keys: [], virtual_key_code: VK_DELETE }, [0, 83] ],
    [ { control_keys: [], virtual_key_code: VK_HOME },   [0, 71] ],
    [ { control_keys: [], virtual_key_code: VK_END },    [0, 79] ],

    # Emulate ANSI key sequence.
    [ { control_keys: :SHIFT, virtual_key_code: VK_TAB }, [27, 91, 90] ],
  ]

  def process_key_event(repeat_count, virtual_key_code, virtual_scan_code, char_code, control_key_state)

    # high-surrogate
    if 0xD800 <= char_code and char_code <= 0xDBFF
      @hsg = char_code
      return
    end
    # low-surrogate
    if 0xDC00 <= char_code and char_code <= 0xDFFF
      if @hsg
        char_code = 0x10000 + (@hsg - 0xD800) * 0x400 + char_code - 0xDC00
        @hsg = nil
      else
        # no high-surrogate. ignored.
        return
      end
    else
      # ignore high-surrogate without low-surrogate if there
      @hsg = nil
    end

    key = KeyEventRecord.new(virtual_key_code, char_code, control_key_state)

    match = KEY_MAP.find { |args,| key.match?(**args) }
    unless match.nil?
      @output_buf.concat(match.last)
      return
    end

    # no char, only control keys
    return if key.char_code == 0 and key.control_keys.any?

    @output_buf.push("\e".ord) if key.control_keys.include?(:ALT) and !key.control_keys.include?(:CTRL)

    @output_buf.concat(key.char.bytes)
  end

  def check_input_event(timeout_second)
    initial_time = Time.now
    num_of_events = 0.chr * 8
    while @output_buf.empty?
      Reline.core.line_editor.handle_signal
      if @WaitForSingleObject.(@hConsoleInputHandle, 100) != 0 # max 0.1 sec
        break if Time.now - initial_time > timeout_second
        next
      end
      next if @GetNumberOfConsoleInputEvents.(@hConsoleInputHandle, num_of_events) == 0 or num_of_events.unpack1('L') == 0
      input_records = 0.chr * 20 * 80
      read_event = 0.chr * 4
      if @ReadConsoleInputW.(@hConsoleInputHandle, input_records, 80, read_event) != 0
        read_events = read_event.unpack1('L')
        0.upto(read_events) do |idx|
          input_record = input_records[idx * 20, 20]
          event = input_record[0, 2].unpack1('s*')
          case event
          when WINDOW_BUFFER_SIZE_EVENT
            @winch_handler.()
          when KEY_EVENT
            key_down = input_record[4, 4].unpack1('l*')
            repeat_count = input_record[8, 2].unpack1('s*')
            virtual_key_code = input_record[10, 2].unpack1('s*')
            virtual_scan_code = input_record[12, 2].unpack1('s*')
            char_code = input_record[14, 2].unpack1('S*')
            control_key_state = input_record[16, 2].unpack1('S*')
            is_key_down = key_down.zero? ? false : true
            if is_key_down
              process_key_event(repeat_count, virtual_key_code, virtual_scan_code, char_code, control_key_state)
            end
          end
        end
      end
    end
  end

  def with_raw_input
    yield
  end

  def getc(timeout_second)
    check_input_event(timeout_second)
    @output_buf.shift
  end

  def ungetc(c)
    @output_buf.unshift(c)
  end

  def in_pasting?
    not empty_buffer?
  end

  def empty_buffer?
    if not @output_buf.empty?
      false
    elsif @kbhit.call == 0
      true
    else
      false
    end
  end

  def get_screen_size
    input = @input.tty? ? IO.console : @input
    s = input.winsize
    return s if s[0] > 0 && s[1] > 0
    s = [ENV["LINES"].to_i, ENV["COLUMNS"].to_i]
    return s if s[0] > 0 && s[1] > 0
    [24, 80]
  rescue Errno::ENOTTY, Errno::ENODEV, Errno::EBADF
    [24, 80]
  end

  def set_screen_size(rows, columns)
    raise NotImplementedError
  end

  private def cursor_pos_internal(timeout:)
    match = nil
    @input.raw do |stdin|
      @output << "\e[6n"
      @output.flush
      timeout_at = Time.now + timeout
      buf = +''
      while (wait = timeout_at - Time.now) > 0 && c = getc(wait)
        buf << c
        if (match = buf.match(/\e\[(?<row>\d+);(?<column>\d+)R/))
          buf = match.pre_match + match.post_match
          break
        end
      end
      buf.chars.reverse_each do |ch|
        ungetc ch.ord
      end
    end
    [match[:column].to_i - 1, match[:row].to_i - 1] if match
  end

  def cursor_pos
    col, row = cursor_pos_internal(timeout: 0.5) if both_tty?
    Reline::CursorPos.new(col || 0, row || 0)
  end

  def both_tty?
    @input.tty? && @output.tty?
  end

  def move_cursor_column(x)
    @output.write "\e[#{x + 1}G"
  end

  def move_cursor_up(x)
    if x > 0
      @output.write "\e[#{x}A"
    elsif x < 0
      move_cursor_down(-x)
    end
  end

  def move_cursor_down(x)
    if x > 0
      @output.write "\e[#{x}B"
    elsif x < 0
      move_cursor_up(-x)
    end
  end

  def hide_cursor
    @output.write "\e[?25l"
  end

  def show_cursor
    @output.write "\e[?25h"
  end

  def erase_after_cursor
    @output.write "\e[K"
  end

  # This only works when the cursor is at the bottom of the scroll range
  # For more details, see https://github.com/ruby/reline/pull/577#issuecomment-1646679623
  def scroll_down(x)
    return if x.zero?
    # We use `\n` instead of CSI + S because CSI + S would cause https://github.com/ruby/reline/issues/576
    @output.write "\n" * x
  end

  def clear_screen
    @output.write "\e[2J"
    @output.write "\e[1;1H"
  end

  def set_winch_handler(&handler)
    @winch_handler = handler
  end

  def prep
    # do nothing
    nil
  end

  def deprep(otio)
    # do nothing
  end

  def disable_auto_linewrap(setting = true, &block)
    block.call if block
  end

  class KeyEventRecord

    attr_reader :virtual_key_code, :char_code, :control_key_state, :control_keys

    def initialize(virtual_key_code, char_code, control_key_state)
      @virtual_key_code = virtual_key_code
      @char_code = char_code
      @control_key_state = control_key_state
      @enhanced = control_key_state & ENHANCED_KEY != 0

      (@control_keys = []).tap do |control_keys|
        # symbols must be sorted to make comparison is easier later on
        control_keys << :ALT   if control_key_state & (LEFT_ALT_PRESSED | RIGHT_ALT_PRESSED) != 0
        control_keys << :CTRL  if control_key_state & (LEFT_CTRL_PRESSED | RIGHT_CTRL_PRESSED) != 0
        control_keys << :SHIFT if control_key_state & SHIFT_PRESSED != 0
      end.freeze
    end

    def char
      @char_code.chr(Encoding::UTF_8)
    end

    def enhanced?
      @enhanced
    end

    # Verifies if the arguments match with this key event.
    # Nil arguments are ignored, but at least one must be passed as non-nil.
    # To verify that no control keys were pressed, pass an empty array: `control_keys: []`.
    def match?(control_keys: nil, virtual_key_code: nil, char_code: nil)
      raise ArgumentError, 'No argument was passed to match key event' if control_keys.nil? && virtual_key_code.nil? && char_code.nil?

      (control_keys.nil? || [*control_keys].sort == @control_keys) &&
      (virtual_key_code.nil? || @virtual_key_code == virtual_key_code) &&
      (char_code.nil? || char_code == @char_code)
    end

  end
end
