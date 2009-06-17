# experimental "Wx::Grid" version of the strings window

require 'rbkb/extends'

module Hexwrench
  class StringsFrame < Wx::Frame
    def initialize(parent, data, strings_opts=nil)
      super(parent, :title => "Strings")
      @grid = Wx::Grid.new(self)

      @data = data
      @strings_opts =(strings_opts || {})
      @strings_opts[:font] ||= 
        Wx::Font.new(10, Wx::MODERN, Wx::NORMAL, Wx::NORMAL)

      make_grid()
    end

    def make_grid()
      tbl = StringsTableBase.new(@data, @strings_opts)
      @grid.set_table(tbl, Wx::Grid::GridSelectRows)
      @grid.set_row_label_size(0)
      @grid.enable_grid_lines(false)
      @grid.disable_drag_row_size()
      @grid.disable_drag_grid_size()
      @grid.set_label_font(@strings_opts[:font])
    end
  end

  class StringsTableBase < Wx::GridTableBase
    def initialize(data, strings_opts=nil)
      super()
      strings_opts ||= {}
      @font = strings_opts[:font] 
      @font ||= Wx::Font.new(10, Wx::MODERN, Wx::NORMAL, Wx::NORMAL)
      @cell_attr = Wx::GridCellAttr.new( Wx::BLACK, Wx::WHITE, @font, 
                                        Wx::ALIGN_LEFT, Wx::ALIGN_CENTRE)
      @cell_attr.set_read_only(true)
      @strings = data.strings(strings_opts)
    end

    def get_number_cols
      4
    end

    def get_number_rows
      @strings.size
    end

    def get_col_label_value(col)
      ["start", "end", "kind", "string"][col]
    end

    def get_row_label_value(row)
      ""
    end

    def get_value(row, col)
      val=@strings[row][col].to_s
      return (col > 2)?  val.inspect : val
    end

    def is_empty_cell(row, col)
      (r=@strings[row]).nil? or r[col].nil?
    end

    def get_attr(*args)
      @cell_attr.clone
    end

  end
end
