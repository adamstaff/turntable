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
    tt.mismatch = tt.rpm / tt.recordSpeed
  end)

  params:add_option('rrpm', 'record rpm', rpmOptions, 1)
  params:set_action('rrpm', function(x)
    if x == 1 then 
      tt.recordSpeed = 100/3
      tt.recordSize = 27
      tt.holeSize = 1
      tt.stickerSize = 9
    end
    if x == 2 then 
      tt.recordSpeed = 45
      tt.recordSize = 16
      tt.holeSize = 3
      tt.stickerSize = 7
    end
    if x == 3 then 
      tt.recordSpeed = 78
      tt.recordSize = 27
      tt.holeSize = 1
      tt.stickerSize = 9
    end
    tt.mismatch = tt.rpm / tt.recordSpeed
  end)

  params:add_number('faderSpeed', 'Pitch', -8, 8, 0)
  params:set_action('faderSpeed', function(x) tt.faderSpeed = 2^(x/12) end) 
  
  params:add_option('zoom', 'waveform zoom', zoomOptions, 3)
  params:set_action('zoom', function(x) 
    waveform.zoom = zoomOptions[params:get('zoom')]
    if waveform.isLoaded then
      redraw_sample(waveform.length * ((waveform.rate / 48000) / waveform.rate), waveform.length)
    end
  end)
  
  params:add_file('file', 'File: ', "")
  params:set_action('file', function(x) load_file(x) end)

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
  zoomOptions = {0.25, 0.5, 1, 2, 4}
  tt = {}
  tt.rpm = 33.3
  tt.recordSize = 27
  tt.recordSpeed = 33.33
  tt.playRate = 0.
  tt.destinationRate = 0.
  tt.nudgeRate = 0.
  tt.inertia = 0.1
  tt.position = 0
  tt.faderSpeed = 1
  tt.stickerSize = 9
  tt.stickerHole = 1
  tt.mismatch = 1
  
  waveform = {}
  waveform.isLoaded = false
  waveform.samples = {}
  waveform.rate = 44100
  waveform.position = 0
  waveform.length = 0
  waveform.zoom = 1
  
  heldKeys = {}
  
  init_params()

  playing = false
  paused = false
  weLoading = false
  
  pausedHand = 15
  
  softcut.event_render(copy_samples)
  softcut.event_phase(get_position)
  
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
  --load_file(_path.audio..'/Breaks/Adrift Break.wav', 0, 0, -1, 0, 1)
  --waveform.isLoaded = true
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
  samples = math.floor(samples / (1024 * waveform.zoom))
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
  if waveform.isLoaded then
      --record
    screen.level(0)
    screen.circle(32,32,tt.recordSize) --vinyl
    screen.fill()
    screen.level(15)
    screen.circle(32,32,tt.stickerSize) --sticker
    screen.fill()
    screen.level(0) -- label arc
    screen.arc(32,32,tt.stickerSize - 1, math.rad(tt.position - 90), math.rad(tt.position - 90) + 1)
    screen.arc(32,32,tt.holeSize + 1, math.rad(tt.position - 90), math.rad(tt.position - 90) + 1)
    screen.fill()
    --grooves
    screen.level(1)
    if playing then
      jitter = util.clamp(jitter + math.random(2)/25 - 0.06, -0.05,0.05)
    end
    screen.level(2)
    screen.arc(32,32, tt.recordSize - 2, 5.2 + jitter, 5.4 + jitter)
    screen.stroke()
    screen.arc(32,32, tt.recordSize - 2, 1.5 + jitter, 2 + jitter)
    screen.stroke()
  end
  screen.level(1)
  screen.circle(32,32,tt.holeSize) --spindle
  screen.fill()
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
  -- 
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
   -- arm
  screen.curve_rel(
    -19 - pro * 8, 
    25 - pro * 8, 
    5 - pro * 1, 
    5 - pro * 1, 
    -18 - pro * 11, 
    40 - pro * 8
  )
  screen.move_rel(-1,-1)
  screen.line_rel(2, -1) --head
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
  screen.rect(74, 43 + 1.8 * params:get('faderSpeed'), -6, 4)
  screen.fill()
  screen.level(15)
  screen.text_rotate(73, 60, params:get('faderSpeed'), 270)
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
  if waveform.isLoaded then
    local remaining = util.s_to_hms(math.floor((((waveform.length - waveform.position * 1024)) / waveform.length) * (waveform.length / waveform.rate)))
    remaining = remaining:sub(3,7)
    screen.text_rotate(128,26,"-"..remaining, 270)
  end
end

function drawWaveform()
  --warning flasher!!
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
			tt.position = tt.position + tt.playRate * ((tt.rpm/60)*360)/60
		end
  end

  screen.update()

end

function redraw_clock() ----- a clock that draws space
  while true do
    clock.sleep(1/60)
    if (screenDirty or playing) and not weLoading then ---- only if something changed
      redraw()
      screen_dirty = false
    end
    tt.nudgeRate = 0
  end
end

function play_clock()
  while true do
    clock.sleep(1/240)
    tt.playRate = tt.playRate + (tt.faderSpeed * (tt.nudgeRate + tt.destinationRate * tt.mismatch) - tt.playRate) * tt.inertia / (120/15)
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
      tt.nudgeRate = d * 10
    end
    if e == 3 then
      params:delta('zoom',d)
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
      params:set('faderSpeed', util.round(params:get('faderSpeed') + d/5, 0.2))
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
  
  if k == 2 and heldKeys[1] and z==0 then
    params:set('loop', math.abs(params:get('loop') - 1))
  end
  
  if k == 2 and not heldKeys[1] and z == 1 then
      paused = true
      if playing then 
        tt.destinationRate = 0
        tt.inertia = 0.7
      end
  end
  if k == 2 and not heldKeys[1] and z == 0 then
    paused = false
    if playing then
      tt.destinationRate = 1
      tt.inertia = 0.3
    end
  end
  
  if k == 3 then
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
  
  if heldKeys[2] and heldKeys[3] then --wheeeell upp
    tt.playRate = -40
    tt.inertia = 0.1
  end
  
  screenDirty = true
end

function cleanup() --------------- cleanup() is automatically called on script close
  clock.cancel(redraw_clock_id) -- melt our clock vie the id we noted
end
