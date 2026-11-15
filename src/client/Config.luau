-- Coin Catcher: every tuning number and every colour in one place.
-- The game script reads this module and never hard-codes a value twice.

local Config = {}

-- Round rules.
Config.ROUND_SECONDS = 60
Config.START_LIVES = 3
Config.LEVEL_SECONDS = 15 -- a new level every 15 seconds: items fall faster

-- Basket.
Config.BASKET_WIDTH = 110
Config.BASKET_HEIGHT = 26
Config.BASKET_SPEED = 560 -- pixels per second, keys and hold buttons

-- Falling items.
Config.COIN_SIZE = 36
Config.STAR_SIZE = 48
Config.BOMB_SIZE = 40
Config.COIN_VALUE = 10
Config.STAR_VALUE = 25
Config.FALL_SPEED = 230 -- pixels per second at level 1
Config.SPAWN_INTERVAL = 0.75 -- seconds between spawns at level 1
Config.STAR_CHANCE = 0.08 -- share of spawns that are star coins
Config.BOMB_CHANCE = 0.12 -- share of spawns that are bombs

-- Palette: deep navy night sky, gold coins, warm basket, danger red.
Config.PALETTE = {
	background = Color3.fromRGB(27, 42, 74),
	arena = Color3.fromRGB(36, 54, 94),
	panel = Color3.fromRGB(20, 30, 56),
	text = Color3.fromRGB(245, 245, 245),
	muted = Color3.fromRGB(170, 185, 215),
	gold = Color3.fromRGB(255, 201, 60),
	goldLight = Color3.fromRGB(255, 224, 130),
	star = Color3.fromRGB(255, 226, 102),
	bomb = Color3.fromRGB(43, 43, 43),
	fuse = Color3.fromRGB(230, 57, 70),
	basket = Color3.fromRGB(224, 123, 57),
	basketRim = Color3.fromRGB(184, 92, 40),
	button = Color3.fromRGB(46, 204, 113),
	buttonText = Color3.fromRGB(255, 255, 255),
	danger = Color3.fromRGB(230, 57, 70),
}

return Config
