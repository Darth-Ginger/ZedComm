return function(test)
    local newItem = instanceItem

    instanceItem = function(itemType)
        local item = newItem(itemType)
        function item:getKeyId() return self.keyId end
        function item:setKeyId(id) self.keyId = id end
        function item:getNumberOfKey() return self.keyCount or 2 end
        function item:setNumberOfKey(count) self.keyCount = count end
        return item
    end

    function test.inventory:haveThisKeyId(id)
        for _, item in ipairs(test.carried) do
            if item:getFullType() == "Base.KeyPadlock" and item:getKeyId() == id then return item end
        end
    end
end
