--[[
    Copyright (c) 2025, Byran Emery

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
]]
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Trove = require(script.Parent.Trove)
local CardinalLifecycles = require(script.Parent.CardinalLifecycles)

export type SubComponentConfig = {
	IsActor: boolean?,
	Instance: any,
	[any]: any,
}

local function Noop() end

local Component = {}
Component.__index = Component

function Component.new(Config: ComponentConfig)
	local self = setmetatable(Config, Component)

	if not Config.IsActor then
		for Index, CallbackOrParam in pairs(Config) do
			if type(Index) ~= "string" then
				continue
			end

			local Event = string.gsub(Index, "On", "")

			if Event == "Destroy" or Event == "Init" then
				continue
			end

			if type(CallbackOrParam) == "function" then
				local Success = pcall(function()
					RunService[Event]:Once(Noop)
				end)

				if not Success then
					continue
				end

				CardinalLifecycles(RunService[Event], function(...)
					if not self.__Active then
						return
					end

					CallbackOrParam(self, ...)
				end)
			end
		end
	end

	return self
end

export type ComponentConfig = {
	Tag: string,
	IsActor: boolean?,
	Ancestors: { string }?,
	[any]: any,
}

local Loaded = {}

local function ComponentCreator(Config: {
	Module: ModuleScript,
	Component: ComponentConfig,
})
	local _Component = Config.Component
	local Tag = _Component.Tag
	local Ancestors = _Component.Ancestors or { workspace }

	_Component.Tag = nil
	_Component.Ancestors = nil

	local Components = {}

	local function IsDescendantOfAncestors(Object)
		local IsModel = Object:IsA("Model")

		if IsModel and Object.PrimaryPart == nil then
			return false
		end

		for _, Ancestor in pairs(Ancestors) do
			local Part = if IsModel then Object.PrimaryPart else Object

			if Part:IsDescendantOf(Ancestor) then
				return true
			end
		end

		return false
	end

	local function OnObjectAdded(Object: Instance)
		if not Components[Object] then
			if not _Component.IsActor then
				local subComponent = table.clone(_Component)
				subComponent.Instance = Object
				subComponent.__Active = false
				local Cleaner = Trove.new()
				subComponent.Cleaner = Cleaner:Extend()

				subComponent = setmetatable(Component.new(subComponent), _Component)

				local function AncestryChanged()
					local IsDescendant = IsDescendantOfAncestors(Object)

					if not IsDescendant and subComponent.__Active then
						subComponent.__Active = false
					elseif IsDescendant and not subComponent.__Active then
						subComponent.__Active = true
						local Init = subComponent.OnInit or subComponent.Init
						if Init then
							task.spawn(Init, subComponent)
						end
					end
				end

				Cleaner:Connect(Object.AncestryChanged, AncestryChanged)
				if Object:IsA("Model") then
					Cleaner:Connect(Object:GetPropertyChangedSignal("PrimaryPart"), AncestryChanged)
				end
				task.spawn(AncestryChanged)

				Cleaner:Connect(Object.Destroying, function()
					if Cleaner then
						Cleaner:Destroy()
					end

					if subComponent.Destroy then
						task.spawn(subComponent.Destroy, subComponent)
					end
					Components[Object] = nil
				end)

				Components[Object] = subComponent
			else
				local Cleaner = Trove.new()

				local Actor = Cleaner:Add(Instance.new("Actor"), "Destroy")

				local Runner = RunService:IsServer() and script.Server:Clone() or script.Client:Clone()

				Runner.Parent = Actor

				local Ref = Cleaner:Add(Instance.new("ObjectValue"), "Destroy")
				Ref.Name = "ObjectRef"
				Ref.Value = Object
				Ref.Parent = Runner

				local Module = Cleaner:Add(Config.Module:Clone(), "Destroy")
				Module.Name = "Module"
				Module.Parent = Runner

				local BindableEvent: BindableEvent = Cleaner:Add(Instance.new("BindableEvent"), "Destroy")
				BindableEvent.Name = "OnInit"
				BindableEvent.Parent = Runner

				local BindableFunction: BindableFunction = Cleaner:Add(Instance.new("BindableFunction"), "Destroy")
				BindableFunction.Name = "InvokeCallback"
				BindableFunction.Parent = Runner

				local Active = false

				local function AncestryChanged()
					local IsDescendant = IsDescendantOfAncestors(Object)

					if not IsDescendant and Active then
						Active = false
					elseif IsDescendant and not Active then
						Active = true
					end

					BindableEvent:Fire(Active, script.Parent.Trove)
				end

				Cleaner:Connect(Object.AncestryChanged, AncestryChanged)
				task.delay(0.1, AncestryChanged)

				Cleaner:Connect(Actor.Destroying, function()
					if Cleaner then
						Cleaner:Destroy()
					end
					Components[Object] = nil
				end)

				Actor.Parent = Object

				local Helper = {}

				for Index in _Component do
					if type(Index) ~= "string" then
						continue
					end

					local Event = string.gsub(Index, "On", "")

					if Event == "Destroy" or Event == "Init" then
						continue
					end

					Helper[Index] = function(_, ...)
						if not Active then
							return Noop()
						end

						return BindableFunction:Invoke(Index, ...)
					end
				end

				Components[Object] = Helper
			end
		end
	end

	for _, Object in CollectionService:GetTagged(Tag) do
		task.spawn(OnObjectAdded, Object)
	end

	CollectionService:GetInstanceAddedSignal(Tag):Connect(OnObjectAdded)

	CollectionService:GetInstanceRemovedSignal(Tag):Connect(function(Object)
		local _Component = Components[Object]

		if not _Component then
			return
		end

		if _Component.Destroy then
			task.spawn(_Component.Destroy, _Component)
		end

		if not Config.Component.IsActor then
			_Component.__Cleaner:Destroy()
		end

		Components[Object] = nil
	end)

	Loaded[Tag] = Components
end

return {
	Load = function(Folder: Folder, Config: { Deep: boolean?, Predicate: ((Instance: Instance) -> boolean)? }?)
		local ModulesToLoad = if Config and Config.Deep then Folder:GetDescendants() else Folder:GetChildren()
		for _, Module in ModulesToLoad do
			if Module:IsA("ModuleScript") then
				if Config and Config.Predicate and not Config.Predicate(Module) then
					continue
				end
				local Success, _Component = pcall(require, Module)

				if Success and type(Component) == "table" then
					if not _Component.Tag then
						_Component.Tag = Module.Name
					end

					task.spawn(ComponentCreator, {
						Module = Module,
						Component = _Component,
					})
				end
			end
		end
	end,

	Get = function(Tag: string): { [Instance]: SubComponentConfig }?
		return Loaded[Tag]
	end,
}
