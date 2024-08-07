turntable, V2.1

A turntable for norns

Demo video:
https://youtu.be/kpuc4MYNU9A?feature=shared

After many years as a musician, I decided this year I wanted to DJ for the first time. I don’t have turntables, but I do have a norns or two. So I made this.

The intention was to squeeze most of the functionality of a single turntable onto norns. And the intention was also to resist making a full DJ app.

Because this uses softcut, softcut’s limitations apply: wavs only, 48kHz recommended, max 5 minutes 49.52 seconds in length.

All gratitude and props to monome, the documentation writers, and the lines community for teaching me how to do this.

Requirements

Requires: norns, some wavs to play

Documentation

K1+K3: Load a wav file
K3: play / stop
K2: pause (put your hand on the record)

E1: pitch
E2: nudge
E3: small nudge
K1+E2: big nudge
K2+K3: backspin

K1+K2: toggle loop
K1+E3: waveform zoom

See the params menu for fun stuff like changing the player and record rpm. Get your ‘slowlene’ on 28!

To mix:
Bring another audio source (say, another norns running turntable, your phone, or an sl1200), into the norns stereo input.
Map a MIDI controller to the ‘Fader Position’ parameter, and use it to crossfade between turntable and the audio inout

Download

V2.1
Added param for Turntable Drive

V2.0

Mixing has been added to turntable! There are new parameters for:
fader position
fader sharpness (how close to the end of the fader
equal power / DJ style curve (in the middle, how loud are the two sound sources? )
Install and update in the maiden library, or via

;install https://github.com/adamstaff/turntable
