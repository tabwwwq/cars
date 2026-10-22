-- Rail: the grid of big drawn tiles on the left side of the screen (service,
-- orders, work, business, garage, daily...). Any controller can add a tile;
-- tiles are sorted by `layoutOrder`.

local Kit = require(script.Parent.Kit)

local Rail = {}

local gui: ScreenGui? = nil
local grid: Frame? = nil

local function ensure(): Frame
	if grid then
		return grid
	end
	local screen = Kit.screen("CarsRail", 5)
	gui = screen
	local frame = Kit.new("Frame", {
		Name = "Rail",
		Position = UDim2.fromOffset(18, 146),
		Size = UDim2.fromOffset(184, 420),
		BackgroundTransparency = 1,
		Parent = screen,
	})
	Kit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(80, 96),
		CellPadding = UDim2.fromOffset(14, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = frame,
	})
	grid = frame
	return frame
end

function Rail.add(props: {
	icon: string,
	caption: string,
	color: Color3,
	onClick: (() -> ())?,
	layoutOrder: number?,
	name: string?,
}): Kit.BigButton
	return Kit.bigButton({
		icon = props.icon,
		caption = props.caption,
		color = props.color,
		size = 80,
		onClick = props.onClick,
		layoutOrder = props.layoutOrder,
		name = props.name,
		parent = ensure(),
	})
end

-- Hides the whole rail (e.g. while working in a bay).
function Rail.setVisible(visible: boolean)
	ensure()
	if gui then
		gui.Enabled = visible
	end
end

return Rail
