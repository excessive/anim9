local cpml = require "cpml"

local anim = {
	_LICENSE     = "anim9 is distributed under the terms of the MIT license. See LICENSE.md.",
	_URL         = "https://github.com/excessive/anim9",
	_VERSION     = "0.0.3",
	_DESCRIPTION = "Animation library for LÖVE3D.",
}
anim.__index = anim

local function calc_bone_matrix(pos, rot, scale)
	local out = cpml.mat4()
	return out
		:translate(out, pos)
		:rotate(out, rot)
		:scale(out, scale)
end

local function calc_pose(skeleton, base, p1, p2, position)
	local animation_buffer = {}
	local transform = {}
	for i, joint in ipairs(skeleton) do
		local t = cpml.vec3():lerp(p1[i].translate, p2[i].translate, position)
		local r = cpml.quat():slerp(p1[i].rotate, p2[i].rotate, position)
		local s = cpml.vec3():lerp(p1[i].scale, p2[i].scale, position)
		r:normalize(r)
		local m = calc_bone_matrix(t, r, s)
		local render = cpml.mat4()

		if joint.parent > 0 then
			assert(joint.parent < i)
			transform[i] = m * transform[joint.parent]
			render       = base[i] * transform[i]
		else
			transform[i] = m
			render       = base[i] * m
		end

		table.insert(animation_buffer, render:to_vec4s())
	end
	return animation_buffer
end

local function new(data, anims)
	if not data.skeleton then return end

	local t = {
		current_animation = false,
		current_callback  = false,
		current_time      = 0,
		current_frame     = 1,
		current_marker    = 0,
		animations        = {},
		playing           = false,
		skeleton          = data.skeleton,
		inverse_base      = {}
	}

	-- Calculate inverse base pose.
	for i, bone in ipairs(data.skeleton) do
		local m = calc_bone_matrix(bone.position, bone.rotation, bone.scale)
		local inv = cpml.mat4():invert(m)

		if bone.parent > 0 then
			assert(bone.parent < i)
			t.inverse_base[i] = t.inverse_base[bone.parent] * inv
		else
			t.inverse_base[i] = inv
		end
	end

	local o = setmetatable(t, anim)
	if anims ~= nil and not anims then
		return o
	end
	for k, v in ipairs(anims or data) do
		o:add_animation(v, data.frames)
	end
	return o
end

function anim:add_animation(animation, frame_data)
	local anim = {
		name      = animation.name,
		frames    = {},
		length    = animation.last - animation.first,
		framerate = animation.framerate,
		loop      = animation.loop
	}

	for i = animation.first, animation.last do
		table.insert(anim.frames, frame_data[i])
	end
	self.animations[anim.name] = anim
end

function anim:reset()
	self.current_animation = false
	self.current_time      = 0
	self.playing           = false
end

function anim:play(name, callback, stopped)
	self.current_animation = name
	self.current_callback  = callback
	self.playing = stopped == nil and true or not stopped
end

function anim:pause(toggle)
	self.playing = toggle == nil and false or not self.playing
end

function anim:stop()
	self:pause()
	self:reset()
end

function anim:length(aname)
	aname = aname or self.current_animation
	local anim = self.animations[aname]
	assert(anim, string.format("Invalid animation: \'%s\'", aname))
	return anim.length / anim.framerate
end

function anim:step(reverse)
	if self.current_animation and not self.playing then
		local anim = self.animations[self.current_animation]
		local length = anim.length / anim.framerate

		if reverse then
			self.current_time = self.current_time - (1/anim.framerate)
		else
			self.current_time = self.current_time + (1/anim.framerate)
		end

		if anim.loop then
			if self.current_time < 0 then
				self.current_time = self.current_time + length
			end
			self.current_time = cpml.utils.wrap(self.current_time, length)
		else
			if self.current_time < 0 then
				self.current_time = 0
			end
			self.current_time = math.min(self.current_time, length)
		end

		local position = self.current_time * anim.framerate
		local frame = anim.frames[math.floor(position)+1]

		-- Update the final pose
		self.current_pose = calc_pose(
			self.skeleton, self.inverse_base,
			frame, frame, 0
		)
	end
end

function anim:update(dt)
	if self.current_animation and self.playing then
		local anim = self.animations[self.current_animation]
		assert(anim, string.format("Invalid animation: %s", self.current_animation))
		local length = anim.length / anim.framerate
		self.current_time = self.current_time + dt
		if self.current_time > length then
			if type(self.current_callback) == "function" then
				self.current_callback(self)
			end
		end

		-- If we're not looping, we just want to leave the animation at the end.
		if anim.loop then
			self.current_time = cpml.utils.wrap(self.current_time, length)
		else
			self.current_time = math.min(self.current_time, length)
		end

		local position = self.current_time * anim.framerate
		local f1, f2 = math.floor(position), math.ceil(position)
		position = position - f1
		f2 = f2 % (anim.length)

		-- Update the final pose
		self.current_pose = calc_pose(
			self.skeleton, self.inverse_base,
			anim.frames[f1+1], anim.frames[f2+1], position
		)

		self.current_frame = f1
	end
end

function anim:send_pose(shader, uniform, toggle_uniform)
	if not self.current_pose then
		return
	end
	shader:send(uniform, unpack(self.current_pose))
	if toggle_uniform then
		shader:sendInt(toggle_uniform, 1)
	end
end

return setmetatable({
	new = new
}, {
	__call = function(_, ...) return new(...) end
})
