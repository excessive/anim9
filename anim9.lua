local cpml = require "cpml"
local cpml_mat4  = cpml.mat4
local cpml_vec3  = cpml.vec3
local cpml_quat  = cpml.quat
local cpml_utils = cpml.utils


local anim = {
	_LICENSE     = "anim9 is distributed under the terms of the MIT license. See LICENSE.md.",
	_URL         = "https://github.com/excessive/anim9",
	_VERSION     = "0.2.0",
	_DESCRIPTION = "Animation library for LÖVE3D.",
}
anim.__index = anim

local calc_bone_matrix = cpml_mat4.from_transform

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
		if not p1[i] or not p2[i] then
			goto continue
		end
		local mix = weight
		if start > 1 then
			if not is_child(skeleton, i, start) then
				mix = 0
			end
		end
		local r = cpml_quat.slerp(p1[i].rotate, p2[i].rotate, mix)
		r = r:normalize()
		new_pose[i] = {
			translate = cpml_vec3.lerp(p1[i].translate, p2[i].translate, mix),
			rotate    = r,
			scale     = cpml_vec3.lerp(p1[i].scale, p2[i].scale, mix)
		}
		::continue::
	end
	return new_pose
end

local function update_matrices(skeleton, base, pose, indices)
	local animation_buffer = {}
	local transform = {}
	local bone_lookup = {}
	local identity = cpml_mat4()

	for i, joint in ipairs(skeleton) do
		local m = identity
		if pose[i] then
			m = calc_bone_matrix(pose[i].translate, pose[i].rotate, pose[i].scale)
		else
			m = calc_bone_matrix(joint.position, joint.rotation, joint.scale)
		end

		local render
		if joint.parent > 0 then
			assert(joint.parent < i)
			transform[i] = transform[joint.parent] * m
			render       = transform[i] * base[i]
		else
			transform[i] = m
			render       = m * base[i]
		end

		bone_lookup[joint.name] = transform[i]
		animation_buffer[indices[joint.name]] = render:to_vec4s()
	end

	return animation_buffer, bone_lookup
end

local function new(data, anims, markers)
	if not data.skeleton then return end

	local t = {
		time         = 0,
		animations   = {},
		timeline     = {},
		skeleton     = {},
		inverse_base = {},
		index_map    = {},
		bind_pose    = {}
	}

	local o = setmetatable(t, anim)
	if anims ~= nil and not anims then
		return o
	end
	o:rebind(data)
	for _, v in ipairs(anims or data) do
		if markers then
			o:add_animation(v, data.frames, markers[v.name])
		else
			o:add_animation(v, data.frames)
		end
	end
	return o
end

function anim:rebind(data)
	self.skeleton = data.skeleton
	self.bind_pose = bind_pose(self.skeleton)
	self.inverse_base = {}

	self.index_map = {}

	-- Calculate inverse base pose.
	for i, bone in ipairs(data.skeleton) do
		local m = calc_bone_matrix(bone.position, bone.rotation, bone.scale)
		local inv = cpml_mat4():invert(m)

		if bone.parent > 0 then
			assert(bone.parent < i)
			self.inverse_base[i] = inv * self.inverse_base[bone.parent]
		else
			self.inverse_base[i] = inv
		end

		self.index_map[i] = i
		self.index_map[bone.name] = i
	end
end

function anim:find_index(bone_name)
	for i, bone in ipairs(self.skeleton) do
		if bone.name == bone_name then
			return i
		end
	end
	return 1
end

--- Add animation to anim object
-- @param animation Animation data
-- @param frames Frame data
function anim:add_animation(animation, frames, markers)
	if animation.frames then
		for _, v in ipairs(animation) do
			-- if markers then
				-- o:add_animation(v, data.frames, markers[v.name])
			-- else
				self:add_animation(v, animation.frames)
		end
		return
	end

	local new_anim = {
		name      = animation.name,
		frames    = {},
		length    = animation.last - animation.first,
		framerate = animation.framerate,
		loop      = animation.loop,
		markers   = markers or {}
	}

	for i = animation.first, animation.last do
		table.insert(new_anim.frames, frames[i])
	end
	self.animations[new_anim.name] = new_anim
end

--- Create a new track
-- @param name Name of animation for track
-- @param weight Percentage of total timeline blending being given to track
-- @param rate Playback rate of animation
-- @param callback Function to call after non-looping animation ends
-- @param lock Stops track from being affected by transition
-- @return table Track object
function anim:new_track(name, weight, rate, callback, lock, early)
	if not self.animations[name] then
		return nil
	end
	local t = {
		name     = assert(name),
		offset   = self.time,
		time     = self.time,
		weight   = weight   or 1,
		rate     = rate     or 1,
		callback = callback or false,
		lock     = lock     or false,
		early    = early    or false,
		playing  = false,
		active   = true,
		frame    = 0,
		marker   = 0,
		blend    = 1,
		base     = 1
	}
	return t
end

--- Add track to timeline
-- @param track Track object to play
-- @return table Track object
function anim:play(track)
	assert(type(track) == "table")
	assert(self.timeline[track] == nil)
	track.playing = true
	track.offset = self.time
	track.time = self.time

	table.insert(self.timeline, track)
	self.timeline[track] = track
	return track
end

--- Remove track from timeline
-- @param track Track to remove from timeline (optional). If not specified, removes all.
function anim:stop(track)
	if track ~= nil then
		assert(self.timeline[track])
	end
	for i = #self.timeline, 1, -1 do
		if self.timeline[i] == track or track == nil then
			self.timeline[self.timeline[i]] = nil
			table.remove(self.timeline, i)
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
-- @param _dt Delta time
function anim:update(dt)
	self.time = self.time + dt

	for _, track in ipairs(self.timeline) do
		track.time = track.time + (dt * track.rate)
	end

	-- Transition from one animation to the next
	if self.transitioning then
		local t        = self.transitioning
		t.time         = t.time + dt * t.track.rate
		local progress = math.min(t.time / t.length, 1)

		-- fade new animation in
		t.track.blend  = cpml_utils.lerp(0, 1, progress)

		-- fade old animations out
		for _, track in ipairs(self.timeline) do
			if track ~= t.track and not track.lock then
				track.blend = cpml_utils.lerp(0, 1, 1-progress)
			end
		end

		-- remove dead animations
		if progress == 1 then
			for _, track in ipairs(self.timeline) do
				if track.blend == 0 and not track.lock then
					self:stop(track)
					-- Call callback on early exit if flagged
					if track.early and type(track.callback) == "function" then
						track.callback(self)
					end
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

		local time  = track.time - track.offset
		local _anim = self.animations[track.name]
		local frame = time * _anim.framerate

		if _anim.loop then
			frame = frame % _anim.length
		else
			if frame >= _anim.length and not track.lock then
				self:stop(track)
				if type(track.callback) == "function" then
					track.callback(self)
				end
				goto continue
			end
			frame = math.min(_anim.length, frame)
		end

		frame = math.max(frame, 0)
		local f1, f2 = math.floor(frame), math.ceil(frame)
		track.frame = f1

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
		self.skeleton, self.inverse_base, pose, self.index_map
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
		self:play(track)
	end

	self.transitioning = {
		track  = track,
		length = length or 0.2,
		time   = 0
	}

	track.offset = self.time
	track.time = self.time
end

--- Find track in timeline
-- @param track Track to locate
-- @return boolean true if found, false if not found
function anim:find_track(track)
	if self.timeline[track] then
		return true
	end

	return false
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
