local Part = {
	IsActor = true,
}

function Part:Init()
	print("Part component initialized: " .. self.Instance.Name)
end

function Part:RunThisFromOutside()
	return { Success = true, Message = "This is a test message from Part component." }
end

function Part:OnHeartbeat()
	local Instance = self.Instance
	print(Instance:GetPivot())
end

return Part
