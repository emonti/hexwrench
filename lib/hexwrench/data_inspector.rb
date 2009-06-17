require 'rbkb/extends'

module Hexwrench
  DEFAULT_DATA_INSPECTORS = [
    { :label => "8 bit", 
      :enabled => true,
      :proc => lambda {|buf, idx, parent| buf[idx].to_s} },

    { :label => "16 bit", 
      :enabled => true,
      :proc => lambda do |buf, idx, parent| 
        if d=buf[idx,2] and d.size == 2
          d.dat_to_num(parent.endianness)
        end
      end 
    }, 

    { :label => "32 bit", 
      :enabled => true,
      :proc => lambda do |buf, idx, parent| 
        if d=buf[idx,4] and d.size == 4
          d.dat_to_num(parent.endianness)
        end
      end
    },

    { :label => "64 bit",
      :enabled => true,
      :proc => lambda do |buf, idx, parent|
        if d=buf[idx,8] and d.size == 8
          d.dat_to_num(parent.endianness)
        end
      end
    },

    { :label => "128 bit",
      :enabled => false,
      :proc => lambda do |buf, idx, parent|
        if d=buf[idx,16] and d.size == 16
          d.dat_to_num(parent.endianness)
        end
      end
    },

    { :label => "IPv4",
      :enabled => true,
      :proc => lambda do |buf, idx, parent|
        if d=buf[idx,4] and d.size == 4
          "#{d[0]}.#{d[1]}.#{d[2]}.#{d[3]}"
        end
      end
    }
  ]

  DATA_INS_BYTE_ORDER={:big => 0, :little => 1}

  class DataInspector < Wx::Frame
    attr_accessor :endian, :inspectors, :font

    def initialize(parent, opts={})
      unless @editor=opts[:editor]
        raise "#{self.class}.new() requires an :editor parameter" 
      end

      super(parent, :title => "Data Inspector")
      @inspectors =(opts[:inspectors] || DEFAULT_DATA_INSPECTORS)
      @endian =(opts[:endian]|| :big)
      @font = (opts[:font] || Wx::Font.new(10, Wx::MODERN, Wx::NORMAL, Wx::NORMAL))
      set_font(@font)

      @order_sel = Wx::RadioBox.new(self ,
         :choices => ["MSB", "LSB"], :label => "Byte Order")

      @order_sel.selection = DATA_INS_BYTE_ORDER[@endian]

      evt_radiobox(@order_sel) {|evt| do_inspectors() }

      @grid = Wx::Grid.new(self)
      make_grid()
      
      @main_sizer = Wx::BoxSizer.new(Wx::VERTICAL)
      @main_sizer.add(@order_sel)
      @main_sizer.add(@grid, Wx::EXPAND|Wx::ALL)
      self.sizer = @main_sizer
    end
    
    def endianness
      DATA_INS_BYTE_ORDER.invert[@order_sel.selection]
    end

    def make_grid()
      @grid.create_grid(@inspectors.select {|x| x[:enabled]}.size, 1)
      @grid.set_row_label_alignment(Wx::ALIGN_RIGHT, Wx::ALIGN_CENTRE)
      @grid.set_default_cell_background_colour(Wx::LIGHT_GREY)
      @grid.set_col_label_size(0)
      @grid.set_col_minimal_acceptable_width(0)
      @grid.enable_grid_lines(false)
      @grid.disable_drag_row_size()
      @grid.disable_drag_grid_size()
      @grid.set_label_font(@font)
      @grid.set_selection_mode(Wx::Grid::GridSelectRows)

      @grid.begin_batch
      idx=0
      @inspectors.each do |inspector|
        next unless inspector[:enabled]
        label = inspector[:label]
        @grid.set_row_label_value(idx, label.to_s)
        @grid.set_read_only(idx,0) # XXX
        idx+=1
      end
      @grid.end_batch
    end

    def do_inspectors
      if @editor.selection
        pos = 0
        buf = @editor.data[@editor.selection]
      else
        pos = @editor.cur_pos
        buf = @editor.data
      end

      @grid.begin_batch
      idx=0
      @inspectors.each do |inspector|
        next unless inspector[:enabled]
        inspector_proc = inspector[:proc]
        val=inspector_proc.call(buf, pos, self)
        @grid.set_cell_value(idx, 0, val.to_s)
        idx+=1
      end
      @grid.auto_size_column(0, true)
      @grid.end_batch
    end

  end
end
