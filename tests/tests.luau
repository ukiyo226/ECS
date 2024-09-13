local Alecs = require("@Alecs")
local function EXPECT_EQ<T>(expected: T, received: T, message: string): ()
    if expected ~= received then
        error(message .. ": expected " .. tostring(expected) .. ", but got " .. tostring(received))
    else
        print("Test passed")
    end
end

local entity1 = Alecs.SpawnEntity()
EXPECT_EQ(typeof(entity1), "number", "Entity 1 should be a number")

local healthComponent = Alecs.CreateComponent()
Alecs.SetComponent(entity1, healthComponent, { health = 100 })

local componentData = Alecs.Has(entity1, healthComponent)
EXPECT_EQ(componentData.health, 100, "Entity 1 should have health component with 100 health")

local iterator = Alecs.Query({ healthComponent })
local queriedEntity = iterator()
EXPECT_EQ(queriedEntity, entity1, "Queried entity should be Entity 1")

Alecs.RemoveComponent(entity1, healthComponent)
local removedComponentData = Alecs.Has(entity1, healthComponent)
EXPECT_EQ(nil, removedComponentData, "Health component should be removed from Entity 1")

Alecs.DespawnEntity(entity1)
EXPECT_EQ(nil, Alecs.Has(entity1, healthComponent), "Entity 1 should no longer exist")

local entity2 = Alecs.SpawnEntity()
Alecs.SetComponent(entity2, healthComponent, { health = 50 })

local entity3 = Alecs.SpawnEntity()
Alecs.SetComponent(entity3, healthComponent, { health = 30 })

local entitiesWithHealth = {}
iterator = Alecs.Query({ healthComponent })

for entity in iterator do
    table.insert(entitiesWithHealth, entity)
end

EXPECT_EQ(#entitiesWithHealth, 2, "There should be 2 entities with the health component")

iterator = Alecs.Query({ healthComponent })
for entity, health, nonExistingComponent in iterator do
    table.insert(entitiesWithHealth, entity)
    if entity == entity2 then
        EXPECT_EQ(50, health.health, "Entity 2 should have 50 health")
    end
    if entity == entity3 then
        EXPECT_EQ(30, health.health, "Entity 3 should have 50 health")
    end
    EXPECT_EQ(nonExistingComponent, nil, "This component should be nil")
end