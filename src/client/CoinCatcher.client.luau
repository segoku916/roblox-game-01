-- Coin Catcher: catch falling coins in the basket before time runs out.
-- A complete 2D game drawn on a ScreenGui: start screen, 60-second round,
-- score, timer, lives, bombs as hazards, levels that speed up, end screen
-- with Play Again. Fully client-side; all state lives in one table.
--
-- Controls: arrow keys or A/D on desktop (read with IsKeyDown, because
-- Roblox's camera scripts swallow InputBegan for the arrows), drag the
-- basket with a finger on mobile, or hold the on-screen < and > buttons.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(script.Parent.Config)
local PALETTE = Config.PALETTE

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- All mutable game state in one place.
local state = {
	phase = "menu", -- "menu" | "playing" | "over"
	score = 0,
	best = 0,
	lives = Config.START_LIVES,
	timeLeft = Config.ROUND_SECONDS,
	elapsed = 0,
	level = 1,
	basketX = 0.5, -- basket centre as a fraction of the arena width
	dragging = false,
	buttonDir = 0, -- -1 / 0 / +1 while an on-screen button is held
	spawnTimer = 0,
	items = {}, -- active falling items: { kind, frame, x, y, speed, size, value }
}

-- Small factory: create an instance and apply a property table in one call.
local function make(className, props, parent)
	local inst = Instance.new(className)
	for key, value in pairs(props) do
		inst[key] = value
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function roundCorners(frame, radius)
	make("UICorner", { CornerRadius = UDim.new(radius or 0.5, 0) }, frame)
end

-- ---------------------------------------------------------------- interface

local gui = make("ScreenGui", {
	Name = "CoinCatcherGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
}, playerGui)

local background = make("Frame", {
	Name = "Background",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = PALETTE.background,
	BorderSizePixel = 0,
}, gui)

-- HUD bar in two rows, so it never overlaps on a narrow phone screen.
-- Roblox's own menu buttons sit over the top-left corner, so the top row
-- holds only the centred time and the right-aligned score; lives and level
-- sit on a second row, starting 64 px in, clear of that corner.
local hud = make("Frame", {
	Name = "Hud",
	Position = UDim2.new(0, 0, 0, 8),
	Size = UDim2.new(1, 0, 0, 56),
	BackgroundTransparency = 1,
}, background)

local livesLabel = make("TextLabel", {
	Name = "Lives",
	Position = UDim2.new(0, 64, 0, 34),
	Size = UDim2.new(0, 220, 0, 24),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 20,
	TextColor3 = PALETTE.danger,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "Lives: 3",
}, hud)

local timeLabel = make("TextLabel", {
	Name = "Time",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 0),
	Size = UDim2.new(0, 260, 0, 30),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 26,
	TextColor3 = PALETTE.text,
	Text = "Time: 60",
}, hud)

local scoreLabel = make("TextLabel", {
	Name = "Score",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 0),
	Size = UDim2.new(0, 260, 0, 30),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 26,
	TextColor3 = PALETTE.gold,
	TextXAlignment = Enum.TextXAlignment.Right,
	Text = "Score: 0",
}, hud)

local levelLabel = make("TextLabel", {
	Name = "Level",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 34),
	Size = UDim2.new(0, 260, 0, 24),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 18,
	TextColor3 = PALETTE.muted,
	Text = "Level 1",
}, hud)

local arena = make("Frame", {
	Name = "Arena",
	Position = UDim2.new(0, 0, 0, 72),
	Size = UDim2.new(1, 0, 1, -72),
	BackgroundColor3 = PALETTE.arena,
	BorderSizePixel = 0,
	ClipsDescendants = true,
}, background)

-- The basket: a warm rounded tub with a lighter rim, riding the arena floor.
local basket = make("Frame", {
	Name = "Basket",
	Size = UDim2.fromOffset(Config.BASKET_WIDTH, Config.BASKET_HEIGHT),
	BackgroundColor3 = PALETTE.basket,
	BorderSizePixel = 0,
}, arena)
roundCorners(basket, 0.35)
make("Frame", {
	Name = "Rim",
	Size = UDim2.new(1, 0, 0, 8),
	BackgroundColor3 = PALETTE.basketRim,
	BorderSizePixel = 0,
}, basket)

local function placeBasket()
	local arenaWidth = arena.AbsoluteSize.X
	if arenaWidth <= 0 then
		return
	end
	local half = (Config.BASKET_WIDTH / 2) / arenaWidth
	local x = math.clamp(state.basketX, half, 1 - half)
	basket.Position = UDim2.new(x, -Config.BASKET_WIDTH / 2, 1, -34)
end

-- Red flash on losing a life, and a centre announcement line for level-ups.
local flashFrame = make("Frame", {
	Name = "DamageFlash",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = PALETTE.danger,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
}, background)

local announceLabel = make("TextLabel", {
	Name = "Announce",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.35),
	Size = UDim2.new(0, 420, 0, 48),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 34,
	TextColor3 = PALETTE.goldLight,
	TextTransparency = 1,
	Text = "",
}, background)

local function announce(text)
	announceLabel.Text = text
	announceLabel.TextTransparency = 0
	task.spawn(function()
		task.wait(1.1)
		TweenService:Create(announceLabel, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
	end)
end

-- ------------------------------------------------------------------- screens

local function makeScreen(name)
	local screen = make("Frame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = PALETTE.panel,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Visible = false,
	}, background)
	return screen
end

local function makeBigButton(parent, text, yScale)
	local button = make("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, yScale, 0),
		Size = UDim2.new(0, 260, 0, 64),
		BackgroundColor3 = PALETTE.button,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		TextSize = 30,
		TextColor3 = PALETTE.buttonText,
		Text = text,
		AutoButtonColor = true,
	}, parent)
	roundCorners(button, 0.25)
	return button
end

local startScreen = makeScreen("StartScreen")
make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.16, 0),
	Size = UDim2.new(0.9, 0, 0, 72),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 56,
	TextScaled = true,
	TextColor3 = PALETTE.gold,
	Text = "COIN CATCHER",
}, startScreen)
make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.30, 0),
	Size = UDim2.new(0.9, 0, 0, 110),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 22,
	TextColor3 = PALETTE.text,
	TextWrapped = true,
	Text = "Catch the falling coins in your basket.\nStar coins are worth 25. Bombs cost a life.\n60 seconds, 3 lives. How many can you catch?",
}, startScreen)
make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.50, 0),
	Size = UDim2.new(0.9, 0, 0, 40),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 19,
	TextColor3 = PALETTE.muted,
	TextWrapped = true,
	Text = "Move: arrow keys / A D  -  drag with a finger  -  hold < >",
}, startScreen)
local playButton = makeBigButton(startScreen, "PLAY", 0.60)
startScreen.Visible = true

local endScreen = makeScreen("EndScreen")
local endTitle = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.18, 0),
	Size = UDim2.new(0.9, 0, 0, 64),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 48,
	TextScaled = true,
	TextColor3 = PALETTE.gold,
	Text = "TIME'S UP!",
}, endScreen)
local endScore = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.34, 0),
	Size = UDim2.new(0.9, 0, 0, 52),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 38,
	TextColor3 = PALETTE.text,
	Text = "Score: 0",
}, endScreen)
local endBest = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.45, 0),
	Size = UDim2.new(0.9, 0, 0, 36),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 24,
	TextColor3 = PALETTE.muted,
	Text = "Best: 0",
}, endScreen)
local againButton = makeBigButton(endScreen, "PLAY AGAIN", 0.58)

-- On-screen hold buttons for touch players, parented to the GUI (not the
-- arena) so a touch on them never starts an arena drag.
local function makeHoldButton(name, text, xScale)
	local button = make("TextButton", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(xScale, 0, 1, -18),
		Size = UDim2.fromOffset(76, 76),
		BackgroundColor3 = PALETTE.panel,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		TextSize = 40,
		TextColor3 = PALETTE.text,
		Text = text,
		AutoButtonColor = true,
	}, gui)
	roundCorners(button, 0.5)
	return button
end

local leftButton = makeHoldButton("LeftButton", "<", 0.08)
local rightButton = makeHoldButton("RightButton", ">", 0.92)

-- -------------------------------------------------------------------- items

local function makeCoinFrame(size, color, light)
	local outer = make("Frame", {
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, arena)
	roundCorners(outer, 0.5)
	local inner = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(math.floor(size * 0.6), math.floor(size * 0.6)),
		BackgroundColor3 = light,
		BorderSizePixel = 0,
	}, outer)
	roundCorners(inner, 0.5)
	return outer
end

local function makeBombFrame(size)
	local outer = make("Frame", {
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = PALETTE.bomb,
		BorderSizePixel = 0,
	}, arena)
	roundCorners(outer, 0.5)
	local fuse = make("Frame", {
		Position = UDim2.new(1, -12, 0, -2),
		Size = UDim2.fromOffset(12, 12),
		BackgroundColor3 = PALETTE.fuse,
		BorderSizePixel = 0,
	}, outer)
	roundCorners(fuse, 0.5)
	return outer
end

local function spawnItem()
	local roll = math.random()
	local kind, size, value, frame
	if roll < Config.STAR_CHANCE then
		kind, size, value = "star", Config.STAR_SIZE, Config.STAR_VALUE
		frame = makeCoinFrame(size, PALETTE.star, PALETTE.goldLight)
	elseif roll < Config.STAR_CHANCE + Config.BOMB_CHANCE then
		kind, size, value = "bomb", Config.BOMB_SIZE, 0
		frame = makeBombFrame(size)
	else
		kind, size, value = "coin", Config.COIN_SIZE, Config.COIN_VALUE
		frame = makeCoinFrame(size, PALETTE.gold, PALETTE.goldLight)
	end
	local speed = Config.FALL_SPEED * (1 + 0.22 * (state.level - 1)) * (0.85 + math.random() * 0.3)
	table.insert(state.items, {
		kind = kind,
		frame = frame,
		x = 0.05 + math.random() * 0.9, -- fraction of arena width
		y = -size,
		speed = speed,
		size = size,
		value = value,
	})
end

local function clearItems()
	for _, item in ipairs(state.items) do
		item.frame:Destroy()
	end
	state.items = {}
end

local function floatScore(text, xPixels, yPixels)
	local label = make("TextLabel", {
		Position = UDim2.fromOffset(math.floor(xPixels - 40), math.floor(yPixels)),
		Size = UDim2.fromOffset(80, 28),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 22,
		TextColor3 = PALETTE.goldLight,
		Text = text,
	}, arena)
	TweenService:Create(label, TweenInfo.new(0.6), {
		Position = UDim2.fromOffset(math.floor(xPixels - 40), math.floor(yPixels - 36)),
		TextTransparency = 1,
	}):Play()
	task.delay(0.65, function()
		label:Destroy()
	end)
end

-- -------------------------------------------------------------------- rules

local function refreshHud()
	livesLabel.Text = "Lives: " .. tostring(state.lives)
	timeLabel.Text = "Time: " .. tostring(math.ceil(state.timeLeft))
	if state.timeLeft <= 10 then
		timeLabel.TextColor3 = PALETTE.danger
	else
		timeLabel.TextColor3 = PALETTE.text
	end
	scoreLabel.Text = "Score: " .. tostring(state.score)
	levelLabel.Text = "Level " .. tostring(state.level)
end

local function endGame(reason)
	if state.phase ~= "playing" then
		return
	end
	state.phase = "over"
	clearItems()
	if state.score > state.best then
		state.best = state.score
	end
	if reason == "lives" then
		endTitle.Text = "OUT OF LIVES!"
	else
		endTitle.Text = "TIME'S UP!"
	end
	endScore.Text = "Score: " .. tostring(state.score)
	endBest.Text = "Best: " .. tostring(state.best)
	endScreen.Visible = true
end

local function loseLife()
	if state.phase ~= "playing" then
		return
	end
	state.lives -= 1
	refreshHud()
	flashFrame.BackgroundTransparency = 0.55
	TweenService:Create(flashFrame, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
	if state.lives <= 0 then
		endGame("lives")
	end
end

local function catchItem(item, index)
	local arenaWidth = arena.AbsoluteSize.X
	if item.kind == "bomb" then
		loseLife()
	else
		state.score += item.value
		refreshHud()
		scoreLabel.TextSize = 32
		TweenService:Create(scoreLabel, TweenInfo.new(0.25), { TextSize = 26 }):Play()
		floatScore("+" .. tostring(item.value), item.x * arenaWidth, item.y)
	end
	item.frame:Destroy()
	table.remove(state.items, index)
end

local function updateItems(dt)
	local arenaSize = arena.AbsoluteSize
	if arenaSize.X <= 0 or arenaSize.Y <= 0 then
		return
	end
	local basketTop = arenaSize.Y - 34 - Config.BASKET_HEIGHT
	local basketCentreX = state.basketX * arenaSize.X
	local i = 1
	while i <= #state.items do
		local item = state.items[i]
		item.y += item.speed * dt
		item.frame.Position = UDim2.new(item.x, -item.size / 2, 0, math.floor(item.y))
		local itemBottom = item.y + item.size
		local itemCentreX = item.x * arenaSize.X
		local caught = itemBottom >= basketTop
			and itemBottom <= basketTop + Config.BASKET_HEIGHT + 24
			and math.abs(itemCentreX - basketCentreX) <= (Config.BASKET_WIDTH + item.size) / 2 * 0.85
		if caught then
			catchItem(item, i)
			-- catchItem removes index i, so do not advance: the next item slides in.
		elseif item.y > arenaSize.Y then
			if item.kind ~= "bomb" then
				loseLife()
			end
			item.frame:Destroy()
			table.remove(state.items, i)
		else
			i += 1
		end
	end
end

local function startGame()
	clearItems()
	state.score = 0
	state.lives = Config.START_LIVES
	state.timeLeft = Config.ROUND_SECONDS
	state.elapsed = 0
	state.level = 1
	state.basketX = 0.5
	state.spawnTimer = 0
	state.phase = "playing"
	refreshHud()
	placeBasket()
	startScreen.Visible = false
	endScreen.Visible = false
	announce("GO!")
end

playButton.MouseButton1Click:Connect(startGame)
againButton.MouseButton1Click:Connect(startGame)

-- ------------------------------------------------------------------- input

-- Drag: a finger (or mouse) pressed on the arena steers the basket to it.
local function basketXFromScreenX(screenX)
	local arenaPos = arena.AbsolutePosition.X
	local arenaWidth = arena.AbsoluteSize.X
	if arenaWidth <= 0 then
		return state.basketX
	end
	return math.clamp((screenX - arenaPos) / arenaWidth, 0, 1)
end

arena.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseButton1 then
		state.dragging = true
		state.basketX = basketXFromScreenX(input.Position.X)
		placeBasket()
	end
end)

arena.InputChanged:Connect(function(input)
	if not state.dragging then
		return
	end
	if input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseMovement then
		state.basketX = basketXFromScreenX(input.Position.X)
		placeBasket()
	end
end)

arena.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseButton1 then
		state.dragging = false
	end
end)

-- Hold buttons: press and hold to slide the basket.
local function bindHoldButton(button, dir)
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			state.buttonDir = dir
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			if state.buttonDir == dir then
				state.buttonDir = 0
			end
		end
	end)
end

bindHoldButton(leftButton, -1)
bindHoldButton(rightButton, 1)

-- -------------------------------------------------------------------- loop

local function readKeyDirection()
	local dir = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.Left) or UserInputService:IsKeyDown(Enum.KeyCode.A) then
		dir -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.Right) or UserInputService:IsKeyDown(Enum.KeyCode.D) then
		dir += 1
	end
	return dir
end

local function moveBasket(dt)
	if state.dragging then
		return -- the drag handler places the basket directly
	end
	local dir = readKeyDirection() + state.buttonDir
	if dir > 1 then
		dir = 1
	elseif dir < -1 then
		dir = -1
	end
	if dir == 0 then
		return
	end
	local arenaWidth = arena.AbsoluteSize.X
	if arenaWidth <= 0 then
		return
	end
	state.basketX += dir * Config.BASKET_SPEED * dt / arenaWidth
	placeBasket()
end

local function tickRound(dt)
	state.elapsed += dt
	state.timeLeft = math.max(0, Config.ROUND_SECONDS - state.elapsed)
	local newLevel = 1 + math.floor(state.elapsed / Config.LEVEL_SECONDS)
	if newLevel ~= state.level then
		state.level = newLevel
		announce("LEVEL " .. tostring(state.level) .. " — FASTER!")
	end
	refreshHud()
	if state.timeLeft <= 0 then
		endGame("time")
		return
	end
	state.spawnTimer += dt
	local interval = math.max(0.35, Config.SPAWN_INTERVAL * (0.9 ^ (state.level - 1)))
	if state.spawnTimer >= interval then
		state.spawnTimer = 0
		spawnItem()
	end
	updateItems(dt)
end

RunService.RenderStepped:Connect(function(dt)
	if dt > 0.1 then
		dt = 0.1 -- a lag spike must not teleport items or the basket
	end
	if state.phase ~= "playing" then
		return
	end
	moveBasket(dt)
	tickRound(dt)
end)

refreshHud()
placeBasket()
