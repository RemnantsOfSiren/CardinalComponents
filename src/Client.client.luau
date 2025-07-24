--!strict
--!optimize 2
local Module = script:FindFirstChild("Module")

if not Module then
	error("Actor couldn't find Module script.")
end

local ObjectRef = script:FindFirstChild("ObjectRef")

if not ObjectRef then
	error("Actor couldn't find ObjectRef script.")
end

local RunService = game:GetService("RunService")

local Noop = function() end
local OnInit: BindableEvent = script:FindFirstChild("OnInit")
local InvokeCallback: BindableFunction = script:FindFirstChild("InvokeCallback")

Module = require(Module)

local Object = ObjectRef.Value
Module.Instance = Object

OnInit.Event:Connect(function(Active, TroveRef)
	if Module.__Active == Active then
		return
	end

	if not Active then
		if Module.Cleaner then
			Module.Cleaner:Destroy()
		end

		Module.__Initialized = false
		Module.__Active = false
		return
	end

	local Init = Module.OnInit or Module.Init

	if Active and Init then
		local Trove = require(TroveRef) :: { [any]: any }
		Module.Cleaner = Trove.new()

		Module:Init()

		Module.__Initialized = true
	end

	Module.__Active = Active
end)

InvokeCallback.OnInvoke = function(CallbackName, ...)
	if not Module.__Active then
		return
	end

	local Callback = Module[CallbackName]

	if not Callback then
		return
	end

	return Callback(Module, ...)
end

for Index, CallbackOrParam in Module do
	if type(Index) ~= "string" then
		continue
	end

	local Event = string.gsub(Index, "On", "")

	if Event == "Destroy" or Event == "Init" then
		continue
	end

	if type(CallbackOrParam) == "function" then
		local Success = pcall(function()
			local Connection = RunService[Event]:ConnectParallel(Noop)
			if Connection then
				Connection:Disconnect()
			end
		end)

		if not Success then
			continue
		end

		RunService[Event]:ConnectParallel(function(...)
			if not Module.__Initialized then
				return
			end

			CallbackOrParam(Module, ...)
		end)
	end
end
