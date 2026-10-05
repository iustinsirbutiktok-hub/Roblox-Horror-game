-- DoorSystem
-- Place in: ServerScriptService (a Script), next to the DoorServer ModuleScript.
-- Starts the doors. (All the work is in DoorServer, so CrawlerAI can use it too.)

require(script.Parent:WaitForChild("DoorServer"))
