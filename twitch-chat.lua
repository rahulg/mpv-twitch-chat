require 'luarocks.loader'
local https = require 'ssl.https'
local json = require 'lunajson'

local osd_ass_cc = mp.get_property_osd('osd-ass-cc/0')
local username
local chat
local tm_tick, tm_redraw

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
	local url = string.format('https://rechat.twitch.tv/rechat-messages?start=%s&video_id=v%s', ts_absolute, self.video_id)
	local resp_body, code, headers, status = https.request(url)
	if code == 200 then
		local resp = json.decode(resp_body)
		for _, msg in ipairs(resp.data) do
			local message = {}
			message.ts = (msg.attributes.timestamp / 1000) - self.ts_start
			message.user = msg.attributes.tags['display-name'] or 'system message'
			message.text = msg.attributes.message
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

function TwitchChat:next_message()
	while self.messages:length() == 0 do
		self:fetch_next_block()
	end
	return self.messages:lpop()
end

function TwitchChat:update_display(ts)
	while not self.display:empty() and self.display:lpeek().ts < ts - 10 do
		self.display:lpop()
	end
	while (self.messages):length() == 0 do
		self:fetch_next_block()
	end
	while not self.messages:empty() and self.messages:lpeek().ts < ts - 10 do
		self.messages:lpop()
	end
	while not self.messages:empty() and self.messages:lpeek().ts < ts do
		self.display:rpush(self.messages:lpop())
	end
end

function show_chat()
	local vo_conf = mp.get_property("vo-configured")
	local video = mp.get_property("video")
	return vo_conf == "yes" and (video and video ~= "no" and video ~= "")
end

function ev_tick()
	if chat == nil then
		return
	end
	local video_ts = mp.get_property_number('time-pos', 0)
	chat:update_display(video_ts)
end

function ev_redraw()
	if not show_chat() then
		return
	end
	if chat == nil or chat.display:empty() then
		return
	end
	local message = string.format(
		'%s{\\fs%d}{\\fn%s}',
		osd_ass_cc,
		10,
		'Source Sans Pro'
	)
	for idx=chat.display.head, chat.display.tail do
		local msg = chat.display[idx]
		message = message .. string.format(
			'{\\b1}%s:{\\b0}\\h\\h%s\\N',
			msg.user,
			msg.text
		)
	end
	mp.osd_message(message, 1.0)
end

function ev_pause(name, paused)
	if paused == true then
		tm_tick:stop()
		tm_redraw:stop()
	else
		tm_tick:resume()
		tm_redraw:resume()
	end
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
	local pat_twitch_vod = 'twitch.tv/.-/v/(%d+)'
	local video_id = string.match(path, pat_twitch_vod)
	if video_id ~= nil then
		chat = TwitchChat.new(video_id)
		mp.register_event('playback-restart', ev_seek)
		mp.observe_property("pause", "bool", ev_pause)
		tm_tick = mp.add_periodic_timer(0.5, ev_tick)
		tm_redraw = mp.add_periodic_timer(1.0, ev_redraw)
	end
end

mp.register_event('start-file', ev_start_file)
