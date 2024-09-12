local Alecs = require("@Alecs")

-- Custom function to run an assertion
local function EXPECT_EQ<T>(expected: T, received: T, message: string): ()
	if expected ~= received then
		error(message .. ": expected " .. tostring(expected) .. ", but got " .. tostring(received))
	else
		print("Test passed: " .. message)
	end
end

-- Test 1: Spawn Entity
local entity1 = Alecs.SpawnEntity()
EXPECT_EQ(type(entity1), "number", "Entity 1 should be a number")

local healthComponent = Alecs.CreateComponent()
Alecs.AddComponent(entity1, healthComponent, { health = 100 })

local componentData = Alecs.GetComponentData(entity1, healthComponent)
EXPECT_EQ(componentData.health, 100, "Entity 1 should have health component with 100 health")

local iterator = Alecs.Query({ healthComponent })
local queriedEntity = iterator()
EXPECT_EQ(queriedEntity, entity1, "Queried entity should be Entity 1")

Alecs.RemoveComponent(entity1, healthComponent)
local removedComponentData = Alecs.GetComponentData(entity1, healthComponent)
EXPECT_EQ(removedComponentData, nil, "Health component should be removed from Entity 1")

Alecs.DespawnEntity(entity1)
EXPECT_EQ(Alecs.Has(entity1, healthComponent), false, "Entity 1 should no longer have the health component")

local entity2 = Alecs.SpawnEntity()
Alecs.AddComponent(entity2, healthComponent, { health = 50 })

local entity3 = Alecs.SpawnEntity()
Alecs.AddComponent(entity3, healthComponent, { health = 30 })

iterator = Alecs.Query({ healthComponent })
local entitiesWithHealth = {}
for entity in iterator do
	table.insert(entitiesWithHealth, entity)
end

EXPECT_EQ(#entitiesWithHealth, 2, "There should be 2 entities with the health component")
