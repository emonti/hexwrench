#!/usr/bin/env ruby

module Hexwrench
  begin 
    require 'wxirb'
    HAVE_WXIRB=true
  rescue LoadError
    HAVE_WXIRB=false
  end

  # Our main application window super-classes EditorFrameBase, which is
  # pulled in from XRC via gui.rb
  class EditorFrame < EditorFrameBase
    attr_accessor :filename
    attr_reader :editor, :config, :util_search, :util_jump

    def initialize(parent, opts={})
      super(parent)
      set_title "Hexwrench"

      # XXX how we gonna do config? hmm.
      @config ||= {}

      buf = opts.delete(:data)
      sizer = Wx::BoxSizer.new(Wx::HORIZONTAL)
      @editor = EditWindow.new(self, buf)
      if f=opts.delete(:filename)
        do_open_file(f)
      end

      sizer.add(@editor, 1, Wx::EXPAND|Wx::ALL, 2)
      self.sizer = sizer

      # Set up the 'jump' and 'search' toolbar utilities
  		@util_search.extend(UtilTextCtrl)
  		@util_jump.extend(UtilTextCtrl)

      @util_search.init
      @util_jump.init

      evt_text_enter @util_search, :on_search_util
      evt_text_enter @util_jump,   :on_jump_util

      @editor.instance_eval do
        # redirect the hex editor's 'ins_mode accessors to our own
        def ins_mode; parent.ins_mode ; end
        def ins_mode=(val); parent.ins_mode=(val) ; end
      end

      update_status_bar()
      init_menu_bar()

      # Custom event handlers from the EditorWindow
      evt_cursor_moved @editor, :on_cursor_move
      evt_data_changed @editor, :on_data_change

      evt_close :on_close

      @editor.set_focus
    end


    # Arranges all the event handlers, hot-keys, help text, and various 
    # other things related to menu items
    def init_menu_bar
      # File menu
      evt_menu @mitem_open, :on_menu_open
      evt_menu @mitem_new, :on_menu_new
      evt_menu(@mitem_save) {|evt| do_save() }
      evt_menu(@mitem_quit) {|evt| do_quit() }

      # Edit menu
      evt_menu @mitem_copy, :on_menu_copy
      evt_menu @mitem_cut, :on_menu_cut
      evt_menu @mitem_paste, :on_menu_paste
      evt_menu @mitem_select_all, :on_menu_select_all
      evt_menu @mitem_select_range, :on_menu_stub
      evt_menu @mitem_adv_search, :on_menu_stub

      # Tools menu
      evt_menu @mitem_data_inspector, :on_menu_data_inspector
      evt_menu @mitem_strings, :on_menu_strings

      mb = self.get_menu_bar

      # Create hot-key "accelerators" for menu items
      # Note: Clipboard hot-keys are handled in child controls
      shortcuts=[
        [Wx::MOD_CMD, ?o, @mitem_open],
        [Wx::MOD_CMD, ?n, @mitem_new],
        [Wx::MOD_CMD, ?s, @mitem_save],
        [Wx::MOD_CMD, ?q, @mitem_quit],
        [Wx::MOD_CMD, ?r, @mitem_select_range],
        [Wx::MOD_CMD, ?f, @mitem_adv_search],
        [Wx::MOD_CMD, ?i, @mitem_data_inspector],
        [Wx::MOD_CMD|Wx::MOD_SHIFT, ?s, @mitem_strings],
      ]

      # add the WXIRB console option to the tools menu if it's available
      if HAVE_WXIRB
        tools = mb.get_menu(mb.find_menu("Tools"))
        cons_item = Wx::MenuItem.new(
          tools, 
          Wx::ID_ANY, 
          "WxIRB Console", 
          "Toggle Console. Key: shift+cmd+C"
        )
        tools.append_separator
        tools.append_item(cons_item)
        @mitem_console = cons_item.get_id
        evt_menu @mitem_console, :on_menu_console
        shortcuts << [Wx::MOD_CMD|Wx::MOD_SHIFT, ?c, @mitem_console]
      end

      self.accelerator_table = Wx::AcceleratorTable[*shortcuts]

      # Set usage help so it will appear in status bar on mouse-over.
      # We need to look menu items up since they are given to us as ID
      # values by the XRC stub
      mb.find_item(@mitem_open).help="Open a file in editor. Key: cmd+o"
      mb.find_item(@mitem_new).help="Start a new buffer. Key: cmd+n"
      mb.find_item(@mitem_save).help="Save to a file. Key: cmd+s"
      mb.find_item(@mitem_quit).help="Quit program. Key: cmd+q"
      mb.find_item(@mitem_copy).help="Copy to clipboard. Key: cmd+c"
      mb.find_item(@mitem_cut).help="Cut to clipboard. Key: cmd+x"
      mb.find_item(@mitem_paste).help="Paste from clipboard. Key: cmd+v"
      mb.find_item(@mitem_select_all).help="Select entire buffer. Key: cmd+a"
      mb.find_item(@mitem_select_range).help="Select a range. Key: cmd+r"
      mb.find_item(@mitem_adv_search).help="Adv. search/replace. Key: cmd+f"
      mb.find_item(@mitem_data_inspector).help="Toggle Inspector. Key: cmd+i"
      mb.find_item(@mitem_strings).help="Toggle Strings. Key: shift+cmd+S"

      return mb
    end

    # Called when the user clicks on File -> Quit, closes the window,  or 
    # uses the CMD+q hotkey
    def do_quit
      self.close
    end

    # Called internally to update the status bar information
    def update_status_bar
      set_status_text("Offset: #{@editor.cur_pos}/#{@editor.data.size}", 0)

      sel_txt = if sel=@editor.selection
                  "#{sel.last-sel.first+1} bytes (#{sel})"
                else
                  "nil"
                end

      set_status_text("Selection: #{sel_txt}", 1)
    end

    # returns true/false depending on whether the "Ins:" toolbar checkbox is
    # checked
    def ins_mode ; @util_ins_chk.value ; end

    # Changes the "Ins:" toolbar checkbox to true/false (checked/unchecked)
    def ins_mode=(val);  @util_ins_chk.value=value ; end

    # Converts a string from hex to binary - used in the Hex Search feature
    # from the tool-bar
    def unhexify(val)
      if (val =~ /^[a-f0-9 ]+$/i)
        val.strip.gsub(/([a-f0-9]{1,2}) */i) { $1.hex.chr }
      end
    end

    # Handles Wx::CloseEvent. Confirms the user want's to close when
    # unsaved changes exist
    def on_close(evt)
      if @buffer_changed and not confirm_discard_changes?
        evt.can_veto=true
        evt.veto(true)
      else
        evt.skip(true)
      end
    end

    # Called when a user presses enter in the "Search" tool-bar textbox 
    def on_search_util(evt)
      val = @util_search.value
      kstr = @util_search_kind.string_selection
      do_search( val, EditWindow::AREAS[ {"Hex" => 0, "ASCII" => 1}[kstr] ] )
    end

    # Implements data search for the "Search" tool-bar item
    def do_search(val, kind)
      pos = @editor.cur_pos+1
      if ( 
          ( (kind == :ascii) or (kind == :hex and val=unhexify(val)) ) and 
          ( dat = @editor.data[pos..-1]) and
          ( idx = @editor.data[pos..-1].index(val) ) 
         )

        idx+=pos
        @editor.select_range(idx..idx+val.size-1)
        @editor.scroll_to_idx(idx)
        @editor.send("set_area_#{kind.to_s}")
        @editor.refresh
      else
        @util_search.do_error
      end
      @editor.set_focus
    end


    # Called when a user presses enter in the "Jump to" tool-bar textbox 
    def on_jump_util(evt)
      val = @util_jump.value
      if((m=/^(?:0?x([A-Fa-f0-9]+)|(\d+))$/.match(val)) and
         (idx = (m[1])? m[1].hex : m[2].to_i) and
         (@editor.data.size > idx))
        @editor.clear_selection()
        @editor.set_area_hex()
        @editor.move_to_idx(idx)
        @editor.refresh
      else
        @util_jump.do_error
      end
      @editor.set_focus
    end


    # Called from event handlers to clear all utility textbox errors
    def clear_util_errors
      @util_search.clear_error
      @util_jump.clear_error
    end


    # Set's the internal filename and window title info.
    def set_filename(name)
      @filename = name
      if name
        set_title "Hexwrench - "+
                  "#{File.basename(name)} "+
                  "(#{File.dirname(File.expand_path(name))})"
      else
        set_title "Hexwrench"
      end
    end

    # Stub indicating inactive menu items with a message dialog popup
    # note: XXX this is mostly to remind me to add these features =)
    def on_menu_stub(evt)
      Wx::MessageDialog.new(self, :caption => "Coming soon",
        :message => "Sorry. This feature not yet implemented.").show_modal
    end

    # Used to pop-up a confirmation dialog when the user is about to discard
    # changes in the editor.
    def confirm_discard_changes?
      ret = Wx::MessageDialog.new(
        self,
        :style => Wx::YES_NO|Wx::NO_DEFAULT,
        :caption => "Discard Changes?",
        :message => "Un-saved changes will be lost. Proceed anyway?"
      ).show_modal

      if ret == Wx::ID_YES
        @buffer_changed=nil
        return true
      else
        return false
      end
    end

    # Handles the File -> Open menu item.
    def on_menu_open(evt)
      return nil if @buffer_changed and not confirm_discard_changes?

      open_dlg = Wx::FileDialog.new( self, 
        :style => Wx::FD_OPEN|Wx::FD_FILE_MUST_EXIST)

      if open_dlg.show_modal == Wx::ID_OK 
        do_open_file(open_dlg.path)
      end
    end

    # Implements opening new files - pops up a error dialog if a file
    # error is encountered when reading the file.
    def do_open_file(filename)
      dat=nil
      begin
        dat = File.read(filename)
      rescue => e
        Wx::MessageDialog.new(self,
          :caption => "Error Opening File",
          :message => "#{e.class} - #{e.to_s}"
        ).show_modal
      end
      if dat
        set_filename(filename)
        @editor.set_data(dat) if dat
        @editor.move_to_idx(0)
        @new_buffer=true
      end
    end

    # Implements the  File -> New menu item. Replaces the current editor
    # buffer with an empty string.
    def on_menu_new(evt)
      return nil if @buffer_changed and not confirm_discard_changes?
      @new_buffer=true
      set_filename(nil)
      @editor.set_data nil
    end

    # Handles the user clicking on the Edit -> Select All menu item.
    # This method just calls the EditWindow.do_select_all() method
    def on_menu_select_all(evt)
      @editor.do_select_all
    end

    # Implements the File -> Save menu item.
    # This method will call  on_save_as if the user has not specified a 
    # file yet
    def do_save(filename = nil)
      filename ||= @filename
      if filename
        begin
          File.open(filename, "w") {|f| f.write @editor.data }
          @filename = filename
          @new_buffer=true
          @buffer_changed=false
        rescue => e
          Wx::MessageDialog.new(self,
            :caption => "Error Saving File",
            :message => "#{e.class} - #{e.to_s}"
          ).show_modal
        end
      else
        do_save_as()
      end
    end

    # Implements the 'Save As' feature - presenting the user with a file
    # save dialog.
    def do_save_as()
      save_dlg = Wx::FileDialog.new(self,
        :style => Wx::FD_SAVE|Wx::FD_OVERWRITE_PROMPT)
      if save_dlg.show_modal == Wx::ID_OK
        set_filename(save_dlg.path)
        do_save(save_dlg.path)
      end
    end

    # Handles the user clicking on the Edit -> Copy menu item.
    # This method just calls the EditWindow.do_clipboard_copy() method
    def on_menu_copy(evt)
      @editor.do_clipboard_copy()
    end

    # Handles the user clicking on the Edit -> Cut menu item.
    # This method just calls the EditWindow.do_clipboard_cut() method
    def on_menu_cut(evt)
      @editor.do_clipboard_cut()
    end

    # Handles the user clicking on the Edit -> Paste menu item.
    # This method just calls the EditWindow.do_clipboard_paste() method
    def on_menu_paste(evt)
      @editor.do_clipboard_paste()
    end

    # Toggles a strings listing pop-up when the user selects the 
    # 'Tools -> Strings' menu item
    def on_menu_strings(evt)
      if @strings
        @strings.destroy()
        @strings = nil
      else
        @strings = StringsFrame.new(self, @editor, @config[:strings_opts])
        @strings.accelerator_table = self.accelerator_table # clone hotkeys
        @strings.evt_window_destroy {|evt| @strings=nil;evt.skip() }
        @strings.show
      end
    end

    # Toggles the data inspector window on and off when user
    # selects the "Tools -> Data Inspector" menu item
    def on_menu_data_inspector(evt)
      if @d_inspector
        @d_inspector.destroy()
        @d_inspector = nil
      else
        @d_inspector = DataInspector.new(self, :editor => @editor)
        @d_inspector.accelerator_table = self.accelerator_table # clone hotkeys
        @d_inspector.evt_window_destroy { |evt| @d_inspector=nil; evt.skip() }
        @d_inspector.do_inspectors
        @d_inspector.show
      end
    end

    # Event handler for the Tools -> Console menu item.
    # This method only ever fires if wxirb is available. (based on HAVE_WXIRB)
    def on_menu_console(evt)
      return nil unless HAVE_WXIRB
      if $wxirb
        $wxirb.destroy()
        $wxirb = nil
      else
        $wxirb = WxIRB::BaseFrame.new(self, :binding => binding)
        $wxirb.accelerator_table = self.accelerator_table # clone hotkeys
        $wxirb.evt_window_destroy { |evt| $wxirb=nil; evt.skip() }
        $wxirb.show
      end
    end

    # Event handler for cursor movement to update various UI elements and
    # active tool windows.
    def on_cursor_move(evt)
      clear_util_errors
      update_status_bar()
      @d_inspector.do_inspectors if @d_inspector
      evt.skip()
    end

    # Event handler for data changes to update various UI elements and active
    # tool windows.
    def on_data_change(evt)
      if @new_buffer
        @new_buffer=false
      else
        @buffer_changed=true
      end
      clear_util_errors
      update_status_bar()
      @d_inspector.do_inspectors if @d_inspector
      @strings.notify_data_change if @strings
    end
  end


  # This module is used to extend a regular Wx::TextCtrl text box to display
  # greyed out text when idle which describes the control's purpose.
  # As soon as focus is set on the control, the text disappears.
  module UtilTextCtrl

    # This init method is called after creation since we don't
    # override 'new' in the XRC derived window element. Takes a hash of 
    # :name => value options. The only option is currently :default_text, 
    # which is the text to display when the control is idle. If :default_text 
    # is not specified, the control will use the initial value in the text box 
    # as default text.
    def init(opts={})
      @dflt_text = (opts[:default_text] || get_value.dup)
      evt_set_focus  :on_set_focus
      evt_kill_focus :on_kill_focus
      do_default_text
    end

    # Returns text to its greyed-out default display
    def do_default_text
      @error = false
      clear()
      set_default_style(Wx::TextAttr.new( Wx::LIGHT_GREY) )
      set_value(@dflt_text)
      set_default_style(Wx::TextAttr.new( Wx::BLACK) )
    end

    # Indicates an error in the text box by turning current text red.
    def do_error
      @error = true
      val = self.value
      clear()
      set_default_style(Wx::TextAttr.new( Wx::RED))
      set_value(val)
      set_default_style(Wx::TextAttr.new( Wx::BLACK))
      set_insertion_point_end
    end

    # Clears error text set by do_error and returns the textbox to its 
    # default text display.
    def clear_error
      if @error
        @error = false
        do_default_text
      end
    end

    # Event handler for when focus is set to this text control. Clears
    # default text in preparation for user input.
    def on_set_focus(evt)
      @error = false
      clear()
      set_default_style(Wx::TextAttr.new( Wx::BLACK))
      evt.skip()
    end

    # Event handler for when focus is lost to this text control. Returns
    # the text to its default display unless an error in input was flagged.
    def on_kill_focus(evt)
      do_default_text if not @error
      evt.skip()
    end
  end
end

