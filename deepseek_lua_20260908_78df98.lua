-- ============================================================
-- RUSTYHUB AFK SERVER HOPPER + WEBHOOK + PLAYER JOIN TRIGGER
-- ============================================================

local http = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- 🔴 YOUR WEBHOOK
local WEBHOOK_URL = "https://discord.com/api/webhooks/1546895083435987030/fpODwZ3b_czyRmvPTl7T4W09gSoqMKZ32cBUUNLLMPP8q4ZPBxe7MayXcTJAgzKD22fB"

-- ⚙️ Settings
local MINIMUM_MPS = 30000000        -- 30 million
local HOP_INTERVAL = 120            -- 2 minutes (in seconds)
local WEBHOOK_COOLDOWN = 30         -- seconds between webhooks (to avoid spam)

-- ============================================================
-- Helper: Format MPS
-- ============================================================
local function formatMPS(mps)
    if mps >= 1e12 then return string.format("%.2fT/s", mps/1e12) end
    if mps >= 1e9  then return string.format("%.2fB/s", mps/1e9)  end
    if mps >= 1e6  then return string.format("%.2fM/s", mps/1e6)  end
    if mps >= 1e3  then return string.format("%.2fK/s", mps/1e3)  end
    return string.format("%.0f/s", mps)
end

-- ============================================================
-- Send to Discord with cooldown
-- ============================================================
local lastWebhookTime = 0

local function sendToDiscord(content, embed)
    local now = os.clock()
    if now - lastWebhookTime < WEBHOOK_COOLDOWN then
        print("[Webhook] Cooldown, skipping send.")
        return
    end
    lastWebhookTime = now

    local data = { content = content or "", embeds = embed and {embed} or {} }
    local json = http:JSONEncode(data)
    local headers = { ["Content-Type"] = "application/json" }
    pcall(function()
        request({ Url = WEBHOOK_URL, Method = "POST", Headers = headers, Body = json })
    end)
end

-- ============================================================
-- Scan ALL plots for pets ≥30M/s
-- ============================================================
local function getAllPets()
    local pets = {}
    local ok, AnimalsData = pcall(function()
        return require(game:GetService("ReplicatedStorage"):WaitForChild("Datas"):WaitForChild("Animals"))
    end)
    if not ok then return pets end

    local Plots = workspace:FindFirstChild("Plots")
    if not Plots then return pets end

    for _, plot in ipairs(Plots:GetChildren()) do
        local channel = nil
        if _G.MynxxSyncGet then
            channel = _G.MynxxSyncGet(plot.Name)
        end
        if not channel and type(getgc) == "function" then
            local Pkgs = game:GetService("ReplicatedStorage"):FindFirstChild("Packages")
            local Sync = Pkgs and Pkgs:FindFirstChild("Synchronizer")
            if Sync then
                local okMod, mod = pcall(require, Sync)
                if okMod and type(mod) == "table" then
                    local Channel = mod and mod.Channel
                    if Channel then
                        local gc = getgc(true)
                        for _, v in ipairs(gc) do
                            if type(v) == "table" and getmetatable(v) == Channel then
                                local idx = rawget(v, "Index")
                                if idx == plot.Name then
                                    channel = v
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end

        if channel then
            local ct = rawget(channel, "CacheTable")
            if ct and ct.AnimalList then
                for slot, animalData in pairs(ct.AnimalList) do
                    if type(animalData) == "table" then
                        local name = animalData.Index
                        if name then
                            local info = AnimalsData[name]
                            if info and info.Generation then
                                local mps = info.Generation
                                local mutation = animalData.Mutation or "None"

                                if mutation ~= "None" then
                                    local okMut, MutData = pcall(function()
                                        return require(game:GetService("ReplicatedStorage"):WaitForChild("Datas"):WaitForChild("Mutations"))
                                    end)
                                    if okMut then
                                        local m = MutData[mutation]
                                        if m and m.Modifier then
                                            mps = mps * (1 + m.Modifier)
                                        end
                                    end
                                end

                                if animalData.Traits and type(animalData.Traits) == "table" then
                                    local okTr, TraitsData = pcall(function()
                                        return require(game:GetService("ReplicatedStorage"):WaitForChild("Datas"):WaitForChild("Traits"))
                                    end)
                                    if okTr then
                                        for _, tr in ipairs(animalData.Traits) do
                                            local t = TraitsData[tr]
                                            if t and t.MultiplierModifier then
                                                mps = mps * (1 + t.MultiplierModifier)
                                            end
                                        end
                                    end
                                end

                                if mps >= MINIMUM_MPS then
                                    local ownerName = "Unknown"
                                    if ct.Owner then
                                        if type(ct.Owner) == "string" then
                                            ownerName = ct.Owner
                                        elseif type(ct.Owner) == "number" then
                                            local plr = Players:GetPlayerByUserId(ct.Owner)
                                            ownerName = plr and plr.Name or tostring(ct.Owner)
                                        elseif typeof(ct.Owner) == "Instance" and ct.Owner:IsA("Player") then
                                            ownerName = ct.Owner.Name
                                        end
                                    end
                                    table.insert(pets, {
                                        name = info.DisplayName or name,
                                        mps = mps,
                                        mutation = mutation,
                                        plot = plot.Name,
                                        slot = slot,
                                        owner = ownerName
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(pets, function(a, b) return a.mps > b.mps end)
    return pets
end

-- ============================================================
-- Build join link
-- ============================================================
local function buildJoinLink(jobId)
    return "https://www.roblox.com/games/start?placeId=" .. game.PlaceId .. "&gameInstanceId=" .. jobId
end

-- ============================================================
-- Send webhook (top 5 pets + JobId + join link)
-- ============================================================
local function sendWebhook()
    local jobId = game.JobId
    local pets = getAllPets()

    if #pets == 0 then
        sendToDiscord(string.format(
            "❌ **No pets ≥30M/s found**\n🆔 Server: `%s`\n🔗 [Join](%s)",
            jobId, buildJoinLink(jobId)
        ))
        return
    end

    local top5 = {}
    for i = 1, math.min(5, #pets) do top5[i] = pets[i] end

    local description = ""
    local emojis = {"🥇", "🥈", "🥉", "4️⃣", "5️⃣"}
    for i, pet in ipairs(top5) do
        description = description .. string.format(
            "%s **%s** — `%s` | 🏠 %s %s\n",
            emojis[i] or "•",
            pet.name,
            formatMPS(pet.mps),
            pet.plot,
            pet.mutation ~= "None" and "🧬 " .. pet.mutation or ""
        )
    end
    if #pets > 5 then
        description = description .. string.format("\n*…and %d more pets ≥30M/s*", #pets - 5)
    end

    description = description .. string.format(
        "\n\n🆔 **Server:** `%s`\n🔗 **[Click to join this server](%s)**",
        jobId, buildJoinLink(jobId)
    )

    local embed = {
        title = "🌍 Top 5 Pets (All Plots, ≥30M/s)",
        description = description,
        color = 0x9B59B6,
        footer = { text = "Rustyhub | " .. os.date("%Y-%m-%d %H:%M:%S") .. " | " .. #pets .. " pets" }
    }
    sendToDiscord(nil, embed)
    print("[Webhook] Sent! Server: " .. jobId .. " | Pets: " .. #pets)
end

-- ============================================================
-- Server hop function
-- ============================================================
local function serverHop()
    print("[Hopper] Teleporting to a new server...")
    pcall(function()
        TeleportService:Teleport(game.PlaceId)
    end)
end

-- ============================================================
-- REJOIN BUTTON (top-right corner)
-- ============================================================
local function setupRejoinButton()
    local old = game.Players.LocalPlayer.PlayerGui:FindFirstChild("RustyhubRejoin")
    if old then old:Destroy() end

    local sg = Instance.new("ScreenGui")
    sg.Name = "RustyhubRejoin"
    sg.ResetOnSpawn = false
    sg.IgnoreGuiInset = true
    sg.Parent = game.Players.LocalPlayer.PlayerGui

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 100, 0, 40)
    btn.Position = UDim2.new(1, -115, 0, 10)
    btn.BackgroundColor3 = Color3.fromRGB(110, 0, 200)
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.Text = "⟳ Rejoin"
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 16
    btn.BorderSizePixel = 0
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
    btn.Parent = sg

    btn.MouseButton1Click:Connect(function()
        btn.Text = "⏳ Hopping..."
        btn.BackgroundColor3 = Color3.fromRGB(200, 100, 0)
        task.spawn(function()
            serverHop()
        end)
    end)

    -- Reset button when new server loads
    game.Loaded:Connect(function()
        btn.Text = "⟳ Rejoin"
        btn.BackgroundColor3 = Color3.fromRGB(110, 0, 200)
    end)
end

-- ============================================================
-- TRIGGER SCAN ON PLAYER JOIN
-- ============================================================
local function onPlayerAdded()
    print("[Trigger] New player joined, scanning for pets...")
    -- Small delay to let their pets load
    task.wait(2)
    sendWebhook()
end

-- ============================================================
-- MAIN LOOP (auto hop every 2 minutes)
-- ============================================================
local function main()
    print("[Rustyhub] Started. Auto-hop every " .. HOP_INTERVAL .. "s.")
    print("[Rustyhub] Will also scan when any new player joins.")
    task.wait(10)  -- initial load

    while true do
        -- Wait the full interval, but we might also send on player join separately
        task.wait(HOP_INTERVAL)
        -- After waiting, we send a periodic update and then hop
        sendWebhook()
        serverHop()
        task.wait(8)  -- wait for new server to settle
    end
end

-- ============================================================
-- START EVERYTHING
-- ============================================================
-- Listen for new players joining the server
Players.PlayerAdded:Connect(onPlayerAdded)

-- Also send a webhook on our own join (after a hop)
game.Loaded:Connect(function()
    task.wait(8)  -- wait for the game to fully load
    sendWebhook()
end)

-- Launch the 2-minute auto-hop loop
task.spawn(main)

-- Create the rejoin button
task.spawn(setupRejoinButton)