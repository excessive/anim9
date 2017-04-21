local cpml = require "cpml"

local anim = {
	_LICENSE     = "anim9 is distributed under the terms of the MIT license. See LICENSE.md.",
	_URL         = "https://github.com/excessive/anim9",
	_VERSION     = "0.2.0",
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

local function bind_pose(skeleton)
	local pose = {}
	for i = 1, #skeleton do
		pose[i] = {
			translate = skeleton[i].position,
			rotate    = skeleton[i].rotation,
			scale     = skeleton[i].scale
		}
	end
	return pose
end

local function is_child(skeleton, bone, which)
	local next = skeleton[bone]
	if bone == which then
		return true
	elseif next.parent < which then
		return false
	else
		return is_child(skeleton, next.parent, which)
	end
end

local function mix_poses(skeleton, p1, p2, weight, start)
	local new_pose = {}
	for i = 1, #skeleton do
		local mix = weight
		if start > 1 then
			if not is_child(skeleton, i, start) then
				mix = 0
			end
		end
		local r = cpml.quat.slerp(p1[i].rotate, p2[i].rotate, mix)
		r = r:normalize()
		new_pose[i] = {
			translate = cpml.vec3.lerp(p1[i].translate, p2[i].translate, mix),
			rotate    = r,
			scale     = cpml.vec3.lerp(p1[i].scale, p2[i].scale, mix)
		}
	end
	return new_pose
end

local function update_matrices(skeleton, base, pose)
	local animation_buffer = {}
	local transform = {}
	local bone_lookup = {}

	for i, joint in ipairs(skeleton) do
		local m = calc_bone_matrix(pose[i].translate, pose[i].rotate, pose[i].scale)
		local render

		if joint.parent > 0 then
			assert(joint.parent < i)
			transform[i] = m * transform[joint.parent]
			render       = base[i] * transform[i]
		else
			transform[i] = m
			render       = base[i] * m
		end

		bone_lookup[joint.name] = transform[i]
		table.insert(animation_buffer, render:to_vec4s())
	end
	table.insert(animation_buffer, animation_buffer[#animation_buffer])
	return animation_buffer, bone_lookup
end

local function new(data, anims)
	if not data.skeleton then return end

	local t = {
		time         = 0,
		animations   = {},
		timeline     = {},
		skeleton     = data.skeleton,
		inverse_base = {},
		bind_pose    = bind_pose(data.skeleton)
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
	for _, v in ipairs(anims or data) do
		o:add_animation(v, data.frames)
	end
	return o
end

--- Add animation to anim object
-- @param animation Animation data
-- @param frames Frame data
function anim:add_animation(animation, frames)
	local new_anim = {
		name      = animation.name,
		frames    = {},
		length    = animation.last - animation.first,
		framerate = animation.framerate,
		loop      = animation.loop
	}

	for i = animation.first, animation.last do
		table.insert(new_anim.frames, frames[i])
	end
	self.animations[new_anim.name] = new_anim
end

--- Add track to timeline
-- @param name Name of animation for track -or- track object
-- @param weight Percentage of total timeline blending being given to track
-- @param rate Playback rate of animation
-- @param callback Function to call after non-looping animation ends
-- @param lock Stops track from being affected by transition
-- @return table Track object
function anim:add_track(name, weight, rate, callback, lock)
	if type(name) == "table" then
		assert(self.timeline[name] == nil)
		table.insert(self.timeline, name)
		self.timeline[name] = name
		return name
	end

	assert(self.animations[name])
	local t = {
		name     = assert(name),
		offset   = self.time,
		weight   = weight   or 1,
		rate     = rate     or 1,
		callback = callback or false,
		lock     = lock     or false,
		playing  = false,
		active   = true,
		blend    = 1,
		base     = 1
	}
	table.insert(self.timeline, t)
	self.timeline[t] = t
	return t
end

--- Remove track from timeline
-- @param _track Track to remove from timeline
function anim:remove_track(_track)
	local track = assert(self.timeline[_track])
	for i = #self.timeline, 1, -1 do
		if self.timeline[i] == track then
			table.remove(self.timeline, i)
			self.timeline[track] = nil
			break
		end
	end
end

--- Get length of animation
-- @param name Name of animation
-- @return number Length of animation (in seconds)
function anim:length(name)
	local _anim = assert(self.animations[name], string.format("Invalid animation: \'%s\'", name))
	return _anim.length / _anim.framerate
end

--- Update animations
-- @param dt Delta time
function anim:update(dt)
	self.time = self.time + dt

	-- Transition from one animation to the next
	if self.transitioning then
		local t        = self.transitioning
		t.time         = t.time + dt
		local progress = math.min(t.time / t.length, 1)

		-- fade new animation in
		t.track.blend  = cpml.utils.lerp(0, 1, progress)

		-- fade old animations out
		for _, track in ipairs(self.timeline) do
			if track ~= t.track and not track.lock then
				track.blend = cpml.utils.lerp(1, 0, progress)
			end
		end

		-- remove dead animations
		if progress == 1 then
			for _, track in ipairs(self.timeline) do
				if track.blend == 0 and not track.lock then
					self:remove_track(track)
				end
			end

			self.transitioning = nil
		end
	end

	local pose = self.bind_pose
	for _, track in ipairs(self.timeline) do
		if not track.playing then
			track.offset = track.offset + dt
		end

		if not track.active then
			goto continue
		end

		local time  = self.time - track.offset
		local _anim = self.animations[track.name]
		local frame = time * _anim.framerate

		if _anim.loop then
			frame = frame % _anim.length
		else
			if frame >= _anim.length then
				self:remove_track(track)
				if type(track.callback) == "function" then
					track.callback(self)
				end
				goto continue
			end
			frame = math.min(_anim.length, frame)
		end

		local f1, f2 = math.floor(frame), math.ceil(frame)

		-- make sure f2 doesn't exceed anim length or wrongly loop
		if _anim.loop then
			f2 = f2 % _anim.length
		else
			f2 = math.min(_anim.length, f2)
		end

		-- Update the final pose
		local interp = mix_poses(
			self.skeleton,
			_anim.frames[f1+1],
			_anim.frames[f2+1],
			frame - f1,
			track.base
		)

		pose = mix_poses(self.skeleton, pose, interp, track.weight * track.blend, track.base)

		::continue::
	end
	self.current_pose, self.current_matrices = update_matrices(
		self.skeleton, self.inverse_base, pose
	)
end

--- Reset animations
-- @param clear_locked Flag to clear even locked tracks
function anim:reset(clear_locked)
	self.time = 0
	self.transitioning = nil
	for i = #self.timeline, 1, -1 do
		local track = self.timeline[i]
		if not track.lock or clear_locked then
			table.remove(self.timeline, i)
			self.timeline[track] = nil
		end
	end
end

--- Transition from one animation to another
-- @param track Track object to transition to
-- @param length Length of transition (in seconds)
function anim:transition(track, length)
	assert(track)

	if self.transitioning and self.transitioning.track == track then
		return
	end

	if not self.timeline[track] then
		self:add_track(track)
	end

	self.transitioning = {
		track  = track,
		length = length or 0.2,
		time   = 0
	}

	track.offset  = self.time
	track.playing = true
	track.active  = true
end

return setmetatable({
	new = new
}, {
	__call = function(_, ...) return new(...) end
})

--- @table Track
-- @field name Name of animation
-- @field offset Offset from timeline time for track to start play
-- @field weight Blend weight
-- @field rate Playback rate of animation
-- @field callback Function to call after non-looping animation ends
-- @field lock Stop track from being affected by transitions
-- @field playing Determine if animation is playing
-- @field active Toggle influence of track (used for debugging animations)
-- @field blend Fade in/out during transition
-- @field base Starting bone to be used
