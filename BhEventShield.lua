--[[
BhEventShield.lua
Mouse and touch event recording and playback for Gideros. Andy Bower, Bowerhaus LLP

MIT License
Copyright (C) 2012. Andy Bower, Bowerhaus LLP (http://bowerhaus.eu)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software
and associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute,
sublicense, and/or sell copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

This code is MIT licensed, see http://www.opensource.org/licenses/mit-license.php
]]

require "Json"

BhEventShield=Core.class(Sprite)

-- Save original stopPropagation function
if Event.__stopPropagation==nil then
	Event.__stopPropagation = Event.stopPropagation
end
 
-- Reimplement stopPropagation
function Event:stopPropagation()
	self.__isPropagationStopped = true
	self:__stopPropagation()
end
 
function Event:isPropagationStopped()
	return not not self.__isPropagationStopped
end

local function recursiveDispatchEvent(sprite, event)
	for i=sprite:getNumChildren(),1,-1 do
		recursiveDispatchEvent(sprite:getChildAt(i), event)
	end
	if not event:isPropagationStopped() then
		sprite:dispatchEvent(event)
	end
end

function BhEventShield:createButton(name, x, y)
	local button=BhButton.new(name, nil, self.texturePack)
	button:setPosition(x, y)
	self:addChild(button)
	return button
end

function BhEventShield:init(isGreenScreenMode, clapperboardColor)
	self.DOUBLETAPTIME=0.3
	self.CAPTUREDELAY=0.02
	self:reset()
	
	-- Fill a green screen rectangle to be ready for recording, if requested
	if isGreenScreenMode then
		local w=application:getContentWidth()
		local h=application:getContentHeight()
		local size=math.max(w,h)
		self.greenScreen=Shape.bhMakeRect(0, 0, size, size, nil, 0x00ff00)
		self.greenScreen:setAlpha(0.9)
	end
	
	-- Record whether we want a clapperboard marker at start of record and playback
	self.clapperboardColor=clapperboardColor
	
	self:addEventListener(Event.ADDED_TO_STAGE, self.onAddedToStage, self)
	self:addEventListener(Event.REMOVED_FROM_STAGE, self.onRemovedFromStage, self)
	stage:addChild(self)
	
	self:loadSavedRecording("|D|BhEventShield.rec")
end

function BhEventShield:loadSavedRecording(filename)
	local contents
	local file = io.open(filename, "r")
	if file then
		self:reset()
		contents = file:read("*a")
		io.close( file )
		self.capture=Json.Decode(contents)
	end
end

function BhEventShield:saveRecording(filename)
	local file = io.open(filename, "w+")
	if file then
		file:write(Json.Encode(self.capture))
		io.close( file )
	end
end

function BhEventShield:playEvent(event)
	recursiveDispatchEvent(stage, event)
end

function BhEventShield:addEvent(e)
	local touch
	if e.touch then touch=table.copy(e.touch) end
	self.capture[#self.capture+1]={
		type=e:getType(), 
		x=e.x or -1, 
		y=e.y or -1, 
		touch=touch,
		timeOffset=os.timer()-self.time0}
	
	-- Replay of events will typically be slower than normal since we are handling the event dispatch in pure
	-- Lua. This means that the playback may not be able to keep up with a stream of mouse or touch move events
	-- happening at 60fps. To alleviate this we slow the capture process down in order to record fewer events.
	-- You need to choose a judicious value for CAPTUREDELAY to avoid time skippage in playback whilst also
	-- keeping motion smooth enough in the app itself. Note this delay is only interjected during mouse/touch
	-- moves and not for all frame processing.
	--
	local endTime=os.timer()+self.CAPTUREDELAY
	while os.timer()<endTime do end
end

function BhEventShield:reset()
	self.capture={}
	self.isRecording=false
	self.isReplaying=false
	self.replayIndex=0
end

function BhEventShield:record()
	self:reset()
	if self.greenScreen then
		self:addChild(self.greenScreen)
	end
	self.isCapturing=true
	self.isReplaying=false
	self.time0=os.timer()
	self.wantClap=4
	print("BhEventShield recording started")
end

function BhEventShield:stop()
	if self.greenScreen then
		self.greenScreen:removeFromParent()
	end
	if self.isCapturing then
		self:saveRecording("|D|BhEventShield.rec")
	end
	self.isCapturing=false
	self.isReplaying=false
	print("BhEventShield stopped")
end

function BhEventShield:play()
	self.replayIndex=0
	self.isReplaying=true
	self.isCapturing=false
	self.time0=os.timer()
	self.wantClap=4
	print("BhEventShield replay started")
end

function BhEventShield:onCaptureEvent(event)
	if self.isCapturing then 
		self:addEvent(event)
	end
end

function BhEventShield:onMouseDown(event)
	-- Double tap in left corner starts/stops recording and in right, starts/stop playback
	if event.x<100 and event.y>application:getContentHeight()-100 then
		-- Tap in left box
		local timeNow=os.timer()
		if self.lastTapTime and (self.lastTapTime+self.DOUBLETAPTIME)>timeNow then
			if self.isCapturing then self:stop() else self:record() end
			event:stopPropagation()
			return
		end
		self.lastTapTime=timeNow
	end
	if event.x>application:getContentWidth()-100 and event.y>application:getContentHeight()-100 then
		-- Tap in right box
		local timeNow=os.timer()
		if self.lastTapTime and (self.lastTapTime+self.DOUBLETAPTIME)>timeNow then
			if self.isReplaying then self:stop() else self:play() end
			event:stopPropagation()
			return
		end
		self.lastTapTime=timeNow
	end
	self:onCaptureEvent(event)
end

function BhEventShield:onAddedToStage(event)
	self:addEventListener(Event.ENTER_FRAME, self.onEnterFrame, self)
	self:addEventListener(Event.MOUSE_DOWN, self.onMouseDown, self)
	self:addEventListener(Event.MOUSE_MOVE, self.onCaptureEvent, self)
	self:addEventListener(Event.MOUSE_UP, self.onCaptureEvent, self)

	self:addEventListener(Event.TOUCHES_BEGIN, self.onCaptureEvent, self)
	self:addEventListener(Event.TOUCHES_MOVE, self.onCaptureEvent, self)
	self:addEventListener(Event.TOUCHES_END, self.onCaptureEvent, self)
	self:addEventListener(Event.TOUCHES_CANCEL, self.onCaptureEvent, self)
end

function BhEventShield:onRemovedFromStage(event)
	self:removeEventListener(Event.ENTER_FRAME, self.onEnterFrame, self)
	self:removeEventListener(Event.MOUSE_DOWN, self.onMouseDown, self)
	self:removeEventListener(Event.MOUSE_MOVE, self.onCaptureEvent, self)
	self:removeEventListener(Event.MOUSE_UP, self.onCaptureEvent, self)

	self:removeEventListener(Event.TOUCHES_BEGIN, self.onCaptureEvent, self)
	self:removeEventListener(Event.TOUCHES_MOVE, self.onCaptureEvent, self)
	self:removeEventListener(Event.TOUCHES_END, self.onCaptureEvent, self)
	self:removeEventListener(Event.TOUCHES_CANCEL, self.onCaptureEvent, self)
end

function BhEventShield:onEnterFrame(event)
	-- Ensure we are always at top of stage z-order
	stage:addChild(self)
	
	-- Clapperboard to synchronise playbacks
	if self.clapperboard then
		self.clapperboard:removeFromParent()
		self.clapperboard=nil
	end
	if self.wantClap and self.wantClap>0 then
		local w=application:getContentWidth()
		local h=application:getContentHeight()
		local size=math.max(w,h)
		self.clapperboard=Shape.bhMakeRect(0, 0, size, size, nil, self.clapperboardColor)
		self:addChild(self.clapperboard)
		self.wantClap=self.wantClap-1
	end
	
	if self.isReplaying then
		-- In replay mode, build a replay event and dispatch
		local nextEventData=self.capture[self.replayIndex+1]
		local timeOffsetNow=os.timer()-self.time0
		local slipTime=timeOffsetNow - nextEventData.timeOffset
		 
		-- If slip time gets larger than one or two frames then we are processing
		-- events too slowly so we may need to increase the event delay time on recording.
		-- Try increasing self.CAPTUREDELAY in init().
		if slipTime> 0.2 then
			print("Time slippage=", slipTime)
		end
		
		if  slipTime>0 then	
			local nextEvent=Event.new(nextEventData.type)
			nextEvent.x=nextEventData.x
			nextEvent.y=nextEventData.y
			nextEvent.touch=nextEventData.touch
			self:playEvent(nextEvent)
			self.replayIndex=self.replayIndex+1
			if self.replayIndex>=#self.capture then
				self:stop()
			end
		end
	end
end