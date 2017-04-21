# anim9

Intended for use with [LÖVE3D](https://github.com/excessive/love3d)

## Usage:
```lua
-- Using IQM...
local anim9 = require "anim9"
local iqm   = require "iqm"

local file  = "foo.iqm"
local model = iqm.load(file)
local anims = iqm.load_anims(file)
model.anim  = anim9(anims)

-- ...or using IQE
local anim9 = require "anim9"
local iqe   = require "iqe"

local model = iqe.load("bar.iqe")
local anims = model.anims
model.anim  = anim9(anims)

-- play an animation normally
local anim1 = model.anim:add_track("AnimationName")
anim1.playing = true

-- prevent transition() from affecting this track
anim1.lock = true

-- play a second animation on top, mixed in 50% at double speed.
local anim2 = model.anim:add_track("AnimationName2", 0.5, 2.0)
anim2.playing = true

-- transition unlocked layers to a new anim over 0.2s
local anim3 = model.anim:add_track("AnimationName3")
model.anim:transition(anim3, 0.2)

-- disable the second track (useful for debugging)
anim2.active = false

model.anim:update(dt)

-- get the matrix for a given bone...
model.anim.current_matrices["bone_name"]
```
