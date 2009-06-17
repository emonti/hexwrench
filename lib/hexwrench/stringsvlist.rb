
require 'rbkb/extends.rb'

module Hexwrench
  class StringsFrame < Wx::Frame
    attr_reader :strings_list

    def initialize(parent, editor, strings_opts=nil)
      unless @editor = editor
        Kernel.raise "#{self.class}.new() requires an editor window parameter"
      end

      @strings_opts = (strings_opts || {})
      @strings_opts[:min] ||= 5

      super(parent, :title => "Strings")

      # Fire our strings operation only on switching windows (via activation)
      # we do this because finding strings (to a lesser extent) and 
      # populating the window (to a larger extent) may be a costly operation
      evt_idle do |evt| 
        if @data_changed and active?
          @data_changed=false
          do_strings 
        end
      end

      do_strings
    end

    def notify_data_change
      @data_changed=true
    end

    def do_strings
      if @strings_list.nil?
        @strings_list = StringsList.new(self, @editor) unless @strings_list

        evt_list_item_selected(@strings_list) do |evt|
          s_off, e_off, kind, str = @strings_list.strings[evt.get_index]
          if @editor.select_range(s_off..e_off-1)
            @editor.set_area_ascii
            @editor.scroll_to_idx(s_off)
            @editor.refresh
          end
        end
      else
        @strings_list.refresh_strings()
      end
    end
  end

  class StringsList < Wx::ListCtrl
    attr_accessor :strings_opts, :strings, :editor

    def initialize(parent, editor, strings_opts=nil)
      @strings_opts ||= {}
      @editor = editor

      super(parent, :style => Wx::LC_REPORT|Wx::LC_SINGLE_SEL|Wx::LC_HRULES|Wx::LC_VRULES|Wx::LC_VIRTUAL)

      @font = Wx::Font.new(10, Wx::MODERN, Wx::NORMAL, Wx::NORMAL)
      set_font(@font)

      @dc = Wx::WindowDC.new(self)
      @labels = ["start idx", "end idx", "kind", "string"]
      @labels.each_index {|i| insert_column(i, @labels[i]) }

      refresh_strings()

      @attr = Wx::ListItemAttr.new
      @attr.set_background_colour(Wx::WHITE)
    end

    def refresh_strings()
      @strings = []
      colwids = @labels.map {|l| @dc.get_text_extent("@@#{l}@@", @font)[0]}
      @editor.data.strings(@strings_opts) do |*mtch|
        @strings << mtch[0..2]

        # calculate column widths during loop so we don't have to autosize 
        # later. (autosize can be slow on large lists)
        0.upto(2) do |i|
          owid = colwids[i]
          nwid = @dc.get_text_extent("@#{mtch[i]}@", @font)[0]
          colwids[i] = nwid if nwid > owid
        end
        swid=colwids[3]
        nswid=@dc.get_text_extent("@#{get_string(mtch)}@", @font)[0]
        colwids[3] = nswid if nswid > swid
      end
      colwids.each_index {|i| set_column_width(i, colwids[i])}
      set_item_count(@strings.size)
    end

    def get_string(match)
      dat = @editor.data[(match[0]..match[1]-1)]
      if match[2] == :unicode 
        dat.gsub(/(.)\x00/){$1}
      else
        dat
      end.inspect
    end

    def create_strings(data)
    end

    def on_get_item_text(row, col)
      if r = @strings[row]
        if col == 3
          get_string(r)
        else
          r[col].to_s
        end
      end
    end

    def on_get_item_attr(item)
      @attr
    end
  end
end

