-- turntable

util = require "util"
fileselect = require "fileselect"

function init_params()
  params:add_separator('Turntable')
  
  params:add_binary('loop', 'Loop', 'toggle', 1)
  params:set_action('loop', function(x)
    for i = 1, 2, 1 do
      softcut.loop(i,x)
    end
  end)
  
  params:add_binary('warningOn', 'Warning Timer', 'toggle', 1)
  params:add_number('warning', "Warning Length", 1, 60, 10)

  params:add_option('prpm', 'player rpm', rpmOptions, 1)
  params:set_action('prpm', function(x)
    if x == 1 then tt.rpm = 100/3 end
    if x == 2 then tt.rpm = 45 end
    if x == 3 then tt.rpm = 78 end
  end)

  params:add_option('rrpm', 'record rpm', rpmOptions, 1)
  params:set_action('rrpm', function(x)
    if x == 1 then tt.recordSpeed = 100/3
tt.recordSize = 27 end
    if x == 2 then tt.recordSpeed = 45
tt.recordSize = 27 end
    if x == 3 then tt.recordSize = 16
tt.recordSpeed = 78 end
  end)

  ctrlSpeed = controlspec.def{min = 0.625, max = 1.6, warp = 'exp', step = 0.01, default = 1, units = 'x', quantum = 0.01, wrap = false}
  
  params:add_control('speed', 'Turntable Speed', ctrlSpeed)
  params:set_action('speed', function(x) tt.faderRate = x end)
  
  params:add_text('file', 'File: ', "")

  -- here, we set our PSET callbacks for save / load:
  params.action_write = function(filename,name,number)
    os.execute("mkdir -p "..norns.state.data.."/"..number.."/")
    print("finished writing '"..filename.."'", number)
  end
  params.action_read = function(filename,silent,number)
    print("finished reading '"..filename.."'", number)
  end 
  params.action_delete = function(filename,name,number)
    norns.system_cmd("rm -r "..norns.state.data.."/"..number.."/")
    print("finished deleting '"..filename, number)
  end
  params:bang()
end

function init()
  weIniting = true
  introCounter = 5*15
  clockCounter = 60
  osdate = os.date()
  osdate = osdate:sub(12,16)
  jitter = 0
  
  norns.enc.sens(2,1)
  norns.enc.accel(2,-2)

  redraw_clock_id = clock.run(redraw_clock)
  play_clock_id = clock.run(play_clock)
  
  rpmOptions = { "33 1/3", "45", "78" }
  tt = {}
  --tt.faderRate = 1
  tt.rpm = 33.3
tt.recordSize = 27
tt.recordSpeed = 33.33
  tt.playRate = 0.
  tt.destinationRate = 0.
  tt.nudgeRate = 0.
  tt.inertia = 0.1
  tt.position = 0
  
  init_params()

  playing = false
  paused = false
  weLoading = false
  
  pausedHand = 15

  heldKeys = {}
  
  softcut.event_render(copy_samples)
  softcut.event_phase(get_position)
  
  waveform = {}
  waveform.isLoaded = false
  waveform.samples = {}
  waveform.rate = 44100
  waveform.position = 0
  waveform.length = false
  
  -- clear buffer
  softcut.buffer_clear()
  for i=1, 2, 1 do
    -- enable voices
    softcut.enable(i,1)
    -- set voices to buffers
    softcut.buffer(i,i)
    -- set voices level to 1.0
    softcut.level(i,1.0)
    softcut.level_slew_time(i,0.5)
    -- voices enable loop
    softcut.loop(i,1)
    softcut.loop_start(i,0)
    softcut.loop_end(i,10)
    softcut.position(i,0)
    -- set voices rate to 1.0 and no fade
    softcut.rate(i, 0)
    softcut.fade_time(i,0)
    -- disable voices play
    softcut.play(i,1)
  end
  softcut.pan(1,-1)
  softcut.pan(2,1)

  --weIniting = false
  screenDirty = true

  softcut.poll_start_phase(1)
  softcut.phase_quant(1, 1/60)
  
  --temp load a file
  load_file(_path.audio..'/Breaks/Adrift Break.wav', 0, 0, -1, 0, 1)
  waveform.isLoaded = true
end

function copy_samples(ch, start, length, samples)
	print("loading "..#samples.." samples")
  for i = 1, #samples, 1 do
    waveform.samples[i] = samples[i]
  end
  print("finished loading waveform")
  screenDirty = true
  waveform.isLoaded = true
end

function get_position(x, pos)
  pos = pos * (48000 / waveform.rate)
  waveform.position = pos * waveform.rate / 1024
	if params:get('loop') == 0 then
	  if pos > ((waveform.length - 1000) / waveform.rate) or pos < 0 then
	    print("hit end of file")
	    for i = 1, 2, 1 do
	      tt.destinationRate = 0
	      tt.playRate = 0
	      tt.nudgeRate = 0
	      softcut.position(i,0.1)
	      softcut.play(i,1)
	      playing = false
	     end
  	end
	end
end

function redraw_sample(seconds, samples)
  print("copying samples")
  samples = math.floor(samples / 1024)
  softcut.render_buffer(1, 0, seconds, samples)
end

function load_file(file)
  print('loading file '..file)
  if file and file ~= "cancel" then
    --get file info
    local ch, length, rate = audio.file_info(file)
    --calc length in seconds
    local lengthInS = length * ((rate / 48000) / rate)
    print("sample length is "..lengthInS)
    print("sample rate is "..rate)
    waveform.rate = rate
    waveform.length = length
    --load file into buffer (file, start_source (s), start_destination (s), duration (s), preserve, mix)
    softcut.buffer_read_stereo(file, 0, 0, -1, 0, 1)
    --read samples into waveformSamples (number of samples)
    redraw_sample(lengthInS, length)
    --set start/end loop positions
    for i=1, 2, 1 do
      softcut.loop_start(i,0)
      softcut.loop_end(i, lengthInS)
    end
    --update param
    params:set("file",file,0)
  end
  weLoading = false
  heldKeys[1] = false
end

function drawBackground()
  screen.aa(1)
  --background
  screen.level(1)
  screen.rect(0,0,80,64)
  screen.fill()
  --platter
 screen.level(5)
  screen.circle(32,32,30)  
  screen.fill()
    --record
  screen.level(0)
  screen.circle(32,32,tt.recordSize) --vinyl
  screen.fill()
  screen.level(15)
  screen.circle(32,32,10) --sticker
  screen.fill()
  screen.level(0)
  screen.arc(32,32,8,(tt.position / 360 - 90), (tt.position / 360 - 90) + 1)
  screen.arc(32,32,2,(tt.position / 360 - 90), (tt.position / 360 - 90) + 1)
  screen.fill()
  screen.level(1)
  screen.circle(32,32,1) --spindle
  screen.fill()
  --[[turntable
  local nowRad = math.rad(tt.position)
  screen.aa(1)
  screen.level(5)
  screen.arc(32, 32, 29, nowRad, nowRad + 1/3/14)
  screen.line(30,30)
  screen.fill()--]]
  --grooves
  screen.level(1)
  if playing then
    jitter = util.clamp(jitter + math.random(2)/25 - 0.06, -0.05,0.05)
  end
  screen.level(2)
  screen.arc(32,32, 25, 5.2 + jitter, 5.4 + jitter)
  screen.stroke()
  screen.arc(32,32, 25, 1.5 + jitter, 2 + jitter)
  screen.stroke()
  --accessories
  screen.aa(1)
  -- play/stop button
  if playing then screen.level(5) else screen.level(3) end
  screen.rect(3,61,7,-4)
  screen.fill()
  screen.rect(3,61,7,-4)
  screen.stroke()
  screen.aa(0) -- button text
  screen.level(2)
  screen.pixel(4,59)
  screen.pixel(6,59)
  screen.pixel(8,59)
  screen.fill()
  screen.aa(1)
  screen.level(5)
  screen.rect(13,60,3,1)
  screen.fill()
  screen.level(0)
  screen.circle(68, 12, 8) -- tone arm base
  screen.fill()
  screen.level(3)
  screen.circle(68, 12, 6) -- tone arm base
  screen.fill()
  screen.level(0)
  screen.circle(4,51,3) -- turny thing
  screen.fill()
  if playing then -- play light
    screen.level(10)
    screen.arc(4,51,3, 5.3,6.2)
    screen.arc(4,51,7, 5.3,6.2)
    screen.fill()
  end
  --tone arm
  screen.line_width(2)
  screen.level(15)
  screen.move(69,11)
  local pro = 0
  if waveform.isLoaded then
    pro = ((waveform.position * 1024) / waveform.length)
  end
  screen.aa(1)
  --[[
  screen.line_rel(-7.5 - pro * 2.8 ,10 - pro * 2) --short
  screen.line_rel(-1.5 - pro * 7, 19 - pro * 5) --long
  screen.line_rel(-7 - pro * 3.5, 9 - pro * 2.5) --short2
  ]]--
  screen.curve_rel(-19 - pro * 8, 25 - pro * 8, 5 - pro * 1, 5 - pro * 1, -18 - pro * 11, 40 - pro * 8)
  screen.move_rel(-1,-1)
  screen.line_rel(2 - pro * 1, -4 - pro * -0.5) --head
  screen.stroke()
  --[[
  screen.level(2)
  screen.line_rel(2,2)
  screen.stroke()]]--
  screen.line_width(1)
  -- speed fader base
  screen.level(5)
  screen.rect(75,62, -8, -35)
  screen.stroke()
  screen.level(2)
  screen.rect(74,61, -6, -33)
  screen.fill()
  screen.level(8)
  screen.pixel(74,44)
  screen.stroke()
  --speed fader
  screen.aa(0)
  screen.level(0)
  screen.rect(74, 27 + ctrlSpeed:unmap(params:get('speed')) * 30, -7, 4)
  screen.fill()
  screen.level(15)
  screen.text_rotate(73, 60, params:get'speed', 270)
  screen.fill()
  if heldKeys[2] then
    pausedHand = pausedHand - 12
    if pausedHand < 0 then pausedHand = 0 end
  end
  if not heldKeys[2] and pausedHand < 15 then pausedHand = pausedHand + 3 end
  screen.level(8)
  screen.circle(35, pausedHand + 60, 8)
  screen.fill()

end

function drawUI()
  screen.level(15)
  if heldKeys[1] then
    screen.move(3,61)
    screen.text("loop: "..params:get('loop'))
    screen.move(105,61)
    screen.text("load?")
    screen.fill()
  end
  -- clock
  clockCounter = clockCounter - 1
  if clockCounter < 1 then
    clockCounter = 60
    osdate = os.date()
    osdate = osdate:sub(12,16)
  end  
  screen.move(0,6)
  screen.text(osdate)
  --time elapsed / remaining
  if waveform.length then
    local remaining = util.s_to_hms(math.floor((((waveform.length - waveform.position * 1024)) / waveform.length) * (waveform.length / waveform.rate)))
    remaining = remaining:sub(3,7)
    screen.text_rotate(128,26,"-"..remaining, 270)
  end
end

function drawSegmentsAll()
  local nowRad = math.rad(util.round(tt.position, 360/24))
  --turntable
  screen.aa(1)
  screen.level(0)
  for i = 1, 48, 1 do
    local nowRad = nowRad * i / 5
    screen.arc(32, 32, 25, nowRad, nowRad + math.rad(360/48))
    screen.line(30,30)
  end
  screen.fill()
  --speed fader
  screen.aa(0)
  screen.rect(124,1+(tt.faderRate * 59/2), -9, 4)
end

function drawWaveform()
  --warning!!
  if params:get('loop') == 0 and params:get('warningOn') == 1 and math.floor((((waveform.length - waveform.position * 1024)) / waveform.length) * (waveform.length / waveform.rate)) < params:get('warning') and clockCounter < 15 then
    screen.rect(80,0,48,64)
    screen.fill()
  end
	--waveform
	screen.aa(0)
	--waveform proper
	if waveform.isLoaded then
    for i=1, 64, 1 do
    	local width = 24
    	local x = 104
      local offset = -16
    	local playhead = math.floor(waveform.position) + i + offset
    	if playhead >= #waveform.samples then playhead = playhead - #waveform.samples end
    	if playhead < 1 then playhead = playhead + #waveform.samples end
    	local sample = waveform.samples[playhead]
    	if sample then
    	  screen.level(math.floor(1 + math.abs(sample) * 15))
        screen.move(x + sample * width, 64-i)
  	    screen.line(x - sample * width, 64-i)
  	    screen.stroke()
  	 end
    end
  	screen.level(3)
	  for i=80, 128, 1 do
	    if i % 8 == 0 then 
	      screen.pixel(i + 4,47)
	    end
	  end
	else
	  screen.move(110,30)
	  screen.text_center("K1+K3 to")
	  screen.move(110,38)
	  screen.text_center("load file")
	end
end

function redraw()
  if not weLoading then
  	if screenDirty or tt.playRate > 0.001 or tt.playRate < 0.001 then
			screen.clear()
			drawBackground()
			drawWaveform()
			drawUI()
			screen.fill()
			tt.position = tt.position + tt.playRate * (360 / ((60 / tt.rpm) * 15))
		end
  end

  screen.update()

end

function redraw_clock() ----- a clock that draws space
  while true do ------------- "while true do" means "do this forever"
    clock.sleep(1/60) ------- pause for a fifteenth of a second (aka 15fps)
    if (screenDirty or playing) and not weLoading then ---- only if something changed
      redraw() -------------- redraw space
      screen_dirty = false -- and everything is clean again
    end
    tt.nudgeRate = 0
  end
end

function play_clock()
  while true do
    clock.sleep(1/240)
    tt.playRate = tt.playRate + ((params:get('speed') * (tt.nudgeRate + tt.destinationRate) - tt.playRate) * tt.inertia / (120/15))
    softcut.rate(1,tt.playRate)
    softcut.rate(2,tt.playRate)
  end
end

function enc(e, d)
  --SHIFTING
  if (heldKeys[1]) then
    paused = true
    if e == 1 then
    	
    end
    if e == 2 then
      
    end
    if e == 3 then
      
    end
  else
    paused = false
  --Not Shifting
    if (e == 3) then
      tt.nudgeRate = d / 10
    end
    
    if (e == 2) then
      tt.nudgeRate = d * 2
    end
    
    if (e == 1) then
      params:delta('speed', d)
    end
  end
  screenDirty = true
end

function key(k, z)

  heldKeys[k] = z == 1

  -- load sample
  if (k == 3 and z ==0 and heldKeys[1]) then
	  weLoading = true
		fileselect.enter(_path.audio,load_file)
	end
	
  if z == 0 then
    if k == 1 then
      
    end
  end

  if k == 3 then
    if z == 1 and heldKeys[2] then --WHEEEEEL UPPPP
      tt.nudgeRate = -60
    end
    if z == 1 and not heldKeys[1] and not heldKeys[2] and not weLoading then --PLAY/STOP
      if playing then
        playing = false
        tt.destinationRate = 0
      else
        playing = true
        softcut.voice_sync(2,1,0)
        softcut.play(1,1)
        softcut.play(2,1)
        tt.destinationRate = 1
      end
    end
  end

  
  if k == 2 and heldKeys[1] and z==0 then
    params:set('loop', math.abs(params:get('loop') - 1))
  end
  
  if k == 2 and not heldKeys[1] and z == 1 then
      paused = true
      if playing then 
        tt.destinationRate = 0
        tt.inertia = 0.7
      end
    else 
      paused = false
      if playing then
        tt.destinationRate = 1
        tt.inertia = 0.3
      end
    end
  
  screenDirty = true
end

function cleanup() --------------- cleanup() is automatically called on script close
  clock.cancel(redraw_clock_id) -- melt our clock vie the id we noted
end
