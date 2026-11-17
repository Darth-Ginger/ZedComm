ZedComm = ZedComm or {}
ZedComm.ItemTags = {}
for _, name in ipairs({ "endpoint", "source", "receiver", "adapter", "module", "cabinet", "infrastructure", "wire" }) do
    ZedComm.ItemTags[name] = ItemTag.register("zedcomm:" .. name)
end
