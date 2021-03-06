" vimmake.vim - Enhenced Customize Make system for vim
"
" Maintainer: skywind3000 (at) gmail.com
" Last change: 2016.11.25
"
" Execute customize tools: ~/.vim/vimmake.{name} directly:
"     :VimTool {name}
"
" Environment variables are set before executing:
"     $VIM_FILEPATH  - File name of current buffer with full path
"     $VIM_FILENAME  - File name of current buffer without path
"     $VIM_FILEDIR   - Full path of current buffer without the file name
"     $VIM_FILEEXT   - File extension of current buffer
"     $VIM_FILENOEXT - File name of current buffer without path and extension
"     $VIM_CWD       - Current directory
"     $VIM_RELDIR    - File path relativize to current directory
"     $VIM_RELNAME   - File name relativize to current directory 
"     $VIM_CWORD     - Current word under cursor
"     $VIM_CFILE     - Current filename under cursor
"     $VIM_GUI       - Is running under gui ?
"     $VIM_VERSION   - Value of v:version
"     $VIM_MODE      - Execute via 0:!, 1:makeprg, 2:system()
"     $VIM_SCRIPT    - Home path of tool scripts
"     $VIM_TARGET    - Target given after name as ":VimTool {name} {target}"
"     $VIM_COLUMNS   - How many columns in vim's screen
"     $VIM_LINES     - How many lines in vim's screen
"
" Settings:
"     g:vimmake_path - change the path of tools rather than ~/.vim/
"     g:vimmake_mode - dictionary of invoke mode of each tool
" 
" Setup mode for command: ~/.vim/vimmake.{name}
"     let g:vimmake_mode["name"] = "{mode}" 
"     {mode} can be: 
"		"normal"	- launch the tool and return to vim after exit (default)
"		"quickfix"	- launch and redirect output to quickfix
"		"bg"		- launch background and discard any output
"		"async"		- run in async mode and redirect output to quickfix
"	  
"	  note: "g:vimmake_mode" must be initialized to "{}" at first
" 
" Emake can be installed to /usr/local/bin to build C/C++ by: 
"     $ wget https://skywind3000.github.io/emake/emake.py
"     $ sudo python emake.py -i
"
"


"----------------------------------------------------------------------
"- Global Variables
"----------------------------------------------------------------------

" default tool location is ~/.vim which could be changed by g:vimmake_path
if !exists("g:vimmake_path")
	let g:vimmake_path = "~/.vim"
endif

" default cc executable
if !exists("g:vimmake_cc")
	let g:vimmake_cc = "gcc"
endif

" default gcc cflags
if !exists("g:vimmake_cflags")
	let g:vimmake_cflags = []
endif

" default VimMake mode
if !exists("g:vimmake_default")
	let g:vimmake_default = 0
endif

" tool modes
if !exists("g:vimmake_mode")
	let g:vimmake_mode = {}
endif

" using timer to update quickfix
if !exists('g:vimmake_build_timer')
	let g:vimmake_build_timer = 25
endif

" will be executed after async build finished
if !exists('g:vimmake_build_post')
	let g:vimmake_build_post = ''
endif

" build hook
if !exists('g:vimmake_build_hook')
	let g:vimmake_build_hook = ''
endif

" will be executed after output callback
if !exists('g:vimmake_build_update')
	let g:vimmake_build_update = ''
endif

" ring bell after exit
if !exists("g:vimmake_build_bell")
	let g:vimmake_build_bell = 0
endif

" signal to stop job
if !exists('g:vimmake_build_stop')
	let g:vimmake_build_stop = 'term'
endif

" check cursor of quickfix window in last line
if !exists('g:vimmake_build_last')
	let g:vimmake_build_last = 0
endif

" build status
if !exists('g:vimmake_build_status')
	let g:vimmake_build_status = ''
endif

" shell encoding
if !exists('g:vimmake_build_encoding')
	let g:vimmake_build_encoding = ''
endif

" trim empty lines ?
if !exists('g:vimmake_build_trim')
	let g:vimmake_build_trim = 0
endif

" use local errorformat
if !exists('g:vimmake_build_local')
	let g:vimmake_build_local = 0
endif

" trigger autocmd
if !exists('g:vimmake_build_auto')
	let g:vimmake_build_auto = ''
endif

" trigger autocmd event name for VimBuild
if !exists('g:vimmake_build_name')
	let g:vimmake_build_name = ''
endif

" build info
if !exists('g:vimmake_text')
	let g:vimmake_text = ''
endif

" whether to change directory
if !exists('g:vimmake_cwd')
	let g:vimmake_cwd = 0
endif

" main run
if !exists('g:vimmake_run_guess')
	let g:vimmake_run_guess = []
endif

" extname -> command
if !exists('g:vimmake_extrun')
	let g:vimmake_extrun = {}
endif


"----------------------------------------------------------------------
" Internal Definition
"----------------------------------------------------------------------

" path where vimmake.vim locates
let s:vimmake_home = fnamemodify(resolve(expand('<sfile>:p')), ':h')
let g:vimmake_home = s:vimmake_home
let s:vimmake_advance = 0	" internal usage, won't be modified by user
let g:vimmake_advance = 0	" external reference, may be modified by user
let s:vimmake_windows = 0	" internal usage, won't be modified by user
let g:vimmake_windows = 0	" external reference, may be modified by user

" check has advanced mode
if v:version >= 800 || has('patch-7.4.1829') || has('nvim')
	if has('job') && has('channel') && has('timers') && has('reltime') 
		let s:vimmake_advance = 1
		let g:vimmake_advance = 1
	elseif has('nvim')
		let s:vimmake_advance = 1
		let g:vimmake_advance = 1
	endif
endif

" check running in windows
if has('win32') || has('win64') || has('win95') || has('win16')
	let s:vimmake_windows = 1
	let g:vimmake_windows = 1
endif

" join two path
function! s:PathJoin(home, name)
    let l:size = strlen(a:home)
    if l:size == 0 | return a:name | endif
    let l:last = strpart(a:home, l:size - 1, 1)
    if has("win32") || has("win64") || has("win16") || has('win95')
        if l:last == "/" || l:last == "\\"
            return a:home . a:name
        else
            return a:home . '/' . a:name
        endif
    else
        if l:last == "/"
            return a:home . a:name
        else
            return a:home . '/' . a:name
        endif
    endif
endfunc

" error message
function! s:ErrorMsg(msg)
	echohl ErrorMsg
	echom 'ERROR: '. a:msg
	echohl NONE
endfunc

" show not support message
function! s:NotSupport()
	let msg = "required: +timers +channel +job +reltime and vim >= 7.4.1829"
	call s:ErrorMsg(msg)
endfunc

" run autocmd
function! s:AutoCmd(name)
	if has('autocmd')
		exec 'silent doautocmd User VimMake'.a:name
	endif
endfunc


"----------------------------------------------------------------------
"- build in background
"----------------------------------------------------------------------
let s:build_nvim = has('nvim')? 1 : 0
let s:build_info = { 'text':'', 'post':'', 'postsave':'' }
let s:build_output = {}
let s:build_head = 0
let s:build_tail = 0
let s:build_code = 0
let s:build_state = 0
let s:build_start = 0.0
let s:build_debug = 0
let s:build_quick = 0
let s:build_hold = 0
let s:build_scroll = 0
let s:build_congest = 0
let s:build_efm = &errorformat

" check :cbottom available, cursor in quick need to hold ?
if s:build_nvim == 0
	let s:build_quick = (v:version >= 800 || has('patch-7.4.1997'))? 1 : 0
	let s:build_hold = (v:version >= 800 || has('patch-7.4.2100'))? 0 : 1
else
	let s:build_quick = 0
	let s:build_hold = 1
endif

" check if we have vim 8.0.100
if s:build_nvim == 0 && v:version >= 800
	let s:build_congest = has('patch-8.0.100')? 1 : 0
	let s:build_congest = 0
endif

" scroll quickfix down
function! s:Vimmake_Build_Scroll()
	if getbufvar('%', '&buftype') == 'quickfix'
		silent exec 'normal! G'
	endif
endfunc

" check last line
function! s:Vimmake_Build_Cursor()
	if &buftype == 'quickfix'
		if s:build_hold != 0
			let w:vimmake_build_qfview = winsaveview()
		endif
		if line('.') != line('$')
			let s:build_last = 0
		endif
	endif
endfunc

" find quickfix window and scroll to the bottom then return last window
function! s:Vimmake_Build_AutoScroll()
	if s:build_quick == 0
		let l:winnr = winnr()			
		windo call s:Vimmake_Build_Scroll()
		silent exec ''.l:winnr.'wincmd w'
	else
		cbottom
	endif
endfunc

" restore view in neovim
function! s:Vimmake_Build_ViewReset()
	if &buftype == 'quickfix'
		if exists('w:vimmake_build_qfview')
			call winrestview(w:vimmake_build_qfview)
			unlet w:vimmake_build_qfview
		endif
	endif
endfunc

" neoview will reset cursor when caddexpr is invoked
function! s:Vimmake_Build_QuickReset()
	if &buftype == 'quickfix'
		call s:Vimmake_Build_ViewReset()
	else
		let l:winnr = winnr()
		windo call s:Vimmake_Build_ViewReset()
		silent exec ''.l:winnr.'wincmd w'
	endif
endfunc

" check if quickfix window can scroll now
function! s:Vimmake_Build_CheckScroll()
	if g:vimmake_build_last == 0
		if &buftype == 'quickfix'
			if s:build_hold != 0
				let w:vimmake_build_qfview = winsaveview()
			endif
			return (line('.') == line('$'))
		else
			return 1
		endif
	elseif g:vimmake_build_last == 1
		let s:build_last = 1
		let l:winnr = winnr()
		windo call s:Vimmake_Build_Cursor()
		silent exec ''.l:winnr.'wincmd w'
		return s:build_last
	elseif g:vimmake_build_last == 2
		return 1
	else
		if &buftype == 'quickfix'
			if s:build_hold != 0
				let w:vimmake_build_qfview = winsaveview()
			endif
			return (line('.') == line('$'))
		else
			return (!pumvisible())
		endif
	endif
endfunc

" invoked on timer or finished
function! s:Vimmake_Build_Update(count)
	let l:iconv = (g:vimmake_build_encoding != "")? 1 : 0
	let l:count = 0
	let l:total = 0
	let l:empty = [{'text':''}]
	let l:check = s:Vimmake_Build_CheckScroll()
	let l:efm1 = &g:efm
	let l:efm2 = &l:efm
	if g:vimmake_build_encoding == &encoding
		let l:iconv = 0 
	endif
	if &g:efm != s:build_efm && g:vimmake_build_local != 0
		let &l:efm = s:build_efm
		let &g:efm = s:build_efm
	endif
	let l:raw = (s:build_efm == '')? 1 : 0
	while s:build_tail < s:build_head
		let l:text = s:build_output[s:build_tail]
		if l:iconv != 0
			try
				let l:text = iconv(l:text, 
					\ g:vimmake_build_encoding, &encoding)
			catch /.*/
			endtry
		endif
		if l:text != ''
			if l:raw == 0
				caddexpr l:text
			else
				call setqflist([{'text':l:text}], 'a')
			endif
		elseif g:vimmake_build_trim == 0
			call setqflist(l:empty, 'a')
		endif
		let l:total += 1
		unlet s:build_output[s:build_tail]
		let s:build_tail += 1
		let l:count += 1
		if a:count > 0 && l:count >= a:count
			break
		endif
	endwhile
	if g:vimmake_build_local != 0
		if l:efm1 != &g:efm | let &g:efm = l:efm1 | endif
		if l:efm2 != &l:efm | let &l:efm = l:efm2 | endif
	endif
	if s:build_scroll != 0 && l:total > 0 && l:check != 0
		call s:Vimmake_Build_AutoScroll()
	elseif s:build_hold != 0
		call s:Vimmake_Build_QuickReset()
	endif
	if g:vimmake_build_update != ''
		exec g:vimmake_build_update
	endif
	return l:count
endfunc

" trigger autocmd
function! s:Vimmake_Build_AutoCmd(mode, auto)
	if !has('autocmd') | return | endif
	let name = (a:auto == '')? g:vimmake_build_auto : a:auto
	if name !~ '^\w\+$' || name == 'NONE' || name == '<NONE>'
		return
	endif
	if a:mode == 0
		silent exec 'doautocmd QuickFixCmdPre '. name
	else
		silent exec 'doautocmd QuickFixCmdPost '. name
	endif
endfunc

" invoked on timer
function! g:Vimmake_Build_OnTimer(id)
	let limit = (g:vimmake_build_timer < 10)? 10 : g:vimmake_build_timer
	" check on command line window
	if &ft == 'vim' && &buftype == 'nofile'
		return
	endif
	if s:build_nvim == 0
		if exists('s:build_job')
			call job_status(s:build_job)
		endif
	endif
	call s:Vimmake_Build_Update(limit)
	if and(s:build_state, 7) == 7
		if s:build_head == s:build_tail
			call s:Vimmake_Build_OnFinish()
		endif
	endif
endfunc

" invoked on "callback" when job output
function! s:Vimmake_Build_OnCallback(channel, text)
	if !exists("s:build_job")
		return
	endif
	if type(a:text) != 1
		return
	endif
	let s:build_output[s:build_head] = a:text
	let s:build_head += 1
	if s:build_congest != 0
		call s:Vimmake_Build_Update(-1)
	endif
endfunc

" because exit_cb and close_cb are disorder, we need OnFinish to guarantee
" both of then have already invoked
function! s:Vimmake_Build_OnFinish()
	" caddexpr '(OnFinish): '.a:what.' '.s:build_state
	if exists('s:build_job')
		unlet s:build_job
	endif
	if exists('s:build_timer')
		call timer_stop(s:build_timer)
		unlet s:build_timer
	endif
	call s:Vimmake_Build_Update(-1)
	let l:current = float2nr(reltimefloat(reltime()))
	let l:last = l:current - s:build_start
	let l:check = s:Vimmake_Build_CheckScroll()
	if s:build_code == 0
		let l:text = "[Finished in ".l:last." seconds]"
		call setqflist([{'text':l:text}], 'a')
		let g:vimmake_build_status = "success"
	else
		let l:text = 'with code '.s:build_code
		let l:text = "[Finished in ".l:last." seconds ".l:text."]"
		call setqflist([{'text':l:text}], 'a')
		let g:vimmake_build_status = "failure"
	endif
	let s:build_state = 0
	if s:build_scroll != 0 && l:check != 0
		call s:Vimmake_Build_AutoScroll()
	else
		call s:Vimmake_Build_QuickReset()
	endif
	if g:vimmake_build_bell != 0
		exec "norm! \<esc>"
	endif
	if s:build_info.post != ''
		exec s:build_info.post
		let s:build_info.post = ''
	endif
	if g:vimmake_build_post != ""
		exec g:vimmake_build_post
	endif
	call s:Vimmake_Build_AutoCmd(1, s:build_info.auto)
	call s:AutoCmd('Stop')
	redrawstatus!
	redraw
endfunc

" invoked on "close_cb" when channel closed
function! s:Vimmake_Build_OnClose(channel)
	" caddexpr "[close]"
	let s:build_debug = 1
	let l:limit = 128
	let l:options = {'timeout':0}
	while ch_status(a:channel) == 'buffered'
		let l:text = ch_read(a:channel, l:options)
		if l:text == '' " important when child process is killed
			let l:limit -= 1
			if l:limit < 0 | break | endif
		else
			call s:Vimmake_Build_OnCallback(a:channel, l:text)
		endif
	endwhile
	let s:build_debug = 0
	if exists('s:build_job')
		call job_status(s:build_job)
	endif
	let s:build_state = or(s:build_state, 4)
endfunc

" invoked on "exit_cb" when job exited
function! s:Vimmake_Build_OnExit(job, message)
	" caddexpr "[exit]: ".a:message." ".type(a:message)
	let s:build_code = a:message
	let s:build_state = or(s:build_state, 2)
endfunc

" invoked on neovim when stderr/stdout/exit
function! s:Vimmake_Build_NeoVim(job_id, data, event)
	if a:event == 'stdout' || a:event == 'stderr'
		let l:index = 0
		let l:size = len(a:data)
		while l:index < l:size
			let s:build_output[s:build_head] = a:data[l:index]
			let s:build_head += 1
			let l:index += 1
		endwhile
	elseif a:event == 'exit'
		if type(a:data) == type(1)
			let s:build_code = a:data
		endif
		let s:build_state = or(s:build_state, 6)
	endif
endfunc

" start background build
function! s:Vimmake_Build_Start(cmd)
	let l:running = 0
	let l:empty = 0
	if s:vimmake_advance == 0
		call s:NotSupport()
		return -1
	endif
	if exists('s:build_job')
		if s:build_nvim == 0
			if job_status(s:build_job) == 'run'
				let l:running = 1
			endif
		else
			if s:build_job > 0
				let l:running = 1
			endif
		endif
	endif
	if type(a:cmd) == 1
		if a:cmd == '' | let l:empty = 1 | endif
	elseif type(a:cmd) == 3
		if a:cmd == [] | let l:empty = 1 | endif
	endif
	if s:build_state != 0 || l:running != 0
		call s:ErrorMsg("background job is still running")
		return -2
	endif
	if l:empty != 0
		echo "empty cmd"
		return -3
	endif
	if !executable(&shell)
		let l:text = "invalid config in &shell and &shellcmdflag"
		call s:ErrorMsg(l:text . ", &shell must be an executable.")
		return -4
	endif
	let l:args = [&shell, &shellcmdflag]
	let l:name = []
	if type(a:cmd) == 1
		let l:name = a:cmd
		if s:vimmake_windows == 0
			let l:args += [a:cmd]
		else
			let l:tmp = fnamemodify(tempname(), ':h') . '\vimmake.cmd'
			let l:run = ['@echo off', a:cmd]
			call writefile(l:run, l:tmp)
			let l:args += [l:tmp]
		endif
	elseif type(a:cmd) == 3
		if s:vimmake_windows == 0
			let l:temp = []
			for l:item in a:cmd
				if index(['|', '`'], l:item) < 0
					let l:temp += [fnameescape(l:item)]
				else
					let l:temp += ['|']
				endif
			endfor
			let l:args += [join(l:temp, ' ')]
		else
			let l:args += a:cmd
		endif
		let l:vector = []
		for l:x in a:cmd
			let l:vector += ['"'.l:x.'"']
		endfor
		let l:name = join(l:vector, ', ')
	endif
	let s:build_efm = &errorformat
	call s:AutoCmd('Pre')
	if s:build_nvim == 0
		let l:options = {}
		let l:options['callback'] = function('s:Vimmake_Build_OnCallback')
		let l:options['close_cb'] = function('s:Vimmake_Build_OnClose')
		let l:options['exit_cb'] = function('s:Vimmake_Build_OnExit')
		let l:options['out_io'] = 'pipe'
		let l:options['err_io'] = 'out'
		let l:options['in_io'] = 'null'
		let l:options['out_mode'] = 'nl'
		let l:options['err_mode'] = 'nl'
		let l:options['stoponexit'] = 'term'
		if g:vimmake_build_stop != ''
			let l:options['stoponexit'] = g:vimmake_build_stop
		endif
		let s:build_job = job_start(l:args, l:options)
		let l:success = (job_status(s:build_job) != 'fail')? 1 : 0
	else
		let l:callbacks = {'shell': 'VimMake'}
		let l:callbacks['on_stdout'] = function('s:Vimmake_Build_NeoVim')
		let l:callbacks['on_stderr'] = function('s:Vimmake_Build_NeoVim')
		let l:callbacks['on_exit'] = function('s:Vimmake_Build_NeoVim')
		let s:build_job = jobstart(l:args, l:callbacks)
		let l:success = (s:build_job > 0)? 1 : 0
	endif
	if l:success != 0
		let s:build_output = {}
		let s:build_head = 0
		let s:build_tail = 0
		let l:arguments = "[".l:name."]"
		let l:title = ':VimMake '.l:name
		if s:build_nvim == 0
			if v:version >= 800 || has('patch-7.4.2210')
				call setqflist([], ' ', {'title':l:title})
			else
				call setqflist([], ' ')
			endif
		else
			call setqflist([], ' ', l:title)
		endif
		call setqflist([{'text':l:arguments}], 'a')
		let s:build_start = float2nr(reltimefloat(reltime()))
		let l:name = 'g:Vimmake_Build_OnTimer'
		let s:build_timer = timer_start(100, l:name, {'repeat':-1})
		let s:build_state = 1
		let g:vimmake_build_status = "running"
		let s:build_info.post = s:build_info.postsave
		let s:build_info.auto = s:build_info.autosave
		let s:build_info.postsave = ''
		let s:build_info.autosave = ''
		let g:vimmake_text = s:build_info.text
		call s:Vimmake_Build_AutoCmd(0, s:build_info.auto)
		call s:AutoCmd('Start')
		redrawstatus!
	else
		unlet s:build_job
		call s:ErrorMsg("Background job start failed '".a:cmd."'")
		redrawstatus!
		return -5
	endif
	return 0
endfunc

" stop background job
function! s:Vimmake_Build_Stop(how)
	let l:how = a:how
	if s:vimmake_advance == 0
		call s:NotSupport()
		return -1
	endif
	if l:how == '' | let l:how = 'term' | endif
	while s:build_head > s:build_tail
		let s:build_head -= 1
		unlet s:build_output[s:build_head]
	endwhile
	if exists('s:build_job')
		if s:build_nvim == 0
			if job_status(s:build_job) == 'run'
				call job_stop(s:build_job, l:how)
			else
				return -2
			endif
		else
			if s:build_job > 0
				call jobstop(s:build_job)
			endif
		endif
	else
		return -3
	endif
	return 0
endfunc

" get job status
function! s:Vimmake_Build_Status()
	if exists('s:build_job')
		if s:build_nvim == 0
			return job_status(s:build_job)
		else
			return 'run'
		endif
	else
		return 'none'
	endif
endfunc


"----------------------------------------------------------------------
" Utility
"----------------------------------------------------------------------
function! s:StringReplace(text, old, new)
	let l:data = split(a:text, a:old, 1)
	return join(l:data, a:new)
endfunc

" Trim leading and tailing spaces
function! s:StringStrip(text)
	return substitute(a:text, '^\s*\(.\{-}\)\s*$', '\1', '')
endfunc

" extract options from command
function! s:ExtractOpt(command) 
	let cmd = a:command
	let opts = {}
	while cmd =~# '^-\%(\w\+\)\%([= ]\|$\)'
		let opt = matchstr(cmd, '^-\zs\w\+')
		if cmd =~ '^-\w\+='
			let val = matchstr(cmd, '^-\w\+=\zs\%(\\.\|\S\)*')
		else
			let val = (opt == 'cwd')? '' : 1
		endif
		let opts[opt] = substitute(val, '\\\(\s\)', '\1', 'g')
		let cmd = substitute(cmd, '^-\w\+\%(=\%(\\.\|\S\)*\)\=\s*', '', '')
	endwhile
	let cmd = substitute(cmd, '^\s*\(.\{-}\)\s*$', '\1', '')
	let cmd = substitute(cmd, '^@\s*', '', '')
	let opts.cwd = get(opts, 'cwd', '')
	let opts.mode = get(opts, 'mode', '')
	let opts.save = get(opts, 'save', '')
	let opts.program = get(opts, 'program', '')
	let opts.post = get(opts, 'post', '')
	let opts.text = get(opts, 'text', '')
	let opts.auto = get(opts, 'auto', '')
	if 0
		echom 'cwd:'. opts.cwd
		echom 'mode:'. opts.mode
		echom 'save:'. opts.save
		echom 'program:'. opts.program
		echom 'command:'. cmd
	endif
	return [cmd, opts]
endfunc

" write script to a file and return filename
function! s:ScriptWrite(command, pause)
	let l:tmp = fnamemodify(tempname(), ':h') . '\vimmake.cmd'
	if s:vimmake_windows != 0
		let l:line = ['@echo off', 'call '.a:command]
		if a:pause != 0
			let l:line += ['pause']
		endif
	else
		let l:line = ['#! '.&shell]
		let l:line += [a:command]
		if a:pause != 0
			let l:line += ['read -n1 -rsp "press any key to confinue ..."']
		endif
		let l:tmp = tempname()
	endif
	if v:version >= 700
		call writefile(l:line, l:tmp)
	else
		exe 'redir ! > '.fnameescape(l:tmp)
		for l:index in range(len(l:line))
			silent echo l:line[l:index]
		endfor
		redir END
	endif
	return l:tmp
endfunc


"----------------------------------------------------------------------
" run commands
"----------------------------------------------------------------------
function! vimmake#run(bang, opts, args)
	let l:macros = {}
	let l:macros['VIM_FILEPATH'] = expand("%:p")
	let l:macros['VIM_FILENAME'] = expand("%:t")
	let l:macros['VIM_FILEDIR'] = expand("%:p:h")
	let l:macros['VIM_FILENOEXT'] = expand("%:t:r")
	let l:macros['VIM_FILEEXT'] = "." . expand("%:e")
	let l:macros['VIM_CWD'] = getcwd()
	let l:macros['VIM_RELDIR'] = expand("%:h:.")
	let l:macros['VIM_RENAME'] = expand("%:p:.")
	let l:macros['VIM_CWORD'] = expand("<cword>")
	let l:macros['VIM_CFILE'] = expand("<cfile>")
	let l:macros['VIM_VERSION'] = ''.v:version
	let l:macros['VIM_SVRNAME'] = v:servername
	let l:macros['VIM_COLUMNS'] = ''.&columns
	let l:macros['VIM_LINES'] = ''.&lines
	let l:macros['VIM_GUI'] = has('gui_running')? 1 : 0
	let l:macros['<cwd>'] = getcwd()
	let l:command = s:StringStrip(a:args)
	let cd = haslocaldir()? 'lcd ' : 'cd '
	let l:retval = ''

	" extract options
	let [l:command, l:opts] = s:ExtractOpt(l:command)

	" replace macros and setup environment variables
	for [l:key, l:val] in items(l:macros)
		let l:replace = (l:key[0] != '<')? '$('.l:key.')' : l:key
		if l:key[0] != '<'
			exec 'let $'.l:key.' = l:val'
		endif
		let l:command = s:StringReplace(l:command, l:replace, l:val)
		let l:opts.cwd = s:StringReplace(l:opts.cwd, l:replace, l:val)
		let l:opts.text = s:StringReplace(l:opts.text, l:replace, l:val)
	endfor

	" combine options
	if type(a:opts) == type({})
		for [l:key, l:val] in items(a:opts)
			let l:opts[l:key] = l:val
		endfor
	endif

	" check if need to save
	if get(l:opts, 'save', '')
		try
			silent update
		catch /.*/
		endtry
	endif

	if a:bang == '!'
		let s:build_scroll = 0
	else
		let s:build_scroll = 1
	endif

	" check mode
	let l:mode = g:vimmake_default

	if l:opts.mode != ''
		let l:mode = l:opts.mode
	endif

	" process makeprg/grepprg in -program=?
	let l:program = ""

	if l:opts.program == 'make'
		let l:program = &makeprg
	elseif l:opts.program == 'grep'
		let l:program = &grepprg
	endif

	if l:program != ''
		if l:program =~# '\$\*'
			let l:command = s:StringReplace(l:program, '\$\*', l:command)
		elseif l:command != ''
			let l:command = l:program . ' ' . l:command
		else
			let l:command = l:program
		endif
		let l:command = s:StringStrip(l:command)
	endif

	if l:command =~ '^\s*$'
		echohl ErrorMsg
		echom "E471: Command required"
		echohl NONE
		return
	endif

	if l:mode >= 10
		let l:opts.cmd = l:command
		let l:opts.mode = l:mode
		if g:vimmake_build_hook != ''
			exec 'call '. g:vimmake_build_hook .'(l:opts)'
		endif
		return
	endif

	if l:opts.cwd != ''
		let l:opts.savecwd = getcwd()
		try
			silent exec cd . fnameescape(l:opts.cwd)
		catch /.*/
			echohl ErrorMsg
			echom "E344: Can't find directory \"".l:opts.cwd."\" in -cwd"
			echohl NONE
			return
		endtry
	endif

	if l:mode == 0 && s:vimmake_advance != 0
		let s:build_info.postsave = opts.post
		let s:build_info.autosave = opts.auto
		let s:build_info.text = opts.text
		if s:Vimmake_Build_Start(l:command) != 0
			call s:AutoCmd('Error')
		endif
	elseif l:mode <= 1 && has('quickfix')
		call s:AutoCmd('Pre')
		call s:AutoCmd('Start')
		let l:makesave = &l:makeprg
		let l:script = s:ScriptWrite(l:command, 0)
		if s:vimmake_windows != 0
			let &l:makeprg = shellescape(l:script)
		else
			let &l:makeprg = 'source '. shellescape(l:script)
		endif
		if has('autocmd')
			call s:Vimmake_Build_AutoCmd(0, opts.auto)
			exec "noautocmd make!"
			call s:Vimmake_Build_AutoCmd(1, opts.auto)
		else
			exec "make!"
		endif
		let &l:makeprg = l:makesave
		if s:vimmake_windows == 0
			try | call delete(l:script) | catch | endtry
		endif
		let g:vimmake_text = opts.text
		if opts.post != '' 
			exec opts.post
		endif
		call s:AutoCmd('Stop')
	elseif l:mode <= 2
		call s:AutoCmd('Pre')
		call s:AutoCmd('Start')
		exec '!'. escape(l:command, '%#')
		let g:vimmake_text = opts.text
		if opts.post != '' 
			exec opts.post
		endif
		call s:AutoCmd('Stop')
	elseif l:mode == 3
		if s:vimmake_windows != 0 && has('python')
			let l:script = s:ScriptWrite(l:command, 0)
			py import subprocess, vim
			py argv = {'args': vim.eval('l:script'), 'shell': True}
			py argv['stdout'] = subprocess.PIPE
			py argv['stderr'] = subprocess.STDOUT
			py p = subprocess.Popen(**argv)
			py text = p.stdout.read()
			py p.stdout.close()
			py p.wait()
			if has('patch-7.4.145') || v:version >= 800
				let l:retval = pyeval('text')
			else
				py text = text.replace('\\', '\\\\').replace('"', '\\"')
				py text = text.replace('\n', '\\n').replace('\r', '\\r')
				py vim.command('let l:retval = "%s"'%text)
			endif
		elseif s:vimmake_windows != 0 && has('python3')
			let l:script = s:ScriptWrite(l:command, 0)
			py3 import subprocess, vim
			py3 argv = {'args': vim.eval('l:script'), 'shell': True}
			py3 argv['stdout'] = subprocess.PIPE
			py3 argv['stderr'] = subprocess.STDOUT
			py3 p = subprocess.Popen(**argv)
			py3 text = p.stdout.read()
			py3 p.stdout.close()
			py3 p.wait()
			if has('patch-7.4.145') || v:version >= 800
				let l:retval = py3eval('text')
			else
				py3 text = text.replace('\\', '\\\\').replace('"', '\\"')
				py3 text = text.replace('\n', '\\n').replace('\r', '\\r')
				py3 vim.command('let l:retval = "%s"'%text)
			endif
		else
			let l:retval = system(l:command)
		endif
		let g:vimmake_text = opts.text
		if opts.post != '' 
			exec opts.post
		endif
	elseif l:mode <= 5
		if s:vimmake_windows != 0 && has('gui_running')
			let l:ccc = shellescape(s:ScriptWrite(l:command, 1))
			if l:mode == 4
				silent exec '!start cmd /C '. l:ccc
			else
				silent exec '!start /b cmd /C '. l:ccc
			endif
			redraw
		else
			if l:mode == 4
				exec '!' . escape(l:command, '%#')
			else
				call system(l:command . ' &')
			endif
		endif
		let g:vimmake_text = opts.text
		if opts.post != '' 
			exec opts.post
		endif
	endif

	if l:opts.cwd != ''
		silent exec cd fnameescape(l:opts.savecwd)
	endif

	return l:retval
endfunc



"----------------------------------------------------------------------
" stop the background process
"----------------------------------------------------------------------
function! vimmake#stop(bang)
	if a:bang == ''
		return s:Vimmake_Build_Stop('term')
	else
		return s:Vimmake_Build_Stop('kill')
	endif
endfunc


"----------------------------------------------------------------------
" get status
"----------------------------------------------------------------------
function! vimmake#status()
	return s:Vimmake_Build_Status()
endfunc


"----------------------------------------------------------------------
" define commands
"----------------------------------------------------------------------
command! -bang -nargs=+ -complete=file VimMake 
		\ call vimmake#run("<bang>", '', <q-args>)

command! -bang -nargs=0 VimStop call vimmake#stop('<bang>')


"----------------------------------------------------------------------
"- Execute ~/.vim/vimmake.{command}
"----------------------------------------------------------------------
function! s:Cmd_VimTool(bang, ...)
	if a:0 == 0
		echohl ErrorMsg
		echom "E471: Argument required"
		echohl NONE
		return
	endif
	let l:command = a:1
	let l:target = ''
	if a:0 >= 2
		let l:target = a:2
	endif
	let l:home = expand(g:vimmake_path)
	let l:fullname = "vimmake." . l:command
	let l:fullname = s:PathJoin(l:home, l:fullname)
	let l:value = get(g:vimmake_mode, l:command, '')
	if a:bang != '!'
		try | silent update | catch | endtry
	endif
	if type(l:value) == 0 
		let l:mode = string(l:value) 
	else
		let l:mode = l:value
	endif
	let l:pos = stridx(l:mode, '/')
	let l:auto = ''
	if l:pos >= 0
		let l:size = len(l:mode)
		let l:auto = strpart(l:mode, l:pos + 1)
		let l:mode = strpart(l:mode, 0, l:pos)
		if len(l:auto) > 0
			let l:auto = '-auto='.escape(matchstr(l:auto, '\w*'), ' ')
		endif
	endif
	let $VIM_TARGET = l:target
	let $VIM_SCRIPT = g:vimmake_path
	let l:fullname = shellescape(l:fullname)
	if index(['', '0', 'normal', 'default'], l:mode) >= 0
		exec 'VimMake -mode=4 '.l:auto.' @ '. l:fullname
	elseif index(['1', 'quickfix', 'make', 'makeprg'], l:mode) >= 0
		exec 'VimMake -mode=1 '.l:auto.' @ '. l:fullname
	elseif index(['2', 'system', 'silent'], l:mode) >= 0
		exec 'VimMake -mode=3 '.l:auto.' @ '. l:fullname
	elseif index(['3', 'background', 'bg'], l:mode) >= 0
		exec 'VimMake -mode=5 '.l:auto.' @ '. l:fullname
	elseif index(['6', 'async', 'job', 'channel'], l:mode) >= 0
		exec 'VimMake -mode=0 '.l:auto.' @ '. l:fullname
	else
		call s:ErrorMsg("invalid mode: ".l:mode)
	endif
	return l:fullname
endfunc


" command definition
command! -bang -nargs=+ VimTool call s:Cmd_VimTool('<bang>', <f-args>)


"----------------------------------------------------------------------
"- Execute Files
"----------------------------------------------------------------------
function! s:ExecuteMe(mode)
	if a:mode == 0		" Execute current filename
		let l:fname = shellescape(expand("%:p"))
		if has('gui_running') && (s:vimmake_windows != 0)
			silent exec '!start cmd /C '. l:fname .' & pause'
		else
			exec '!' . l:fname
		endif
	elseif a:mode == 1	" Execute current filename without extname
		let l:fname = shellescape(expand("%:p:r"))
		if has('gui_running') && (s:vimmake_windows != 0)
			silent exec '!start cmd /C '. l:fname .' & pause'
		else
			exec '!' . l:fname
		endif
	elseif a:mode == 2
		let l:fname = shellescape(expand("%"))
		if has('gui_running') && (s:vimmake_windows != 0)
			silent exec '!start cmd /C emake -e '. l:fname .' & pause'
		else
			exec '!emake -e ' . l:fname
		endif
	else
	endif
endfunc


"----------------------------------------------------------------------
"- Execute current file by mode or filetype
"----------------------------------------------------------------------
function! s:Cmd_VimExecute(bang, ...)
	let cd = haslocaldir()? 'lcd ' : 'cd '
	let l:mode = ''
	let l:cwd = g:vimmake_cwd
	if a:0 >= 1
		let l:mode = a:1
	endif
	if a:0 >= 2
		if index(['1', 'true', 'True', 'yes', 'cwd', 'cd'], a:2) >= 0 
			let l:cwd = 1 
		endif
	endif
	if a:bang != '!'
		try | silent update | catch | endtry
	endif
	if bufname('%') == '' | return | endif
	let l:ext = expand("%:e")
	let l:savecwd = getcwd()
	if l:cwd > 0
		let l:dest = expand('%:p:h')
		try
			silent exec cd . fnameescape(l:dest)
		catch
		endtry
	endif
	if index(['', '0', 'file', 'filename'], l:mode) >= 0
		call s:ExecuteMe(0)
	elseif index(['1', 'main', 'mainname', 'noext', 'exe'], l:mode) >= 0
		call s:ExecuteMe(1)
	elseif index(['2', 'emake'], l:mode) >= 0
		call s:ExecuteMe(2)
	elseif index(['c', 'cpp', 'cc', 'm', 'mm', 'cxx'], l:ext) >= 0
		call s:ExecuteMe(1)
	elseif index(['h', 'hh', 'hpp'], l:ext) >= 0
		call s:ExecuteMe(1)
	elseif index(g:vimmake_run_guess, l:ext) >= 0
		call s:ExecuteMe(1)
	elseif index(['mak', 'emake'], l:ext) >= 0
		call s:ExecuteMe(2)
	elseif &filetype == "vim"
		exec 'source ' . fnameescape(expand("%"))
	elseif has('gui_running') && (s:vimmake_windows != 0)
		let l:cmd = get(g:vimmake_extrun, l:ext, '')
		let l:fname = shellescape(expand("%"))
		if l:cmd != ''
			silent exec '!start cmd /C '. l:cmd . ' ' . l:fname . ' & pause'
		elseif index(['py', 'pyw', 'pyc', 'pyo'], l:ext) >= 0
			silent exec '!start cmd /C python ' . l:fname . ' & pause'
		elseif l:ext  == "js"
			silent exec '!start cmd /C node ' . l:fname . ' & pause'
		elseif l:ext == 'sh'
			silent exec '!start cmd /C sh ' . l:fname . ' & pause'
		elseif l:ext == 'lua'
			silent exec '!start cmd /C lua ' . l:fname . ' & pause'
		elseif l:ext == 'pl'
			silent exec '!start cmd /C perl ' . l:fname . ' & pause'
		elseif l:ext == 'rb'
			silent exec '!start cmd /C ruby ' . l:fname . ' & pause'
		elseif l:ext == 'php'
			silent exec '!start cmd /C php ' . l:fname . ' & pause'
		elseif index(['osa', 'scpt', 'applescript'], l:ext) >= 0
			silent exec '!start cmd /C osascript '.l:fname.' & pause'
		else
			call s:ExecuteMe(0)
		endif
	else
		let l:cmd = get(g:vimmake_extrun, l:ext, '')
		if l:cmd != ''
			exec '!'. l:cmd . ' ' . shellescape(expand("%"))
		elseif index(['py', 'pyw', 'pyc', 'pyo'], l:ext) >= 0
			exec '!python ' . shellescape(expand("%"))
		elseif l:ext  == "js"
			exec '!node ' . shellescape(expand("%"))
		elseif l:ext == 'sh'
			exec '!sh ' . shellescape(expand("%"))
		elseif l:ext == 'lua'
			exec '!lua ' . shellescape(expand("%"))
		elseif l:ext == 'pl'
			exec '!perl ' . shellescape(expand("%"))
		elseif l:ext == 'rb'
			exec '!ruby ' . shellescape(expand("%"))
		elseif l:ext == 'php'
			exec '!php ' . shellescape(expand("%"))
		elseif index(['osa', 'scpt', 'applescript'], l:ext) >= 0
			exec '!osascript '. shellescape(expand('%'))
		else
			call s:ExecuteMe(0)
		endif
	endif
	if l:cwd > 0 
		try
			silent exec cd . fnameescape(l:savecwd)
		catch
		endtry
	endif
endfunc


" command definition
command! -bang -nargs=* VimExecute call s:Cmd_VimExecute('<bang>', <f-args>)
command! -bang -nargs=? VimRun call s:Cmd_VimExecute('<bang>', '?', <f-args>)



"----------------------------------------------------------------------
"- build via gcc/make/emake
"----------------------------------------------------------------------
function! s:Cmd_VimBuild(bang, ...)
	if bufname('%') == '' | return | endif
	if a:0 == 0
		echohl ErrorMsg
		echom "E471: Argument required"
		echohl NONE
		return
	endif
	if a:bang != '!'
		silent! update
	endif
	let l:what = a:1
	let l:conf = ""
	if a:0 >= 2
		let l:conf = a:2
	endif
	let vimmake = 'VimMake '
	if g:vimmake_build_name != ''
		let vimmake .= '-auto='.fnameescape(g:vimmake_build_name).' @ '
	endif
	if index(['0', 'gcc', 'cc'], l:what) >= 0
		let l:filename = expand("%")
		let l:source = shellescape(l:filename)
		let l:output = shellescape(fnamemodify(l:filename, ':r'))
		let l:cc = (g:vimmake_cc == '')? 'gcc' : g:vimmake_cc
		let l:flags = join(g:vimmake_cflags, ' ')
		let l:extname = expand("%:e")
		if index(['cpp', 'cc', 'cxx', 'mm'], l:extname) >= 0
			let l:flags .= ' -lstdc++'
		endif
		let l:cmd = l:cc . ' -Wall '. l:source . ' -o ' . l:output
		let l:cmd .= (l:conf == '')? '' : (' '. l:conf)
		exec vimmake .l:cmd . ' ' . l:flags 
	elseif index(['1', 'make'], l:what) >= 0
		if l:conf == ''
			exec vimmake .'make'
		else
			exec vimmake .'make '.shellescape(l:conf)
		endif
	elseif index(['2', 'emake'], l:what) >= 0
		let l:source = shellescape(expand("%"))
		if l:conf == ''
			exec vimmake .'emake "$(VIM_FILEPATH)"'
		else
			exec vimmake .'emake --ini='.shellescape(l:conf).' '.l:source
		endif
	endif
endfunc


command! -bang -nargs=* VimBuild call s:Cmd_VimBuild('<bang>', <f-args>)




"----------------------------------------------------------------------
" get full filename, '' as current cwd, '%' as current buffer
"----------------------------------------------------------------------
function! vimmake#fullname(f)
	let f = a:f
	if f =~ "'."
		try
			redir => m
			silent exe ':marks' f[1]
			redir END
			let f = split(split(m, '\n')[-1])[-1]
			let f = filereadable(f)? f : ''
		catch
			let f = '%'
		endtry
	endif
	let f = (f != '%')? f : expand('%')
	let f = fnamemodify(f, ':p')
	if s:vimmake_windows
		let f = substitute(f, "\\", '/', 'g')
	endif
	if len(f) > 1
		let size = len(f)
		if f[size - 1] == '/'
			let f = strpart(f, 0, size - 1)
		endif
	endif
	return f
endfunc


"----------------------------------------------------------------------
" guess root, '' as current direct, '%' as current buffer
"----------------------------------------------------------------------
function! vimmake#find_root(path, markers)
    function! s:guess_root(filename, markers)
        let fullname = vimmake#fullname(a:filename)
        if exists('b:vimmake_root')
            let l:vimmake_root = fnamemodify(b:vimmake_root, ':p')
            if stridx(fullfile, l:vimmake_root) == 0
                return b:vimmake_root
            endif
        endif
        if fullname =~ '^fugitive:/'
            if exists('b:git_dir')
                return fnamemodify(b:git_dir, ':h')
            endif
            return '' " skip any fugitive buffers early
        endif
		let pivot = fullname
		if !isdirectory(pivot)
			let pivot = fnamemodify(pivot, ':h')
		endif
		while 1
			let prev = pivot
			for marker in a:markers
				let newname = s:PathJoin(pivot, marker)
				if filereadable(newname)
					return pivot
				elseif isdirectory(newname)
					return pivot
				endif
			endfor
			let pivot = fnamemodify(pivot, ':h')
			if pivot == prev
				break
			endif
		endwhile
        return ''
    endfunc
	let root = s:guess_root(a:path, a:markers)
	if len(root)
		return vimmake#fullname(root)
	endif
	" Not found: return parent directory of current file / file itself.
	let fullname = vimmake#fullname(a:path)
	if isdirectory(fullname)
		return fullname
	endif
	return vimmake#fullname(fnamemodify(fullname, ':h'))
endfunc


function! vimmake#get_root(path)
	let markers = ['.project', '.git', '.hg', '.svn', '.root']
	if exists('g:vimmake_rootmarks')
		let markers = g:vimmake_rootmarks
	endif
	return vimmake#find_root(a:path, markers)
endfunc


"----------------------------------------------------------------------
" grep code
"----------------------------------------------------------------------
if !exists('g:vimmake_grep_exts')
	let g:vimmake_grep_exts = ['c', 'cpp', 'cc', 'h', 'hpp', 'hh', 'as']
	let g:vimmake_grep_exts += ['m', 'mm', 'py', 'js', 'php', 'java', 'vim']
	let g:vimmake_grep_exts += ['asm', 's', 'pyw', 'lua', 'go']
endif

function! vimmake#grep(text, cwd)
	let mode = get(g:, 'vimmake_grep_mode', '')
	if mode == ''
		let mode = (s:vimmake_windows == 0)? 'grep' : 'findstr'
	endif
	if mode == 'grep'
		let l:inc = ''
		for l:item in g:vimmake_grep_exts
			let l:inc .= " --include=*." . l:item
		endfor
        if a:cwd == '.' || a:cwd == ''
            let l:inc .= ' *'
        else
            let l:full = vimmake#fullname(a:cwd)
            let l:inc .= ' '.shellescape(l:full)
        endif
		let cmd = 'grep -n -s -R ' .shellescape(a:text). l:inc .' /dev/null'
		call vimmake#run('', {}, cmd)
	elseif mode == 'findstr'
		let l:inc = ''
		for l:item in g:vimmake_grep_exts
            if a:cwd == '.' || a:cwd == ''
                let l:inc .= '*.'.l:item.' '
            else
                let l:full = vimmake#fullname(a:cwd)
				let l:inc .= '"%CD%/*.'.l:item.'" '
            endif
		endfor
		let options = { 'cwd':a:cwd }
		call vimmake#run('', options, 'findstr /n /s /C:"'.a:text.'" '.l:inc)
	elseif mode == 'ag'
		let inc = []
		for item in g:vimmake_grep_exts
			let inc += ['\.'.item]
		endfor
		let cmd = 'ag '
		if len(inc) > 0
			let cmd .= '-G '.shellescape('('.join(inc, '|').')$'). ' '
		endif
		let cmd .= '--nogroup --nocolor '.shellescape(a:text)
        if a:cwd != '.' && a:cwd != ''
			let cmd .= ' '. shellescape(vimmake#fullname(a:cwd))
        endif
		call vimmake#run('', {'mode':0}, cmd)
	endif
endfunc

function! s:Cmd_GrepCode(bang, what, ...)
    let l:cwd = (a:0 == 0)? fnamemodify(expand('%'), ':h') : a:1
    if a:bang != ''
        let l:cwd = vimmake#get_root(l:cwd)
    endif
    if l:cwd != ''
        let l:cwd = vimmake#fullname(l:cwd)
    endif
    call vimmake#grep(a:what, l:cwd)
endfunc

command! -bang -nargs=+ GrepCode call s:Cmd_GrepCode('<bang>', <f-args>)



"----------------------------------------------------------------------
" cscope easy
"----------------------------------------------------------------------
function! s:Cmd_VimScope(what, name)
	let l:text = ''
	if a:what == '0' || a:what == 's'
		let l:text = 'symbol "'.a:name.'"'
	elseif a:what == '1' || a:what == 'g'
		let l:text = 'definition of "'.a:name.'"'
	elseif a:what == '2' || a:what == 'd'
		let l:text = 'functions called by "'.a:name.'"'
	elseif a:what == '3' || a:what == 'c'
		let l:text = 'functions calling "'.a:name.'"'
	elseif a:what == '4' || a:what == 't'
		let l:text = 'string "'.a:name.'"'
	elseif a:what == '6' || a:what == 'e'
		let l:text = 'egrep "'.a:name.'"'
	elseif a:what == '7' || a:what == 'f'
		let l:text = 'file "'.a:name.'"'
	elseif a:what == '8' || a:what == 'i'
		let l:text = 'files including "'.a:name.'"'
	elseif a:what == '9' || a:what == 'a'
		let l:text = 'assigned "'.a:name.'"'
	endif
	silent cexpr "[cscope ".a:what.": ".l:text."]"
	try
		exec 'cs find '.a:what.' '.fnameescape(a:name)
	catch /^Vim\%((\a\+)\)\=:E259/
		echohl ErrorMsg
		echo "E259: not find '".a:name."'"
		echohl NONE
	catch /^Vim\%((\a\+)\)\=:E567/
		echohl ErrorMsg
		echo "E567: no cscope connections"
		echohl NONE
	catch /^Vim\%((\a\+)\)\=:E/
		echohl ErrorMsg
		echo "ERROR: cscope error"
		echohl NONE
	endtry
endfunc

command! -nargs=* VimScope call s:Cmd_VimScope(<f-args>)


"----------------------------------------------------------------------
" Keymap Setup
"----------------------------------------------------------------------
function! vimmake#keymap()
	noremap <silent><F5> :VimExecute run<cr>
	noremap <silent><F6> :VimExecute filename<cr>
	noremap <silent><F7> :VimBuild emake<cr>
	noremap <silent><F8> :VimExecute emake<cr>
	noremap <silent><F9> :VimBuild gcc<cr>
	noremap <silent><F10> :call vimmake#toggle_quickfix(6)<cr>
	inoremap <silent><F5> <ESC>:VimExecute run<cr>
	inoremap <silent><F6> <ESC>:VimExecute filename<cr>
	inoremap <silent><F7> <ESC>:VimBuild emake<cr>
	inoremap <silent><F8> <ESC>:VimExecute emake<cr>
	inoremap <silent><F9> <ESC>:VimBuild gcc<cr>
	inoremap <silent><F10> <ESC>:call vimmake#toggle_quickfix(6)<cr>

	noremap <silent><F11> :cp<cr>
	noremap <silent><F12> :cn<cr>
	inoremap <silent><F11> <ESC>:cp<cr>
	inoremap <silent><F12> <ESC>:cn<cr>

	noremap <silent><leader>cp :cp<cr>
	noremap <silent><leader>cn :cn<cr>
	noremap <silent><leader>co :copen 6<cr>
	noremap <silent><leader>cl :cclose<cr>
	
	" VimTool startup
	for l:index in range(10)
		exec 'noremap <leader>c'.l:index.' :VimTool ' . l:index . '<cr>'
		if has('gui_running')
			let l:button = 'F'.l:index
			if l:index == 0 | let l:button = 'F10' | endif
			exec 'noremap <S-'.l:button.'> :VimTool '. l:index .'<cr>'
			exec 'inoremap <S-'.l:button.'> <ESC>:VimTool '. l:index .'<cr>'
		endif
	endfor
	
	" set keymap to GrepCode 
	noremap <silent><leader>cq :VimStop<cr>
	noremap <silent><leader>cQ :VimStop!<cr>
	noremap <silent><leader>cv :GrepCode <C-R>=expand("<cword>")<cr><cr>
	noremap <silent><leader>cx :GrepCode! <C-R>=expand("<cword>")<cr><cr>
	
	" set keymap to cscope
	if has("cscope")
		noremap <leader>cs :VimScope s <C-R>=expand("<cword>")<CR><CR>
		noremap <leader>cg :VimScope g <C-R>=expand("<cword>")<CR><CR>
		noremap <leader>cc :VimScope c <C-R>=expand("<cword>")<CR><CR>
		noremap <leader>ct :VimScope t <C-R>=expand("<cword>")<CR><CR>
		noremap <leader>ce :VimScope e <C-R>=expand("<cword>")<CR><CR>
		noremap <leader>cd :VimScope d <C-R>=expand("<cword>")<CR><CR>
		noremap <leader>ca :VimScope a <C-R>=expand("<cword>")<CR><CR>
		noremap <leader>cf :VimScope f <C-R>=expand("<cfile>")<CR><CR>
		noremap <leader>ci :VimScope i <C-R>=expand("<cfile>")<CR><CR>
		if v:version >= 800 || has('patch-7.4.2038')
			set cscopequickfix=s+,c+,d+,i+,t+,e+,g+,f+,a+
		else
			set cscopequickfix=s+,c+,d+,i+,t+,e+,g+,f+
		endif
		set csto=0
		set cst
		set csverb
	endif
	
	" cscope update
	noremap <leader>cz1 :call vimmake#update_tags('', 'ctags', '.tags')<cr>
	noremap <leader>cz2 :call vimmake#update_tags('', 'cs', '.cscope')<cr>
	noremap <leader>cz3 :call vimmake#update_tags('!', 'ctags', '.tags')<cr>
	noremap <leader>cz4 :call vimmake#update_tags('!', 'cs', '.cscope')<cr>
	noremap <leader>cz5 :call vimmake#update_tags('', 'py', '.cscopy')<cr>
	noremap <leader>cz6 :call vimmake#update_tags('!', 'py', '.cscopy')<cr>
endfunc

command! -nargs=0 VimmakeKeymap call vimmake#keymap()

function! vimmake#load()
endfunc

" toggle quickfix window
function! vimmake#toggle_quickfix(size, ...)
	let l:mode = (a:0 == 0)? 2 : (a:1)
	function! s:WindowCheck(mode)
		if &buftype == 'quickfix'
			let s:quickfix_open = 1
			return
		endif
		if a:mode == 0
			let w:quickfix_save = winsaveview()
		else
			if exists('w:quickfix_save')
				call winrestview(w:quickfix_save)
				unlet w:quickfix_save
			endif
		endif
	endfunc
	let s:quickfix_open = 0
	let l:winnr = winnr()			
	noautocmd windo call s:WindowCheck(0)
	noautocmd silent! exec ''.l:winnr.'wincmd w'
	if l:mode == 0
		if s:quickfix_open != 0
			silent! cclose
		endif
	elseif l:mode == 1
		if s:quickfix_open == 0
			exec 'botright copen '. ((a:size > 0)? a:size : ' ')
			wincmd k
		endif
	elseif l:mode == 2
		if s:quickfix_open == 0
			exec 'botright copen '. ((a:size > 0)? a:size : ' ')
			wincmd k
		else
			silent! cclose
		endif
	endif
	noautocmd windo call s:WindowCheck(1)
	noautocmd silent! exec ''.l:winnr.'wincmd w'
endfunc


" update filelist
function! vimmake#update_filelist(outname)
	let l:names = ['*.c', '*.cpp', '*.cc', '*.cxx']
	let l:names += ['*.h', '*.hpp', '*.hh', '*.py', '*.pyw', '*.java', '*.js']
	if has('win32') || has("win64") || has("win16")
		silent! exec '!dir /b ' . join(l:names, ',') . ' > '.a:outname
	else
		let l:cmd = ''
		let l:ccc = 1
		for l:name in l:names
			if l:ccc == 1
				let l:cmd .= ' -name "'.l:name . '"'
				let l:ccc = 0
			else
				let l:cmd .= ' -o -name "'.l:name. '"'
			endif
		endfor
		silent! exec '!find . ' . l:cmd . ' > '.a:outname
	endif
	redraw!
endfunc

if !exists('g:vimmake_ctags_flags')
	let g:vimmake_ctags_flags = '--fields=+iaS --extra=+q --c++-kinds=+px -n'
endif

function! vimmake#update_tags(cwd, mode, outname)
    if a:cwd == '!'
        let l:cwd = vimmake#get_root('%')
    else
        let l:cwd = vimmake#fullname(a:cwd)
        let l:cwd = fnamemodify(l:cwd, ':p:h')
    endif
    let l:cwd = substitute(l:cwd, '\\', '/', 'g')
	if a:mode == 'ctags' || a:mode == 'ct'
        let l:ctags = s:PathJoin(l:cwd, a:outname)
		if filereadable(l:ctags) 
			try | call delete(l:ctags) | catch | endtry
		endif
        let l:options = {}
        let l:options['cwd'] = l:cwd
        let l:command = 'ctags -R -f '. shellescape(l:ctags)
		let l:parameters = ' '. g:vimmake_ctags_flags. ' '
		let l:parameters .= '--sort=yes '
        call vimmake#run('', l:options, l:command . l:parameters . ' .')
	endif
	if index(['cscope', 'cs', 'pycscope', 'py'], a:mode) >= 0
		let l:fullname = s:PathJoin(l:cwd, a:outname)
		let l:fullname = vimmake#fullname(l:fullname)
		let l:fullname = substitute(l:fullname, '\\', '/', 'g')
		let l:cscope = fnameescape(l:fullname)
		silent! exec "cs kill ".l:cscope
		let l:command = "silent! cs add ".l:cscope.' '.fnameescape(l:cwd)." "
		let l:options = {}
		let l:options['post'] = l:command
		let l:options['cwd'] = l:cwd
		if filereadable(l:fullname) 
			try | call delete(l:fullname) | catch | endtry
		endif
		if a:mode == 'cscope' || a:mode == 'cs'
			let l:fullname = shellescape(l:fullname)
			call vimmake#run('', l:options, 'cscope -b -R -f '.l:fullname)
		elseif a:mode == 'pycscope' || a:mode == 'py'
			let l:fullname = shellescape(l:fullname)
			call vimmake#run('', l:options, 'pycscope -R -f '.l:fullname)
		endif
	endif
endfunc


" call python system to avoid window flicker on windows
function! vimmake#python_system(command)
	if s:vimmake_windows != 0 && has('python')
		py import subprocess, vim
		py argv = {'args': vim.eval('a:command'), 'shell': True}
		py argv['stdout'] = subprocess.PIPE
		py argv['stderr'] = subprocess.STDOUT
		py p = subprocess.Popen(**argv)
		py text = p.stdout.read()
		py p.stdout.close()
		py p.wait()
		if has('patch-7.4.145') || v:version >= 800
			let l:text = pyeval('text')
		else
			py text = text.replace('\\', '\\\\').replace('"', '\\"')
			py text = text.replace('\n', '\\n').replace('\r', '\\r')
			py vim.command('let l:text = "%s"'%text)
		endif
		return l:text
	elseif s:vimmake_windows != 0 && has('python3')
		py3 import subprocess, vim
		py3 argv = {'args': vim.eval('a:command'), 'shell': True}
		py3 argv['stdout'] = subprocess.PIPE
		py3 argv['stderr'] = subprocess.STDOUT
		py3 p = subprocess.Popen(**argv)
		py3 text = p.stdout.read()
		py3 p.stdout.close()
		py3 p.wait()
		if has('patch-7.4.145') || v:version >= 800
			let l:text = py3eval('text')
		else
			py3 text = text.replace('\\', '\\\\').replace('"', '\\"')
			py3 text = text.replace('\n', '\\n').replace('\r', '\\r')
			py3 vim.command('let l:text = "%s"'%text)
		endif
		return l:text
	else
		return system(a:command)
	endif
endfunc




