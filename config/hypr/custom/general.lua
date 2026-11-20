-- NovelKnock: window gaps chosen in the Settings app (Quick > Bar & screen > Window gaps).
-- The file sits outside the locked custom folder so the Settings app can write it.
if is_file_exists(HOME .. "/.config/hypr/gaps.lua") then
    require("gaps")
end
