-- Signal: a tiny synchronous event object for module-to-module communication.

export type Connection = { Connected: boolean, Disconnect: (self: Connection) -> () }

local Signal = {}
Signal.__index = Signal

export type Signal<T...> = typeof(setmetatable({} :: { _handlers: { [Connection]: (T...) -> () } }, Signal))

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal.Connect(self, fn: (...any) -> ()): Connection
	local handlers = self._handlers
	local conn = { Connected = true } :: any
	function conn.Disconnect(c)
		c.Connected = false
		handlers[c] = nil
	end
	handlers[conn] = fn
	return conn
end

function Signal.Once(self, fn: (...any) -> ()): Connection
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

function Signal.Fire(self, ...: any)
	for conn, fn in table.clone(self._handlers) do
		if conn.Connected then
			local ok, err = pcall(fn, ...)
			if not ok then
				warn("[Signal] handler error: " .. tostring(err))
			end
		end
	end
end

function Signal.DisconnectAll(self)
	for conn in self._handlers do
		conn.Connected = false
	end
	table.clear(self._handlers)
end

return Signal
