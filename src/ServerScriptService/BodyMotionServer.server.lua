-- BodyMotionServer
-- Place in: ServerScriptService (a Script named "BodyMotionServer")
--
-- Each player's screen knows how it's moving (walking, sprinting, crouching,
-- crawling); this passes that on as the character's "Stance" attribute so
-- every other screen can show it too (BodyMotion reads it).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = ReplicatedStorage:FindFirstChild("BodyMotion") or Instance.new("RemoteEvent")
remote.Name = "BodyMotion"
remote.Parent = ReplicatedStorage

local STANCES = { Walk = true, Sprint = true, Crouch = true, Crawl = true }

remote.OnServerEvent:Connect(function(player, stance)
	local character = player.Character
	if character and type(stance) == "string" and STANCES[stance] then
		character:SetAttribute("Stance", stance)
	end
end)
