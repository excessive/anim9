# anim9

Intended for use with [LÖVE3D](https://github.com/excessive/love3d)

## Usage:
```lua
-- Using IQM
local anim9 = require "anim9"
local iqm   = require "iqm"

local model = iqm.load("foo.iqm")
local anims = iqm.load_anims(model)
model.anim  = anim9(anims)

model.anim:play("AnimationName")

-- Using IQE
local anim9 = require "anim9"
local iqe   = require "iqe"

local model = iqe.load("bar.iqe")
local anims = model.anims
model.anim  = anim9(anims)

model.anim:play("AnimationName")
```
