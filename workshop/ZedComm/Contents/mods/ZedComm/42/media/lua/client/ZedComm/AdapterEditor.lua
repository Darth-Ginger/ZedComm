-- Singleplayer editor for a lamp's installed Advanced Adapter.
if isClient() or isServer() then return end

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISTextBox"
require "ZedComm/InternalCircuit"

local Circuit = ZedComm.InternalCircuit
local Editor = ISPanel:derive("ISZedCommAdapterEditor")
local gridX, gridY, cell = 16, 64, 78
local textureFolder = "media/textures/"
local textures = {}
local panels = {}

local function selectedLamp(player, registry, target)
    local placement = ZedComm.PlayerPlacement
    local entry = placement.getRegistry() == registry and placement.resolve(registry, target.id)
    if entry and entry.object == target.object and placement.canReach(player, entry.square) then return entry end
end

local function readLayout(registry, id)
    local record = registry.network:record(id)
    return record and record.state and record.state.circuit
end

local function thresholdIds(layout)
    local ids = {}
    for id, part in pairs(layout.modules) do
        if type(id) == "string" and type(part) == "table" and part.kind == "threshold" then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids
end

function Editor.setThreshold(player, registry, target, id)
    local entry = selectedLamp(player, registry, target)
    local expected = entry and entry.piece.state and entry.piece.state.circuit
    local module = type(expected) == "table" and type(expected.modules) == "table" and expected.modules[id]
    if not module then return end

    local function confirm(_, button)
        if button.internal ~= "OK" then return end
        local current = selectedLamp(player, registry, target)
        if not current or not current.piece.state or current.piece.state.circuit ~= expected then
            player:Say("The lamp or circuit changed. Open it again.")
            return
        end
        local layout = readLayout(registry, target.id)
        layout.modules[id].threshold = tonumber(button.parent.entry:getText())
        local ok, reason = ZedComm.PlayerPlacement.editLampCircuit(player, registry, target, expected, layout)
        local message = ok and ("Lamp threshold set to " .. layout.modules[id].threshold .. ".") or reason
        player:Say(message)
        print("[ZedComm] " .. message)
    end
    local box = ISTextBox:new(0, 0, 310, 150, "Lamp threshold (0 to 255):", tostring(module.threshold),
        nil, confirm, player:getPlayerNum())
    box:initialise()
    box:addToUIManager()
end

function Editor.addOptions(add, registry, entry)
    local layout = entry.piece.state and entry.piece.state.circuit
    if entry.piece.definitionId ~= ZedComm.RelayLamp.ID or type(layout) ~= "table"
        or type(layout.modules) ~= "table" then return end
    add("Open Advanced Adapter", Editor.open, registry, entry)
    local ids = thresholdIds(layout)
    for i, id in ipairs(ids) do
        local name = #ids == 1 and "Set threshold" or ("Set threshold (" .. id .. ")")
        add(name, Editor.setThreshold, registry, entry, id)
    end
end

local function geometry(layout)
    local parts = Circuit.fixedParts()
    for id, module in pairs(layout.modules) do parts[id] = module end
    for _, part in pairs(parts) do
        local width, height = Circuit.footprint(part.rotation)
        part.x, part.y = gridX + (part.column - 1) * cell, gridY + (part.row - 1) * cell
        part.width, part.height = width * cell, height * cell
    end
    return parts
end

local function terminalPosition(part, name)
    local x, y = Circuit.terminalPosition(part.rotation, name)
    local px, py = part.x + x * cell, part.y + y * cell
    -- Keep contact hit targets on their own part, including adjacent parts.
    if x == 0 then px = px + 9 elseif x * cell == part.width then px = px - 9 end
    if y == 0 then py = py + 9 elseif y * cell == part.height then py = py - 9 end
    return px, py
end

function Editor:refresh()
    local entry = selectedLamp(self.player, self.registry, self.target)
    local circuit = entry and entry.piece.state and entry.piece.state.circuit
    if not circuit then return false end
    if circuit ~= self.expected then
        local layout = readLayout(self.registry, self.target.id)
        local evaluate = Circuit.compile(layout)
        if not evaluate then return false end
        self.expected, self.layout, self.evaluate = circuit, layout, evaluate
        self.parts = geometry(readLayout(self.registry, self.target.id))
        self.terminal = nil
        self.placing, self.movingPart, self.pendingRotation = nil, false, nil
        if not layout.modules[self.selected] then self.selected = nil end
    end

    local inventory = self.player:getInventory():getItems()
    self.carried, self.moduleItem = 0, nil
    for i = 0, inventory:size() - 1 do
        local item = inventory:get(i)
        if item:getFullType() == "ZedComm.ThresholdModule" then
            self.carried = self.carried + 1
            self.moduleItem = self.moduleItem or item
        end
    end
    local report = ZedComm.DeviceRuntime.inspect(self.target.id)
    self.input = report and report.sourceByte or nil
    self.output = self.evaluate(self.input)
    return true
end

function Editor:commit(layout, install, remove)
    local ok, reason = ZedComm.PlayerPlacement.editLampCircuit(self.player, self.registry, self.target,
        self.expected, layout, install, remove)
    self.message = reason
    if ok then self:refresh() end
    return ok
end

function Editor:beginPlacement()
    if not self:refresh() or not self.moduleItem then return end
    self.placing, self.movingPart, self.terminal, self.message = self.moduleItem, false, nil, "Choose an empty cell."
    self.pendingRotation = 0
end

function Editor:beginMove()
    if not self:refresh() or not self.selected then return end
    self.movingPart, self.placing, self.terminal, self.message = true, nil, nil, "Choose the module's new top-left cell."
    self.pendingRotation = self.layout.modules[self.selected].rotation
end

function Editor:rotatePart()
    if not self:refresh() then return end
    if self.pendingRotation then
        self.pendingRotation = (self.pendingRotation + 90) % 360
        self.message = "Rotation " .. self.pendingRotation .. " degrees. Choose a cell."
        return
    end
    if not self.selected then return end
    local layout = readLayout(self.registry, self.target.id)
    local part = layout.modules[self.selected]
    if not part then return end
    part.rotation = (part.rotation + 90) % 360
    self:commit(layout)
end

function Editor:removePart()
    if not self:refresh() or not self.selected then return end
    local layout = readLayout(self.registry, self.target.id)
    local id = self.selected
    layout.modules[id] = nil
    for i = #layout.links, 1, -1 do
        local link = layout.links[i]
        if link.from == id or link.to == id then table.remove(layout.links, i) end
    end
    self:commit(layout, nil, true)
end

function Editor:configure()
    if self:refresh() and self.selected then Editor.setThreshold(self.player, self.registry, self.target, self.selected) end
end

function Editor:autoConnect()
    if not self:refresh() then return end
    local layout = readLayout(self.registry, self.target.id)
    local ids = thresholdIds(layout)
    if #ids ~= 1 then return end
    layout.links = {
        { from = "input", output = "out", to = ids[1], input = "in" },
        { from = ids[1], output = "out", to = "output", input = "in" },
    }
    self:commit(layout)
end

function Editor:placeAt(column, row)
    local layout = readLayout(self.registry, self.target.id)
    local id = self.selected
    if self.placing then
        local index = 1
        while layout.modules["threshold-" .. index] do index = index + 1 end
        id = "threshold-" .. index
        layout.modules[id] = { kind = "threshold", rotation = 0, threshold = 50 }
    end
    local part = layout.modules[id]
    if not part then return end
    part.column, part.row, part.rotation = column, row, self.pendingRotation or part.rotation
    if self:commit(layout, self.placing) then
        self.placing, self.movingPart, self.selected = nil, false, id
    end
end

function Editor:linkTerminal(id, name)
    local first = self.terminal
    if not first or first.name == name then
        self.terminal = { id = id, name = name }
        self.message = name == "out" and "Choose an input contact." or "Choose an output contact."
        return
    end
    local from, to = first.id, id
    if name == "out" then from, to = to, from end
    local layout = readLayout(self.registry, self.target.id)
    for i, link in ipairs(layout.links) do
        if link.from == from and link.to == to then
            table.remove(layout.links, i)
            self:commit(layout)
            return
        end
    end
    layout.links[#layout.links + 1] = { from = from, output = "out", to = to, input = "in" }
    self:commit(layout)
end

function Editor:onMouseUp(x, y)
    if not self:refresh() then self:close(); return true end
    if x < gridX or x >= gridX + 3 * cell or y < gridY or y >= gridY + 3 * cell then
        return ISPanel.onMouseUp(self, x, y)
    end
    self.moving = false
    ISMouseDrag.dragView = nil
    if self.placing or self.movingPart then
        self:placeAt(math.floor((x - gridX) / cell) + 1, math.floor((y - gridY) / cell) + 1)
        return true
    end
    for id, part in pairs(self.parts) do
        if x >= part.x and x < part.x + part.width and y >= part.y and y < part.y + part.height then
            for _, name in ipairs({ "in", "out" }) do
                if not (id == "input" and name == "in") and not (id == "output" and name == "out") then
                    local px, py = terminalPosition(part, name)
                    if math.abs(px - x) <= 8 and math.abs(py - y) <= 8 then
                        self:linkTerminal(id, name)
                        return true
                    end
                end
            end
            self.selected = part.kind == "threshold" and id or nil
            self.terminal, self.message = nil, nil
            return true
        end
    end
    self.selected, self.terminal, self.message = nil, nil, nil
    return true
end

function Editor:onMouseDown(x, y)
    if x >= gridX and x < gridX + 3 * cell and y >= gridY and y < gridY + 3 * cell then
        self:bringToTop()
        return true
    end
    return ISPanel.onMouseDown(self, x, y)
end

function Editor:onRightMouseUp(x, y)
    if not self:refresh() then self:close(); return true end
    if self.placing or self.movingPart or self.terminal then
        self.placing, self.movingPart, self.terminal, self.message, self.pendingRotation = nil, false, nil, nil, nil
        return true
    end
    for id, part in pairs(self.parts) do
        if part.kind == "threshold" and x >= part.x and x < part.x + part.width
            and y >= part.y and y < part.y + part.height then
            self.selected = id
            self:configure()
            return true
        end
    end
    return true
end

local function drawPart(panel, kind, rotation, x, y, width, height)
    local name = "ZedCommCircuit_" .. kind .. "_" .. rotation
    local texture = textures[name]
    if texture == nil then
        texture = getTexture(textureFolder .. name .. ".png") or false
        textures[name] = texture
    end
    panel:drawRect(x, y, width, height, 1, 0.18, 0.25, 0.19)
    if texture then panel:drawTextureScaled(texture, x, y, width, height, 1, 1, 1, 1) end
end

function Editor:render()
    if not self:refresh() then self:close(); return end
    self:drawText("Advanced Adapter", 16, 10, 1, 1, 1, 1, UIFont.Medium)
    self:drawText("Wire in  " .. tostring(self.input or "--"), 16, 41, 0.85, 0.90, 0.85, 1, UIFont.Small)
    self:drawText("Lamp out  " .. tostring(self.output or "--"), 134, 41, 0.85, 0.90, 0.85, 1, UIFont.Small)
    for row = 0, 2 do
        for column = 0, 2 do
            self:drawRectBorder(gridX + column * cell, gridY + row * cell, cell, cell, 0.8, 0.34, 0.43, 0.35)
        end
    end
    for id, part in pairs(self.parts) do
        drawPart(self, part.kind, part.rotation, part.x + 2, part.y + 2, part.width - 4, part.height - 4)
        if id == self.selected then
            self:drawRectBorder(part.x + 1, part.y + 1, part.width - 2, part.height - 2, 1, 0.91, 0.76, 0.41)
        end
        local label = part.kind == "threshold" and ("THR " .. part.threshold)
            or (id == "input" and "Fixed IN" or "Fixed OUT")
        self:drawRect(part.x + 5, part.y + 5, part.width - 10, 18, 0.85, 0.08, 0.11, 0.08)
        self:drawTextCentre(label, part.x + part.width / 2, part.y + 6, 1, 1, 0.91, 1, UIFont.Small)
    end
    for _, link in ipairs(self.layout.links) do
        local x1, y1 = terminalPosition(self.parts[link.from], "out")
        local x2, y2 = terminalPosition(self.parts[link.to], "in")
        local mid = (x1 + x2) / 2
        self:drawRect(math.min(x1, mid), y1 - 1, math.abs(mid - x1) + 1, 2, 1, 0.48, 0.86, 0.65)
        self:drawRect(mid - 1, math.min(y1, y2), 2, math.abs(y2 - y1) + 1, 1, 0.48, 0.86, 0.65)
        self:drawRect(math.min(mid, x2), y2 - 1, math.abs(x2 - mid) + 1, 2, 1, 0.48, 0.86, 0.65)
    end
    for id, part in pairs(self.parts) do
        for _, name in ipairs({ "in", "out" }) do
            if not (id == "input" and name == "in") and not (id == "output" and name == "out") then
                local x, y = terminalPosition(part, name)
                local active = self.terminal and self.terminal.id == id and self.terminal.name == name
                self:drawRect(x - 6, y - 6, 12, 12, 1, active and 1 or 0.52, 0.71, name == "out" and 0.93 or 0.35)
            end
        end
    end

    self:drawText("Carried modules", 272, 44, 1, 1, 1, 1, UIFont.Small)
    self:drawText("Threshold  x" .. self.carried, 312, 82, 0.91, 0.93, 0.86, 1, UIFont.Small)
    drawPart(self, "threshold", 0, 274, 69, 27, 54)
    self:drawText(self.message or "Select two contacts to link or unlink.", 16, 314, 0.90, 0.90, 0.80, 1, UIFont.Small)
    self.installButton:setEnable(self.carried > 0)
    for _, button in ipairs(self.partButtons) do button:setEnable(self.selected ~= nil) end
    self.rotateButton:setEnable(self.selected ~= nil or self.placing ~= nil)
    self.autoButton:setEnable(#thresholdIds(self.layout) == 1)
end

function Editor:createChildren()
    local function button(x, y, width, title, action)
        local widget = ISButton:new(x, y, width, 23, title, self, action)
        widget:initialise()
        self:addChild(widget)
        return widget
    end
    button(383, 9, 54, "Close", self.close)
    self.installButton = button(274, 131, 162, "Install Threshold", self.beginPlacement)
    self.autoButton = button(274, 162, 162, "Auto-connect", self.autoConnect)
    self.rotateButton = button(358, 200, 78, "Rotate", self.rotatePart)
    self.partButtons = {
        button(274, 200, 78, "Move", self.beginMove),
        button(274, 231, 78, "Remove", self.removePart),
        button(358, 231, 78, "Threshold", self.configure),
    }
end

function Editor:close()
    self:setVisible(false)
    self:removeFromUIManager()
    if panels[self.player] == self then panels[self.player] = nil end
end

function Editor.open(player, registry, target)
    local entry = selectedLamp(player, registry, target)
    if not entry or not entry.piece.state or not Circuit.compile(entry.piece.state.circuit) then
        player:Say("Choose a nearby lamp with an Advanced Adapter.")
        return
    end
    if panels[player] then panels[player]:close() end
    local width, height = 452, 345
    local panel = ISPanel.new(Editor, math.max(0, (getCore():getScreenWidth() - width) / 2),
        math.max(0, (getCore():getScreenHeight() - height) / 2), width, height)
    panel.player, panel.registry, panel.target = player, registry, target
    panel.moveWithMouse = true
    panel.backgroundColor = { r = 0.09, g = 0.13, b = 0.10, a = 1 }
    panel:initialise()
    panel:addToUIManager()
    panels[player] = panel
end

ZedComm = ZedComm or {}
ZedComm.AdapterEditor = Editor
