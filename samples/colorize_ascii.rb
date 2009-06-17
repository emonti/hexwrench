# highlights ascii characters as green, null as dark grey, and everything else 
# as medium-grey
#

raw_palette =  [[48,48,48]] +
               [[96,96,96]] * 31 +
               [[128,196,128]] * 96 +
               [[96,96,96]] * 128

@palette = raw_palette.map {|p| Wx::Brush.new(Wx::Colour.new(*p[0..2]))}
editor.post_paint_proc = lambda {|this,dc,idx,c,hX,aX,y| 
 brush = [@palette[c], Wx::TRANSPARENT_BRUSH]
 this.colorize_byte_bg(brush, dc, hX,aX,y)
}
editor.refresh
