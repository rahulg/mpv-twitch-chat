require 'luarocks.loader'
local https = require 'ssl.https'
local json = require 'lunajson'
local options = require 'mp.options'

local osd_ass_cc = mp.get_property_osd('osd-ass-cc/0')
local chat

local opt = {
	toggle_key = 'c',
	enable_position_binds = true,
	osd_position = 1, -- osd_position uses 'numpad values'
	message_duration = 10, -- in seconds
	message_limit = 10,
	update_interval = 0.3,
	redraw_interval = 0.5,

	-- text styling
	font = 'Helvetica',
	font_size = 8,
	font_colour = 'FFFFFF',
	border_size = 1.0,
	border_colour = '000000',
	alpha = '11',
	mod_font_colour = '00FF00',
	mod_border_colour = '111111',
	streamer_font_colour = '0000FF',
	streamer_border_colour = '111111',
}
options.read_options(opt)

local Deque = {}
Deque.__index = Deque

function Deque.new()
	local self = setmetatable({}, Deque)
	self.head = 0
	self.tail = -1
	return self
end

function Deque:flush()
	while not self:empty() do
		self:lpop()
	end
	self.head = 0
	self.tail = -1
end

function Deque:lpush(value)
	local head = self.head - 1
	self.head = head
	self[head] = value
end

function Deque:rpush(value)
	local tail = self.tail + 1
	self.tail = tail
	self[tail] = value
end

function Deque:lpeek()
	if self:empty() then error('empty deque') end
	return self[self.head]
end

function Deque:lpop()
	if self:empty() then error('empty deque') end
	local head = self.head
	local value = self[head]
	self[head] = nil
	self.head = head + 1
	return value
end

function Deque:rpeek()
	if self:empty() then error('empty deque') end
	return self[self.tail]
end

function Deque:rpop()
	if self:empty() then error('empty deque') end
	local tail = self.tail
	local value = self[tail]
	self[tail] = nil
	self.tail = tail - 1
	return value
end

function Deque:length()
	if self.head > self.tail then
		return 0
	else
		return self.tail - self.head + 1
	end
end

function Deque:empty()
	return self:length() == 0
end

local TwitchChat = {}
TwitchChat.__index = TwitchChat

function TwitchChat.new(video_id)
	local self = setmetatable({}, TwitchChat)

	self.video_id = video_id
	self.messages = Deque.new()
	self.display = Deque.new()

	local url = string.format('https://rechat.twitch.tv/rechat-messages?start=%s&video_id=v%s', 0, video_id)
	local resp_body, code, headers, status = https.request(url)
	if code ~= 400 then
		error(string.format('received http status %s for "%s"', code, url))
	end

	local resp = json.decode(resp_body)
	local pat_range = '0 is not between (%d+) and (%d+)'
	self.ts_start, self.ts_end = string.match(resp.errors[1].detail, pat_range)
	if self.ts_start == nil or self.ts_end == nil then
		error('unable to parse start and end timestamps')
	end
	self.ts_current = self.ts_start

	return self
end

function TwitchChat:fetch_block(ts_absolute)
	local url = string.format('https://rechat.twitch.tv/rechat-messages?start=%s&video_id=v%s', math.floor(ts_absolute), self.video_id)
	local resp_body, code, headers, status = https.request(url)
	if code == 200 then
		local resp = json.decode(resp_body)
		for _, msg in ipairs(resp.data) do
			local message = {}
			message.ts = (msg.attributes.timestamp / 1000) - self.ts_start
			message.user = msg.attributes.tags['display-name']
			message.text = msg.attributes.message
			message.is_streamer = msg.attributes.from:lower() == msg.attributes.room:lower()
			message.is_mod = msg.attributes.tags.mod
			self.messages:rpush(message)
		end
	else
		error(string.format('http error %s: %s', code, resp_body))
	end
	self.ts_current = ts_absolute + 30
end

function TwitchChat:fetch_next_block()
	self:fetch_block(self.ts_current)
end

function TwitchChat:fetch_block_at_ts(ts)
	self:fetch_block(self.ts_start + ts)
end

function TwitchChat:update_display(ts)
	while not self.display:empty() and self.display:lpeek().ts < ts - opt.message_duration do
		self.display:lpop()
	end
	if self.messages:empty() then
		self:fetch_next_block()
	end
	while not self.messages:empty() and self.messages:lpeek().ts < ts - opt.message_duration do
		self.messages:lpop()
	end
	while not self.messages:empty() and self.messages:lpeek().ts < ts do
		self.display:rpush(self.messages:lpop())
	end
end

function has_vo()
	local vo_conf = mp.get_property("vo-configured")
	local video = mp.get_property("video")
	return vo_conf == "yes" and (video and video ~= "no" and video ~= "")
end

function txt_username(msg)
	local s = ''
	if msg.user == nil then
		return ''
	end
	if msg.is_streamer then
		s = string.format(
			'{\\1c&H%s&}{\\3c&H%s&}%s:{\\1c&H%s&}{\\3c&H%s&}',
			opt.streamer_font_colour,
			opt.streamer_border_colour,
			msg.user,
			opt.font_colour,
			opt.border_colour
		)
	elseif msg.is_mod then
		s = string.format(
			'{\\1c&H%s&}{\\3c&H%s&}%s:{\\1c&H%s&}{\\3c&H%s&}',
			opt.mod_font_colour,
			opt.mod_border_colour,
			msg.user,
			opt.font_colour,
			opt.border_colour
		)
	else
		s = msg.user .. ':'
	end
	return string.format('{\\b1}%s{\\b0}', s)
end

function ev_tick()
	if chat == nil then
		return
	end
	local video_ts = mp.get_property_number('time-pos', 0)
	chat:update_display(video_ts)
end

function ev_redraw()
	if chat == nil or chat.display:empty() then return end
	local message = ''
	if not has_vo() then return end
	message = string.format(
		'%s{\\an%d}{\\fs%d}{\\fn%s}{\\bord%f}{\\3c&H%s&}{\\1c&H%s&}{\\alpha&H%s&}',
		osd_ass_cc,
		opt.osd_position,
		opt.font_size,
		opt.font,
		opt.border_size,
		opt.border_colour,
		opt.font_colour,
		opt.alpha
	)
	for idx=chat.display.head, chat.display.tail do
		if idx - chat.display.head == opt.message_limit then
			chat.display:lpop()
			break
		end
		local msg = chat.display[idx]
			message = message .. string.format(
			'%s %s\\N',
			txt_username(msg),
			msg.text
		)
	end
	mp.osd_message(message, opt.redraw_interval + 0.1)
end

local tm_tick = mp.add_periodic_timer(opt.update_interval, ev_tick)
tm_tick:kill()
local tm_redraw = mp.add_periodic_timer(opt.redraw_interval, ev_redraw)
tm_redraw:kill()
local tm_redraw_enabled = false

function ev_pause(name, paused)
	if paused == true then
		tm_tick:stop()
	else
		tm_tick:resume()
	end
end

function ev_toggle()
	if tm_redraw_enabled then
		tm_redraw:kill()
		tm_redraw_enabled = false
		mp.osd_message('', 0)
	else
		tm_redraw:resume()
		tm_redraw_enabled = true
		ev_redraw()
	end
end

function ev_set_pos(position)
	opt.osd_position = position
end

function ev_seek()
	tm_tick:kill()
	chat.messages:flush()
	local video_ts = mp.get_property_number('time-pos', 0)
	chat:fetch_block_at_ts(video_ts)
	tm_tick:resume()
end

function ev_start_file()
	local path = mp.get_property('path')
	if path == nil then
		return
	end
	local pat_twitch_vod = 'twitch.tv/videos/(%d+)'
	local video_id = string.match(path, pat_twitch_vod)
	if video_id ~= nil then
		chat = TwitchChat.new(video_id)
		tm_tick:resume()
		tm_redraw:resume()
		tm_redraw_enabled = true
		mp.register_event('playback-restart', ev_seek)
		mp.observe_property('pause', 'bool', ev_pause)
		mp.add_key_binding(opt.toggle_key, 'toggle', ev_toggle, {repeatable=false})
	end
end

function ev_end_file()
	if tm_tick ~= nil then tm_tick:kill() end
	if tm_redraw ~= nil then tm_redraw:kill() end
	tm_redraw_enabled = false
	tm_tick = nil
	tm_redraw = nil
	mp.unregister_event(ev_seek)
	mp.unobserve_property(ev_pause)
	mp.remove_key_binding('toggle')
end

mp.register_event('start-file', ev_start_file)
mp.register_event('end-file', ev_end_file)
if opt.enable_position_binds then
	for key=1, 9 do
		mp.add_key_binding('KP' .. key, 'position-' .. key, function() ev_set_pos(key) end)
	end
end
