-- 
--         turntable v3.0.1
--         By Adam Staff
--
--
--
--               
--    ▼ instructions below ▼
--
-- K1+K3: Load a wav file
-- K3: play / stop
-- K2: pause
--
-- E1: pitch
-- E2: nudge
-- E3: small nudge
-- K1+E2: big nudge
-- K2+K3: backspin
--
-- K1+K2: toggle loop
-- K1+E3: waveform zoom
--
-- Map a MIDI controller to
-- 'Fader Position' to fade
-- between the turntable and
-- norns stereo inputs
--
-- see params for lots of
-- fun things to play with

engine.name = "turntable"
util = require "util"
fileselect = require "fileselect"

function init_params()
	-- Turntable controls
  params:add_separator('Turntable Controls')
  params:add_option('prpm', 'player rpm', rpmOptions, 1)
  params:set_action('prpm', function(x)
    if x == 1 then tt.rpm = 100/3 end
    if x == 2 then tt.rpm = 45 end
    if x == 3 then tt.rpm = 78 end
    tt.mismatch = tt.rpm / tt.recordSpeed
    tt.rps = tt.rpm / 60
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
  params:add_number('pitchSpeed', 'Pitch', -8, 8, 0)
  params:set_action('pitchSpeed', function(x) tt.pitch = 2^(x/12) end)
  params:add_number('stiffness', 'Turntable Stiffness', 1, 16, 12)
  params:set_action('stiffness', function(x) engine.stiffness(4 - (x/4)) end)
  params:add_number('noise', 'Turntable Noise', 0, 200, 0)
  params:set_action('noise', function(x) 
    x = x/50
    engine.tnoise(0.07 * x)
    engine.trumble(5 * x)
    engine.tmotor(3 * x)
  end)
  params:add_number('dust', 'Turntable Dust', 0, 200, 0)
  params:set_action('dust', function(x) engine.tdust(x/50) end)
  params:add_number('warble', 'Turntable Warble', 0, 200, 0)
  params:set_action('warble', function(x) engine.warble(x/800) end)
  params:add_number('riaa', 'Turntable RIAA Filter', -200, 200, 0)
  params:set_action('riaa', function(x) engine.riaa(x/100) end)
  params:add_number('filter', 'Turntable Lofi Filter', 0, 100, 0)
  params:set_action('filter', function(x) engine.filter(x/100) end)
  params:add_binary('loop', 'Loop', 'toggle', 0)
  params:add_binary('warningOn', 'Warning Timer', 'toggle', 1)
  params:add_number('warning', "Warning Length", 1, 60, 10)
  
  -- fader controls
  params:add_separator('Crossfader Controls')
  params:add_number('faderPosition', 'Fader Position', 0, 127, 0)
  params:add_option('faderSharpness', 'Crossfade Sharpness', faderOptions, 1)
  params:add_binary('equalPower', 'Equal Power Crossfade', 'toggle', 0)
  params:set_action('equalPower', function() setFader(params:get('faderPosition')) end )
  params:set_action('faderSharpness', function() setFader(params:get('faderPosition')) end)
  params:set_action('faderPosition', function() setFader(params:get('faderPosition')) end)
  
  --crow controls
  params:add_separator('crow')
  params:add_option('crowmode', 'mode', crowModes, 1)
  params:set_action('crowmode', function(mode)
    if mode == 1 then 
        crow.input[1].mode("change", 1.0, 0.1, "both")
        crow.input[1].change = crow_playstop
    end
    if mode == 2 then 
      crow.input[1].mode("stream", 0.1)
      crow.input[1].stream = crow_pos
    end
  end)
  
  --other controls
  params:add_separator('Other')
  params:add_option('zoom', 'waveform zoom', zoomOptions, 4, 'x')
  params:set_action('zoom', function(x) 
    waveform.zoom = zoomOptions[params:get('zoom')]
    if waveform.isLoaded then
      local pos = waveform.position / #waveform.samples
      redraw_sample(waveform.length * ((waveform.rate / 48000) / waveform.rate), waveform.length)
      --reset get position
      --local newamt = waveform.length / (1024 * waveform.zoom)
      --waveform.position = math.floor(pos * newamt)
    end
  end)  
  params:add_file('file', 'File: ', "")
  params:set_action('file', function(x) load_file(x) end)

  -- preset callbacks
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
  clockCounter = 60
  osdate = os.date()
  osdate = osdate:sub(12,16)
  jitter = 0
  
	-- encoder settings
  norns.enc.sens(2,1)
  norns.enc.accel(2,-2)

	-- clocks setup
  redraw_clock_id = clock.run(redraw_clock)
  play_clock_id = clock.run(play_clock)
  
  -- turntable variables
  rpmOptions = { "33 1/3", "45", "78" }
  zoomOptions = {0.125, 0.25, 0.5, 1, 1.5, 2, 4}
  faderOptions = {0, 1, 3, 10}
  tt = {}
  tt.rpm = 33.3
  tt.rps = 0.555
  tt.recordSize = 27
  tt.recordSpeed = 33.33
  tt.playRate = 0.
  tt.destinationRate = 0.
  tt.nudgeRate = 0.
  tt.inertia = 0.1
  tt.position = 0
  tt.pitch = 1
  tt.stickerSize = 9
  tt.stickerHole = 1
  tt.mismatch = 1
  tt.rateRate = 1
  tt.crowRate = 0
  
  --waveform variables
  waveform = {}
  waveform.isLoaded = false
  waveform.samples = {}
  waveform.rate = 48000
  waveform.position = 0
  waveform.length = 0
  waveform.lengthInS = 0
  waveform.zoom = 1
  
  heldKeys = {}
  
  --crow stuff
  crowModes = { "play / rate", "position / rate" }
  crowDestination = 0
  crow.input[2].mode("stream", 0.1)
  crow.input[2].stream = crow_rate 
  
  init_params()

  playing = false
  paused = false
  weLoading = false
  screenDirty = true
  
  pausedHand = 15
  
  --softcut view setup
  softcut.event_render(copy_samples)
  
  -- polls
  -- file position
  position_poll = poll.set("get_position")
  position_poll.callback = function(val)
    waveform.position = val
    tt.position = (tt.rps * waveform.lengthInS * val * 360) % 360
  end
  position_poll.time = 1/60
  position_poll:start()
	-- file loaded
	loaded_poll = poll.set("file_loaded")
	loaded_poll.callback = function(val)
	  print("waveformisLoaded = "..val)
	  waveform.isLoaded = val
	end
	loaded_poll:start()

end

function stopper()
  if waveform.position > 0.99 or waveform.position < 0 then
    print("hit end of file")
    tt.destinationRate = 0
    tt.playRate = 0
    tt.nudgeRate = 0
    engine.stiffness(0)
    engine.prate(0)
    engine.t_trigger(1)
    playing = false
    engine.stiffness(4 - (params:get("stiffness")/4))
	end
end

function copy_samples(ch, start, length, samples)
  print("loading "..#samples.." samples")
  waveform.samples = {}
  for i = 1, #samples, 1 do
    waveform.samples[i] = samples[i]
  end
  print("finished loading waveform")
  screenDirty = true
  waveform.isLoaded = true
end

function setFader(x)
	local y = 0
	local y2 = 1
	x = x/127
	if params:get('equalPower') == 1 then
		y = math.cos((math.pi / 4) * (2 * x - 1) ^ (2 * params:get('faderSharpness') + 1) + 1)
		y2 = math.cos((math.pi / 4) * (2 * (x - 1) - 1) ^ (2 * params:get('faderSharpness') + 1) + 1)
	else
		y = math.cos((math.pi / 2) * (x ^ params:get('faderSharpness')))
		y2 = math.cos((math.pi / 2) * ((x - 1) ^ params:get('faderSharpness')))
	end
	-- turntable engine level
	engine.overall(y)
	-- input level
	audio.level_adc(y2)
end

function redraw_sample(seconds, samples)
  samples = math.floor(samples / (1024 * waveform.zoom))
  softcut.render_buffer(1, 0, seconds, samples)
end

function load_file(file)
  if file and file ~= "cancel" then
    print('loading file '..file)
    --get file info
    local ch, length, rate = audio.file_info(file)
    --calc length in seconds
    if rate > 0 then
      waveform.lengthInS = length * ((rate / 48000) / rate)
    end
    print("sample length is "..waveform.lengthInS)
    print("sample rate is "..rate)
    print("file is"..file)
    waveform.rate = rate
    waveform.length = length
    tt.rateRate = rate / 48000
    --load file into buffer (file, start_source (s), start_destination (s), duration (s), preserve, mix)
    engine.fileload(file, length)
    --load file into buffer (file, start_source (s), start_destination (s), duration (s), preserve, mix)
    softcut.buffer_read_stereo(file, 0, 0, -1, 0, 1)
    --read samples into waveformSamples (number of samples)
    redraw_sample(waveform.lengthInS, length)
    --update param
    params:set("file",file,0)
  end
  weLoading = false
  heldKeys[1] = false
  screenDirty = true
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
  -- tone arm --
  screen.line_width(2)
  screen.level(15)
  screen.aa(1)
  local arm_base_x, arm_base_y = 69, 11
  local record_center_x, record_center_y = 32, 32
  -- Calculate the progress of the playback
  local progress = 0
  if waveform.isLoaded then
    progress = waveform.position
  end
  -- Calculate the position of the tone arm tip
  local start_radius = tt.recordSize - 1
  local end_radius = tt.stickerSize + 2
  local current_radius = start_radius - progress * (start_radius - end_radius)
  -- Set the fixed angle of the tone arm
  local arm_angle = math.pi * 1.75
  -- Calculate the tip position of the tone arm
  local tip_x = record_center_x + math.cos(arm_angle) * current_radius
  local tip_y = record_center_y - math.sin(arm_angle) * current_radius
  -- Calculate the arm vector
  local arm_vec_x = tip_x - arm_base_x
  local arm_vec_y = tip_y - arm_base_y
  local arm_length = math.sqrt(arm_vec_x^2 + arm_vec_y^2)
  -- Normalize the arm vector
  local arm_norm_x = arm_vec_x / arm_length
  local arm_norm_y = arm_vec_y / arm_length
  -- Calculate perpendicular vector (rotate 90 degrees)
  local perp_x = -arm_norm_y
  local perp_y = arm_norm_x
  -- Define control point offsets
  local cp1_along = 0.5  -- 30% along the arm
  local cp2_along = 0.7  -- 70% along the arm
  local cp_offset = -5   -- Perpendicular offset, adjust as needed
  -- Calculate control points
  local cp1_x = arm_base_x + arm_vec_x * cp1_along - perp_x * cp_offset
  local cp1_y = arm_base_y + arm_vec_y * cp1_along + perp_y * cp_offset
  local cp2_x = arm_base_x + arm_vec_x * cp2_along + perp_x * cp_offset
  local cp2_y = arm_base_y + arm_vec_y * cp2_along + perp_y * cp_offset
  -- Draw the tone arm
  screen.move(arm_base_x, arm_base_y)
  screen.curve(
    cp1_x, cp1_y,  -- Control point 1
    cp2_x, cp2_y,  -- Control point 2
    tip_x, tip_y   -- End point
  )
  -- Draw the tone arm head
  screen.move(tip_x, tip_y)
  screen.line_rel(2, -1)
  screen.stroke()
	-- Draw the tone arm head
	screen.move(tip_x, tip_y)
	screen.line_rel(2, -1)
	screen.stroke()
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
  screen.rect(74, 43 + 1.8 * params:get('pitchSpeed'), -6, 4)
  screen.fill()
  screen.level(15)
  screen.text_rotate(73, 60, params:get('pitchSpeed'), 270)
  screen.fill()
  if heldKeys[2] then
    pausedHand = pausedHand - 12
    if pausedHand < 0 then pausedHand = 0 end
  end
  if not heldKeys[2] and pausedHand < 15 then pausedHand = pausedHand + 3 end
	if pausedHand < 15 then
		screen.level(8)
		screen.circle(35, pausedHand + 60, 8)
		screen.fill()
	end
end

function drawWaveform()
  --warning flasher!!
  if params:get('loop') == 0 and params:get('warningOn') == 1 and math.floor((((waveform.length - waveform.position * 1024)) / waveform.length) * (waveform.length / waveform.rate)) < params:get('warning') and clockCounter < 15 and playing then
    screen.rect(80,0,48,64)
    screen.fill()
  end
	--waveform
	screen.aa(0)
	--waveform proper
	if waveform.isLoaded then
  	local width = 24
  	local x = 104
    local offset = -16
	  -- for each pixel row, from bottom up
    for i=1, 64, 1 do
      -- set the position we'll read a sample from
    	local drawhead = math.floor(waveform.position * #waveform.samples) + i + offset
    	if drawhead >= #waveform.samples then
    	  if params:get('loop') == 1 then drawhead = drawhead - #waveform.samples
    	  else drawhead = -1
    	  end
    	end
    	if drawhead < 1 then
      	if params:get('loop') == 1 then drawhead = drawhead + #waveform.samples 
      	else drawhead = -1
      	end
    	end
    	local sample = 0
    	if drawhead == -1 then sample = 0 else sample = waveform.samples[drawhead] end
    	if sample then
    	  if playhead == 1 then sample = 1 end
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

function drawUI()
  screen.level(15)
  if heldKeys[1] then
    screen.move(3,61)
    screen.text("loop: "..params:get('loop'))
    screen.move(105,61)
    screen.text("load?")
    screen.fill()
  end
  --[[ clock
  clockCounter = clockCounter - 1
  if clockCounter < 1 then
    clockCounter = 60
    osdate = os.date()
    osdate = osdate:sub(12,16)
  end  
  screen.move(0,6)
  screen.text(osdate)
  --]]
  --time elapsed / remaining
  if waveform.isLoaded then
    local remaining = util.s_to_hms(math.floor(((1 - waveform.position) * waveform.lengthInS)))
    remaining = remaining:sub(3,7)
    screen.text_rotate(128,26,"-"..remaining, 270)
  end
  --[[
  screen.level(15)
  screen.move(20,60)
  screen.text(util.round(tt.playRate, 0.01))
  --]]
end

function redraw()
  if not weLoading then
  	if screenDirty or tt.playRate > 0.001 or tt.playRate < 0.001 then
			screen.clear()
			drawBackground()
			drawWaveform()
			drawUI()
			screen.fill()
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

function play_clock() ------ churning out updated playrates, and passing them to SC
  while true do
    clock.sleep(1/24)
    if params:get('crowmode') == 1 then
      tt.playRate = tt.rateRate * tt.pitch * tt.mismatch * tt.destinationRate + tt.nudgeRate + tt.crowRate
      if tt.playRate < 0.01 and tt.playRate > -0.01 then 
        tt.playRate = 0
      end
      --print("setting rate to "..tt.playRate)
      engine.prate(tt.playRate)
    else
      --get time in seconds between here and there
      local distance = (crowDestination - waveform.position) * waveform.lengthInS
      local intime = util.clamp(tt.crowRate + 2.5, 0.01, 5)
      tt.playRate = distance / intime
      engine.prate(tt.playRate)
    end
    if params:get("loop") == 0 then
      stopper()
    end
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
      if not heldKeys[2] then
        params:set('zoom', params:get('zoom') - d)
      end
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
      params:set('pitchSpeed', util.round(params:get('pitchSpeed') + d/5, 0.2))
    end
  end
  screenDirty = true
end

function crow_playstop(v)
  if v then 
    playing = true 
    tt.destinationRate = 1
  else playing = false 
    tt.destinationRate = 0
  end
end

function crow_rate(v)
  tt.crowRate = (v/2.5)
end

function crow_pos(v)
  crowDestination = (v / 10 + 0.5)
end

function key(k, z)

  heldKeys[k] = z == 1

  -- load sample
  if (k == 3 and z ==0 and heldKeys[1]) then
	  weLoading = true
		fileselect.enter(_path.audio,load_file)
		loaded_poll:update()
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
      engine.stiffness(0.25)
    end
  end
  if k == 2 and z == 0 then
    paused = false
    if playing then
      tt.destinationRate = 1
      engine.stiffness(1.0)
    end
  end
  
  if k == 3 then
    if z == 1 and not heldKeys[1] and not heldKeys[2] and not weLoading then --PLAY/STOP
      if playing then
        playing = false
        tt.destinationRate = 0
      else
        playing = true
        tt.destinationRate = 1
      end
    end
  end
  
  if heldKeys[2] and heldKeys[3] then --wheeeell upp
    engine.stiffness(0.1)
    engine.prate(-400)
    engine.stiffness(2)
  end
  
  screenDirty = true
end

function cleanup() --------------- cleanup() is automatically called on script close
  clock.cancel(redraw_clock_id)
  clock.cancel(play_clock_id)
--  clock.cancel(sync_clock_id)
end