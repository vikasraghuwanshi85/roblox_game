return {
    -- Keep this module in ServerScriptService. User ID lists use numeric IDs.
    -- A personally owned experience automatically grants its creator Owner.
    -- For group experiences, the current group owner is resolved by the server.
    OwnerUserIds = {},
    AdminUserIds = {},
    -- Exact usernames, resolved to User IDs by Roblox on the server.
    AdminUsernames = {"progamer2013988", "raindeer_g6"},
    AutoDetectOwner = true,
    -- Roblox physics needs finite values. This is the "infinite speed" mode.
    InfiniteWalkSpeed = 1000000000,
    FlySpeed = 100,
}
