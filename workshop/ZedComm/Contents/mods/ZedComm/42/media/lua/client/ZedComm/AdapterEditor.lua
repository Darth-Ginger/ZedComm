-- Singleplayer editor for fixture boards and Small Cabinets.
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
local paletteGroups = {
    { name = "Connections", kinds = { "inputExtension", "outputExtension", "splitter", "cache" } },
    { name = "Logic", kinds = { "threshold", "and", "or", "xor", "not" } },
    { name = "Arithmetic", kinds = { "adder", "subtractor", "multiplier" } },
    { name = "Timing", kinds = { "timer", "wait" } },
    { name = "Power", kinds = { "mainsSource", "batterySource" } },
}
local kindByItem = {}
for kind, spec in pairs(Circuit.kinds) do
    if spec.item then kindByItem[spec.item] = kind end
end
local textureFolder = "media/textures/"
local textures = {}
local panels = {}

local function reachMessage(cabinet)
    return "Step next to the " .. (cabinet == "door" and "door" or cabinet and "cabinet" or "lamp") .. " to make changes."
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
    local cabinet = Circuit.profileFor(entry.piece.definitionId)
    if (not cabinet and entry.piece.definitionId ~= ZedComm.RelayLamp.ID) or type(layout) ~= "table"
        or type(layout.modules) ~= "table" then return end
    add(cabinet == "door" and "Open Door Board" or cabinet and "Open Small Cabinet" or "Open Advanced Adapter", Editor.open, registry, entry)
    local ids = thresholdIds(layout)
    for i, id in ipairs(ids) do
        local name = #ids == 1 and "Set threshold" or ("Set threshold (" .. id .. ")")
        add(name, Editor.setThreshold, registry, entry, id)
    end
end

local function geometry(layout, cabinet, cell)
    local parts = Circuit.fixedParts(cabinet)
    for id, module in pairs(layout.modules) do
        local part = {}
        for field, value in pairs(module) do part[field] = value end
        parts[id] = part
    end
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

local function linkPoints(parts, link)
    local x1, y1 = terminalPosition(parts[link.from], link.output)
    local x2, y2 = terminalPosition(parts[link.to], link.input)
    return x1, y1, x2, y2, (x1 + x2) / 2
end

local function segmentDistanceSquared(x, y, x1, y1, x2, y2)
    local dx = math.max(math.min(x1, x2) - x, x - math.max(x1, x2), 0)
    local dy = math.max(math.min(y1, y2) - y, y - math.max(y1, y2), 0)
    return dx * dx + dy * dy
end

local function nearestLink(parts, links, x, y)
    local hit, tied
    local closest = 5 * 5
    for i, link in ipairs(links) do
        local x1, y1, x2, y2, mid = linkPoints(parts, link)
        local distance = math.min(segmentDistanceSquared(x, y, x1, y1, mid, y1),
            segmentDistanceSquared(x, y, mid, y1, mid, y2), segmentDistanceSquared(x, y, mid, y2, x2, y2))
        if distance <= closest then
            tied = distance == closest and hit ~= nil
            hit, closest = i, distance
        end
    end
    return hit, tied
end

local function inside(x, y, left, top, width, height)
    return x >= left and x < left + width and y >= top and y < top + height
end

local function partAt(parts, x, y)
    for id, part in pairs(parts) do
        if inside(x, y, part.x, part.y, part.width, part.height) then return id, part end
    end
end

function Editor:insideGrid(x, y)
    return inside(x, y, gridX, gridY, self.gridWidth, self.gridHeight)
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
    self.fixtureName = entry.piece.state.fixtureName
    self.reachable = ZedComm.PlayerPlacement.canReach(self.player, entry.square) and true or false
    self.readOnly = self.cabinet == "door" and entry.piece.state.adapter ~= "advanced"
    if not self.reachable then self:endDrag() end
    if circuit ~= self.expected then
        local layout = readLayout(self.registry, self.target.id)
        self.adapter = self.cabinet and entry.piece.state.adapter or nil
        if not Circuit.compile(layout, self.cabinet, self.adapter) then return false end
        self.expected, self.layout = circuit, layout
        self.parts = geometry(layout, self.cabinet, self.cell)
        self.terminal = nil
        self:endDrag()
        if not self.parts[self.selected] then self.selected = nil end
    end

    local inventory = self.player:getInventory():getItems()
    local carried = {}
    for i = 0, inventory:size() - 1 do
        local item = inventory:get(i)
        local kind = kindByItem[item:getFullType()]
        if kind and not self.readOnly and Circuit.moduleAllowed(kind, self.cabinet) then
            local row = carried[kind]
            if row then
                row.count = row.count + 1
            else
                carried[kind] = { kind = kind, item = item, count = 1 }
            end
        end
    end
    local entries = {}
    for _, group in ipairs(paletteGroups) do
        local header
        for _, kind in ipairs(group.kinds) do
            local row = carried[kind]
            if row then
                if not header then
                    header = { group = group.name, count = 0 }
                    entries[#entries + 1] = header
                end
                header.count = header.count + row.count
                if not self.collapsed[group.name] then entries[#entries + 1] = row end
            end
        end
    end
    self.paletteEntries = entries
    self.paletteOffset = math.min(self.paletteOffset, math.max(0, #entries - paletteRows))
    if not self.cabinet then
        local report = ZedComm.DeviceRuntime.inspect(self.target.id)
        self.input = report and report.sourceByte or nil
        self.output = ZedComm.DeviceRuntime.getCircuitOutput(self.target.id)
    end
    return true
end

function Editor:inReach()
    if not self:refresh() then return false end
    if self.readOnly then self.message = "Door logic requires two Advanced Adapters."; return false end
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
    return spec and not part.action and (part.kind == "threshold" or part.kind == "cache" or spec.timed or spec.source
        or (advanced and (spec.full ~= nil or spec.jack == "source" or spec.externalOutputs ~= nil)))
end

local function addSplitterOptions(panel, context, id, branchCount)
    for branch = 1, branchCount do
        local port = Circuit.splitterPort(id, branch)
        local label = Circuit.jackLabel(port, "source")
        context:addOption("Rename " .. label, panel.player, Editor.renameJack, panel.registry, panel.target, port)
        if panel.adapter == "advanced" then
            local advanced = panel.layout.outputModes and panel.layout.outputModes[port] == "advanced"
            context:addOption("Set " .. label .. " to " .. (advanced and "Basic" or "Advanced"),
                panel, panel.toggleOutputMode, port)
        end
    end
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
    if spec.externalOutputs then
        local context = ISContextMenu.get(self.player:getPlayerNum(), getMouseX(), getMouseY())
        addSplitterOptions(self, context, id, spec.externalOutputs)
        return
    elseif spec.timed then
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
    local id, part = partAt(self.parts, x, y)
    local name = part and contactAt(part, x, y)
    if name then
        self:linkTerminal(id, name)
        return true
    end
    local selectable = part and (Circuit.kinds[part.kind].item or configurable(part, self.adapter == "advanced"))
    self.selected, self.terminal, self.message = selectable and id or nil, nil, nil
    return true
end

function Editor:onMouseDown(x, y)
    if self.drag then return true end
    self.gridPress = nil
    if inside(x, y, self.carriedX, carriedY, carriedWidth, paletteRows * carriedStep) then
        if not self:refresh() then return true end
        self:bringToTop()
        local row = math.floor((y - carriedY) / carriedStep) + 1
        local entry = self.paletteEntries[self.paletteOffset + row]
        if not entry or (y - carriedY) % carriedStep >= carriedHeight then return true end
        if entry.group then
            self.collapsed[entry.group] = not self.collapsed[entry.group]
        elseif self:inReach() then
            local kind = entry.kind
            local width, height = Circuit.footprint(Circuit.defaultRotation(kind), kind)
            self:beginDrag(nil, entry.item, width * self.cell / 2, height * self.cell / 2, kind)
        end
        return true
    end
    if self:insideGrid(x, y) then
        self:bringToTop()
        self.gridPress = true
        if self:inReach() then
            local id, part = partAt(self.parts, x, y)
            if part and Circuit.kinds[part.kind].item and not contactAt(part, x, y) then
                self.gridPress = nil
                self:beginDrag(id, nil, math.floor(x - part.x), math.floor(y - part.y))
            end
        end
        return true
    end
    return ISPanel.onMouseDown(self, x, y)
end

function Editor:onMouseWheel(delta)
    if self.drag or not inside(self:getMouseX(), self:getMouseY(),
        self.carriedX, carriedY, carriedWidth, paletteRows * carriedStep) then return false end
    if not self:refresh() then return false end
    self.paletteOffset = math.max(0, math.min(self.paletteOffset + delta, #self.paletteEntries - paletteRows))
    return true
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
    if self.drag then
        self:endDrag()
        self.gridPress, self.terminal, self.message = nil, nil, nil
        return true
    end
    local selectingContact = self.terminal ~= nil
    if selectingContact then self.gridPress, self.terminal, self.message = nil, nil, nil end
    local id, part = partAt(self.parts, x, y)
    if not selectingContact and self:insideGrid(x, y) and not (part and contactAt(part, x, y)) then
        local link, tied = nearestLink(self.parts, self.layout.links, x, y)
        if link then
            if self:inReach() then
                if tied then
                    self.message = "Right-click a section where the links separate."
                else
                    local layout = readLayout(self.registry, self.target.id)
                    table.remove(layout.links, link)
                    self:commit(layout)
                end
            end
            return true
        end
    end
    if part then
        local spec = Circuit.kinds[part.kind]
        local canRename = self.cabinet and spec.jack and not part.action
        local canConfigure = configurable(part, self.adapter == "advanced")
        local canRemove = self.layout.modules[id] ~= nil
        if not (canRename or canConfigure or canRemove) or not self:inReach() then return true end

        local context = ISContextMenu.get(self.player:getPlayerNum(), getMouseX(), getMouseY())
        if canRename then
            context:addOption("Rename jack", self.player, Editor.renameJack, self.registry, self.target, id)
        end
        if spec.externalOutputs then
            addSplitterOptions(self, context, id, spec.externalOutputs)
        elseif canConfigure then
            context:addOption("Configure", self, editPart, id, self.configure)
        end
        if canRemove then
            context:addOption("Remove module", self, editPart, id, self.removePart)
        end
    end
    return true
end

local function contactColor(name, active)
    if active then return 0.95, 0.25, 0.25 end
    if name == "out" then return 0.52, 0.71, 0.93 end
    return 0.52, 0.71, 0.35
end
local LEGEND = { { "out", "Output contact" }, { "in", "Input contact" }, { "selected", "Selected contact" } }
local contactLabels = { a = "A", b = "B", data = "Data", enable = "Enable" }
local multiplierLabels = { a = "Reading", b = "Factor" }

local function drawContact(panel, part, name, direction, active)
    local x, y = terminalPosition(part, name)
    local r, g, b = contactColor(direction, active)
    panel:drawRect(x - 6, y - 6, 12, 12, 1, r, g, b)
    return x, y
end

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

local function jackReading(panel, id)
    local report = ZedComm.DeviceRuntime.inspect(panel.target.id, id)
    local packet = report and report.sourcePacket
    local byte = report and report.sourceByte
    if panel.adapter == "advanced" and packet and packet.type == "signal.advanced" then
        local value = packet.value
        local amount = tostring(value.amount)
        local exact = amount .. " " .. value.unit
        local compact = #amount <= 5 and amount or tostring(math.floor(value.amount + 0.5))
        local face = #compact <= 5 and compact .. " " .. value.unit or "Weight"
        return face, exact .. (byte ~= nil and (" (byte " .. byte .. ")") or "")
    end
    if byte ~= nil then return tostring(byte), "byte " .. byte end
    return "--", "No signal"
end

function Editor:render()
    if not self:refresh() then self:close(); return end
    local cell = self.cell
    local mouseX, mouseY = self:getMouseX(), self:getMouseY()
    local title = self.cabinet == "door" and (self.adapter == "advanced" and "Advanced Door Board" or "Basic Door Board")
        or self.cabinet and (self.adapter == "advanced" and "Advanced Small Cabinet" or "Basic Small Cabinet")
        or "Advanced Adapter"
    self:setStencilRect(16, 8, self.carriedX + 100, 23)
    self:drawText(self.fixtureName and (title .. " (" .. self.fixtureName .. ")") or title,
        16, 10, 1, 1, 1, 1, UIFont.Medium)
    self:clearStencilRect()
    if not self.cabinet then
        self:drawText("Wire in  " .. tostring(self.input or "--"), 16, 41, 0.85, 0.90, 0.85, 1, UIFont.Small)
        self:drawText("Lamp out  " .. tostring(self.output or "--"), 134, 41, 0.85, 0.90, 0.85, 1, UIFont.Small)
    elseif self.cabinet == "door" then
        local state = ZedComm.DeviceRuntime.getDoorState(self.target.id)
        if state then
            self:drawText((state.open and "Open" or "Closed") .. " | " .. (state.locked and "Locked" or "Unlocked"),
                16, 41, 0.85, 0.90, 0.85, 1, UIFont.Small)
        end
    end
    for row = 0, self.gridRows - 1 do
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
        local label = part.label or (part.kind == "threshold" and ("THR " .. part.threshold)) or spec.label
            or (id == "input" and "Fixed IN" or "Fixed OUT")
        local labelY = part.label and part.height < part.width and 25 or 6
        if spec.source then label = part.kind == "batterySource" and "Battery" or "Mains" end
        if self.cabinet and spec.jack and not part.action then
            label = Circuit.jackLabel(id, spec.jack)
            local advanced = self.layout.outputModes and self.layout.outputModes[id] == "advanced"
            if advanced then label = label .. " Adv" end
            local reading, detail = jackReading(self, id)
            self:drawTextCentre(reading, part.x + part.width / 2,
                part.y + (labelY == 25 and 41 or 25), 1, 1, 0.91, 1, UIFont.Small)
            local custom = self.jackLabels and self.jackLabels[id]
            if custom and part.height >= part.width then
                self:setStencilRect(part.x + 6, part.y + 41, part.width - 12, 17)
                self:drawText(custom, part.x + 6, part.y + 41, 0.85, 0.90, 0.85, 1, UIFont.Small)
                self:clearStencilRect()
            end
            if inside(mouseX, mouseY, part.x, part.y, part.width, part.height) then
                hoveredJack = Circuit.jackLabel(id, spec.jack, custom)
                    .. (advanced and " [Advanced]" or "") .. " | " .. detail
            end
            drawJack(self, part)
        end
        if part.action and inside(mouseX, mouseY, part.x, part.y, part.width, part.height) then
            local state = ZedComm.DeviceRuntime.getDoorState(self.target.id)
            local result = state and state.actions[id]
            hoveredJack = part.label .. " | " .. (result and (result.reason or result.status) or "Manual control")
        end
        for branch = 1, spec.externalOutputs or 0 do
            local x, y = drawJack(self, part, branch)
            if math.abs(mouseX - x) <= 8 and math.abs(mouseY - y) <= 8 then
                local port = Circuit.splitterPort(id, branch)
                local _, detail = jackReading(self, port)
                local advanced = self.layout.outputModes and self.layout.outputModes[port] == "advanced"
                hoveredJack = Circuit.jackLabel(port, "source", self.jackLabels and self.jackLabels[port])
                    .. (advanced and " [Advanced]" or "") .. " | " .. detail
            end
        end
        self:drawRect(part.x + 5, part.y + labelY - 1, part.width - 10, 18, 0.85, 0.08, 0.11, 0.08)
        local textX = part.x + part.width / 2
        if spec.timed and part.width > part.height then textX = part.x + part.width / 4 end
        self:drawTextCentre(label, textX, part.y + labelY, 1, 1, 0.91, 1, UIFont.Small)
        if spec.full or part.kind == "cache" then
            local mode = spec.full and (part.fullReading and "Full" or "Byte")
                or (part.always and "Always" or "Enabled")
            self:drawTextCentre(mode, part.x + part.width / 2, part.y + 25, 1, 1, 0.91, 1, UIFont.Small)
        elseif spec.timed or spec.source then
            local setting = spec.timed and (tostring(part.seconds or spec.defaultSeconds) .. "s")
                or tostring(part.level or 255)
            self:drawTextCentre(setting, textX, part.y + 25, 1, 1, 0.91, 1, UIFont.Small)
            if spec.timed then
                local remaining = ZedComm.DeviceRuntime.getTimingRemaining(self.target.id, id)
                if remaining then
                    local seconds = math.ceil(remaining * 10) / 10
                    self:drawTextCentre(string.format("%.1fs", seconds), textX, part.y + 39,
                        1, 0.79, 0.42, 1, UIFont.Small)
                end
            elseif part.kind == "batterySource" then
                self:drawTextCentre(part.charge and "Battery in" or "Empty",
                    part.x + part.width / 2, part.y + 39, 1, 1, 0.91, 1, UIFont.Small)
            end
        end
    end
    for _, link in ipairs(self.layout.links) do
        local x1, y1, x2, y2, mid = linkPoints(self.parts, link)
        self:drawRect(math.min(x1, mid), y1 - 1, math.abs(mid - x1) + 1, 2, 1, 0.48, 0.86, 0.65)
        self:drawRect(mid - 1, math.min(y1, y2), 2, math.abs(y2 - y1) + 1, 1, 0.48, 0.86, 0.65)
        self:drawRect(math.min(mid, x2), y2 - 1, math.abs(x2 - mid) + 1, 2, 1, 0.48, 0.86, 0.65)
    end
    for id, part in pairs(self.parts) do
        local labels = part.kind == "multiplier" and multiplierLabels or contactLabels
        for name, direction in pairs(Circuit.kinds[part.kind].ports) do
            local active = self.terminal and self.terminal.id == id and self.terminal.name == name
            local x, y = drawContact(self, part, name, direction, active)
            local label = self.cabinet and labels[name]
            if label and math.abs(mouseX - x) <= 8 and math.abs(mouseY - y) <= 8 then
                hoveredJack = Circuit.kinds[part.kind].label .. " | " .. label
            end
        end
    end

    local drag = self.drag
    local hint = self.readOnly and "Basic Door has fixed Lock and Open paths."
        or self.reachable and "Drag modules or select two contacts to link." or reachMessage(self.cabinet)
    if drag then
        local preview = self:previewAt(mouseX, mouseY)
        if preview then
            self:setStencilRect(gridX, gridY, self.gridWidth, self.gridHeight)
            local x, y, w, h = preview.x + 2, preview.y + 2, preview.width - 4, preview.height - 4
            drawPart(self, drag.part.kind, drag.rotation, x, y, w, h, 0.78)
            local part = { kind = drag.part.kind, rotation = drag.rotation, cell = cell,
                x = preview.x, y = preview.y, width = preview.width, height = preview.height }
            local spec = Circuit.kinds[part.kind]
            self:drawTextCentre(spec.label, x + w / 2, y + 5, 1, 1, 1, 1, UIFont.Small)
            for name, direction in pairs(spec.ports) do
                drawContact(self, part, name, direction)
            end
            if spec.jack then drawJack(self, part) end
            for branch = 1, spec.externalOutputs or 0 do drawJack(self, part, branch) end
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
        local entry = self.paletteEntries[self.paletteOffset + row]
        if not entry then break end
        local y = carriedY + (row - 1) * carriedStep
        if entry.group then
            local marker = self.collapsed[entry.group] and "+ " or "- "
            self:drawRect(carriedX, y, carriedWidth, carriedHeight, 0.9, 0.16, 0.23, 0.18)
            self:drawText(marker .. entry.group .. " (" .. entry.count .. ")",
                carriedX + 8, y + 7, 0.91, 0.93, 0.86, 1, UIFont.Small)
        else
            local spec = Circuit.kinds[entry.kind]
            self:drawRectBorder(carriedX + 8, y, carriedWidth - 8, carriedHeight, 0.8, 0.34, 0.43, 0.35)
            self:drawText(spec.label .. "  x" .. entry.count,
                carriedX + 27, y + 7, 0.91, 0.93, 0.86, 1, UIFont.Small)
            drawPart(self, entry.kind, Circuit.defaultRotation(entry.kind), carriedX + 11, y + 2, 13, carriedHeight - 4)
        end
    end
    if #self.paletteEntries > paletteRows then
        self:drawText("Scroll for more", carriedX + 83, 44, 0.75, 0.81, 0.74, 1, UIFont.Small)
    end
    for i, row in ipairs(LEGEND) do
        local y = self.legendY + (i - 1) * 15
        local r, g, b = contactColor(row[1], row[1] == "selected")
        self:drawRect(carriedX + 4, y + 2, 10, 10, 1, r, g, b)
        self:drawText(row[2], carriedX + 20, y, 0.85, 0.90, 0.85, 1, UIFont.Small)
    end
    self:drawText((not drag and hoveredJack) or (self.reachable and self.message) or hint, 16, gridY + self.gridHeight + 16,
        0.90, 0.90, 0.80, 1, UIFont.Small)
    local reach = self.reachable and not drag
    local selected = self.layout.modules[self.selected]
    self.removeButton:setEnable(reach and selected ~= nil)
    self.configureButton:setEnable(reach and configurable(self.parts[self.selected], self.adapter == "advanced") == true)
    self.batteryButton:setEnable(reach and selected ~= nil and selected.kind == "batterySource")
    if self.autoButton then self.autoButton:setEnable(reach and onlyModule(self.layout) ~= nil) end
end

function Editor:createChildren()
    local function button(x, y, width, title, action)
        local widget = ISButton:new(x, y, width, 23, title, self, action)
        widget:initialise()
        self:addChild(widget)
        return widget
    end
    local x = self.carriedX + 2
    local controlsY = carriedY + paletteRows * carriedStep
    button(x + 109, 9, 54, "Close", self.close)
    if not self.cabinet then
        self.autoButton = button(x, controlsY, 162, "Auto-connect", self.autoConnect)
        controlsY = controlsY + 31
    end
    self.removeButton = button(x, controlsY, 78, "Remove", self.removePart)
    self.configureButton = button(x + 84, controlsY, 78, "Configure", self.configure)
    self.batteryButton = button(x, controlsY + 28, 162,
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
    local cabinet = entry and Circuit.profileFor(entry.piece.definitionId)
    local adapter = cabinet and entry.piece.state.adapter or nil
    if not entry or not entry.piece.state or not Circuit.compile(entry.piece.state.circuit, cabinet, adapter) then
        player:Say("Choose a nearby circuit cabinet, networked door or lamp with an Advanced Adapter.")
        return
    end
    if panels[player] then panels[player]:close() end
    local cell, gridSize = cabinet and 60 or 78, Circuit.size(cabinet)
    local _, gridRows = Circuit.dimensions(cabinet)
    local gridWidth, gridHeight = gridSize * cell, gridRows * cell
    local controlsY = carriedY + paletteRows * carriedStep
    local legendY = controlsY + (cabinet and 55 or 88)
    local width, height = gridWidth + 218, math.max(gridHeight + 111, legendY + 50)
    local panel = ISPanel.new(Editor, math.max(0, (getCore():getScreenWidth() - width) / 2),
        math.max(0, (getCore():getScreenHeight() - height) / 2), width, height)
    panel.player, panel.registry, panel.target = player, registry, target
    panel.cabinet, panel.cell, panel.gridSize, panel.gridWidth = cabinet, cell, gridSize, gridWidth
    panel.gridRows, panel.gridHeight = gridRows, gridHeight
    panel.carriedX = gridX + gridWidth + 22
    panel.paletteOffset, panel.legendY = 0, legendY
    panel.collapsed = {}
    panel.moveWithMouse = true
    panel:setWantKeyEvents(true)
    panel.backgroundColor = { r = 0.09, g = 0.13, b = 0.10, a = 1 }
    panel:initialise()
    panel:addToUIManager()
    panels[player] = panel
end

ZedComm = ZedComm or {}
ZedComm.AdapterEditor = Editor
