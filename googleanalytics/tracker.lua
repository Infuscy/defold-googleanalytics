local uuid_generator = require "googleanalytics.internal.uuid"
local queue = require "googleanalytics.internal.queue"
local file = require "googleanalytics.internal.file"

local M = {}

local UUID_FILENAME = "__ga_uuid"

local function url_encode(str)
	if (str) then
		str = string.gsub (str, "\n", "\r\n")
		str = string.gsub (str, "([^%w %-%_%.%~])", function (c) return string.format ("%%%02X", string.byte(c)) end)
		str = string.gsub (str, " ", "+")
	end
	return str	
end

local function url_decode(str)
	str = string.gsub (str, "+", " ")
	str = string.gsub (str, "%%(%x%x)", function(h) return string.char(tonumber(h,16)) end)
	str = string.gsub (str, "\r\n", "\n")
	return str
end

local function limit(s, max)
	if #s <= max then
		return s
	else
		return s:sub(1, max)
	end
end


local function get_uuid()
	local uuid, err = file.load(UUID_FILENAME)
	if not uuid then
		uuid_generator.seed()
		uuid = uuid_generator()
		file.save(UUID_FILENAME, uuid)
	end
	return uuid
end

local function get_application_name()
	return sys.get_config("project.title"):gsub(" ", "_")
end

local function get_application_id()
	local APPLICATION_IDS = {
		["Android"] = sys.get_config("android.package"),
		["iPhone OS"] = sys.get_config("ios.bundle_identifier"),
		["Darwin"] = sys.get_config("osx.bundle_identifier"),
	}
	local system_name = sys.get_sys_info().system_name
	return APPLICATION_IDS[system_name] or (get_application_name() .. system_name)
end

local function get_application_version()
	return sys.get_config("project.version")
end


--- Create a tracker instance
-- @param tracking_id Tracking id from the Google Analytics admin dashboard
-- @return Tracker instance
function M.create(tracking_id)
	local tracker = {}
	
	-- https://developers.google.com/analytics/devguides/collection/protocol/v1/parameters
	local tracking_params = "v=1&ds=app"
		.. "&cid=" .. get_uuid()
		.. "&tid=" .. tracking_id
		.. "&vp=" .. limit(sys.get_config("display.width") .. "x" .. sys.get_config("display.height"), 20)
		.. "&ul=" .. limit(sys.get_sys_info().device_language, 20)
		.. "&an=" .. limit(get_application_name(), 100)
		.. "&aid=" .. limit(get_application_id(), 150)
		.. "&av=" .. limit(get_application_version(), 10)

	local event_params = tracking_params .. "&t=event"
	local timing_params = tracking_params .. "&t=timing"
	local screenview_params = tracking_params .. "&t=screenview"
	local exception_params = tracking_params .. "&t=exception"
	
	--- Enable or disable crash reporting
	-- If enabled the tracker will automatically get Lua soft crashes using
	-- the sys.set_error_handler() function and track them as non-fatal crashes.
	-- It will also, when called, load any previous hard crash using
	-- crash.load_previous() and track that as a fatal crash.
	-- @param enabled Set to true to enable automatic crash reporting
	function tracker.enable_crash_reporting(enabled)
		if enabled then
			sys.set_error_handler(function(source, message, traceback)
				queue.add(exception_params .. "&exf=0%exd=" .. limit(message, 150))
			end)
			local handle = crash.load_previous()
			if handle then
				queue.add(exception_params .. "&exf=1%exd=" .. limit(crash.get_extra_data(handle), 150))
				crash.release(handle)
			end
		else
			sys.set_error_handler(function() end)
		end
	end
	
	--- Raw tracking
	-- @params params A valid Google Analytics parameter string
	function tracker.raw(params)
		assert(params and type(params) == "string", "You must provide some params (of type string)")
		queue.add(params)
	end
	
	--- Event tracking
	-- @param category Specifies the event category. Must not be empty.
	-- @param action Specifies the event action. Must not be empty.
	-- @param label Specifies the event label. Optional.
	-- @param value Specifies the event value. Optional. Non-negative.
	function tracker.event(category, action, label, value)
		assert(category and type(category) == "string" and #category > 0, "You must provide a category (of type string, must not be empty)")
		assert(action and type(action) == "string" and #action > 0, "You must provide an action (of type string, must not be empty)")
		assert(not label or type(label) == "string", "Label must be nil or of type string")
		assert(not value or (type(value) == "number" and value >= 0), "Value must be nil or a positive number")
		queue.add(event_params .. "&ec=" .. limit(category, 150) .. "&ea=" .. limit(action, 500) .. (label and ("&el=" .. limit(label, 500)) or "") .. (value and ("&ev=" .. tostring(value)) or ""))
	end
	
	--- Screenview
	-- @param screen_name Specified the screen name of a screenview hit
	function tracker.screenview(screen_name)
		assert(screen_name and type(screen_name) == "string", "You must specify a screen name (of type string)")
		queue.add(screenview_params .. "&cd=" .. limit(screen_name, 2048))
	end
	
	--- User timing
	-- @param category Specifies the user timing category
	-- @param variable Specifies the user timing variable
	-- @param time Specifies the user timing value (milliseconds)
	-- @param label Specifies the user timing label. Optional.
	function tracker.timing(category, variable, time, label)
		assert(category and type(category) == "string", "You must provide a category (of type string)")
		assert(variable and type(variable) == "string", "You must provide a variable (of type string)")
		assert(time and type(time) == "number" and time >= 0, "You must provide a time (as a positive number)")
		assert(not label or type(label) == "string", "Label must be nil or a string")
		queue.add(timing_params .. "&utc=" .. limit(category, 150) .. "&utv=" .. limit(variable, 500) .. "&utt=" .. tostring(time) .. (label and ("&utl=" .. limit(label, 500)) or ""))
	end
	
	return tracker
end


return M