-- Singleplayer editor for Advanced Adapters and Small Cabinets.
if isClient() or isServer() then return end

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISContextMenu"
require "ISUI/ISTextBox"
require "ZedComm/InternalCircuit"

local Circuit = ZedComm.InternalCircuit
local Editor = ISPanel:derive("ISZedCommAdapterEditor")
local gridX, gridY = 16, 64
local carriedY, carriedWidth, carriedHeight, carriedStep = 69, 164, 30, 34
local paletteRows = 8
local textureFolder = "media/textures/"
local textures = {}
local panels = {}

local function reachMessage(cabinet)
    return "Step next to the " .. (cabinet and "cabinet" or "lamp") .. " to make changes."
end

-- `view` allows the two-tile looking range; anything that changes the board needs reach.
local function selectedHost(player, registry, target, view)
    local placement = ZedComm.PlayerPlacement
    local entry = placement.getRegistry() == registry and placement.resolve(registry, target.id)
    if not entry or entry.object ~= target.object then return nil end
    if view and placement.canView(player, entry.square) or placement.canReach(player, entry.square) then return entry end
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

local function onlyModule(layout)
    local found
    for id in pairs(layout.modules) do
        if found then return nil end
        found = id
    end
    return found
end

local function setNumber(player, registry, target, id, field, title, default)
    local entry = selectedHost(player, registry, target)
    local expected = entry and entry.piece.state and entry.piece.state.circuit
    local module = type(expected) == "table" and type(expected.modules) == "table" and expected.modules[id]
    if not module then return end

    local function confirm(_, button)
        if button.internal ~= "OK" then return end
        local current = selectedHost(player, registry, target)
        if not current or not current.piece.state or current.piece.state.circuit ~= expected then
            player:Say("The device or circuit changed. Open it again.")
            return
        end
        local value = tonumber(button.parent.entry:getText())
        if not value then
            player:Say("Enter a number.")
            return
        end
        local layout = readLayout(registry, target.id)
        layout.modules[id][field] = value
        local ok, reason = ZedComm.PlayerPlacement.editCircuit(player, registry, target, expected, layout)
        local message = ok and ("Set to " .. value .. ".") or reason
        player:Say(message)
        print("[ZedComm] " .. message)
    end
    local box = ISTextBox:new(0, 0, 310, 150, title, tostring(module[field] or default),
        nil, confirm, player:getPlayerNum())
    box:initialise()
    box:addToUIManager()
end

function Editor.setThreshold(player, registry, target, id)
    setNumber(player, registry, target, id, "threshold", "Threshold (0 to 255)", 50)
end

function Editor.renameJack(player, registry, target, id)
    local entry = selectedHost(player, registry, target)
    local board = entry and entry.piece.board
    local direction = board and board.directions[id]
    if not direction then return end
    local labels = entry.piece.state.portLabels
    local label = labels and labels[id]

    local function confirm(_, button)
        if button.internal ~= "OK" then return end
        if not selectedHost(player, registry, target) then
            player:Say("That object is no longer within reach.")
            return
        end
        local ok, result = registry:renameCabinetPort(target.id, id, button.parent.entry:getText())
        local message = ok and ("Jack label updated to " .. result .. ".") or result
        player:Say(message)
        print("[ZedComm] " .. message)
    end

    local title = "Label " .. Circuit.jackLabel(id, direction, label) .. " (blank resets)"
    local box = ISTextBox:new(0, 0, 320, 160, title, label or "", nil, confirm, player:getPlayerNum())
    box:initialise()
    box:addToUIManager()
end

function Editor.addOptions(add, registry, entry)
    local layout = entry.piece.state and entry.piece.state.circuit
    local cabinet = entry.piece.definitionId == Circuit.CABINET_ID
    if (not cabinet and entry.piece.definitionId ~= ZedComm.RelayLamp.ID) or type(layout) ~= "table"
        or type(layout.modules) ~= "table" then return end
    add(cabinet and "Open Small Cabinet" or "Open Advanced Adapter", Editor.open, registry, entry)
    local ids = thresholdIds(layout)
    for i, id in ipairs(ids) do
        local name = #ids == 1 and "Set threshold" or ("Set threshold (" .. id .. ")")
        add(name, Editor.setThreshold, registry, entry, id)
    end
end

local function geometry(layout, cabinet, cell)
    local parts = Circuit.fixedParts(cabinet)
    for id, module in pairs(layout.modules) do parts[id] = module end
    for _, part in pairs(parts) do
        local width, height = Circuit.footprint(part.rotation, part.kind)
        part.x, part.y = gridX + (part.column - 1) * cell, gridY + (part.row - 1) * cell
        part.width, part.height = width * cell, height * cell
        part.cell = cell
    end
    return parts
end

local function terminalPosition(part, name)
    local cell = part.cell
    local x, y = Circuit.terminalPosition(part.rotation, name, part.kind)
    local px, py = part.x + x * cell, part.y + y * cell
    -- Keep contact hit targets on their own part, including adjacent parts.
    if x == 0 then px = px + 9 elseif x * cell == part.width then px = px - 9 end
    if y == 0 then py = py + 9 elseif y * cell == part.height then py = py - 9 end
    return px, py
end

local function inside(x, y, left, top, width, height)
    return x >= left and x < left + width and y >= top and y < top + height
end

function Editor:insideGrid(x, y)
    return inside(x, y, gridX, gridY, self.gridWidth, self.gridWidth)
end

local function contactAt(part, x, y)
    for name in pairs(Circuit.kinds[part.kind].ports) do
        local px, py = terminalPosition(part, name)
        if math.abs(px - x) <= 8 and math.abs(py - y) <= 8 then return name end
    end
end

function Editor:endDrag()
    if not self.drag then return end
    self.drag = nil
    self:setCapture(false)
end

function Editor:refresh()
    local entry = selectedHost(self.player, self.registry, self.target, true)
    local circuit = entry and entry.piece.state and entry.piece.state.circuit
    if not circuit then self:endDrag(); return false end
    self.jackLabels = entry.piece.state.portLabels
    self.reachable = ZedComm.PlayerPlacement.canReach(self.player, entry.square) and true or false
    if not self.reachable then self:endDrag() end
    if circuit ~= self.expected then
        local layout = readLayout(self.registry, self.target.id)
        self.adapter = self.cabinet and entry.piece.state.adapter or nil
        local evaluate = Circuit.compile(layout, self.cabinet, self.adapter)
        if not evaluate then return false end
        self.expected, self.layout, self.evaluate = circuit, layout, evaluate
        self.parts = geometry(readLayout(self.registry, self.target.id), self.cabinet, self.cell)
        self.terminal = nil
        self:endDrag()
        if not self.parts[self.selected] then self.selected = nil end
    end

    local inventory = self.player:getInventory():getItems()
    local carried = {}
    for _, kind in ipairs(self.moduleKinds) do
        carried[Circuit.kinds[kind].item] = { count = 0 }
    end
    for i = 0, inventory:size() - 1 do
        local item = inventory:get(i)
        local row = carried[item:getFullType()]
        if row then
            row.count = row.count + 1
            row.item = row.item or item
        end
    end
    self.carried = carried
    if not self.cabinet then
        local report = ZedComm.DeviceRuntime.inspect(self.target.id)
        self.input = report and report.sourceByte or nil
        self.output = ZedComm.DeviceRuntime.getCircuitOutput(self.target.id)
    end
    return true
end

-- Read-only from two tiles away: edits ask the player to step closer.
function Editor:inReach()
    if not self:refresh() then return false end
    if self.reachable then return true end
    self.terminal = nil
    self.message = reachMessage(self.cabinet)
    return false
end

function Editor:commit(layout, install, remove)
    local ok, reason = ZedComm.PlayerPlacement.editCircuit(self.player, self.registry, self.target,
        self.expected, layout, install, remove)
    self.message = reason
    if ok then self:refresh() end
    return ok
end

function Editor:beginDrag(id, item, grabX, grabY, kind)
    local layout = readLayout(self.registry, self.target.id)
    if item then
        local index = self.cabinet and (layout.nextModule or 1) or 1
        while layout.modules[kind .. "-" .. index] do index = index + 1 end
        id = kind .. "-" .. index
        if self.cabinet then layout.nextModule = index + 1 end
        local part = { kind = kind, rotation = Circuit.defaultRotation(kind),
            threshold = kind == "threshold" and 50 or nil }
        if Circuit.kinds[kind].source then part.level = item:getModData().zedcommSourceLevel end
        if kind == "batterySource" then part.charge = item:getModData().zedcommCharge end
        layout.modules[id] = part
    end
    self.drag = {
        id = id, item = item, layout = layout, part = layout.modules[id],
        grabX = grabX, grabY = grabY, rotation = layout.modules[id].rotation,
    }
    if not item then self.selected = id end
    self.terminal, self.message = nil, nil
    self:setCapture(true)
end

function Editor:isKeyConsumed(key)
    return self.drag ~= nil and getCore():isKey(KeybindId.ROTATE_BUILDING, key)
end

function Editor:onKeyPress(key)
    if not self:isKeyConsumed(key) or not self:inReach() or not self.drag then return end
    local drag = self.drag
    local _, height = Circuit.footprint(drag.rotation, drag.part.kind)
    drag.grabX, drag.grabY = height * self.cell - 1 - drag.grabY, drag.grabX
    drag.rotation = (drag.rotation + 90) % 360
end

-- Preview and drop use the same snapped position and circuit validation.
function Editor:previewAt(x, y)
    if not self:insideGrid(x, y) then return nil end
    local cell = self.cell
    local drag = self.drag
    local width, height = Circuit.footprint(drag.rotation, drag.part.kind)
    local column = math.floor((x - gridX - drag.grabX) / cell) + 1
    local row = math.floor((y - gridY - drag.grabY) / cell) + 1
    local part = drag.part
    if column ~= part.column or row ~= part.row or drag.rotation ~= part.rotation or not drag.preview then
        part.column, part.row, part.rotation = column, row, drag.rotation
        local evaluate, reason = Circuit.compile(drag.layout, self.cabinet, self.adapter)
        drag.preview = { valid = evaluate ~= nil, reason = reason,
            x = gridX + (column - 1) * cell, y = gridY + (row - 1) * cell,
            width = width * cell, height = height * cell }
    end
    return drag.preview
end

function Editor:dropAt(x, y)
    if not self:inReach() or not self.drag then return end
    local drag = self.drag
    local preview = self:previewAt(x, y)
    self:endDrag()
    if not preview then return end
    if not preview.valid then self.message = preview.reason; return end

    local previous = self.layout.modules[drag.id]
    local part = drag.part
    if previous and previous.column == part.column and previous.row == part.row
        and previous.rotation == part.rotation then return end
    if self:commit(drag.layout, drag.item) then self.selected = drag.id end
end

function Editor:removePart()
    if not self:inReach() or not self.selected then return end
    local layout = readLayout(self.registry, self.target.id)
    local id = self.selected
    local part = layout.modules[id]
    if not part then return end
    layout.modules[id] = nil
    if layout.outputModes then
        layout.outputModes[id] = nil
        for branch = 1, Circuit.kinds[part.kind].externalOutputs or 0 do
            layout.outputModes[Circuit.splitterPort(id, branch)] = nil
        end
    end
    for i = #layout.links, 1, -1 do
        local link = layout.links[i]
        if link.from == id or link.to == id then table.remove(layout.links, i) end
    end
    self:commit(layout, nil, true)
end

local function configurable(part, advanced)
    local spec = part and Circuit.kinds[part.kind]
    return spec and (part.kind == "threshold" or part.kind == "cache" or spec.timed or spec.source
        or (advanced and (spec.full ~= nil or spec.jack == "source")))
end

function Editor:toggleOutputMode(id)
    if not self:inReach() or self.adapter ~= "advanced" then return end
    local entry = selectedHost(self.player, self.registry, self.target)
    if not entry or entry.piece.board.directions[id] ~= "source" then return end
    local layout = readLayout(self.registry, self.target.id)
    layout.outputModes = layout.outputModes or {}
    local advanced = layout.outputModes[id] == nil
    layout.outputModes[id] = advanced and "advanced" or nil
    if self:commit(layout) then self.message = advanced and "Output: Advanced." or "Output: Basic." end
end

function Editor:configure()
    if not self:inReach() then return end
    local id, part = self.selected, self.parts[self.selected]
    if not configurable(part, self.adapter == "advanced") then return end
    if part.kind == "threshold" then
        Editor.setThreshold(self.player, self.registry, self.target, id)
        return
    end
    local spec = Circuit.kinds[part.kind]
    if spec.timed then
        setNumber(self.player, self.registry, self.target, id, "seconds", "Duration in seconds", spec.defaultSeconds)
        return
    elseif spec.source then
        setNumber(self.player, self.registry, self.target, id, "level", "Source byte (1 to 255)", 255)
        return
    elseif spec.jack == "source" then
        self:toggleOutputMode(id)
        return
    end
    local layout = readLayout(self.registry, self.target.id)
    local message
    if part.kind == "cache" then
        layout.modules[id].always = not part.always
        message = layout.modules[id].always and "Cache: Always." or "Cache: When enabled."
    else
        layout.modules[id].fullReading = not part.fullReading
        message = layout.modules[id].fullReading and "Mode: Full reading." or "Mode: Byte."
    end
    if self:commit(layout) then self.message = message end
end

function Editor:changeBattery()
    if not self:inReach() then return end
    local part = self.layout.modules[self.selected]
    if not part or part.kind ~= "batterySource" then return end
    local ok, reason = ZedComm.PlayerPlacement.changeCircuitBattery(self.player, self.registry,
        self.target, self.expected, self.selected)
    if ok then self:refresh() end
    self.message = reason
end

function Editor:autoConnect()
    if not self:inReach() then return end
    local layout = readLayout(self.registry, self.target.id)
    local id = onlyModule(layout)
    if not id then return end
    layout.links = { { from = id, output = "out", to = "output", input = "in" } }
    if Circuit.kinds[layout.modules[id].kind].ports["in"] then
        layout.links[#layout.links + 1] = { from = "input", output = "out", to = id, input = "in" }
    end
    self:commit(layout)
end

function Editor:linkTerminal(id, name)
    if not self:inReach() then return end
    local first = self.terminal
    local direction = Circuit.kinds[self.parts[id].kind].ports[name]
    if not first or first.direction == direction then
        self.terminal = { id = id, name = name, direction = direction }
        self.message = direction == "out" and "Choose an input contact." or "Choose an output contact."
        return
    end
    local from, to, output, input = first.id, id, first.name, name
    if direction == "out" then from, to, output, input = to, from, input, output end
    local layout = readLayout(self.registry, self.target.id)
    for i, link in ipairs(layout.links) do
        if link.from == from and link.to == to and link.output == output and link.input == input then
            table.remove(layout.links, i)
            self:commit(layout)
            return
        end
    end
    layout.links[#layout.links + 1] = { from = from, output = output, to = to, input = input }
    self:commit(layout)
end

function Editor:onMouseUp(x, y)
    if self.drag then self:dropAt(x, y); return true end
    if not self:refresh() then self:close(); return true end
    local gridPress = self.gridPress
    self.gridPress = nil
    if not self:insideGrid(x, y) then
        return ISPanel.onMouseUp(self, x, y)
    end
    self.moving = false
    ISMouseDrag.dragView = nil
    if not gridPress then return true end
    for id, part in pairs(self.parts) do
        if inside(x, y, part.x, part.y, part.width, part.height) then
            local name = contactAt(part, x, y)
            if name then self:linkTerminal(id, name); return true end
            self.selected = (Circuit.kinds[part.kind].item or configurable(part, self.adapter == "advanced")) and id or nil
            self.terminal, self.message = nil, nil
            return true
        end
    end
    self.selected, self.terminal, self.message = nil, nil, nil
    return true
end

function Editor:onMouseDown(x, y)
    if self.drag then return true end
    self.gridPress = nil
    for row = 1, paletteRows do
        local kind = self.moduleKinds[self.paletteOffset + row]
        if kind and inside(x, y, self.carriedX, carriedY + (row - 1) * carriedStep, carriedWidth, carriedHeight) then
            self:bringToTop()
            if self:inReach() then
                local item = self.carried[Circuit.kinds[kind].item].item
                if item then
                    local width, height = Circuit.footprint(Circuit.defaultRotation(kind), kind)
                    self:beginDrag(nil, item, width * self.cell / 2, height * self.cell / 2, kind)
                end
            end
            return true
        end
    end
    if self:insideGrid(x, y) then
        self:bringToTop()
        self.gridPress = true
        if self:inReach() then
            for id, part in pairs(self.parts) do
                if Circuit.kinds[part.kind].item and inside(x, y, part.x, part.y, part.width, part.height)
                    and not contactAt(part, x, y) then
                    self.gridPress = nil
                    self:beginDrag(id, nil, math.floor(x - part.x), math.floor(y - part.y))
                    break
                end
            end
        end
        return true
    end
    return ISPanel.onMouseDown(self, x, y)
end

function Editor:onMouseUpOutside(x, y)
    self.gridPress = nil
    self:endDrag()
    return ISPanel.onMouseUpOutside(self, x, y)
end

function Editor:onRightMouseUpOutside()
    self:endDrag()
end

local function editPart(editor, id, action)
    editor.selected = id
    action(editor)
end

function Editor:onRightMouseUp(x, y)
    if not self:refresh() then self:close(); return true end
    if self.drag or self.terminal then
        self:endDrag()
        self.gridPress, self.terminal, self.message = nil, nil, nil
        return true
    end
    for id, part in pairs(self.parts) do
        if inside(x, y, part.x, part.y, part.width, part.height) then
            local spec = Circuit.kinds[part.kind]
            local canRename = self.cabinet and spec.jack
            local canConfigure = configurable(part, self.adapter == "advanced")
            local canRemove = self.layout.modules[id] ~= nil
            if not (canRename or canConfigure or canRemove) or not self:inReach() then return true end

            local context = ISContextMenu.get(self.player:getPlayerNum(), getMouseX(), getMouseY())
            if canRename then
                context:addOption("Rename jack", self.player, Editor.renameJack, self.registry, self.target, id)
            end
            for branch = 1, spec.externalOutputs or 0 do
                local port = Circuit.splitterPort(id, branch)
                local label = Circuit.jackLabel(port, "source")
                context:addOption("Rename " .. label, self.player, Editor.renameJack, self.registry, self.target, port)
                if self.adapter == "advanced" then
                    local advanced = self.layout.outputModes and self.layout.outputModes[port] == "advanced"
                    context:addOption("Set " .. label .. " to " .. (advanced and "Basic" or "Advanced"),
                        self, self.toggleOutputMode, port)
                end
            end
            if canConfigure then
                context:addOption("Configure", self, editPart, id, self.configure)
            end
            if canRemove then
                context:addOption("Remove module", self, editPart, id, self.removePart)
            end
            return true
        end
    end
    return true
end

-- Blue = output contact, green = input contact, red = the contact picked for a link.
local function contactColor(name, active)
    if active then return 0.95, 0.25, 0.25 end
    if name == "out" then return 0.52, 0.71, 0.93 end
    return 0.52, 0.71, 0.35
end
local LEGEND = { { "out", "Output contact" }, { "in", "Input contact" }, { "selected", "Selected contact" } }

local function drawPart(panel, kind, rotation, x, y, width, height, alpha)
    local name = "ZedCommCircuit_" .. kind .. "_" .. rotation
    local texture = textures[name]
    if texture == nil then
        texture = getTexture(textureFolder .. name .. ".png") or false
        textures[name] = texture
    end
    alpha = alpha or 1
    panel:drawRect(x, y, width, height, alpha, 0.18, 0.25, 0.19)
    if texture then panel:drawTextureScaled(texture, x, y, width, height, alpha, 1, 1, 1) end
end

local function drawJack(panel, part, branch)
    local jackX, jackY = Circuit.jackAt(part, branch)
    local x = part.x + math.max(4, math.min(part.width - 4, jackX * part.cell))
    local y = part.y + math.max(4, math.min(part.height - 4, jackY * part.cell))
    panel:drawRect(x - 3, y - 3, 6, 6, 1, 0.84, 0.66, 0.29)
    return x, y
end

function Editor:render()
    if not self:refresh() then self:close(); return end
    local cell = self.cell
    local title = self.cabinet and (self.adapter == "advanced" and "Advanced Small Cabinet" or "Basic Small Cabinet")
        or "Advanced Adapter"
    self:drawText(title, 16, 10, 1, 1, 1, 1, UIFont.Medium)
    if not self.cabinet then
        self:drawText("Wire in  " .. tostring(self.input or "--"), 16, 41, 0.85, 0.90, 0.85, 1, UIFont.Small)
        self:drawText("Lamp out  " .. tostring(self.output or "--"), 134, 41, 0.85, 0.90, 0.85, 1, UIFont.Small)
    end
    for row = 0, self.gridSize - 1 do
        for column = 0, self.gridSize - 1 do
            self:drawRectBorder(gridX + column * cell, gridY + row * cell, cell, cell, 0.8, 0.34, 0.43, 0.35)
        end
    end
    local hoveredJack
    for id, part in pairs(self.parts) do
        drawPart(self, part.kind, part.rotation, part.x + 2, part.y + 2, part.width - 4, part.height - 4)
        if id == self.selected then
            self:drawRectBorder(part.x + 1, part.y + 1, part.width - 2, part.height - 2, 1, 0.91, 0.76, 0.41)
        end
        local spec = Circuit.kinds[part.kind]
        local label = part.kind == "threshold" and ("THR " .. part.threshold) or spec.label
            or (id == "input" and "Fixed IN" or "Fixed OUT")
        if spec.source then label = part.kind == "batterySource" and "Battery" or "Mains" end
        if self.cabinet and spec.jack then
            label = Circuit.jackLabel(id, spec.jack)
            local report = ZedComm.DeviceRuntime.inspect(self.target.id, id)
            local reading = report and report.sourceByte or "--"
            if spec.jack == "source" and self.layout.outputModes and self.layout.outputModes[id] then
                reading = "Adv " .. reading
            end
            self:drawTextCentre(tostring(reading), part.x + part.width / 2,
                part.y + 25, 1, 1, 0.91, 1, UIFont.Small)
            local custom = self.jackLabels and self.jackLabels[id]
            if custom then
                self:setStencilRect(part.x + 6, part.y + 41, part.width - 12, 17)
                self:drawText(custom, part.x + 6, part.y + 41, 0.85, 0.90, 0.85, 1, UIFont.Small)
                self:clearStencilRect()
                if inside(self:getMouseX(), self:getMouseY(), part.x, part.y, part.width, part.height) then
                    hoveredJack = Circuit.jackLabel(id, spec.jack, custom)
                end
            end
            drawJack(self, part)
        end
        for branch = 1, spec.externalOutputs or 0 do
            local x, y = drawJack(self, part, branch)
            if math.abs(self:getMouseX() - x) <= 8 and math.abs(self:getMouseY() - y) <= 8 then
                local port = Circuit.splitterPort(id, branch)
                hoveredJack = Circuit.jackLabel(port, "source", self.jackLabels and self.jackLabels[port])
            end
        end
        self:drawRect(part.x + 5, part.y + 5, part.width - 10, 18, 0.85, 0.08, 0.11, 0.08)
        self:drawTextCentre(label, part.x + part.width / 2, part.y + 6, 1, 1, 0.91, 1, UIFont.Small)
        if spec.full or part.kind == "cache" then
            local mode = spec.full and (part.fullReading and "Full" or "Byte")
                or (part.always and "Always" or "Enabled")
            self:drawTextCentre(mode, part.x + part.width / 2, part.y + 25, 1, 1, 0.91, 1, UIFont.Small)
        elseif spec.timed or spec.source then
            local setting = spec.timed and (tostring(part.seconds or spec.defaultSeconds) .. "s")
                or tostring(part.level or 255)
            self:drawTextCentre(setting, part.x + part.width / 2, part.y + 25, 1, 1, 0.91, 1, UIFont.Small)
            if part.kind == "batterySource" then
                self:drawTextCentre(part.charge and "Battery in" or "Empty",
                    part.x + part.width / 2, part.y + 39, 1, 1, 0.91, 1, UIFont.Small)
            end
        end
    end
    for _, link in ipairs(self.layout.links) do
        local x1, y1 = terminalPosition(self.parts[link.from], link.output)
        local x2, y2 = terminalPosition(self.parts[link.to], link.input)
        local mid = (x1 + x2) / 2
        self:drawRect(math.min(x1, mid), y1 - 1, math.abs(mid - x1) + 1, 2, 1, 0.48, 0.86, 0.65)
        self:drawRect(mid - 1, math.min(y1, y2), 2, math.abs(y2 - y1) + 1, 1, 0.48, 0.86, 0.65)
        self:drawRect(math.min(mid, x2), y2 - 1, math.abs(x2 - mid) + 1, 2, 1, 0.48, 0.86, 0.65)
    end
    for id, part in pairs(self.parts) do
        for name, direction in pairs(Circuit.kinds[part.kind].ports) do
            local x, y = terminalPosition(part, name)
            local active = self.terminal and self.terminal.id == id and self.terminal.name == name
            local r, g, b = contactColor(direction, active)
            self:drawRect(x - 6, y - 6, 12, 12, 1, r, g, b)
            if self.cabinet and name ~= "in" and name ~= "out" then
                local label = ({ a = part.kind == "multiplier" and "Reading" or "A",
                    b = part.kind == "multiplier" and "Factor" or "B", data = "Data", enable = "Enable",
                    outA = "Out A", outB = "Out B" })[name]
                if label and self:getMouseX() >= x - 8 and self:getMouseX() <= x + 8
                    and self:getMouseY() >= y - 8 and self:getMouseY() <= y + 8 then
                    self:drawText(label, x + 8, y - 5, 1, 1, 1, 1, UIFont.Small)
                end
            end
        end
    end

    local drag = self.drag
    local hint = self.reachable and "Drag modules or select two contacts to link." or reachMessage(self.cabinet)
    if drag then
        local preview = self:previewAt(self:getMouseX(), self:getMouseY())
        if preview then
            self:setStencilRect(gridX, gridY, self.gridWidth, self.gridWidth)
            local x, y, w, h = preview.x + 2, preview.y + 2, preview.width - 4, preview.height - 4
            drawPart(self, drag.part.kind, drag.rotation, x, y, w, h, 0.78)
            if preview.valid then
                self:drawRectBorder(x, y, w, h, 1, 0.45, 0.91, 0.55)
            else
                self:drawRectBorder(x, y, w, h, 1, 0.95, 0.25, 0.25)
            end
            self:clearStencilRect()
        end
        local rotateKey = Keyboard.getKeyName(getCore():getKey(KeybindId.ROTATE_BUILDING))
        hint = rotateKey .. " to rotate. Right-click to cancel."
    end

    local carriedX = self.carriedX
    self:drawText("Carried modules", carriedX, 44, 1, 1, 1, 1, UIFont.Small)
    for row = 1, paletteRows do
        local kind = self.moduleKinds[self.paletteOffset + row]
        if not kind then break end
        local y = carriedY + (row - 1) * carriedStep
        local spec = Circuit.kinds[kind]
        self:drawRectBorder(carriedX, y, carriedWidth, carriedHeight, 0.8, 0.34, 0.43, 0.35)
        self:drawText(spec.label .. "  x" .. self.carried[spec.item].count,
            carriedX + 23, y + 7, 0.91, 0.93, 0.86, 1, UIFont.Small)
        drawPart(self, kind, Circuit.defaultRotation(kind), carriedX + 3, y + 2, 13, carriedHeight - 4)
    end
    -- Legend for the contact squares.
    for i, row in ipairs(LEGEND) do
        local y = self.legendY + (i - 1) * 15
        local r, g, b = contactColor(row[1], row[1] == "selected")
        self:drawRect(carriedX + 4, y + 2, 10, 10, 1, r, g, b)
        self:drawText(row[2], carriedX + 20, y, 0.85, 0.90, 0.85, 1, UIFont.Small)
    end
    self:drawText((self.reachable and self.message) or hoveredJack or hint, 16, gridY + self.gridWidth + 16,
        0.90, 0.90, 0.80, 1, UIFont.Small)
    local reach = self.reachable and not drag
    local selected = self.layout.modules[self.selected]
    self.removeButton:setEnable(reach and selected ~= nil)
    self.configureButton:setEnable(reach and configurable(self.parts[self.selected], self.adapter == "advanced") == true)
    self.batteryButton:setEnable(reach and selected ~= nil and selected.kind == "batterySource")
    if self.autoButton then self.autoButton:setEnable(reach and onlyModule(self.layout) ~= nil) end
    if self.nextPage then
        self.previousPage:setEnable(not drag and self.paletteOffset > 0)
        self.nextPage:setEnable(not drag and self.paletteOffset + paletteRows < #self.moduleKinds)
    end
end

function Editor:createChildren()
    local function button(x, y, width, title, action)
        local widget = ISButton:new(x, y, width, 23, title, self, action)
        widget:initialise()
        self:addChild(widget)
        return widget
    end
    local x = self.carriedX + 2
    local controlsY = carriedY + math.min(paletteRows, #self.moduleKinds) * carriedStep
    button(x + 109, 9, 54, "Close", self.close)
    if not self.cabinet then
        self.autoButton = button(x, controlsY, 162, "Auto-connect", self.autoConnect)
        controlsY = controlsY + 31
    end
    self.removeButton = button(x, controlsY, 78, "Remove", self.removePart)
    self.configureButton = button(x + 84, controlsY, 78, "Configure", self.configure)
    if #self.moduleKinds > paletteRows then
        self.previousPage = button(x, controlsY + 28, 78, "Previous", function(editor)
            if not editor.drag then editor.paletteOffset = math.max(0, editor.paletteOffset - paletteRows) end
        end)
        self.nextPage = button(x + 84, controlsY + 28, 78, "Next", function(editor)
            if not editor.drag and editor.paletteOffset + paletteRows < #editor.moduleKinds then
                editor.paletteOffset = editor.paletteOffset + paletteRows
            end
        end)
    end
    self.batteryButton = button(x, controlsY + (#self.moduleKinds > paletteRows and 56 or 28), 162,
        "Insert or remove battery", self.changeBattery)
end

function Editor:close()
    self:endDrag()
    self:setVisible(false)
    self:removeFromUIManager()
    if panels[self.player] == self then panels[self.player] = nil end
end

function Editor.open(player, registry, target)
    local entry = selectedHost(player, registry, target, true)
    local cabinet = entry and entry.piece.definitionId == Circuit.CABINET_ID
    local adapter = cabinet and entry.piece.state.adapter or nil
    if not entry or not entry.piece.state or not Circuit.compile(entry.piece.state.circuit, cabinet, adapter) then
        player:Say("Choose a nearby Small Cabinet or lamp with an Advanced Adapter.")
        return
    end
    if panels[player] then panels[player]:close() end
    local cell, gridSize = cabinet and 60 or 78, Circuit.size(cabinet)
    local gridWidth = gridSize * cell
    local moduleKinds = cabinet and Circuit.moduleOrder or Circuit.adapterModules
    local controlsY = carriedY + math.min(paletteRows, #moduleKinds) * carriedStep
    local legendY = math.max(cabinet and 375 or 266,
        controlsY + (not cabinet and 88 or (#moduleKinds > paletteRows and 83 or 55)))
    local width, height = gridWidth + 218, math.max(gridWidth + 111, legendY + 50)
    local panel = ISPanel.new(Editor, math.max(0, (getCore():getScreenWidth() - width) / 2),
        math.max(0, (getCore():getScreenHeight() - height) / 2), width, height)
    panel.player, panel.registry, panel.target = player, registry, target
    panel.cabinet, panel.cell, panel.gridSize, panel.gridWidth = cabinet, cell, gridSize, gridWidth
    panel.carriedX = gridX + gridWidth + 22
    panel.moduleKinds, panel.paletteOffset, panel.legendY = moduleKinds, 0, legendY
    panel.moveWithMouse = true
    panel:setWantKeyEvents(true)
    panel.backgroundColor = { r = 0.09, g = 0.13, b = 0.10, a = 1 }
    panel:initialise()
    panel:addToUIManager()
    panels[player] = panel
end

ZedComm = ZedComm or {}
ZedComm.AdapterEditor = Editor
