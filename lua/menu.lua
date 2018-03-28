-- menu.lua
-- norns screen-based navigation module
local tab = require 'tabutil'
local util = require 'util'
local menu = {}

-- global functions for scripts
key = norns.none
enc = norns.none
redraw = norns.blank
cleanup = norns.none 

-- level enums
local pHOME = 1
local pSELECT = 2
local pPREVIEW = 3
local pSTATUS = 4
local pPARAMS = 5
local pSYSTEM = 6
local pWIFI = 7
local pSLEEP = 8
local pLOG = 9
local pWIFIPASS = 10

-- page pointer
local p = {}
p.key = {}
p.enc = {}
p.redraw = {}
p.init = {}

menu.mode = false
menu.page = pHOME

local pending = false
-- metro for key hold detection
local metro = require 'metro'
local t = metro[31]
t.count = 2
t.callback = function(stage)
    if(stage==2) then
        if menu.mode == false then
            menu.key(1,1)
        end 
        pending = false
    end
end

-- metro for status updates
local u = metro[30]
u.time = 2
u.count = -1


-- assigns key/enc/screen handlers after user script has loaded
norns.menu = {}
norns.menu.init = function() 
    menu.set_mode(menu.mode)
    os.execute("~/norns/wifi.sh scan &")
end


-- input redirection
local _enc = {{},{},{}}
_enc[1].sens = 1
_enc[1].tick = 0
_enc[2].sens = 1
_enc[2].tick = 0 
_enc[3].sens = 1
_enc[3].tick = 0

norns.enc = function(n, delta) 
    _enc[n].tick = _enc[n].tick + delta
    if math.abs(_enc[n].tick) > _enc[n].sens then
        _enc[n].tick = 0
        if(menu.mode==false) then
            enc(n, delta)
        else
            if n==1 then menu.level(delta)
            else menu.enc(n, delta) end
        end
    end
end

set_enc_sens = function(n, sens)
    _enc[n].sens = sens
    _enc[n].tick = 0
end


norns.key = function(n, z)
    -- key 1 detect for short press
	if(n==1) then
        if z==1 then
            pending = true
            t.time = 0.25
            t:start()
        elseif z==0 and pending==true then
            if menu.mode == true then menu.set_mode(false)
            else menu.set_mode(true) end
            t:stop()
            pending = false
        elseif z==0 and menu.mode==false then
            menu.key(n,z) -- always 1,0
        else
            menu.set_mode(false)
 		end
    -- key 2/3 pass
	else 
        menu.key(n,z)
	end
end

-- menu set mode
menu.set_mode = function(mode)
    if mode==false then
        menu.mode = false 
        --FIXME: should the interface pages have deinits?
        u:stop()
        norns.vu = norns.none
        s_enable()
        menu.key = key
        menu.enc = enc
        set_enc_sens(1,1)
        set_enc_sens(2,1)
        set_enc_sens(3,1)
        redraw() 
    else -- enable menu mode
        menu.mode = true
        s_disable()
        s_font_face(0)
        s_font_size(8)
        s_line_width(1)
        menu.set_page(menu.page)
        set_enc_sens(1,1)
        set_enc_sens(2,2)
        set_enc_sens(3,2) 
    end
end

-- set page
menu.set_page = function(page)
    menu.page = page
    menu.key = p.key[page]
    menu.enc = p.enc[page]
    menu.redraw = p.redraw[page]
    p.init[page]()
    menu.redraw()
end

-- set audio level
menu.level = function(delta)
    local l = util.clamp(norns.state.out + delta,0,64)
    if l ~= norns.state.out then
        norns.state.out = l 
        audio_output_level(l / 64.0)
    end
end 

-- --------------------------------------------------
-- interfaces

-- HOME

p.home = {}
p.home.pos = 0
p.home.list = {"SELECT >", "PARAMETERS >", "SYSTEM >", "SLEEP >"}
p.home.len = 4

p.init[pHOME] = norns.none

p.key[pHOME] = function(n,z)
    if n==2 and z==1 then
        menu.set_page(pSTATUS)
    elseif n==3 and z==1 then 
        option = {pSELECT, pPARAMS, pSYSTEM, pSLEEP}
        menu.set_page(option[p.home.pos+1]) 
    end
end 

p.enc[pHOME] = function(n,delta)
    if n==2 then 
        p.home.pos = p.home.pos + delta 
	    if p.home.pos > p.home.len - 1 then p.home.pos = p.home.len - 1
        elseif p.home.pos < 0 then p.home.pos = 0 end
        menu.redraw()
    end
end

p.redraw[pHOME] = function()
    s_clear()
    -- draw current script loaded
    s_move(0,10)
    s_level(15)
    line = string.gsub(norns.state.script,'.lua','')
    s_text(string.upper(line))

    -- draw file list and selector
    for i=3,6 do
       	s_move(0,10*i)
       	line = string.gsub(p.home.list[i-2],'.lua','')
       	if(i==p.home.pos+3) then
           	s_level(15)
       	else
           	s_level(4)
       	end
       	s_text(string.upper(line)) 
    end
    s_update()
end


-- SELECT

p.sel = {}
p.sel.pos = 0
p.sel.list = util.scandir(script_dir)
p.sel.len = tab.count(p.sel.list)
p.sel.depth = 0
p.sel.folders = {}
p.sel.path = ""
p.sel.file = ""

p.sel.dir = function()
    local path = script_dir
    for k,v in pairs(p.sel.folders) do
        path = path .. v
    end
    print("path: "..path)
    return path
end

p.init[pSELECT] = function()
    if p.sel.depth == 0 then
        p.sel.list = util.scandir(script_dir)
    else
        p.sel.list = util.scandir(p.sel.dir())
    end
    p.sel.len = tab.count(p.sel.list)
end

p.key[pSELECT] = function(n,z)
    -- back
    if n==2 and z==1 then
        if p.sel.depth > 0 then
            print('back')
            p.sel.folders[p.sel.depth] = nil
            p.sel.depth = p.sel.depth - 1
            -- FIXME return to folder position
            p.sel.list = util.scandir(p.sel.dir())
            p.sel.len = tab.count(p.sel.list)
            p.sel.pos = 0
            menu.redraw()
        else
            menu.set_page(pHOME)
        end 
    -- select
    elseif n==3 and z==1 then 
        p.sel.file = p.sel.list[p.sel.pos+1]
        if string.find(p.sel.file,'/') then 
            print("folder")
            p.sel.depth = p.sel.depth + 1
            p.sel.folders[p.sel.depth] = p.sel.file
            p.sel.list = util.scandir(p.sel.dir())
            p.sel.len = tab.count(p.sel.list)
            p.sel.pos = 0
            menu.redraw()
        else 
            local path = ""
            for k,v in pairs(p.sel.folders) do
                path = path .. v
            end
            p.sel.path = path .. p.sel.file
            menu.set_page(pPREVIEW)
        end
    end
end

p.enc[pSELECT] = function(n,delta)
    -- scroll file list
    if n == 1 then
        p.sel.level(delta)
    elseif n==2 then 
        p.sel.pos = p.sel.pos + delta 
	    if p.sel.pos > p.sel.len - 1 then p.sel.pos = p.sel.len - 1
        elseif p.sel.pos < 0 then p.sel.pos = 0 end
        menu.redraw()
    elseif n==3 then
        p.sel.page = 1 - p.sel.page
        print("page "..p.sel.page)
    end
end

p.redraw[pSELECT] = function()
    -- draw file list and selector
    s_clear()
    s_level(15)
    for i=1,6 do
		if (i > 2 - p.sel.pos) and (i < p.sel.len - p.sel.pos + 3) then
        	s_move(0,10*i)
        	line = string.gsub(p.sel.list[i+p.sel.pos-2],'.lua','')
        	if(i==3) then
            	s_level(15)
        	else
            	s_level(4)
        	end
        	s_text(string.upper(line)) 
		end
    end
    s_update()
end



-- PREVIEW

p.pre = {}
p.pre.meta = {}
p.pre.state = 0

p.init[pPREVIEW] = function()
    p.pre.meta = norns.script.metadata(p.sel.path)
    p.pre.state = 0
end

p.key[pPREVIEW] = function(n,z)
    if n==3 and p.pre.state == 1 then
        norns.script.load(p.sel.path)
        menu.set_page(pHOME)
        menu.set_mode(false)
    elseif n ==3 and z == 1 then
        p.pre.state = 1
    elseif n == 2 and z == 1 then
        menu.set_page(pSELECT)
    end
end

p.enc[pPREVIEW] = norns.none

p.redraw[pPREVIEW] = function()
    s_clear()
	if tab.count(p.pre.meta) == 0 then
		p.pre.meta.name = string.gsub(p.sel.file,'.lua','') .. " (no metadata)"
	end 
    if p.pre.meta.name == nil then
		p.pre.meta.name = string.gsub(p.sel.file,'.lua','')
    end 
	local name = string.upper(p.pre.meta.name)
	local version = ""
	if p.pre.meta.version ~= nil then
		version = p.pre.meta.version		
	end 
	name = name .. " " .. version
	local l = 8
	s_move(0,l)
	s_level(15)
	s_text(name)
	local byline = ''
	if p.pre.meta.author ~= nil then
		byline = p.pre.meta.author
	end
	if p.pre.meta.url ~= nil then
		byline = byline .. " - " .. p.pre.meta.url
	end
	if byline ~= '' then
        l = l + 8
		s_level(8)
		s_move(0,l) 
		s_text(byline)	
	end
	l = l + 16 
	if p.pre.meta.txt ~= nil then
		s_move(0,l)
		--TODO this should wrap and scroll!
		s_text(p.pre.meta.txt)
	end 
    s_update()
end

-- PARAMS

p.key[pPARAMS] = function(n,z)
    if n==2 and z==1 then 
        menu.set_page(pHOME)
    end
end

p.enc[pPARAMS] = norns.none

p.redraw[pPARAMS] = function()
    s_clear()
    s_level(10)
    s_move(0,10)
    s_text("params")
    s_update()
end

p.init[pPARAMS] = norns.none


-- SYSTEM
p.sys = {}
p.sys.pos = 0
p.sys.list = {"wifi >", "input gain:","headphone gain:", "log >"}
p.sys.len = 4
p.sys.input = 0
p.sys.battery = ''
p.sys.net = ''

p.key[pSYSTEM] = function(n,z)
    if n==2 and z==1 then 
        norns.state.save()
        u:stop()
        menu.set_page(pHOME)
    elseif n==3 and z==1 and p.sys.pos==3 then
        u:stop()
        menu.set_page(pLOG)
    elseif n==3 and z==1 and p.sys.pos==1 then
        p.sys.input = (p.sys.input + 1) % 3
        menu.redraw()
    elseif n==3 and z==1 and p.sys.pos==0 then
        u:stop()
        menu.set_page(pWIFI) 
    end
end

p.enc[pSYSTEM] = function(n,delta)
    if n==2 then 
        p.sys.pos = p.sys.pos + delta 
        p.sys.pos = util.clamp(p.sys.pos, 0, p.sys.len-1)
	    --if p.sys.pos > p.sys.len - 1 then p.sys.pos = p.sys.len - 1
        --elseif p.sys.pos < 0 then p.sys.pos = 0 end
        menu.redraw()
    elseif n==3 then
        if p.sys.pos == 1 then
            if p.sys.input == 0 or p.sys.input == 1 then
                norns.state.input_left = norns.state.input_left + delta
                norns.state.input_left = util.clamp(norns.state.input_left,0,63)
                gain_in(norns.state.input_left,0)
            end 
            if p.sys.input == 0 or p.sys.input == 2 then
                norns.state.input_right = norns.state.input_right + delta
                norns.state.input_right = util.clamp(norns.state.input_right,0,63)
                gain_in(norns.state.input_right,1)
            end 
            menu.redraw()
        elseif p.sys.pos == 2 then
            norns.state.hp = norns.state.hp + delta
            norns.state.hp = util.clamp(norns.state.hp,0,63)
            gain_hp(norns.state.hp) 
            menu.redraw()
        end
    end
end

p.redraw[pSYSTEM] = function()
    s_clear() 
    s_level(4)
    s_move(0,10)
    s_text(p.sys.battery)
 
    for i=1,p.sys.len do
       	s_move(0,10*i+20)
       	if(i==p.sys.pos+1) then
           	s_level(15)
       	else
           	s_level(4)
       	end
       	s_text(string.upper(p.sys.list[i])) 
    end

    if p.sys.pos==1 and (p.sys.input == 0 or p.sys.input == 1) then
        s_level(15) else s_level(4) end
    s_move(101,40)
    if(norns.state.input_left == 0) then s_text_right("m")
    else s_text_right(norns.state.input_left - 48) end -- show 48 as unity (0)
    if p.sys.pos==1 and (p.sys.input == 0 or p.sys.input == 2) then 
        s_level(15) else s_level(4) end
    s_move(127,40)
    if(norns.state.input_right == 0) then s_text_right("m")
    else s_text_right(norns.state.input_right - 48) end
    if p.sys.pos==2 then s_level(15) else s_level(4) end
    s_move(127,50)
    s_text_right(norns.state.hp)
    s_level(4)
    s_move(127,30) 
    s_text_right(p.sys.net)
    s_move(127,60)
    s_text_right("norns v"..norns.version.norns)
    s_update()
end

p.init[pSYSTEM] = function()
    u.callback = function()
        p.sysquery()
        menu.redraw()
    end
    u:start()
end

p.sysquery = function()
    p.sys.battery = "battery "..norns.batterypercent 
    if norns.powerpresent==1 then p.sys.battery = p.sys.battery.."+" end 
    local current = util.os_capture("cat /sys/class/power_supply/bq27441-0/current_now")
    current = tonumber(current) / 1000 
    p.sys.battery = p.sys.battery .. " / "..current.."mA"

    p.sys.net = ''..util.os_capture("ifconfig wlan0| grep 'inet ' | awk '{print $2}'")
    local wifi_status = util.os_capture("cat ~/status.wifi");
    -- if p.sys.net == '' or wifi
    if wifi_status == 'router'
    then
        p.sys.net = p.sys.net .. " / "
        p.sys.net = p.sys.net .. util.os_capture("iw dev wlan0 link | grep 'signal' | awk '{print $2}'")
        p.sys.net = p.sys.net .. "dBm"
    else
       p.sys.net = wifi_status
    end 
end
 



-- SLEEP

p.key[pSLEEP] = function(n,z)
    if n==2 and z==1 then 
        menu.set_page(pHOME)
    elseif n==3 and z==1 then
        print("SLEEP")
        --TODO fade out screen then run the shutdown script
        os.execute("sudo shutdown now")
    end
end

p.enc[pSLEEP] = norns.none

p.redraw[pSLEEP] = function()
    s_clear()
    s_move(48,40)
    s_text("sleep?")
    --TODO do an animation here! fade the volume down
    s_update()
end

p.init[pSLEEP] = norns.none


-- STATUS
p.stat = {}
p.stat.tape = false

p.key[pSTATUS] = function(n,z)
    if n==3 and z==1 then 
        norns.vu = norns.none
        menu.set_page(pHOME)
    elseif n==2 then
	if z==1 then p.stat.tape = true
	else p.stat.tape = false end
    end
end

p.enc[pSTATUS] = norns.none

p.redraw[pSTATUS] = function()
    s_clear()
    s_aa(1)

    s_line_width(1)
    s_level(2)
    s_move(0,64-norns.state.out)
    s_line(0,63)
    s_stroke()

    s_level(15)
    s_move(3,63)
    s_line(3,63-p.stat.out1)
    s_move(6,63)
    s_line(6,63-p.stat.out2)
    s_move(16,63)
    s_line(16,63-p.stat.in1)
    s_move(19,63)
    s_line(19,63-p.stat.in2)
    s_stroke()

    if p.stat.tape then
	s_level(2)
        s_move(127,63)
	s_text_right("TAPE")
    end

    if norns.powerpresent==0 then
	s_level(2)
	s_move(24,63)
	s_text("99") -- add batt percentage
    end

    s_update()
end

p.init[pSTATUS] = function()
    norns.vu = p.stat.vu
    p.stat.in1 = 0
    p.stat.in2 = 0
    p.stat.out1 = 0
    p.stat.out2 = 0
end

p.stat.vu = function(in1,in2,out1,out2)
    p.stat.in1 = in1
    p.stat.in2 = in2
    p.stat.out1 = out1
    p.stat.out2 = out2 
    menu.redraw()
end



-- WIFI
p.wifi = {}
p.wifi.pos = 0
p.wifi.list = {"off","hotspot","connect:","select >"}
p.wifi.len = 4 
p.wifi.scan = {}
p.wifi.num = 0
p.wifi.selected = 0
p.wifi.status = ""
p.wifi.ssid = ""
p.wifi.try = ""

p.key[pWIFI] = function(n,z)
    if n==2 and z==1 then
        menu.set_page(pSYSTEM)
    elseif n==3 and z==1 then
        if p.wifi.pos == 0 then
            print "wifi off"
            os.execute("~/norns/wifi.sh off &")
            menu.set_page(pSYSTEM)
        elseif p.wifi.pos == 1 then
            print "wifi hotspot"
            os.execute("~/norns/wifi.sh hotspot &")
            menu.set_page(pSYSTEM)
        elseif p.wifi.pos == 2 then
            print "wifi on"
            os.execute("~/norns/wifi.sh on &")
            menu.set_page(pSYSTEM)
	elseif p.wifi.num > 0 then
	    p.wifi.try = p.wifi.scan[p.wifi.selected+1]
	    menu.set_page(pWIFIPASS)
	end
    end
end

p.enc[pWIFI] = function(n,delta)
    if n==2 then 
        p.wifi.pos = p.wifi.pos + delta 
	    if p.wifi.pos > p.wifi.len - 1 then p.wifi.pos = p.wifi.len - 1
        elseif p.wifi.pos < 0 then p.wifi.pos = 0 end
        menu.redraw()
    elseif n==3 and p.wifi.pos == 3 then
	p.wifi.selected = util.clamp(0,p.wifi.selected+delta,p.wifi.num-1)
	menu.redraw()
    end
end

p.redraw[pWIFI] = function()
    s_clear()
    s_level(15)
    s_move(0,30+p.wifi.status*10)
    s_text("-")

    for i=1,4 do
       	s_move(8,20+10*i)
       	line = p.wifi.list[i]
       	if(i==p.wifi.pos+1) then
           	s_level(15)
       	else
           	s_level(4)
       	end
       	s_text(string.upper(line)) 
    end

    s_move(127,50)
    if p.wifi.pos==2 then s_level(15) else s_level(4) end
    s_text_right(p.wifi.ssid) 
    s_move(127,60)
    if p.wifi.pos==3 then s_level(15) else s_level(4) end
    if p.wifi.num > 0 then
    	s_text_right(p.wifi.scan[p.wifi.selected+1])
    else
	s_text_right("NONE")
    end

    s_update() 
end 

p.init[pWIFI] = function()
   p.wifi.status = 0
   p.wifi.ssid = util.os_capture("cat ~/ssid.wifi")
   wifi_status = util.os_capture("cat ~/status.wifi");
   if wifi_status == 'hotspot' then p.wifi.status = 1 
   elseif wifi_status == 'router' then p.wifi.status = 2 end

   for line in io.lines(home_dir.."/scan.wifi") do
       table.insert(p.wifi.scan,line)
   end
   p.wifi.num = tab.count(p.wifi.scan)
end

-- WIFIPASS
p.wifipass = {}
p.wifipass.x = 0
p.wifipass.y = 0
p.wifipass.psk = ""
p.wifipass.page = 33
p.wifipass.delok = 0

p.key[pWIFIPASS] = function(n,z)
    if n==2 and z==1 then
        menu.set_page(pWIFI)
    elseif n==3 and z==1 then
	if p.wifipass.y < 4 then
            local ch = 5+(p.wifipass.x+p.wifipass.y*23)%92+33
            p.wifipass.psk = p.wifipass.psk .. string.char(ch)
	    menu.redraw() 
	else 
          local i = p.wifipass.delok >> 2
          if i==0 then
            p.wifipass.psk = string.sub(p.wifipass.psk,0,-2)
          elseif i==1 then 
            os.execute("~/norns/wifi.sh select "..p.wifi.try.." "..p.wifipass.psk.." &")
            menu.set_page(pSYSTEM)
          end 
          menu.redraw()
	end
    end
end

p.enc[pWIFIPASS] = function(n,delta)
    if n==2 then 
        if p.wifipass.y == 4 then
	  p.wifipass.delok = (p.wifipass.delok + delta) % 8
        else p.wifipass.x = (p.wifipass.x + delta) % 92 end
        menu.redraw()
    elseif n==3 then
	p.wifipass.y = util.clamp(p.wifipass.y-delta,0,4)
	menu.redraw()
    end
end

p.redraw[pWIFIPASS] = function()
    s_clear()
    s_level(15)
    s_move(0,10)
    s_text("PASSWORD: "..p.wifipass.psk)
    local x,y
    for x=0,15 do
        for y=0,3 do
	    if x==5 and y==p.wifipass.y then s_level(15) else s_level(2) end
	    s_move(x*8,y*8+24)
	    s_text(string.char((x+p.wifipass.x+y*23)%92+33))
	end
    end

    local i = p.wifipass.delok >> 2 
    s_move(0,60)
    if p.wifipass.y==4 and i==0 then s_level(15) else s_level(2) end
    s_text("DEL")
    s_move(127,60)
    if p.wifipass.y==4 and i==1 then s_level(15) else s_level(2) end
    s_text_right("OK")

    s_update() 
end 

p.init[pWIFIPASS] = function() end


-- LOG
p.log = {}
p.log.pos = 0

p.key[pLOG] = function(n,z)
    if n==2 and z==1 then
        menu.set_page(pSYSTEM)
    elseif n==3 and z==1 then
        p.log.pos = 0
        menu.redraw()
    end
end 

p.enc[pLOG] = function(n,delta)
    if n==2 then
        p.log.pos = util.clamp(p.log.pos+delta, 0, norns.log.len()-7)
        menu.redraw()
    end
end

p.redraw[pLOG] = function()
    s_clear()
    s_level(10)
    for i=1,8 do
        s_move(0,(i*8)-1)
        s_text(norns.log.get(i+p.log.pos))
    end
    s_update()
end

p.init[pLOG] = function()
    p.log.pos = 0
end

