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
  waveform.isLoaded = false
  waveform.samples = {}
  
  --add samples
--  file = {}
  
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
    softcut.rate(i, tt.playRate)
    softcut.fade_time(i,0)
    -- disable voices play
    softcut.play(i,0)
  end
  softcut.pan(1,-1)
  softcut.pan(2,1)

  --weIniting = false
  screenDirty = true
  
  --temp load a file
  softcut.buffer_read_stereo(_path.audio..'/Empathy Stems/Your Energy (127bpm)/Anew Colour - Your Energy Stems (MUSIC).wav', 0, 0, -1, 0, 1)

end

function newDestinationRate()
  
end

function copy_samples(ch, start, length, samples)
  for i = 1, 128, 1 do
    waveform.samples[i] = samples[i]
  end
  print("finished loading waveform")
  screenDirty = true
  waveform.isLoaded = true
end

-- draw waveform
function redraw_sample(length)
  softcut.render_buffer(1, 0, length, 128)
end

function load_file(file)
  if file and file ~= "cancel" then
    --if not track then track = currentTrack end
    --get file info
    local ch, length, rate = audio.file_info(file)
    --get length and limit to 1s
    local lengthInS = length * (1 / rate)
    print("sample length is "..length)
    print("channels is "..ch)
    print("sample rate is "..rate)
    --load file into buffer (file, start_source, start_destination, duration, preserve, mix)
    softcut.buffer_read_stereo(file, 0, 0, -1, 0, 1)
    --read samples into waveformSamples (channel)
    redraw_sample(length)
    --set start/end play positions
    for i=1, 2, 1 do
      softcut.loop_start(i,0)
      softcut.loop_end(i, lengthInS)
    end
    --update param
    --params:set("sample_"..track,file,0)
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
  --record
  screen.level(0)
  screen.circle(32,32,29)
  screen.fill()
  screen.level(10)
  screen.circle(32,32,10)
  screen.fill()
  screen.level(1)
  screen.circle(32,32,3)
  screen.fill()
  --platter
  screen.level(5)
  screen.circle(32,32,2)
  screen.stroke()
  screen.circle(32,32,30)
  --accessories
  screen.rect(3,61,7,-4)
  screen.rect(13,60,3,1)
  screen.stroke()
  screen.level(6)
  screen.circle(4,52,2)
  screen.fill()
  screen.level(0)
  screen.circle(68, 12, 8)
  screen.fill()
  screen.level(3)
  screen.circle(68, 12, 6)
  screen.fill()
  --tone arm
  screen.level(8)
  screen.move(68,12)
  screen.line(59, 30)
  screen.line(57, 40)
  screen.line(48, 50)
  screen.line(50, 46)
  screen.stroke()
  screen.aa(0)
  -- speed fader
  screen.level(4)
  screen.rect(75,62, -8, -35)
  screen.stroke()
  screen.level(2)
  screen.rect(74,61, -6, -33)
  screen.fill()
  screen.level(8)
  screen.pixel(74,44)
  screen.stroke()
end

function drawSegments()
  local nowRad = math.rad(util.round(tt.position, 360/24))
  --turntable
  screen.aa(1)
  screen.level(3)
  screen.arc(32, 32, 29, nowRad, nowRad + 1/3/14)
  screen.line(30,30)
  screen.fill()
  --grooves
  screen.level(2)
  screen.arc(32,32, 25, 5.2, 5.4)
  screen.stroke()
  screen.arc(32,32, 25, 2, 3,5)
  screen.stroke()
  --speed fader
  screen.aa(0)
  screen.level(0)
  screen.rect(74, 27 + ctrlSpeed:unmap(params:get('speed')) * 30, -7, 4)
  screen.fill()
  screen.level(15)
  screen.text_rotate(73, 60, params:get'speed', 270)
  -- clock
  clockCounter = clockCounter - 1
  if clockCounter < 1 then
    clockCounter = 60
    osdate = os.date()
    osdate = osdate:sub(12,16)
  end  
  drawClock(osdate)
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
  screen.move(75,6)
  screen.text_right(x)
  screen.fill()
end

function drawWaveform()
	--waveform
	screen.level(8)
	if waveform.isLoaded then
    for i=1, 128, 1 do
      screen.move(100 + waveform.samples[i] * 20, 64-i)
	    screen.line(100 - waveform.samples[i] * 20, 64-i)
	    screen.stroke()
    end
	else
	  screen.move(64,34)
	  screen.text_center("K1+K3 to load sample")
	end
	screen.fill()
end

function redraw()
  screen.clear()
  if not weLoading then
    drawBackground()
    drawSegments()
    drawWaveform()
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
    if playing or (tt.playRate > 0.001 or tt.playRate < -0.001) then
      tt.playRate = tt.playRate + ((params:get('speed') * tt.destinationRate - tt.playRate) * tt.inertia / 2)
      tt.position = tt.position + tt.playRate * (360 / ((60 / tt.rpm) * 15))
      screen.dirty = true
    else tt.playRate = 0 end
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
    if (e == 1) then
      tt.playRate = tt.playRate + d * 1/100
    end
    
    if (e == 2) then
      --softcut.set_position(1, softcut.query_position(1) + d/10)
      print(softcut.query_position(1))
    end
    
    if (e == 3) then
      params:delta('speed', d)
    end
  end
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
    if k == 2 then

    end
    if k == 3 and not heldKeys[1] and not weLoading then
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
end

function cleanup() --------------- cleanup() is automatically called on script close
  clock.cancel(redraw_clock_id) -- melt our clock vie the id we noted
end