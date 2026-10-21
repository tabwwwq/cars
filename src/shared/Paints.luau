-- Paints: color palette and paint finishes shared by the builder, garage UI and server validation.

export type Swatch = { name: { ru: string, en: string }, color: Color3 }
export type Finish = {
	id: string,
	name: { ru: string, en: string },
	material: Enum.Material,
	reflectance: number,
}

local Paints = {}

local function c(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Paints.Palette = {
	{ name = { ru = "Снежный", en = "Snow" }, color = c(240, 242, 245) },
	{ name = { ru = "Серебро", en = "Silver" }, color = c(176, 182, 190) },
	{ name = { ru = "Графит", en = "Graphite" }, color = c(70, 74, 82) },
	{ name = { ru = "Чёрный", en = "Black" }, color = c(22, 23, 27) },
	{ name = { ru = "Красный", en = "Red" }, color = c(214, 32, 40) },
	{ name = { ru = "Вишня", en = "Cherry" }, color = c(130, 14, 32) },
	{ name = { ru = "Оранжевый", en = "Orange" }, color = c(255, 116, 24) },
	{ name = { ru = "Жёлтый", en = "Yellow" }, color = c(255, 206, 28) },
	{ name = { ru = "Лайм", en = "Lime" }, color = c(150, 222, 40) },
	{ name = { ru = "Зелёный", en = "Green" }, color = c(32, 150, 72) },
	{ name = { ru = "Хаки", en = "Olive" }, color = c(96, 104, 58) },
	{ name = { ru = "Бирюза", en = "Teal" }, color = c(18, 170, 170) },
	{ name = { ru = "Голубой", en = "Sky" }, color = c(80, 180, 255) },
	{ name = { ru = "Синий", en = "Blue" }, color = c(28, 82, 214) },
	{ name = { ru = "Ночной", en = "Midnight" }, color = c(20, 30, 74) },
	{ name = { ru = "Фиолетовый", en = "Purple" }, color = c(120, 52, 206) },
	{ name = { ru = "Розовый", en = "Pink" }, color = c(255, 92, 178) },
	{ name = { ru = "Песочный", en = "Sand" }, color = c(214, 186, 138) },
	{ name = { ru = "Коричневый", en = "Brown" }, color = c(108, 66, 38) },
	{ name = { ru = "Бронза", en = "Bronze" }, color = c(176, 120, 62) },
	{ name = { ru = "Золото", en = "Gold" }, color = c(222, 176, 52) },
	{ name = { ru = "Мята", en = "Mint" }, color = c(150, 236, 200) },
	{ name = { ru = "Лаванда", en = "Lavender" }, color = c(186, 166, 240) },
	{ name = { ru = "Кислотный", en = "Toxic" }, color = c(198, 255, 0) },
} :: { Swatch }

Paints.Finishes = {
	{ id = "Gloss", name = { ru = "Глянец", en = "Gloss" }, material = Enum.Material.SmoothPlastic, reflectance = 0.12 },
	{ id = "Matte", name = { ru = "Мат", en = "Matte" }, material = Enum.Material.SmoothPlastic, reflectance = 0 },
	{ id = "Metallic", name = { ru = "Металлик", en = "Metallic" }, material = Enum.Material.Foil, reflectance = 0.05 },
	{ id = "Pearl", name = { ru = "Перламутр", en = "Pearl" }, material = Enum.Material.Glass, reflectance = 0.25 },
	{ id = "Chrome", name = { ru = "Хром", en = "Chrome" }, material = Enum.Material.Metal, reflectance = 0.55 },
	{ id = "Neon", name = { ru = "Неон", en = "Neon" }, material = Enum.Material.Neon, reflectance = 0 },
} :: { Finish }

local finishById: { [string]: Finish } = {}
for _, f in Paints.Finishes do
	finishById[f.id] = f
end

function Paints.getColor(index: number?): Color3
	local swatch = Paints.Palette[index or 1]
	return if swatch then swatch.color else Paints.Palette[1].color
end

function Paints.isValidIndex(index: any): boolean
	return typeof(index) == "number" and index == math.floor(index) and Paints.Palette[index] ~= nil
end

function Paints.getFinish(id: string?): Finish
	return finishById[id or "Gloss"] or finishById.Gloss
end

function Paints.isValidFinish(id: any): boolean
	return typeof(id) == "string" and finishById[id] ~= nil
end

return Paints
