-- KAPUT

local Vector = Vector
local IsValid = IsValid
local Material = Material

local render = render
local math = math

local hook_Add = hook.Add

local ents_FindByClass = ents.FindByClass

local math_sin = math.sin
local math_abs = math.abs
local math_min = math.min

local SERVER = SERVER

local MATERIAL_FOG_LINEAR = 1

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"

ENT.Editable = true
ENT.PrintName		= "Mesh Water"
ENT.Author			= "Ty4a"
ENT.Instructions	= "Do you have any ideas where I can use this?"
ENT.Spawnable = true

local posplus = Vector(0, 0, 30)
local pospluss = Vector(0, 0, 50)

function ENT:SetupDataTables()

	self:NetworkVar( "Vector", 0, "BoxSize", { KeyName = "size", Edit = { type = "Vector", order = 1 } } )

    -- Experimental optimization zone
    if CLIENT then
		self:NetworkVarNotify( "BoxSize", self.CLOptBoxSize )
    else
        self:NetworkVarNotify( "BoxSize", self.SVOptBoxSize )
    end

end

local DEFVEC = Vector(400, 400, 200)

function ENT:Initialize()
    if SERVER then
        self:SetModel("models/hunter/misc/sphere025x025.mdl")
        self:SetSolid(SOLID_VPHYSICS)
        self:SetCollisionGroup(COLLISION_GROUP_WORLD)

        self:SetBoxSize( DEFVEC )

        self.SVBoxSize = DEFVEC
    else
        local obb = Vector(200, 200, 50)
        self:SetRenderBounds(-obb, obb)

        self.СLBoxSize = DEFVEC
    end
end

function ENT:SpawnFunction( ply, tr, ClassName )

	if ( !tr.Hit ) then return end

	local SpawnPos = tr.HitPos + tr.HitNormal * 48

	local ent = ents.Create( ClassName )
	ent:SetPos( SpawnPos )
    ent:SetAngles( Angle(0, 0, 180) )
	ent:Spawn()
	ent:Activate()

	return ent

end

local function inWater(pos)
    local entities = ents_FindByClass("ent_watermesh")
    for i=1, #entities do
        local ent = entities[i]
        local entpos = ent:GetPos()
        local size = ent.SVBoxSize or ent.СLBoxSize
        if !size then return end
        
        local sizex, sizey, sizez = size.x, size.y, size.z

        local min = entpos - Vector(sizex, sizey, 0)
        local max = entpos + Vector(sizex, sizey, -sizez)

        if pos:WithinAABox(min, max) then
            return true --return pos:WithinAABox(min, max)
        end
    end
    return false
end

local meta = FindMetaTable("Entity")
local OldWaterLevel = meta.WaterLevel

function meta:WaterLevel()
    local pos = self:GetPos() + pospluss
    return inWater(pos) and 3 or OldWaterLevel(self)
end

/*
local meta = FindMetaTable("NavArea")

function meta:IsUnderwater()
...
end
*/

-- https://steamcommunity.com/id/NotSoKodya/ Swim Code
hook_Add("CalcMainActivity", "WATERMESH_Act", function(ply)
    if ply:IsOnGround() or ply:InVehicle() then return end

    local pos = ply:GetPos() + posplus
    if !inWater(pos) then return end

    return ACT_MP_SWIM, -1
end)

local sv_gravity = GetConVar("sv_gravity")
hook_Add("Move", "WATERMESH_Movement", function(ply, move)
    if !inWater(ply:GetPos() + posplus) then return end

    local frametime = FrameTime()
    local maxspeed = ply:GetMaxSpeed()

	local vel = move:GetVelocity()
	local ang = move:GetMoveAngles()

	local acel = (ang:Forward() * move:GetForwardSpeed()) + (ang:Right() * move:GetSideSpeed()) + (ang:Up() * move:GetUpSpeed())

	local aceldir = acel:GetNormalized()
	local acelspeed = math_min(acel:Length(), maxspeed)
	acel = aceldir * acelspeed * 2

	if bit.band(move:GetButtons(), IN_JUMP) ~= 0 then
	    acel.z = acel.z + maxspeed
	end

	vel = vel + acel * frametime
	vel = vel * (1 - frametime * 2)

	local pgrav = ply:GetGravity() == 0 and 1 or ply:GetGravity()
	local gravity = pgrav * sv_gravity:GetFloat() * 0.5
	vel.z = vel.z + frametime * gravity

	move:SetVelocity(vel * 0.99)
end)

hook_Add("FinishMove", "WATERMESH_MovementF", function(ply, move)
    if !inWater(ply:GetPos() + posplus) then return end

    local vel = move:GetVelocity()
    local pgrav = ply:GetGravity()
    local gravity = (pgrav == 0 and 1 or pgrav) * sv_gravity:GetFloat() * 0.5

    vel.z = vel.z + FrameTime() * gravity
    move:SetVelocity(vel)
end)

hook_Add("PlayerFootstep", "WATERMESH_SndFoot", function(ply, pos, foot, sound, volume, rf)
    if !inWater(ply:GetPos()) then return end

    ply:EmitSound(foot == 0 and "Water.StepLeft" or "Water.StepRight", nil, nil, volume, CHAN_BODY)
    return true
end )

/*hook_Add( "OnDamagedByExplosion", "WATERMESH_BarrelFuck", function(ply)
	return !inWater(ply:GetPos())
end )*/

if SERVER then
    local obb = {}
    local wmat = {
        ["floating_metal_barrel"] = true,
        ["wood"] = true,
        ["wood_crate"] = true,
        ["wood_furniture"] = true,
        ["rubbertire"] = true,
        ["wood_solid"] = true,
        ["plastic"] = true,
        ["watermelon"] = true,
        ["default"] = true,
        ["cardboard"] = true,
        ["paper"] = true,
        ["popcan"] = true,
        ["plastic_barrel"] = true
    }

    hook_Add("GetFallDamage", "WATERMESH_FallDMG", function(ply, speed)
        local pos = ply:GetPos()
        local tr = util.TraceHull({
            start = pos,
            endpos = pos + ply:GetVelocity(),
            maxs = ply:OBBMaxs(),
            mins = ply:OBBMins(),
            filter = ply
        })

        if tr.Hit and inWater(tr.HitPos) then return 0 end
    end)

    hook_Add( "EntityTakeDamage", "WATERMESH_BarrelFuck", function(ply, dmginfo)
        return !inWater(ply:GetPos()) and dmginfo:IsExplosionDamage()
    end )

    function ENT:Think()
        local waterHeight = self:GetPos().z
        local entities = ents_FindByClass("prop_*")

        for i=1, #entities do
            local prop = entities[i]

            local phys = prop:GetPhysicsObject()
            if !IsValid(phys) or phys:IsAsleep() then continue end

            local is_airboat = prop:GetClass() == "prop_vehicle_airboat"
            if !wmat[phys:GetMaterial()] and !is_airboat then continue end

            local proppos = prop:GetPos()
            if inWater(proppos) and prop:IsOnFire() then prop:Extinguish() end

            local mins, maxs = prop:OBBMins(), prop:OBBMaxs()
            local minsx, maxsx = mins.x, maxs.x
            local minsy, maxsy = mins.y, maxs.y
            local minsz, maxsz = mins.z, maxs.z
            local propZ = proppos.z - 1

            if (propZ - math_abs(minsz) > waterHeight) and (propZ - math_abs(maxsz) > waterHeight) then continue end

            if is_airboat then 
                mins, maxs = mins * 0.5, maxs * 0.5
                mins.z, maxs.z = 0, 0
            end

            obb = {
                prop:LocalToWorld(Vector(minsx, minsy, minsz)),
                prop:LocalToWorld(Vector(minsx, minsy, maxsz)),
                prop:LocalToWorld(Vector(minsx, maxsy, minsz)),
                prop:LocalToWorld(Vector(maxsx, minsy, minsz)),
                prop:LocalToWorld(Vector(minsx, maxsy, maxsz)),
                prop:LocalToWorld(Vector(maxsx, maxsy, minsz)),
                prop:LocalToWorld(Vector(maxsx, minsy, maxsz)),
                prop:LocalToWorld(Vector(maxsx, maxsy, maxsz))
            }

            local vel = phys:GetVelocity()
            local angvel = phys:GetAngleVelocity()

            local prop_inwater = false
            local mass = phys:GetMass()

            local plusf = is_airboat and 0.75 or 0.2
            local plusd = is_airboat and -0.001 or -0.003

            for j=1, #obb do
                local pos = obb[j]

                if inWater(pos) then
                    local force = Vector(0, 0, mass * math_min((waterHeight - pos.z) * (plusf), is_airboat and 2 or 3))

                    phys:ApplyForceOffset(force, pos)
                    phys:ApplyForceCenter(mass * vel * (plusd))

                    phys:AddAngleVelocity(angvel * -0.01)
                    prop_inwater = true
                end
            end

            if prop_inwater then
                local should_sleep = proppos.z > waterHeight - 30 and (vel + angvel):LengthSqr() < 1 and !prop:IsPlayerHolding()

                if should_sleep then phys:Sleep() end
            end
        end

        self:NextThink(CurTime() + 0.01)
        return true
    end

    function ENT:SVOptBoxSize( varname, oldvalue, newvalue )

        if ( oldvalue == newvalue ) then return end

        self.SVBoxSize = newvalue

    end
end

if SERVER then return end

local function generateUV(vertices, scale)

    local function calculateUV(vertex, normal)
        vertex.u = vertex.pos.x * scale
        vertex.v = vertex.pos.y * scale
    end

    for i = 1, #vertices - 2, 2 do
        local a, b, c = vertices[i], vertices[i + 1], vertices[i + 2]

        local apos = a.pos

        local normal = (b.pos - apos):Cross(c.pos - apos):GetNormalized()

        calculateUV(a, normal)
        calculateUV(b, normal)
        calculateUV(c, normal)
    end

    return vertices
end

local function generateNormals(vertices)
    local v = vector_origin
    local cross = v.cross or v.Cross
    local normalize = v.normalize or v.Normalize
    local dot = v.dot or v.Dot
    local add = v.add or v.Add
    local div = v.div or v.Div
    local org = cross

    cross = function(a, b)
        return org(b, a)
    end
    
    for i = 1, #vertices - 2, 3 do
        local a, b, c = vertices[i], vertices[i + 1], vertices[i + 2]

        local apos = a.pos
        local norm = cross(b.pos - apos, c.pos - apos)
        normalize(norm)
        
        a.normal = norm
        b.normal = norm
        c.normal = norm
    end

end

function ENT:GenerateMesh()
    if self.RENDER_MESH then self.RENDER_MESH:Destroy() end
    self.RENDER_MESH = Mesh()

    local verts = {}
    local curtime = CurTime()

    local size = self.СLBoxSize

    local xx = (size.x * 2) / 7
    local yy = (size.y * 2) / 7

    for x = 0, 6 do
        for y = 0, 6 do 
            local xPos = -size.x + x * xx
            local yPos = -size.y + y * yy

            local zPos1 = math_sin(curtime + (x + 0) * 0.3 + (y + 0) * 0.3) * 10
            local zPos2 = math_sin(curtime + (x + 1) * 0.3 + (y + 0) * 0.3) * 10
            local zPos3 = math_sin(curtime + (x + 1) * 0.3 + (y + 1) * 0.3) * 10
            local zPos4 = math_sin(curtime + (x + 0) * 0.3 + (y + 1) * 0.3) * 10

            local v1 = { pos = Vector(xPos, yPos, zPos1) }
            local v2 = { pos = Vector(xPos + xx, yPos, zPos2) }
            local v3 = { pos = Vector(xPos + xx, yPos + yy, zPos3) }
            local v4 = { pos = Vector(xPos, yPos + yy, zPos4) }

            verts[#verts + 1] = v1
            verts[#verts + 1] = v2
            verts[#verts + 1] = v3

            verts[#verts + 1] = v1
            verts[#verts + 1] = v3
            verts[#verts + 1] = v4
        end
    end

    generateNormals(verts)
    generateUV(verts, 1 / 50)

    self.RENDER_MESH:BuildFromTriangles(verts)
end


local mat = Material("models/wireframe")

function ENT:GetRenderMesh()
    self:GenerateMesh()
    if !self.RENDER_MESH then return end
    return { Mesh = self.RENDER_MESH, Material = mat }
end

local GripMaterial = Material( "sprites/grip" )
local GripMaterialHover = Material( "sprites/grip_hover" )
local color_gwater = Color(0, 255, 255)
local angnull = Angle()

function ENT:Draw()
    self:DrawModel()

    if GetConVarNumber("cl_draweffectrings") == 0 then return end

    local ply = LocalPlayer()
    local wep = ply:GetActiveWeapon()
    if !IsValid(wep) then return end

    local weapon_name = wep:GetClass()
    if weapon_name ~= "weapon_physgun" and weapon_name ~= "gmod_tool" then
        return
    end

    if self:BeingLookedAtByLocalPlayer() then
        render.SetMaterial(GripMaterialHover)
    else
        render.SetMaterial(GripMaterial)
    end

    local selfpos = self:GetPos()
    render.DrawSprite(selfpos, 16, 16, color_white)

    local size = self.СLBoxSize
    local sizex, sizey = size.x, size.y

    local min = selfpos - Vector(sizex, sizey, 0)
    local max = selfpos + Vector(sizex, sizey, -size.z)

    render.DrawWireframeBox(selfpos, angnull, min - selfpos, max - selfpos, color_gwater, true)
end

function ENT:CLOptBoxSize( varname, oldvalue, newvalue )

    if ( oldvalue == newvalue ) then return end

    self.СLBoxSize = newvalue
    self:SetRenderBounds(-newvalue, newvalue)

end

hook_Add("SetupWorldFog", "WATERMESH_Fog", function()
    local ply = LocalPlayer()

    local pos = ply:GetPos() + pospluss

    if !inWater(pos) then return end

    render.FogMode( MATERIAL_FOG_LINEAR )
    render.FogStart( 0 )
    render.FogEnd( 3000 )
    render.FogMaxDensity( 0.9 )

    render.FogColor( 0, 150, 150 )

    return true
end)

hook_Add("SetupSkyboxFog", "WATERMESH_FogS", function(s)
    local ply = LocalPlayer()

    local pos = ply:GetPos() + pospluss
    if !inWater(pos) then return end

    render.FogMode( MATERIAL_FOG_LINEAR )
    render.FogStart( 0 )
    render.FogEnd( 3000 * s )
    render.FogMaxDensity( 0.9 )

    render.FogColor( 0, 150, 150 )

    return true
end)

local changedWater = false
hook_Add("RenderScreenspaceEffects", "WATERMESH_Effect", function()
    local ply = LocalPlayer()
    local pos = ply:GetPos() + pospluss
    local isInWater = inWater(pos)

    if isInWater != changedWater then
        changedWater = !changedWater
        local dsp = changedWater and 14 or 0
        
        ply:EmitSound("Physics.WaterSplash")
        ply:SetDSP(dsp, true)

        if changedWater then
            DrawMaterialOverlay("effects/water_warp01", 0.1)

            local effectdata = EffectData()
            effectdata:SetScale(15)
            effectdata:SetOrigin(pos)
            util.Effect("watersplash", effectdata)
        end
    end

    if changedWater then
        DrawMaterialOverlay("effects/water_warp01", 0.1)
    end
end)
