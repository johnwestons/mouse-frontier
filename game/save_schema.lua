local SaveSchema = {
    CURRENT_VERSION = 25,
}

function SaveSchema.stamp(data)
    assert(type(data) == "table", "save data must be a table")
    data.version = SaveSchema.CURRENT_VERSION
    return data
end

function SaveSchema.isCurrent(data)
    return type(data) == "table" and data.version == SaveSchema.CURRENT_VERSION
end

return SaveSchema
