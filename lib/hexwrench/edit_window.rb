
module Hexwrench

  # The CursorMoveEvent event is fired when a user moves the cursor around the 
  # hex editor window. It is used mostly by the parent window to trigger 
  # behaviours in various other UI elements when this happens.
  class CursorMoveEvent < Wx::CommandEvent
    EVT_CURSOR_MOVED = Wx::EvtHandler.register_class(self, nil, 'evt_cursor_moved', 1)
    def initialize(editor)
      super(EVT_CURSOR_MOVED)
      self.client_data = {:editor => editor}
      self.id = editor.get_id
    end

    def editor ; client_data[:editor] ; end
  end
  
  # The DataChangeEvent event is fired when a user makes any change to data
  # in the hex editor window. It is used mostly by the parent window to trigger
  # behaviours in various other UI elements when this happens.
  class DataChangeEvent < Wx::CommandEvent
    EVT_DATA_CHANGED = Wx::EvtHandler.register_class(self, nil, 'evt_data_changed', 1)
    def initialize(editor)
      super(EVT_DATA_CHANGED)
      self.client_data = {:editor => editor}
      self.id = editor.get_id
    end

    def editor ; client_data[:editor] ; end
  end


  # The EditWindow is the actual hex editor widget. This is a pure ruby
  # implementation using WxRuby's VScrolledWindow and direct painting for
  # the hexdump and all editor actions within it.
  class EditWindow < Wx::VScrolledWindow
    attr_reader :font, :cursor, :data, :selection
    attr_accessor :post_paint_proc

    HEX_CHARS=['0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f']

    DEFAULT_FONT = Wx::Font.new(10, Wx::MODERN, Wx::NORMAL, Wx::NORMAL)
    STYLE = Wx::VSCROLL |Wx::ALWAYS_SHOW_SB

    AREAS = [ :hex, :ascii ]
    HEX_AREA = 0
    ASCII_AREA = 1

    def initialize(parent, data, opt={})
      super parent, 
            :id => (opt[:id] || -1),
            :pos => (opt[:pos] || Wx::DEFAULT_POSITION),
            :size => (opt[:size] || Wx::DEFAULT_SIZE),
            :style => (opt[:style] || 0) | STYLE,
            :name => (opt[:name] || '')

      @data = (data || '')

      Struct.new "Cursor", 
                  :pos,        # current index into the data
                  :area,       # primary data_area the cursor is in
                  :ins_mode    # Insert/Overwrite mode boolean

      @cursor = Struct::Cursor.new()
      @cursor.pos = 0
      @cursor.area = HEX_AREA
      @other_area = ASCII_AREA
      @cursor.ins_mode = true

      @selection = nil

      @post_paint_proc = opt[:post_paint_proc]

      init_font( (opt[:font] || DEFAULT_FONT) )

      ## set color palette:

      # color behind address and in dead-space to right
      @bg_color = Wx::WHITE
      set_background_colour(@bg_color)

      # hexdump text and bounds colors
      @dump_color=Wx::Colour.new(Wx::BLACK)
      @addr_color=Wx::Colour.new(128,128,128)
      @area_bounds_pen = Wx::Pen.new("GREY", 2, Wx::SOLID)
      @word_bounds_pen = Wx::Pen.new("LIGHT GREY", 1, Wx::SOLID)

      # alternating row background colors
      @alt_row_bgs = [ 
        Wx::Brush.new( Wx::Colour.new("WHITE") ),
        Wx::Brush.new( Wx::Colour.new(237, 247, 254 ) )
      ]

      # colors for selection in primary and 'other' data displays
      @select_bgs = [
        Wx::Brush.new( Wx::Colour.new(181,213,255) ),
        Wx::Brush.new( Wx::Colour.new(212,212,212) )
      ]

      # colors for the cursor
      @cursor_text1 = Wx::Colour.new(Wx::BLACK)
      @cursor_pen1 = Wx::Colour.new(220, 158, 50)
      @cursor_bg1  = Wx::Colour.new(220, 158, 50)
      @cursor_text2  = @dump_color
      @cursor_pen2 = Wx::Colour.new(Wx::BLACK)
      @cursor_bg2  = Wx::TRANSPARENT_BRUSH

      ## initialize event handlers
      evt_window_create :on_create
      evt_size          :on_size
      evt_paint {|evt| paint_buffered {|dc| on_paint(dc)} }

      evt_idle          :on_idle

      evt_char          :on_char
      evt_left_down     :on_left_button_down
      evt_motion        :on_mouse_motion
      evt_left_up       :on_left_button_up
    end


    def ins_mode; @cursor.ins_mode ; end
    def ins_mode=(v) ; @cursor.ins_mode = v ; end

    # returns the current cursor position
    def cur_pos
      @cursor.pos
    end

    # set the cursor position to 'idx'
    def cur_pos=(idx)
      @cursor_moved=true
      @cursor.pos=idx
    end

    # Triggered when the window is first created. Establishes dimensions
    # (by calling update_dimensions) along with various associated instance 
    # variables.
    def on_create(evt=nil)
      update_dimensions()
      @started = true
    end


    # Triggered whenever the window size changes. Updates dimensions and
    # keeps the scroll bar in place.
    def on_size(evt=nil)
      update_dimensions()
      @started = true
      scroll_to_idx((self.cur_pos || 0))
      refresh
    end


    # This method is required by the Wx::VScrolledWindow super-class which 
    # calls it to determine the size of scroll units for the scrollbar at 
    # a given line. We just return our @row_height for all lines (which
    # is calculated from do_row_count() ).
    # Returns -1 if for some reason the row height has not been calculated.
    def on_get_line_height(x); (@row_height || -1); end


    # This method initializes a new font for the hexdump and determines 
    # text sizes. If it is called after the editor has been initialized,
    # it will also update scrollbar information with the new dimensions.
    #
    # This method is always called during initialization and is passed the
    # default font or whatever is provided when calling new(). 
    def init_font(font)
      @font=font
      dc = Wx::WindowDC.new(self)
      dc.set_font(font)
      @asc_width, asc_h = dc.get_text_extent("@")[0,2]
      @asc_width+2 # compact, but not too much so
      @hex_width, hex_h = dc.get_text_extent("@@")[0,2]
      @txt_height = (hex_h > asc_h)? hex_h : asc_h
      @addr_width = dc.get_text_extent(@data.size.to_s(16).rjust(4,'@'))[0]
      @row_height = @txt_height

      update_dimensions() if @started
    end


    # This method must be called on initialization, on size events, and 
    # whenever the size of data contents has changed.
    def update_dimensions
      spacer=@hex_width                    # 3-char space between areas
      ui_width = @addr_width + (spacer*4)  # addr sp sp hex sp ascii sp

      @columns = (client_size.width - ui_width) / (@hex_width + @asc_width*2)
      @columns = 1 if @columns < 1
      @rows = (@data.size / @columns)+1

      # calculate hex/ascii area boundaries
      @hex0 = @addr_width + spacer*2
      @hexN = @hex0 + (@columns * (@hex_width+@asc_width))
      @asc0 = @hexN + spacer
      @ascN = @asc0 + (@columns * @asc_width)
      @row_width = @ascN - @addr_width - @hex_width

      # update scroll-bar info
      old_pos=first_visible_line
      set_line_count(@rows)
      scroll_to_line(old_pos)
    end


    # An idle event handler for Wx::IdleEvent. Keeps track of data changes and
    # cursor movements and produces the appropriate events for them.
    # See also: CursorMoveEvent and DataChangeEvent
    def on_idle(evt)
      if @cursor_moved
        @cursor_moved=false
        event_handler.process_event( CursorMoveEvent.new(self) )
      end

      if @data_changed
        @data_changed=false
        event_handler.process_event( DataChangeEvent.new(self) )
      end
    end


    # Use this method to set a new internal data value from outside the 
    # class. Doing so should keep all the furniture aranged correctly.
    def set_data(data)
      @data_changed=true
      data ||= ""
      self.cur_pos=@last_pos=0
      clear_selection
      @data = data
      update_dimensions()
      refresh()
    end

    # This method just repaints the window
#    def repaint
#      paint_buffered {|dc| on_paint(dc)}
#    end


    # This method does the heavy lifting of drawing the hex editor dump 
    # window. Takes a 'dc' device context parameter
    def on_paint(dc)
      return unless @started
      dc.set_font(@font)
      first_row = row = get_first_visible_line
      last_row = get_last_visible_line+1
      y = 0
      hX = @hex0
      aX = @asc0
      idx = (row.zero?)? 0 : @columns * row

      hex_w = @hex_width + @asc_width
      h_off = @hex_width / 2

      # draw blank background
      dc.set_pen(Wx::TRANSPARENT_PEN)
      dc.set_brush(Wx::Brush.new(@bg_color))
      dc.draw_rectangle(0, 0, client_size.width, client_size.height)

      paint_row(dc, y, idx, row)

      while(c=@data[idx]) and row <= last_row
        if(hX >= @hexN)
          hX = @hex0
          aX = @asc0
          y += @txt_height
          row +=1
          paint_row(dc, y, idx, row)
        end

        # call byte colorization block if we have one
        text_color =
          if( @post_paint_proc and
              bret=@post_paint_proc.call(self,dc,idx,c,hX+h_off,aX,y) )
            bret
          else
            @dump_color
          end

        # selection stuff goes here
        if @selection and @selection.include?(idx)
          sbrushes = [
            @select_bgs[ @cursor.area ],
            @select_bgs[ (@cursor.area+1) % AREAS.size ]
          ]
          colorize_byte_bg(sbrushes, dc, hX+h_off, aX, y)
#          hsw = (@selection.last == idx)? @hex_width : hex_w
#          dc.set_pen(Wx::TRANSPARENT_PEN)
#          dc.set_brush(@select_bgs[ @cursor.area ])
#          dc.draw_rectangle(hX+h_off, y, hsw, @txt_height)
#          dc.set_brush(@select_bgs[ (@cursor.area+1) % AREAS.size ])
#          dc.draw_rectangle(aX, y, @asc_width, @txt_height)
        end

        dc.set_text_foreground(text_color)
        dc.draw_text("#{disp_hex_byte(c)}", hX+h_off, y)
        dc.draw_text("#{disp_ascii_byte(c)}", aX, y)

        hX += hex_w
        aX += @asc_width
        idx += 1
      end

      paint_boundaries(dc)
      paint_cursor(dc)
    end


    # This method is called from the on_paint method to draw a row for each
    # hexdump row in the display
    def paint_row(dc, y, addr, row_num)
      dc.set_pen(Wx::TRANSPARENT_PEN)
      dc.set_text_foreground(@addr_color)
      addr_str = addr.to_s(16).rjust(2,"0")
      w = dc.get_text_extent(addr_str)[0]
      dc.draw_text(addr_str, (@hex0 - w - @asc_width), y) 
      if row_num
        dc.set_brush(@alt_row_bgs[ row_num % @alt_row_bgs.size ])
        dc.draw_rectangle(@hex0, y, @row_width, @txt_height)
      end
    end


    # This method is called from the on_paint method to draw bounding lines
    # on 4-byte word boundaries and between the address/hex/ascii columns
    def paint_boundaries(dc)
      height = @rows * @txt_height

      # draw area boundaries
      dc.set_pen(@area_bounds_pen)
      dc.draw_line(x2=(@hex0)-2, 0, x2, height)
      dc.draw_line(x2=(@asc0-@asc_width), 0, x2, height)
      dc.draw_line(x2=(@hex0+@row_width), 0, x2, height)

      hex_w = @hex_width + @asc_width
      h_off = @hex_width /2
      l_off = @asc_width /2

      # draw WORD boundary indicator lines in the hex area
      divW = (hex_w << 2)
      divX = @hex0 + divW - 1
      dc.set_pen( @word_bounds_pen )
      while divX < @hexN-h_off
        dc.draw_line(x2=(divX+l_off), 0, x2, height)
        divX += divW
      end
    end


    # A helper method for colorizing post_paint_proc blocks. this colorizes
    # the hex and ascii background for a given byte position with the same
    # color. brush must be a Wx::Brush object.
    def colorize_byte_bg(brush, dc, hX, aX, y)
      if brush.kind_of? Array
        hbrush, abrush = brush[0..1]
      else
        hbrush = abrush = brush
      end

      h_off = @hex_width /4

      dc.set_pen(Wx::TRANSPARENT_PEN)

      dc.set_brush(hbrush)
      dc.draw_rectangle(hX-h_off, y, @hex_width+h_off+h_off, @txt_height)
      dc.set_brush(abrush)
      dc.draw_rectangle(aX, y, @asc_width, @txt_height)

      return nil
    end

    # Called from the on_paint method to draw the editor cursor
    def paint_cursor(dc)
      return unless self.cur_pos and @selection.nil?

      pos = self.cur_pos

      if pos == 0
        row = col = 0
      else
        row = pos / @columns 
        col = pos % @columns
      end

      return unless (first_visible_line..last_visible_line+1).include? row 
      row -= first_visible_line

      w_hex = @hex_width+2
      w_asc = @asc_width+2

      h_pen, h_brush, h_txt, a_pen, a_brush, a_txt = 
        case @cursor.area
        when HEX_AREA    : [ @cursor_pen1, @cursor_bg1, @cursor_text1, 
                             @cursor_pen2, @cursor_bg2, @cursor_text2 ]
        when ASCII_AREA  : [ @cursor_pen2, @cursor_bg2, @cursor_text2, 
                              @cursor_pen1, @cursor_bg1, @cursor_text1 ]
        else 
          [ @cursor_pen2, @cursor_bg2, @cursor_txt2, 
            @cursor_pen2, @cursor_bg2, @cursor_txt2 ]
        end

      h_off = (@hex_width /2)

      y = row * @txt_height
      hX = (col * (@hex_width+@asc_width)) + @hex0
      aX = (col * @asc_width) + @asc0

      dc.set_text_foreground(h_txt)
      dc.set_pen(Wx::Pen.new(h_pen))
      dc.set_brush(Wx::Brush.new(h_brush))
      dc.draw_rectangle(hX+h_off-1, y, w_hex-1, @txt_height)

      dc.set_text_foreground(a_txt)
      dc.set_pen(Wx::Pen.new(a_pen))
      dc.set_brush(Wx::Brush.new(a_brush))
      dc.draw_rectangle(aX-1, y, w_asc-1, @txt_height)

      return unless c=@data[pos]

      dc.draw_text("#{disp_hex_byte(c)}", hX+h_off, y )
      dc.draw_text("#{disp_ascii_byte(c)}", aX, y )
    end


    # Returns a two-character hex byte representation, always a gives 
    # a leading nibble.
    def disp_hex_byte(ch)
      HEX_CHARS[(ch >> 4)] + HEX_CHARS[(ch & 0x0f)]
    end


    # Returns a single ascii character given its numeric value.
    # If the character is non-printible, this method returns '.'
    def disp_ascii_byte(ch)
      (0x20..0x7e).include?(ch) ? ch.chr : '.'
    end


    # moves the scroll-bar so that it includes the row for the
    # specified data index
    def scroll_to_idx(idx)
      row = idx / @columns
      d_row = get_first_visible_line
      max_row = get_last_visible_line

      if (d_row..max_row-1).include?(row)
        return
      elsif row==max_row
        scroll_to_line(d_row+1)
      else
        scroll_to_line(row)
      end
    end


    def select_range(rng)
      if rng.first >= 0 and rng.last <= @data.size
        clear_selection()
        self.cur_pos = @last_pos = rng.first
        @selection = rng
      end
    end


    # Used internally to expand selections from mouse dragging or 
    # shift+arrow cursor movement.
    def expand_selection(idx)
      @selection = 
        if @last_pos
          if idx < @last_pos
            (idx..@last_pos)
          else
            (@last_pos..idx)
          end
        end
    end


    # Clear's the text/data selection if one has been made
    def clear_selection()
      @last_pos = nil
      @selection = nil
    end
   

    # This method implements cursor movement
    def move_to_idx(idx, adj=nil, expand_sel=false)
      @hexbyte_started=false
      adj ||= 0
      newidx = idx + adj
      if @selection and not expand_sel
        if adj < 0
          newidx = @selection.first + adj
          pos = (newidx < 0)? 0 : newidx
        else
          newidx = @selection.last + adj
          pos = (newidx > @data.size)? @data.size : newidx
        end
        clear_selection()
        @last_pos = self.cur_pos = pos
        scroll_to_idx(pos)
        refresh
        return pos
      elsif (0..@data.size).include? newidx
        @last_pos ||= self.cur_pos
        self.cur_pos = newidx
        if expand_sel
          expand_selection(newidx)
        else
          @last_pos = nil
        end
        scroll_to_idx(newidx)
        refresh
        return newidx
      end
    end


    def move_cursor_right(expand_sel=false)
      move_to_idx(idx = self.cur_pos, 1, expand_sel)
    end

    def move_cursor_left(expand_sel=false)
      move_to_idx(idx = self.cur_pos, -1, expand_sel)
    end

    def move_cursor_down(expand_sel=false)
      move_to_idx(self.cur_pos, @columns, expand_sel)
    end

    def move_cursor_up(expand_sel=false)
      move_to_idx(self.cur_pos, -@columns, expand_sel)
    end


    # Sets a value at the given index, or if a selection is active,
    # overwrites the selection area with the value. For non-selection
    # edits, the insert-mode flag is checked to determine whether to
    # overwrite or insert at the index.
    #
    # Parameters: 
    #   idx : The index to the data where the value is set.
    #         (The idx parameter is ignored in selection overwrites.)
    #   val : The value to set at @data[idx]
    #         Value can be zero-length in which-case the area or index 
    #         is deleted. 
    #   force_overwrite : Causes the @data[idx] to be overwritten regardless
    #         of the insert-mode flag.
    #
    # Returns: the index where the change was made.
    #
    def gui_set_value(idx, val, force_overwrite=false)
      sel=@selection
      clear_selection()
      ret=nil
      if not sel.nil?
        @data[sel] = val
        @data_changed=true
        ret=sel.first
      elsif idx and (0..@data.size).include? idx
        if ins_mode and not val.empty? and not force_overwrite
          @data[idx, 0] = val
        else
          vsize = (val.size>0)? val.size : 1
          @data[idx, vsize] = val
        end
        @data_changed=true
        ret=idx
      end
      update_dimensions
      refresh
      return ret
    end


    # Takes a key code parameter and looks it up against constants
    # to return a 'name' if one is found.
    def resolve_key_code(code)
      name=nil
      Wx.constants.grep(/^K_/).each do |kconst|
        if Wx.const_get(kconst) == code
          return kconst.sub(/^K_/, '').downcase
        end
      end
    end


    # Keyboard event handler.
    #
    # Key-presses with ASCII values are deferred to evt_char for correct 
    # translation via the key-press event. However, character-specific handlers 
    # using key modifiers (alt, shift, cmd) are honored and override the 
    # evt_char handler.
    #
    # The resolver looks up key names and calls matching char-specific 
    # handlers by name if they are defined.
    #
    # See http://wxruby.rubyforge.org/doc/keycode.html#keycodes for a 
    # list of key names.
    #
    # This method is not designed for calling directly.
    def on_char(evt)
      ch = evt.get_key_code
      mflag = evt.modifiers

      case ch
      when Wx::K_RIGHT  : move_cursor_right(evt.shift_down)
      when Wx::K_LEFT   : move_cursor_left(evt.shift_down)
      when Wx::K_DOWN   : move_cursor_down(evt.shift_down)
      when Wx::K_UP     : move_cursor_up(evt.shift_down)
      when Wx::K_BACK   : on_key_back(evt)
      when Wx::K_DELETE : on_key_delete(evt)
      when Wx::K_TAB    : on_key_tab(evt)
      when (mflag == Wx::MOD_CMD and ?a) # select all
        do_select_all
      when (mflag == Wx::MOD_CMD and ?c) # copy
        do_clipboard_copy
      when (mflag == Wx::MOD_CMD and ?x) # cut
        do_clipboard_cut
      when (mflag == Wx::MOD_CMD and ?v) # paste
        do_clipboard_paste
      when ((mflag == Wx::MOD_NONE or mflag == Wx::MOD_SHIFT) and 0x20..0x7e)
        if @cursor.area
          # redirect regular typing to on_char_AREANAME
          return self.send("on_char_#{AREAS[@cursor.area]}", evt)
        end
      else  # everything else is for dynamically handling key combo handlers
        m = []
        m << 'alt' if (mflag & Wx::MOD_ALT) != 0
        m << 'cmd' if (mflag & Wx::MOD_CMD) != 0
        m << 'shift' if (mflag & Wx::MOD_SHIFT) != 0
        mods = (m.empty?)? "" : "_" + m.join('_')

        ch = evt.get_key_code
        hex = ch.to_s(16).rjust(2,'0')
        meth=nil

        if (n=resolve_key_code(ch)) and respond_to?("on_key#{mods}_#{n}")
          meth="on_key#{mods}_#{n}"
        elsif respond_to?("on_key#{mods}_0x#{hex}")
          meth="on_key#{mods}_#{hex}"
        end

        if meth and ret=self.send(meth, evt)
          return ret
        else
          evt.skip()
        end
      end
    end

    # Handles a Backspace keypress
    def on_key_back(evt)
      @hexbyte_started=false
      if not @selection.nil?
        idx=gui_set_value(nil, '')
        move_to_idx(idx)
      elsif (didx=self.cur_pos-1) >= 0
        gui_set_value(didx, '')
        move_cursor_left()
      end
    end


    # Handles a DEL keypress
    def on_key_delete(evt)
      @hexbyte_started=false
      if not @selection.nil?
        idx=gui_set_value(nil, '')
        move_to_idx(idx)
      elsif @data[self.cur_pos]
        gui_set_value(self.cur_pos, '')
        refresh
      end
    end


    # switches the cursor between hex and ascii area
    def switch_areas
      o = @cursor.area
      @cursor.area = @other_area
      @other_area = o
    end

    def set_area_ascii
      @cursor.area = ASCII_AREA
      @other_area = HEX_AREA
    end

    def set_area_hex
      @cursor.area = HEX_AREA
      @other_area = ASCII_AREA
    end

    # Handles editor entry actions made in the ascii section.
    def on_char_ascii(evt)
      @hexbyte_started=false
      ch = evt.get_key_code
      pos = self.cur_pos

      return if (pos > @data.size)

      if (idx = gui_set_value(pos, ch.chr)) != pos
        move_to_idx(idx, 1)
      else
        move_cursor_right()
      end
      @selection=nil
    end


    # Handles editor entry actions made in the hex section.
    def on_char_hex(evt)
      ch = evt.get_key_code
      pos = self.cur_pos

      if self.respond_to?(:on_key_space)
        return self.send(:on_key_space)
      elsif (binv=HEX_CHARS.index(ch.chr.downcase)).nil?
        return
      elsif @selection and @selection.to_a.size > 1
        self.cur_pos = pos = gui_set_value(nil, '')
      end

      if (@hexbyte_started)
        orig = (@data[pos] || 0)
        binv = ((orig << 4) + binv) & 0xFF
        @hexbyte_started=false
        overwrite=true
      else
        @hexbyte_started = true
        overwrite=false
      end

      if (idx=gui_set_value(pos, binv.chr, overwrite)) != pos
        move_to_idx(idx, 1)
      elsif not @hexbyte_started
        move_cursor_right()
      else
        refresh
      end
    end


    # Returns data index for [x, y] inside the specified data area
    def coords_to_idx(x, y, area)
      if area == HEX_AREA
        left = @hex0
        right = @hexN
        col_w = @hex_width + @asc_width
      elsif area == ASCII_AREA
        left = @asc0
        right = @ascN
        col_w = @asc_width
      else
        return nil
      end

      xcol = if x < left 
               0
             elsif x > right  
               @columns-1
             else
               ((x-left) / col_w)
             end

      if (row=hit_test(x,y)) != -1
        return( (hit_test(x,y) * @columns) + xcol )
      else
        return @data.size
      end
    end


    # returns the area (display column) for an x window coordinate
    def area_for_x(x)
      if (@hex0..@hexN-(@asc_width>>1)).include?(x)    then HEX_AREA
      elsif (@asc0..@ascN).include?(x) then ASCII_AREA
      end
    end


    # Handles a left mouse button click
    def on_left_button_down(evt)
      if evt.left_is_down()
        @hexbyte_started = false
        set_focus()
        x=evt.get_x ; y=evt.get_y 
        if ( @dragging or evt.shift_down ) 
          if ( idx=coords_to_idx(x,y, @cursor.area) )
            expand_selection(idx)
            refresh
          end
        elsif area=area_for_x(x)
          switch_areas() if area != @cursor.area and not AREAS[area].nil?
          if idx=coords_to_idx(x,y, area)
            clear_selection()
            @cursor.area = area
            @last_pos = self.cur_pos = (idx <= @data.size)? idx : @data.size
          end
          refresh
        end
      else
        evt.skip()
        return
      end
    end 

    # Handles a left mouse button release
    def on_left_button_up(evt)
      if !evt.left_is_down()
        @dragging = false
        x=evt.get_x ; y=evt.get_y 
        if @selection.nil? and 
          idx=coords_to_idx(x,y, @cursor.area) and 
          @data[idx]
          self.cur_pos = idx
        end
      else
        evt.skip()
        return
      end
    end

    # Handles mouse motion - skips if left mouse button is not down
    def on_mouse_motion(evt)
      if evt.left_is_down()
        @dragging = true
        x=evt.get_x ; y=evt.get_y 
        idx=coords_to_idx(x,y, @cursor.area)
        if idx 
          idx = @data.size unless @data[idx]
          @last_pos ||= self.cur_pos
          self.cur_pos = idx
          expand_selection(idx)
          refresh
        end
      else
        evt.skip()
        return
      end
    end

    # Handles a 'tab' keypress. Switches between hex/ascii areas
    def on_key_tab(evt)
      switch_areas
      refresh
    end

    # Selects all data loaded in the hex editor. like doing select all in
    # a text editor.
    def do_select_all
      return nil unless @data.size > 0
      select_range(0..@data.size-1)
      refresh
    end

    # Clipboard notes: Wx::Clipboard is not quite stable yet. Specifically
    # the copy/pasting of raw binary data with non-ascii bytes is buggy and
    # inconsistent between platforms. 
    #
    # This is a clipboard format that will work reliably *within* the app
    # but does not to/from other apps. 
    #
    # XXX We can't use Wx::DF_TEXT or other externally compatible formats
    # until (hopefully) problems are addressed in a future wxruby version.
    class RawDataObject < Wx::DataObject
      RAW_FORMAT = Wx::DataFormat.new("raw.format")
      attr_accessor :raw_data
      def initialize(data = nil)
        super()
        @raw_data = data
      end

      def get_all_formats(dir); [RAW_FORMAT]; end
      def set_data(format, buf); @raw_data = buf.dup; end
      def get_data_here(format); @raw_data; end
    end

    # Implements the clipboard 'copy' operation
    def do_clipboard_copy
      return nil unless sel=@selection and dat=@data[sel]
      # XXX i feel dirty
      if Wx::PLATFORM == "WXMAC"
        IO.popen("pbcopy", "w") {|io| io.write dat}
        stat = $?.success?
      else
        dobj = RawDataObject.new(dat)
        stat = Wx::Clipboard.open {|clip| clip.place dobj}
      end
      return stat
    end

    # Implements the clipboard 'cut' operation (calls do_clipboard_copy under
    # the hood -- then deletes the selection if it was successful)
    def do_clipboard_cut
      if do_clipboard_copy()
        pos = @selection.first
        self.gui_set_value(nil, '')
        self.cur_pos = pos
      end
    end

    # Implements the clipboard 'paste' operation
    def do_clipboard_paste
      dat = if Wx::PLATFORM == "WXMAC" 
        # XXX i feel dirty
         `pbpaste`
        else
          dobj=RawDataObject.new
          Wx::Clipboard.open {|clip| clip.fetch dobj}
          dobj.raw_data
        end

      self.gui_set_value(self.cur_pos, dat) if dat and dat.size > 0
    end
  end
end

