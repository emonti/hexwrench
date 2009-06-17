# a byte-value heat colorizer based on colorbindump

raw_palette = [[0x30, 0x30, 0x30] ] +
              (1..31).map {|x| [96,96,96]} +
              (32..127).map {|x| [128,196,128]} +
              (128..255).map {|x| [96,96,96]}

@palette = raw_palette.map {|p| Wx::Brush.new(Wx::Colour.new(*p[0..2]))}
editor.post_paint_proc = lambda {|this,dc,idx,c,hX,aX,y| 
 brush = [@palette[c], Wx::TRANSPARENT_BRUSH]
 this.colorize_byte_bg(brush, dc, hX,aX,y)
}
editor.refresh
