-- turntable

util = require "util"
fileselect = require "fileselect"

function init_params()
  params:add_separator('Turntable')
  params:add_option('rpm', 'record rpm', rpmOptions, 1)
  params:set_action('rpm', function(x)
    if x == 1 then tt.rpm = 100/3 end
    if x == 2 then tt.rpm = 45 end
    if x == 3 then tt.rpm = 78 end
  end)
  
  ctrlSpeed = controlspec.def{min = 0.625, max = 1.6, warp = 'exp', step = 0.01, default = 1, units = 'x', quantum = 0.01, wrap = false}
  
  params:add_control('speed', 'Turntable Speed', ctrlSpeed)
  params:set_action('speed', function(x) tt.faderRate = x end)
  

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

  redraw_clock_id = clock.run(redraw_clock)
  play_clock_id = clock.run(play_clock)
  
  rpmOptions = { "33 1/3", "45", "78" }
  tt = {}
  tt.position = 270
  --tt.faderRate = 1
  tt.rpm = 33.3
  tt.playRate = 0.
  tt.destinationRate = 0.
  tt.inertia = 0.3

  init_params()

  playing = false
  paused = false
  weLoading = false

  heldKeys = {}
  
  softcut.event_render(copy_samples)
  waveform = {}
  waveform.isLoaded = {false, false, false, false, false, false, false, false}
  waveform.samples = {}
  waveform.channels = {}
  waveform.length = {}
  waveform.rate = {}
  
  --add samples
  file = {}
  
  -- clear buffer
  softcut.buffer_clear()
  for i=1, 2, 1 do
    -- enable voices
    softcut.enable(i,1)
    -- set voices to buffer 1
    softcut.buffer(i,1)
    -- set voices level to 1.0
    softcut.level(i,1.0)
    softcut.level_slew_time(i,0.5)
    softcut.pan(i,0)
    -- voices disable loop
    softcut.loop(i,1)
    softcut.loop_start(i,i)
    softcut.loop_end(i,10)
    softcut.position(i,0)
    -- set voices rate to 1.0 and no fade
    softcut.rate(i, tt.playRate)
    softcut.fade_time(i,0)
    -- disable voices play
    softcut.play(i,0)
  end

  --weIniting = false
  screenDirty = true
  
  --temp load a file
  softcut.buffer_read_stereo(_path.audio..'/Dynamite Remix/130 House Kick Loop 022 bpm120.wav', 0, 0, -1, 0, 1)

end

function newDestinationRate()
  
end

function copy_samples(ch, start, length, samples)
  --start = math.floor(start)
  for i = 1, samples, 1 do
    waveform.samples[i] = samples[i]
  end
  screenDirty = true
  waveform.isLoaded[start] = true
end

-- draw waveform
function redraw_sample()
  softcut.render_buffer(1, 0, 10, 256)
end

function load_file(file)
  if file and file ~= "cancel" then
    --if not track then track = currentTrack end
    --get file info
    local ch, length, rate = audio.file_info(file)
    --get length and limit to 1s
    local lengthInS = length * (1 / rate)
    print("sample length is "..lengthInS)
    --if lengthInS > 1 then lengthInS = 1 end
    --if waveform then
    --  waveform.length[track-1] = lengthInS
    --end
    -- erase section of buffer -- required?
    --softcut.buffer_clear_region(track, 1, 0, 0)
    --load file into buffer (file, start_source, start_destination, duration, preserve, mix)
    softcut.buffer_read_stereo(file, 0, 0, -1, 0, 1)
    --read samples into waveformSamples (channel)
    --redraw_sample()
    --set start/end play positions
    --softcut.loop_start(1,track + params:get('sampStart_'..track))
    softcut.loop_end(1, lengthInS)
    --update param
    --params:set("sample_"..track,file,0)
  end
  weLoading = false
end

--function play(track, level)
--  if not level then level = 1.0 end
	-- put the playhead in position (voice, position)
--	softcut.position(track, track + params:get('sampStart_'.. track))
  --set dynamic level
--  softcut.level(track, level * 10^(params:get('trackVolume_'..track) / 20))
	-- play from position to softcut.loop_end
--  softcut.play(track, 1)
--end

function drawIntro()
  if introCounter > 0 then
    introCounter = introCounter - 2
    screen.clear()
    drawBackground()
    if introCounter % (2 * 15) > 15 then
      drawSegmentsAll()
      drawClock("00:00")
    end
  else weIniting = false end
end

function drawBackground()
  screen.aa(1)
  --background
  screen.level(1)
  screen.rect(0,0,127,64)
  screen.fill()
  --platter
  screen.circle(32,32,30)
  screen.circle(32,32,2)
  --tone arm
  screen.level(5)
  screen.move(74,5)
  screen.line(68,30)
  screen.line(50, 50)
  screen.line(54, 42)
  screen.stroke()
  screen.aa(0)
  -- speed fader
  screen.rect(125,3, -10, 59)
  screen.pixel(114,32)
  screen.stroke()
end

function drawSegments()
  local nowRad = math.rad(util.round(tt.position, 360/24))
  --turntable
  screen.aa(1)
  screen.level(0)
  screen.arc(32, 32, 29, nowRad, nowRad + math.rad(360/48))
  screen.line(30,30)
  screen.fill()
  --speed fader
  screen.aa(0)
  screen.rect(124, ctrlSpeed:unmap(params:get('speed')) * 54 + 3, -9, 4)
  screen.fill()
  -- clock
  clockCounter = clockCounter - 1
  if clockCounter < 1 then
    clockCounter = 60
    osdate = os.date()
    osdate = osdate:sub(12,16)
  end  
  drawClock(osdate)
  --rate
  screen.move(80, 63)
  screen.text(tt.playRate)
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
  screen.fill()
end

function drawClock(x)
  screen.move(1,6)
  screen.text(x)
  screen.fill()
end

function drawWaveform()
	--waveform
--[[	screen.level(15)
	if waveform.isLoaded[currentTrack] then
  	for i=1, editArea.width, 1 do
  	  screen.move(i+editArea.border, editArea.border  + editArea.height * 0.5 + waveform.samples[(currentTrack) * editArea.width + i] * editArea.height * 0.5)
	    screen.line(i+editArea.border, editArea.border  + editArea.height * 0.5 + waveform.samples[(currentTrack) * editArea.width + i] * editArea.height * -0.5)
	    screen.stroke()
  	end
	else
	   screen.move(64,34)
	   screen.text_center("K3 to load sample")
	end
	screen.fill()]]--
end

function redraw()
  if weIniting then
    drawIntro()
  else
    if not weLoading then
    drawBackground()
    drawSegments()
    drawWaveform()
    end
  end

  screen.update()

end

function redraw_clock() ----- a clock that draws space
  while true do ------------- "while true do" means "do this forever"
    clock.sleep(1/15) ------- pause for a fifteenth of a second (aka 15fps)
    if (screenDirty or playing) and not weLoading then ---- only if something changed
      redraw() -------------- redraw space
      screen_dirty = false -- and everything is clean again
    end
  end
end

function play_clock()
  while true do
    clock.sleep(1/15) --60 ticks per second
    if playing or tt.playRate > 0.001 then
      tt.playRate = tt.playRate + ((params:get('speed') * tt.destinationRate - tt.playRate) * tt.inertia / 2)
      tt.position = tt.position + tt.playRate * (360 / ((60 / tt.rpm) * 15))
      screen.dirty = true
    else tt.playRate = 0 end
    softcut.rate(1,tt.playRate)
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
    if (e == 1) then
      tt.playRate = tt.playRate + d * 1/100
    end
    
    if (e == 2) then
    
    end
    
    if (e == 3) then
      params:delta('speed', d)
    end
  end
end

function key(k, z)
  
  heldKeys[k] = z == 1

  -- load sample
--[[	if sampleView and k == 3 and z == 0 and not heldKeys[1] then
	  weLoading = true
		fileselect.enter(_path.audio,load_file)
	end ]]--
	
  if z == 0 then
    if k == 1 then
      
    end
    if k == 2 then

    end
    if k == 3 then
      if playing then
        playing = false
        tt.destinationRate = 0
      else
        playing = true
        softcut.play(1,1)
        tt.destinationRate = 1
      end
    end
  end
end

function cleanup() --------------- cleanup() is automatically called on script close
  clock.cancel(redraw_clock_id) -- melt our clock vie the id we noted
end