local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local CardinalComponents = require(Packages.CardinalComponents)

CardinalComponents.Load(script.Components)

task.wait(5)

for _, Component in CardinalComponents.Get("Part") do
	local Response = Component:RunThisFromOutside()
	print("Response from Part component: ", Response.Success, Response.Message)
end
