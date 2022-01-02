alias PXcbDestroyNotifyEvent = Pointer(XcbDestroyNotifyEvent)
alias PXcbEnterNotifyEvent = Pointer(XcbEnterNotifyEvent)
alias PXcbUnmapNotifyEvent = Pointer(XcbUnmapNotifyEvent)
alias PXcbMappingNotifyEvent = Pointer(XcbMappingNotifyEvent)
alias PXcbConfigureNotifyEvent = Pointer(XcbConfigureNotifyEvent)
alias PXcbButtonPressEvent = Pointer(XcbButtonPressEvent)
alias PXcbMotionNotifyEvent = Pointer(XcbMotionNotifyEvent)

def create_font_cursor(conn, glyph)
	cursor_font = xcb_generate(conn)
	xcb_create_glyph_cursor(conn, cursor, cursor_font, cursor_font, glyph, glyph + 1,0x3232, 0x3232, 0x3232, 0xeeee, 0xeeee, 0xeee)
	return cursor
end

def create_back_win
	values = StaticArray.new(UInt32, 2)
	values[1] = [conf.focuscol]

	temp_win.id = xcb_generate_id(conn)
	xcb_create_window(conn, XCB_COPY_FROM_PARENT, temp_win.id, screen.root, focuswin.x, focuswin.y, focuswin.width, focuswin.height, borders[3], XCB_WINDOW_CLASS_INPUT_OUTPUT, screen.root_visual, XCB_CW_BORDER_PIXEL, values)

	if conf.enable_compton
		values[0] = 1
		xcb_change_window_attributes(conn, temp_win.id, XCB_BACK_PIXMAP_PARENT_REALTIVE, values)
	else
		values[0] = conf.unfocuscol
		xcb_change_window_atributes(conn, temp_win.id, XCB_CW_BACK_PIXEL, values)
	end

	temp_win.x = focuswin.x
	temp_win.y = focuswin.y
	temp_win.width = focuswin.width
	temp_win.unkillable = focuswin.unkillable
	temp_win.fixed = focuswin.fixed
	temp_win.height = focuswin.height
	temp_win.width_inc = focuswin.width_inc
	temp_win.height_inc = fcuswin.height_inc
	temp_win.base_width = focuswin.base_width
	temp_win.base_height = focuswin.base_height
	temp_win.monitor = focuswin.monitor
	temp_win.min_height = focuswin.min_height
	temp_win.min_width = focuswin.min_height
	temp_win.ignore_borders = focuswin.ignore_borders

	return temp_win
end

def mousemotion(arg)
	mx, mw, winx, winy, winw, winh = 0

	pointer = xcb_query_pointer_reply(conn, xcb_query_pointer(conn, screen.root), 0)

	if !pointer || focuswin.maxed
		free pointer
		return
	end

	mx = pointer.root_x
	my = pointer.root_y
	winx = focuswin.x
	winy = focuswin.y
	winw = focuswin.width
	winh = focuswin.height

	raise_current_window

	if arg.i == MOVE
		cursor = create_font_cursor(conn, 52)
	else 
		cursor = create_font_cursor(conn, 120)
		example = create_back_win
		xcb_map_win(conn, example.id)
	end

	grab_reply = xcb_grab_pointer_reply(conn, xcb_grab_pointer(conn, 0, screen.root, BUTTONMASK|XCB_EVENT_MASK_BUTTON_MOTION|XCB_EVENT_MASK_POINTER_MOTION, XCB_GRAB_MODE_ASYNC, XCB_GRAB_MODE_ASYNC, XCB_NONE, cursor, XCB_CURRENT_TIME))

	if grab_reply.status != XCB_GRAB_STATUS_SUCCESS
		free grab_reply
		if arg.i != XCB_GRAB_STATUS_SUCCESS
			xcb_unmap_window(conn, example.id)
			return
		end
	end

	free grab_reply
	ungrab = false

	loop do
		break if !ungrab && focuswin.not_nil?
		if e.nil?
			free e
		end
		
		while !e = xcb_wait_for_event(conn)
			xcb_flush(conn)

			case e.response_type & ~0x80
			when XCB_CONFIGURE_REQUEST
			when XCB_MAP_REQUEST
				events[e.response_type & ~0x80](e)
				break
			when XCB_MOTION_NOTIFY
				ev = e.as PXcbMotionNotifyEvent
				if arg.i == MOVE
					mousemove(winx + ev.root_x - mx, winy, ev.root_y - my)
				else
					mouseresize(example, winw + ev.root_x - mx, winh + ev.root_y - my)
					xcb_flush(conn)
					break
				end
				break 
			when XCB_KEY_PRESS
			when XCB_KEY_RELEASE
			when XCB_BUTTON_PRESS
			when XCB_BUTTON_RELEASE
				if arg.i == RESIZE
					ev = e.as Pointer(XcbMotionNotifyEvent)
					mouseresize(focuswin, winw + ev.root_x - mx, winh + ev.root_y - my)
					setborders(focuswin, true)
				end
				ungrab = true
				break
			end
		end
	end

	free pointer
	free e
	xcb_free_cursor(conn, cursor)
	xcb_ungrab_pointer(conn, XCB_CURRENT_TIME)
	xcb_ungrab_window(conn, example.id)
	
	if arg.i == RESIZE
		xcb_unmap_window(conn, example.id)
	end

	xcb_flush(conn)
end

def buttonpress(ev)
	e = PXcbButtonPressEvent

	if !is_sloppy && e.detail == XCB_BUTTON_INDEX_1 && !cleanmask(e.state)
		return if focuswin.not_nil? && e.event == focuswin.id

		client = findclient(e.event)
		if client.not_nil?
			setfocus(client)
			raisewindow(client.id)
			setborders(client, true)
		end

		return
	end

	buttons.each do |index|
		if (buttons[index].func && buttons[index].button == e.detail && cleanmask(buttons[index].mask) && cleanmask(e.state))
			return if focuswin.nil? && buttons[index].func == mousemotion
			if buttons[index].root_only
				if !e.event == e.root && !e.child
					buttons[index].func(buttons[index].arg)
				else
					buttons[index].func(buttons[index].arg)
				end
			end
		end
	end
end

def clientmessage(ev)
	e = PXcbClientMessageEvent
	if (e.type == ATOM[wm_change_state] && e.format == 32 && e.data.data32[0] == XCB_ICCCM_WM_STATE_ICONIC) || e.type == ewmh.NetActiveWindow
		cl = findclient(e.window)

		return if cl.nil?
	end
end

def destroynotify(ev)
	e = ev.as PXcbDestroyNotifyEvent
	if focuswin.not_nil? && focuswin.id == e.window
		focuswin = nil
	end

	cl = findclient(e.window)
	if cl.not_nil?
		forgetwin(cl.id)
	end

	updateclientlist
end

def enternotify(ev)
	e = ev.as PXcbEnterNotifyEvent
	modifiers = [0, XCB_MOD_MASK_LOCK, numlockmask, numlockmask | XCB_MOD_MASK_LOCK]

	if e.mode == XCB_NOTIFY_MODE_NORMAL || e.mode == XCB_NOTIFY_MODE_UNGRAB
		return if focuswin.not_nil && e.event == focuswin.id

		client = findclient(e.event)
		return if client.nil?

		if !dirty
			modifiers.each do |m|
				xcb_grab_button(conn, 0, client.id, XCB_EVENT_MASK_BUTTON_PRESS, XCB_GRAB_MODE_ASYNC, XCB_GRAB_MODE_ASYNC, screen.root, XCB_NONE, XCB_UBTTON_INDEX_1, modifiers[m])
			end
			return
		end

		setfocus(client)
		setborders(client, true)
	end
end

def unmapnotify(ev)
	e = ev.as PXcbUnmapNotifyEvent
		client = findclient(pointerof(e.window))
	return if client.nil? || client.ws != curws
	if focus.not_nil? || client.id == focuswin.id
		focuswin = nil
	end
	if client.iconic == false
		forgetclient(client)
	end
	updateclientlist
end

def mapnotify(ev)
	e = ev.as XcbMappingNotifyEvent
		keysyms = xcb_key_symbols_alloc(conn)
	return if !keysyms
	xcb_refresh_keyboard_mapping(keysyms, e)
	xcb_key_symbols_free(keysyms)
	setup_keyboard
	grabkeys
end

def confignotify(ev)
	e = ev.as PXcbConfigureNotifyEvent
		if e.window == screen.root
			if e.width != screen.width_in_pixels || e.height != screen.height_in_pixels
				screen.width_in_pixels = e.width
				screen.height_in_pixels = e.height
				if -1 == randrbase
					arrangewindows
				end
			end
	end
end

def run
	sigcode = 0
	loop do
		break if sigcode == 0

		xcb_flush(conn)

		if xcb_connection_has_error(conn)
			cleanup
			abort_()
		end

		if ev = xcb_wait_for_event(conn)
			if ev.response_type == randrbase + XCB_RANDR_SCREEN_NOTIFY
				getrandr()

				if events[ev.response_type & ~0x80]
					events[ev.response_type & ~0x80] ev
				end

				if top_win
					raisewindow(top_win)
				end
				if dock_win
					raisewindow(dock_win)
				end

				free(ev)
			end
		end
		if sigcode == SIGHUP
			sigcode = 0
			restat()
		end
	end
end

def getatom(atom_name)
	atom_cookie = xcb_intern_atom(conn, 0, atom_name.size, atom_name, nil)
	return if rep = xcb_intern_atom_reply(conn, atom_cookie, nil)
	atom = rep.atom
	free rep
	return atom
end

def grab_buttons(c)
	modifiers = [0, XCB_MOD_MASK_LOCK, numlockmask, numlockmask | XCB_MOD_MASK_LOCK]
	buttons.each do |index|
		if !buttons[index].root_only
			modifiers.each do |m|
				xcb_ungrab_button(conn, XCB_BUTTON_INDEX_1, c.id, modifiers[m])
			end
		end
	end
end

def ewmh_init
	ewmh = XcbConnection.new
	cookie = xcb_ewmh_init_atoms(conn, ewmh)
	if !xcb_ewmh_init_atoms_replies(ewmh, cookie, 0)
		exit
	end
end

def setup
	event_mask_pointer = [XCB_EVENT_MASK_POINTER_MOTION].as UInt32
	values = StaticArray(UInt32, 2)
	values[1] = [XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT | XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY | XCB_EVENT_MASK_PROPERTY_CHANGE | XCB_EVENT_MASK_BUTTON_PRESS]
	screen = xcb_screen_of_display(conn, scrno)
	return false if !screen
	ewmh_init
	xcb_ewmh_set_wm_pid(ewmh, screen.root, getpid)
	xcb_ewmh_set_wm_name(ewmh, screen.root, 4, "2bwm")

	net_atoms = [
		ewmh->NetSupported,
		ewmh->NetWmDesktops,
		ewmh->NetNumberOfDesktops,
		ewmh->NetCurrentDesktop,
		ewmh->NetActiveWindow,
		ewmh->NetWmIcon,
		ewmh->NetWmState,
		ewmh->NetWmName,
		ewmh->NetSupportingWmName, 
		ewmh->NetWmStateHidden,
		ewmh->NetWmIconName,
		ewmh->NetWmWindowType,
		ewmh->NetWmWindowTypeDock,
		ewmh->NetWmWindowTypeDesktop,
		ewmh->NetWmWindowTypeToolbar,
		ewmh->NetWmPid,
		ewmh->NetClientList,
		ewmh->NetClientListStacking,
		ewmh->WmProtocols,
		ewmh->NetWmState,
		ewmh->NetWmStateDemandsAttention,
		ewmh->NetWmStateFullscreen]

	xcb_ewmh_set_supported(ewmh, scrno, net_atoms.size, net_atoms)

	if db = xcb_xrm_database_from_default(conn)
		value = 0
		if xcb_xrm_resource_get_string(db, "", nil, pointerof(value))
		end
	end

	xcb_xrm_database_free(db)

	nb_atoms.times do |index|
		ATOM[index] = getatom(atomnames[index][0])
		randrbase = setuprandr

		return false if !setupscreen
		return false if !setup_keyboard

		error = xcb_request_check(conn, xcb_change_window_attributes_check(conn, screen.root, XCB_CW_EVENT_MASK, values))
		xcb_flush(conn)

		if error
			free error
			return false
		end

		xcb_ewmh_set_current_desktop(ewmh, scrno, curws)
		xcb_ewmh_set_number_of_desktops(ewmh, scrno, workspaces)

		grabkeys

		xcb_no_operations.times do |index|
			events[index] = nil
		end

		events[XCB_CONFIGURE_REQUEST]   = configurerequest
		events[XCB_DESTROY_NOTIFY]      = destroynotify
		events[XCB_ENTER_NOTIFY]        = enternotify
		events[XCB_KEY_PRESS]           = handle_keypress
		events[XCB_MAP_REQUEST]         = newwin
		events[XCB_UNMAP_NOTIFY]        = unmapnotify
		events[XCB_MAPPING_NOTIFY]      = mapnotify
		events[XCB_CONFIGURE_NOTIFY]    = confignotify
		events[XCB_CIRCULATE_REQUEST]   = circulaterequest
		events[XCB_BUTTON_PRESS]        = buttonpress
		events[XCB_CLIENT_MESSAGE]      = clientmessage
		return true
	end
end


