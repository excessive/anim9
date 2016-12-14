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
model.anim:play("AnimationName")

-- play a second animation on top, mixed in 50% at double speed.
model.anim:play("AnimationName2", 0.5, 2.0)

model.anim:update(dt)

-- get the matrix for a given bone...
model.anim.current_matrices["bone_name"]
```
