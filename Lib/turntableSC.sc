Engine_turntable : CroneEngine {

    // global variables for some reason
	  var params;
	  var turntable;
	  var tBuff;
	  // needs a beak for some reason
	  var <posBus;
    
    // this for some reason
    *new { arg context, doneCallback;
        ^super.new(context, doneCallback);
    }

	// we need to make sure the server is running before asking it to do anything
	alloc { // allocate memory to the following:

    var s = Server.default;
    var isLoaded = false;
    // ( server, frames, channels, bufnum )
    tBuff = Buffer.new(context.server, 0, 2, 0);
    posBus = Bus.control(context.server);

    // add SynthDefs
		SynthDef("turntable", {
			arg t_trigger, prate, stiffness, skipto, overall,
			noise_level, tnoise, tdust, trumble, tmotor, warble;

			var playrate = LFNoise2.kr(1 + prate, prate * warble, prate);
			// playhead
			var playhead = Phasor.ar(
				trig: t_trigger,
				rate: playrate,
				start: 0,
				end: BufFrames.kr(0),
				resetPos: skipto;
			);
			//  playhead position
			var position = playhead;
			var position_deci = position / BufFrames.kr(tBuff);
			//  playback engine
			var playback = BufRd.ar(
				numChannels: tBuff.numChannels,
				bufnum: 0,
				phase: playhead,
				interpolation: 4;
			);
	    	// noise stuff
		    var dtrig = Dust.ar(5);
		    var v_noise = BBandPass.ar(PinkNoise.ar([tnoise,tnoise]), 10000, 5);
		    var v_dust = Pan2.ar(BBandPass.ar(BBandPass.ar(Dust2.ar(10,2), TRand.ar(170, 3370, dtrig), 3), 5370,0.4) * EnvGen.ar(Env.perc(0.05, 0.05), dtrig), TRand.ar(-1, 1, dtrig), tdust);
		    var v_rumble = BBandPass.ar(PinkNoise.ar([trumble,trumble]), [13.5,13.5], 1);
		    var v_motor = BBandPass.ar(WhiteNoise.ar(), 100, 0.1, tmotor) + BBandPass.ar(WhiteNoise.ar(), 150, 0.1, tmotor * 0.5);
		    var v_mix = (v_noise + v_dust + v_rumble + v_motor) * Clip.kr(playrate, -1,1);
			var withnoise = (playback + v_mix) * overall;

			Out.ar(0, withnoise);
			// bus output for poll
			Out.kr(posBus.index, position_deci)
		}).add;

		// let's create an Dictionary (an unordered associative collection)
  	//   to store parameter values, initialized to defaults
  	// for user control
	  params = Dictionary.newFrom([
  		\prate, 0.0,
  		\stiffness, 1,
  		\skipto, 0.0,
  		\t_trigger, 0,
  		\tnoise, 0.35,
  		\tdust, 1.0, 
  		\trumble, 0.9,
  		\tmotor, 0.5,
  		\overall, 1,
  		\warble, 0
  		;
  	]);
		
		// done and sync
		s.sync;
	
  	turntable = Synth("turntable", target:context.xg);

  	// "Commands" are how the Lua interpreter controls the engine. FROM LUA TO SC
  	// The format string is analogous to an OSC message format string,
  	// and the 'msg' argument contains data.

  	// We'll just loop over the keys of the dictionary, 
  	// and add a command for each one, which updates corresponding value:
  	params.keysDo({ arg key;
  		this.addCommand(key, "f", { arg msg;
  		  //postln("setting command " ++ key ++ " to " ++ msg[1]);
  		  params[key] = msg[1];
  		  turntable.set(key, msg[1]);
  		});
  	});
	
  	// command to load file into buffer
  	// "fileload" will be name of Lua file parameter
  	// i.e. engine.fileload(filename,number_of_samples)
  	this.addCommand("fileload","si", { arg msg;
      // empty buffer
      tBuff.free;
	    // write to the buffer
    	tBuff = Buffer.read(context.server,msg[1],numFrames:msg[2]);
	    postln("and put it in buffer number "++tBuff.bufnum);
	    turntable.set(
	        \prate, 0.0, \goto, 0.0, \t_trigger, 1
	    );
	    // post a friendly message
	    postln("loaded "++tBuff.numFrames++" samples of "++msg[1]);
	    isLoaded = true;
	  });
	
	  // end commands
	
	  // polls FROM SC TO LUA
	  this.addPoll("get_position", {
			var pos = posBus.getSynchronous;
			pos;
	  });

	  this.addPoll("file_loaded", {
	    isLoaded;
	  }, periodic:false
	  );
	
	} // end alloc
	
	// NEW: when the script releases the engine,
	//   free Server resources and nodes!
	// IMPORTANT
	free {
		Buffer.freeAll;
		turntable.free;
		posBus.free;
	} // end free

} // end crone