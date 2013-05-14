#!/usr/bin/env ruby
=begin
  GamingCX new video checker
  Author: Gunbard
  
  Checks if a new GameCenter CX video's been released at gamingcx.com.
  Windows executable version shows a basic message box displaying name of new vid.
  
  Environment:
  Ruby 1.9.3, Tk 8.5, ActiveTcl 8.6, vtcl 1.6.1.a1 with patch
  
  Build into executable using ocra:
  ocra gcxchk.rb gcxchk.tcl --windows C:\Ruby193\lib\tcltk\ --no-autoload --no-enc
=end

require 'open-uri'
require 'win32/api'
require 'tk'

# CONSTANTS
SAVE_FILE = 'gcxsave.txt'
DATE_PATTERN = /<h2 class='date-header'><span>(.*)<\/span><\/h2>/
TITLE_PATTERN = /<h1 class='post-title entry-title'>\s*<a href='.*'>(.*)<\/a>\s*<\/h1>/
VERSION_NO = 0.1

# WIN32-API CONSTANTS
WM_USER             = 0x400
WM_TRAYICON         = WM_USER + 0x0001
WM_LBUTTONDBLCLK    = 0x0203
WM_LBUTTONUP        = 0x0202
GWL_WNDPROC         = -4

# TRAY ICON CONSTANTS
RT_ICON             = 3
DIFFERENCE          = 11
RT_GROUP_ICON       = RT_ICON + DIFFERENCE
NIF_MESSAGE         = 1
NIF_ICON            = 2
NIF_TIP             = 4
NIM_ADD             = 0
NIM_MODIFY          = 1
NIM_DELETE          = 2


# Tk/Tcl stuff
temp_dir = File.dirname($0)
Tk.tk_call('source', "#{temp_dir}/gcxchk.tcl")

root = TkRoot.new

top_window = root.winfo_children[0]
top_window.resizable = false, false
top_window.title = "GamingCX Checker v#{VERSION_NO}"
$window_handle = top_window.winfo_id

# Win32 Stuff
SetWindowLong     = Win32::API.new('SetWindowLong', 'LIK', 'L', 'user32')
CallWindowProc    = Win32::API.new('CallWindowProc', 'LIIIL', 'L', 'user32')
ExtractIcon       = Win32::API.new('ExtractIcon', 'LPI', 'L', 'shell32')
Shell_NotifyIcon  = Win32::API.new('Shell_NotifyIconA', 'LP', 'I', 'shell32')

# Get icon
hicoY = ExtractIcon.call(0, 'C:\WINDOWS\SYSTEM32\INETCPL.CPL', 21)  # Green tick

#-------WNDPROC OVERRIDE---------#
# Initialize old_window_proc
old_window_proc = 0

# Custom windowProc override
my_window_proc = Win32::API::Callback.new('LIIL', 'I') { |hwnd, umsg, wparam, lparam|
  
  if umsg == WM_TRAYICON
    if lparam == WM_LBUTTONUP
      # Restore window
      top_window.deiconify
	end
  end
  
  # I HAVE NO IDEA IF THIS IS THE ACTUAL MINIMIZE MESSAGE but it seems to work okay
  if umsg == 24
    if wparam == 0
      top_window.withdraw
    end
  end
  
  # Pass messages to original windowProc
  CallWindowProc.call(old_window_proc, hwnd, umsg, wparam, lparam)
}

# Intercept windowProc messages, original windowProc should be returned
old_window_proc = SetWindowLong.call($window_handle.to_i(16), GWL_WNDPROC, my_window_proc)
#------END WNDPROC OVERRIDE------#

$tiptxt = 'GamingCX Checker'
$pnid = [6*4+64, $window_handle.to_i(16), 'ruby'.hash, NIF_MESSAGE | NIF_ICON | NIF_TIP, WM_TRAYICON, hicoY].pack('LLIIIL') << $tiptxt << "\0"*(64 - $tiptxt.size)

ret = Shell_NotifyIcon.call(NIM_ADD, $pnid)
p 'Err: NIM_ADD' if ret == 0


$time_interval = 10 # minutes

# Allow first command line argument to set time
if ARGV.length > 0 and Integer(ARGV[0]) > 0
  $time_interval = Integer(ARGV[0])
end

$time_trigger = false # resets timer to new value if true

# Gets the widget in a window [window] given a path [str]
def wpath(window, str)
  window.winfo_children.each do |some_widget|
    if some_widget.path == str
      return some_widget
    end
  end
end

# Sleep handler so that program isn't completely unresponsive when sleeping
def sleep_brk(seconds) # breaks after n seconds or after interrupt
  while (seconds > 0)
    sleep 1
    seconds -= 1
	if $time_trigger
	  $time_trigger = false
	  break
	end
  end
end

# Validator for $text_interval
def valid_interval(text)
  if text.to_i.to_s == text
	return 0
  else
    return 1
  end
end

# Ruby tk widget bindings
ent_interval = wpath(top_window, ".top45.ent48")
but_apply = wpath(top_window, ".top45.but49")

ent_interval_textvar = TkVariable.new
ent_interval.textvariable = ent_interval_textvar
ent_interval_textvar.value = "#{$time_interval}"

# Click event for the 'Apply' button
but_apply_pressed = Proc.new {
  status = 0
  msg = ''
  status += valid_interval(ent_interval_textvar.value)
  
  if status > 0
    msg = 'Error: Invalid settings'
  else
	msg = 'Settings applied.'
    
    # Don't let time interval be zero
    if Integer(ent_interval_textvar.value) == 0
      ent_interval_textvar.value = 1
    end
    
    $time_interval = Integer(ent_interval_textvar.value)
	
    
    $time_trigger = true
  end
  
  msg_box = Tk.messageBox ({
    :type    => 'ok',  
    :icon    => 'info', 
    :title   => 'gcxchk',
    :message => msg
  })
}

# Bind click event to 'Apply' button
but_apply.command = but_apply_pressed

# Event handler for window close
root.winfo_children[0].protocol(:WM_DELETE_WINDOW) {
  # Clean up tray icon
  ret = Shell_NotifyIcon.call(NIM_DELETE, $pnid)
  p 'Err: NIM_DELETE' if ret == 0  
  
  # Kill. Using just 'exit' requires user to hit the close button twice for some reason
  if defined?(Ocra)
    exit # Don't want to kill when building
  else
	exit!
  end
}


# ---------------MAIN------------------#
puts 'Starting GamingCX checker...'
puts "Checking every #{$time_interval} minutes"

while true do
  prev_date = ''
  prev_title = ''

  # Get info from previous check, if it exists -- TODO: load config here, too
  if File.exists?("#{SAVE_FILE}")
    lines = []
    File.read("#{SAVE_FILE}").each_line do |line|
	  lines.push(line.chomp)
    end
    prev_date = lines[0]
    prev_title = lines[1]
  end

  # Open page and get new info
  page_source = open("http://www.gamingcx.com/").read
  dates = page_source.scan(DATE_PATTERN)
  titles = page_source.scan(TITLE_PATTERN)

  latest_date = dates[0][0]
  latest_title = titles[0][0]

  # Compare checks
  if prev_date and prev_title
    if prev_date == latest_date and prev_title == latest_title
	  puts "[#{Time.now}] Nothing new"
	else
	  # ========== PUT CUSTOM STUFF HERE ========= #
	  msg = "[#{Time.now}] New video uploaded: #{latest_title}"
	  msg_box = Tk.messageBox ({
		:type    => 'ok',  
		:icon    => 'info', 
		:title   => 'GamingCX Checker',
		:message => msg
	  })
	  # ========== END CUSTOM STUFF ============== #
    end
  end

  # Save current check info -- TODO: save config here, too
  File.open("#{SAVE_FILE}", "w"){ |file|
    file.puts "#{latest_date}"
    file.puts "#{latest_title}"
  }
  
  # Don't loop when building
  break if defined?(Ocra)
  
  # Check again in a bit
  sleep_brk(60 * $time_interval)
  
end

Tk.mainloop
