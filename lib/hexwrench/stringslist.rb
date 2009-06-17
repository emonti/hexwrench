### DEPRECATED by stringsvlist.rb

require 'rbkb/extends'

module Hexwrench
  class StringsFrame < Wx::Frame
    attr_reader :strings_list
    def initialize(parent, editor, strings_opts=nil)
      unless @editor = editor
        Kernel.raise "#{self.class}.new() requires an editor window parameter"
      end

      super(parent, :title => "Strings")

      @strings_list = StringsList.new(self, @editor, strings_opts)
      @strings_list.evt_window_destroy do |evt| 
        self.destroy() rescue (ObjectPreviouslyDeleted)
        evt.skip(true)
      end

      evt_list_item_selected(@strings_list) do |evt|
        s_off, e_off, kind, str = evt.item.data
        if @editor.select_range(s_off..e_off-1)
          @editor.set_area_ascii
          @editor.scroll_to_idx(s_off)
          @editor.refresh
        end
      end


      # Fire our strings operation only on switching (via activation)
      # we do this because strings is a costly operation
      evt_activate do |evt| 
        if @data_changed
          @data_changed=false
          @strings_list.do_strings 
        end
      end
    end

    def notify_data_change
      @data_changed=true
    end

    def do_strings
      @strings_list.do_strings
    end
  end

  class StringsList < Wx::ListCtrl
    attr_reader :strings_opts

    def initialize(parent, editor, strings_opts=nil)
      unless @editor = editor
        Kernel.raise "#{self.class}.new() requires an editor window parameter"
      end

      super(parent, :style => Wx::LC_REPORT|Wx::LC_SINGLE_SEL|Wx::LC_HRULES|Wx::LC_VRULES)
      insert_column(0, "start")
      insert_column(1, "len")
      insert_column(2, "kind")
      insert_column(3, "string")

      @strings_opts = (strings_opts || {})
      @strings_opts[:encoding] ||= :both

      @font = Wx::Font.new(10, Wx::MODERN, Wx::NORMAL, Wx::NORMAL)
      set_font(@font)
    end

    GAUGE_STYLE = Wx::PD_CAN_ABORT |
                  Wx::PD_REMAINING_TIME |
                  Wx::PD_ESTIMATED_TIME |
                  Wx::PD_ELAPSED_TIME

    def do_strings
      gauge = 
        Wx::ProgressDialog.new("", "Generating Strings",
          @editor.data.size, self, GAUGE_STYLE)

      self.hide
      delete_all_items
      i=0
      @editor.data.strings(@strings_opts) do |startoff, endoff, stype, str|
        unless gauge.update(endoff)
          # the "abort" button was pressed
          destroy
          return nil
        end
        d_str = ((stype == :unicode)? str.gsub(/(.)\x00/){$1} : str).inspect
        insert_item(i, startoff.to_s)
        set_item i, 1, (endoff-startoff).to_s
        set_item i, 2, stype.to_s
        set_item i, 3, d_str
        set_item_data(i, [startoff, endoff, stype])
        i+=1
      end

      0.upto(3) {|c| set_column_width c, Wx::LIST_AUTOSIZE } if i > 0
      self.show
      gauge.destroy()
      return i
    end
  end
end
