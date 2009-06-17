
# This class was automatically generated from XRC source. It is not
# recommended that this file is edited directly; instead, inherit from
# this class and extend its behaviour there.  
#
# Source file: ui/gui.xrc 
# Generated at: Sun Feb 15 15:08:37 -0600 2009

class Hexwrench::EditorFrameBase < Wx::Frame
	
	attr_reader :top_menu_bar, :mitem_open, :mitem_new, :mitem_save,
              :mitem_quit, :mitem_copy, :mitem_cut, :mitem_paste,
              :mitem_select_all, :mitem_select_range,
              :mitem_adv_search, :mitem_data_inspector,
              :mitem_strings, :util_bar, :util_jump, :util_search,
              :util_search_kind, :util_ins_chk, :status_bar
	
	def initialize(parent = nil)
		super()
		xml = Wx::XmlResource.get
		xml.flags = 2 # Wx::XRC_NO_SUBCLASSING
		xml.init_all_handlers
		xml.load(File.dirname(__FILE__) + "/ui/gui.xrc")
		xml.load_frame_subclass(self, parent, "editor_frame")

		finder = lambda do | x | 
			int_id = Wx::xrcid(x)
			begin
				Wx::Window.find_window_by_id(int_id, self) || int_id
			# Temporary hack to work around regression in 1.9.2; remove
			# begin/rescue clause in later versions
			rescue RuntimeError
				int_id
			end
		end
		
		@top_menu_bar = finder.call("top_menu_bar")
		@mitem_open = finder.call("mitem_open")
		@mitem_new = finder.call("mitem_new")
		@mitem_save = finder.call("mitem_save")
		@mitem_quit = finder.call("mitem_quit")
		@mitem_copy = finder.call("mitem_copy")
		@mitem_cut = finder.call("mitem_cut")
		@mitem_paste = finder.call("mitem_paste")
		@mitem_select_all = finder.call("mitem_select_all")
		@mitem_select_range = finder.call("mitem_select_range")
		@mitem_adv_search = finder.call("mitem_adv_search")
		@mitem_data_inspector = finder.call("mitem_data_inspector")
		@mitem_strings = finder.call("mitem_strings")
		@util_bar = finder.call("util_bar")
		@util_jump = finder.call("util_jump")
		@util_search = finder.call("util_search")
		@util_search_kind = finder.call("util_search_kind")
		@util_ins_chk = finder.call("util_ins_chk")
		@status_bar = finder.call("status_bar")
		if self.class.method_defined? "on_init"
			self.on_init()
		end
	end
end


