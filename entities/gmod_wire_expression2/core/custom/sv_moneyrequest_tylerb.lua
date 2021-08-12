--#################################################################################################################--
--##  _____     _          ______                                          ______                           _    ##--
--## |_   _|   | |         | ___ \                                         | ___ \                         | |   ##--
--##   | |_   _| | ___ _ __| |_/ / ___     _ __ ___   ___  _ __   ___ _   _| |_/ /___  __ _ _   _  ___  ___| |_  ##--
--##   | | | | | |/ _ \  __| ___ \/ __|   |  _   _ \ / _ \|  _ \ / _ \ | | |    // _ \/ _  | | | |/ _ \/ __| __| ##--
--##   | | |_| | |  __/ |  | |_/ /\__ \   | | | | | | (_) | | | |  __/ |_| | |\ \  __/ (_| | |_| |  __/\__ \ |_  ##--
--##   \_/\__, |_|\___|_|  \____/ |___/   |_| |_| |_|\___/|_| |_|\___|\__, \_| \_\___|\__, |\__,_|\___||___/\__| ##--
--##       __/ |                                                       __/ |             | |                     ##--
--##      |___/                                                       |___/              |_|                     ##--
--#################################################################################################################--

--SERVER--

--AddCSLuaFile("cl_moneyrequest_tylerb.lua")

util.AddNetworkString( "moneyRequest" )

local maxreq = CreateConVar("sv_moneyrequest_max", 0, {FCVAR_ARCHIVE})
local allowgive = CreateConVar("sv_moneyrequest_allowgive", 1, {FCVAR_ARCHIVE})

local Requests = 0
local OpenRequests = {}
local Blocked = {}
local Player = FindMetaTable("Player")

function math.IsFinite(num)
    return not (num ~= num or num == math.huge or num == -math.huge);
end

local function AdminLog(message)
    local RF = RecipientFilter()
    for k,v in pairs(player.GetAll()) do
        if v:IsAdmin() then
            RF:AddPlayer(v)
        end
    end
    umsg.Start("DRPLogMsg", RF)
        umsg.Short(255)
        umsg.Short(190)
        umsg.Short(0)
        umsg.String(message)
    umsg.End()
end

function Player:GiveMoney(amount)
	if not math.IsFinite(amount) then return end
	
    self:addMoney(math.abs(amount))
end


function Player:TakeMoney(amount)
    if not math.IsFinite(amount) then return end
	
	self:addMoney(-math.abs(amount))
end

function Player:Money()
    if not IsValid(self) then return 0 end
    if not self:IsPlayer() then return 0 end
    return self.DarkRPVars.money
end

local function handleRequest(e2,ply,amount,timeout,title)
    if not math.IsFinite(amount) then return end
	
	local asker = e2.player
    if not IsValid(ply) then return 0 end
    if not ply:IsPlayer() then return 0 end
    if not IsValid(asker) then return 0 end
    if not asker:IsPlayer() then return 0 end
    if not amount then return 0 end
    if amount <= 0 then return 0 end      
    
	if maxreq:GetInt() >= 1 and amount > maxreq:GetInt() then
		asker:ChatPrint("The server has restricted the maximum amount of money you can transfer to $"..maxreq:GetInt()..".")
        return 0
	end
	
	if ply:Money() - amount < 0 then 
		asker:ChatPrint("The player cannot afford that transaction.")
        return 0 
	end
    
	amount = math.floor(amount)
	
    Requests = Requests + 1
    local id = Requests
    OpenRequests[id] = {}
    OpenRequests[id]["e2"] = e2
    OpenRequests[id]["asker"] = asker
    OpenRequests[id]["ply"] = ply
    OpenRequests[id]["amount"] = amount
    OpenRequests[id]["timeout"] = math.Clamp(timeout and timeout or 0,0,30)
    OpenRequests[id]["title"] = string.sub(title and title or "",1,20)
    
    
    net.Start("moneyRequest")
        net.WriteEntity(asker)
        net.WriteFloat(math.Round(amount))
        net.WriteFloat((timeout and math.Round(timeout) or 0))
        net.WriteString(title and title or "Money Request")
        net.WriteFloat(Requests)
    net.Send(ply)
    
    
    AdminLog("moneyRequest(): "..asker:Name().." asked "..ply:Name().." for $"..amount.." with title '"..(title and title or "Money Request").."'.")
    
    return 1
end

local function handleGive(giver,ply,amount)
    if not math.IsFinite(amount) then return 0 end
	
	if not allowgive:GetBool() then
		giver:ChatPrint("The server has disabled moneyGive().")
		return
	end
	
	if not IsValid(ply) then return 0 end
    if not ply:IsPlayer() then return 0 end
    if not IsValid(giver) then return 0 end
    if not giver:IsPlayer() then return 0 end
    
	amount = math.floor(amount)
	
    if not amount then return 0 end
    if amount <= 0 then return 0 end      
	
	if maxreq:GetInt() >= 1 and amount > maxreq:GetInt() then
		giver:ChatPrint("The server has restricted the maximum amount of money you can transfer to $"..maxreq:GetInt()..".")
        return 0
	end
	
    if giver:Money() - amount < 0 then 
        giver:ChatPrint("Your E2 attempted to give $"..amount..", which you can't afford.")
        return 0
    end
	
    ply:GiveMoney(amount)
    giver:TakeMoney(amount)
    ply:ChatPrint("You received $"..amount.." from "..giver:Name().."'s E2.")
    giver:ChatPrint("You gave $"..amount.." to "..ply:Name()..".")
    AdminLog("moneyGive(): "..giver:Name().." gave "..ply:Name().." $"..amount..".")
  
    return 1
end

local function handleCommand(ply,id,accept)
    if not id then return end
    if not OpenRequests[tonumber(math.Round(id))]["asker"] then return end
    if not ply then return end
    if not ply:IsPlayer() then return end
    local asker = OpenRequests[tonumber(math.Round(id))]["asker"]
    local amount = OpenRequests[tonumber(math.Round(id))]["amount"]
    local title = OpenRequests[tonumber(math.Round(id))]["title"]
    
	if not math.IsFinite(amount) then return end
	
	amount = math.floor(amount)
	
    if accept then
        local e2 = OpenRequests[tonumber(math.Round(id))]["e2"] 
        if IsValid(e2) then
            if ply:Money() - amount < 0 then 
                ply:ChatPrint("You cannot afford to pay this.")
				
				e2.ClkTimeNoMoney = CurTime()
				e2.ClkNoPlayer = ply
				e2.ClkNoTitle = title
				e2:Execute()
			
                return
            end
            ply:TakeMoney(amount)
            asker:GiveMoney(amount)
            asker:ChatPrint("You received $"..amount.." from "..ply:Name()..".")
            ply:ChatPrint("You gave $"..amount.." to "..asker:Name()..".")           
            
            e2.ClkTimeMoney = CurTime()
            e2.ClkPlayer = ply
            e2.ClkAmount = amount
            e2.ClkTitle = title
            e2:Execute()
        end
    else
        local e2 = OpenRequests[tonumber(math.Round(id))]["e2"] 
        if IsValid(e2) then
            e2.ClkTimeNoMoney = CurTime()
            e2.ClkNoPlayer = ply
            e2.ClkNoAmount = amount
			e2.ClkNoTitle = title
            e2:Execute()
        end   
    end
end

local function handleTimeout(ply,id)
    if not ply then return end
    if not ply:IsPlayer() then return end
    
    local e2 = OpenRequests[tonumber(math.Round(id))]["e2"] 
    local title = OpenRequests[tonumber(math.Round(id))]["title"] 
	
    if IsValid(e2) then
        e2.Timeout = CurTime()
        e2.TimeoutPlayer = ply
        e2.TimeoutAmount = ply
        e2.TimeoutTitle = title
        e2:Execute()
    end
end

e2function number moneyRequest(entity ply, amount)
    return handleRequest(self.entity,ply,amount,nil,nil)
end

e2function number moneyRequest(entity ply, amount, timeout)
    return handleRequest(self.entity,ply,amount,timeout,nil)
end

e2function number moneyRequest(entity ply, amount, string title)
    return handleRequest(self.entity,ply,amount,nil,title)
end

e2function number moneyRequest(entity ply, amount, timeout, string title)
    return handleRequest(self.entity,ply,amount,timeout,title)
end

e2function number moneyRequest(entity ply, amount, string title, timeout)
    return handleRequest(self.entity,ply,amount,timeout,title)
end

e2function number moneyGive(entity ply, amount)
    return handleGive(self.player,ply,amount)
end

----------------------------------------------------------------
----------------------------------------------------------------
----------------------------------------------------------------

e2function number moneyClk()
    if not self.entity.ClkTimeMoney then return 0 end   
    return self.entity.ClkTimeMoney == CurTime() and 1 or 0
end

e2function number moneyClk(string str)
    if not self.entity.ClkTimeMoney then return 0 end   
    if not self.entity.ClkTitle then return 0 end   
    return (self.entity.ClkTitle == str and self.entity.ClkTimeMoney == CurTime()) and 1 or 0
end

e2function string moneyClkTitle()
    if not self.entity.ClkTimeMoney then return "" end   
    return self.entity.ClkTimeMoney == CurTime() and self.entity.ClkTitle or ""
end

e2function number moneyClkAmount()
    if not self.entity.ClkTimeMoney then return 0 end   
    return self.entity.ClkTimeMoney == CurTime() and self.entity.ClkAmount or 0
end

e2function entity moneyClkPlayer()
    if not self.entity.ClkPlayer then return nil end   
    if not self.entity.ClkPlayer:IsPlayer() then return nil end   

    return self.entity.ClkPlayer
end

----------------------------------------------------------------
----------------------------------------------------------------
----------------------------------------------------------------

e2function number moneyNoClk()
    if not self.entity.ClkTimeNoMoney then return 0 end   
    return self.entity.ClkTimeNoMoney == CurTime() and 1 or 0
end

e2function number moneyNoClk(string str)
    if not self.entity.ClkTimeNoMoney then return 0 end   
    if not self.entity.ClkNoTitle then return 0 end   
    return (self.entity.ClkNoTitle == str and self.entity.ClkTimeNoMoney == CurTime()) and 1 or 0
end

e2function string moneyNoClkTitle()
    if not self.entity.ClkTimeNoMoney then return "" end   
    return self.entity.ClkTimeNoMoney == CurTime() and self.entity.ClkNoTitle or ""
end

e2function number moneyNoClkAmount()
    if not self.entity.ClkTimeNoMoney then return 0 end   
    return self.entity.ClkTimeNoMoney == CurTime() and self.entity.ClkNoAmount or 0
end

e2function entity moneyNoClkPlayer()
    if not self.entity.ClkNoPlayer then return nil end   
    if not self.entity.ClkNoPlayer:IsPlayer() then return nil end   

    return self.entity.ClkNoPlayer
end

----------------------------------------------------------------
----------------------------------------------------------------
----------------------------------------------------------------

e2function number moneyTimeout()
    if not self.entity.Timeout then return 0 end   
    return self.entity.Timeout == CurTime() and 1 or 0
end

e2function number moneyTimeout(string str)
    if not self.entity.Timeout then return 0 end   
    if not self.entity.TimeoutPlayer:IsPlayer() then return 0 end   
    return (self.entity.TimeoutTitle == str and self.entity.Timeout == CurTime()) and 1 or 0
end

e2function string moneyTimeoutTitle()
    if not self.entity.Timeout then return "" end   
    return self.entity.Timeout == CurTime() and self.entity.TimeoutTitle or ""
end

e2function number moneyTimeoutAmount()
    if not self.entity.Timeout then return 0 end   
    return self.entity.Timeout == CurTime() and self.entity.TimeoutAmount or 0
end

e2function entity moneyTimeoutPlayer()
    if not self.entity.TimeoutPlayer then return nil end   
    if not self.entity.TimeoutPlayer:IsPlayer() then return nil end   

    return self.entity.TimeoutPlayer
end

----------------------------------------------------------------
----------------------------------------------------------------
----------------------------------------------------------------

e2function number entity:money()
    if not IsValid(this) then return 0 end
    if not this:IsPlayer() then 
		if this:GetClass() == "spawned_money" then
			return this:Getamount()
		else
			return 0
		end
	else
		return math.floor(this.DarkRPVars.money)
	end
end

e2function number entity:moneyAmount()
    if not IsValid(this) then return 0 end
    if not this:IsPlayer() then 
		if this:GetClass() == "spawned_money" then
			return this:Getamount()
		else
			return 0
		end
	else
		return math.floor(this.DarkRPVars.money)
	end
end


concommand.Add("rp_acceptmoney",function(ply,com,arg)
    if not ply then print("what are you doing") return end
    if not arg[1] then ply:ChatPrint("hey, don't run this from your console, buddy") return end
    if not OpenRequests[tonumber(arg[1])]["amount"] then return end
    if ply:Money() - OpenRequests[tonumber(arg[1])]["amount"] < 0 then 
        ply:ChatPrint("You cannot afford to pay this.")
        ply:ConCommand("rp_denymoney "..tonumber(arg[1]))
        return
    end
    AdminLog("moneyRequest(): "..ply:Name().." accepted.")
    
    
    if OpenRequests[tonumber(arg[1])]["ply"] == ply then
        if arg[1] then
            handleCommand(ply,arg[1],true)
            return
        end
    end
end)

concommand.Add("rp_denymoney",function(ply,com,arg)
    if not ply then print("what are you doing") return end
    if not arg[1] then ply:ChatPrint("hey, don't run this from your console, buddy") return end
    AdminLog("moneyRequest(): "..ply:Name().." denied.")
    
    if OpenRequests[tonumber(arg[1])]["ply"] == ply then
        if arg[1] then
            handleCommand(ply,arg[1],false)
            return
        end
    end
end)

concommand.Add("rp_timeout",function(ply,com,arg)
    if not ply then print("what are you doing") return end
    if not arg[1] then ply:ChatPrint("hey, don't run this from your console, buddy") return end
    AdminLog("moneyRequest(): "..ply:Name().." timed out.")

    if OpenRequests[tonumber(arg[1])]["ply"] == ply then
        if arg[1] then
            handleTimeout(ply,arg[1])
            return
        end
    end
end)

print("Loaded TylerB's money e2 functions.")