--!native
--!optimize 2

type Archetype = number
type Component = number
type Entity = number

local band, bor, bnot, lshift = bit32.band, bit32.bor, bit32.bnot, bit32.lshift

local entityArchetypes: { [Entity]: number } = table.create(1000, 0)
local entityToArchetypeIndex: { [Entity]: number } = table.create(1000, 0)
local freeEntities: { Entity } = table.create(50)
local archetypeEntities: { [Archetype]: { Entity } } = {}
local archetypeEntityCounts: { [Archetype]: number } = {}
local componentStorage: { [Component]: { [Entity]: any } } = {}
local archetypeBitmap: { [number]: Archetype } = {}

local nextEntityId: Entity = 1
local nextComponentId: Component = 1
local nextArchetypeId: Archetype = 1
local componentMaskCache: { [Component]: number } = {}
local componentBits: number = 0xFFFFF
local COMPONENT_MASK: number = lshift(0b1, componentBits) - 0b1

-- FUture implementation
--local queryCache: { [number]: { Archetype } } = {}
--local queryCacheVersion: number = 0

local Alecs = {}

local function MoveArchetype(entity: Entity, oldArchetype: Archetype, newArchetype: Archetype): ()
	if oldArchetype == newArchetype then
		return
	end

	if oldArchetype ~= 0 then
		local entityCount = archetypeEntityCounts[oldArchetype]
		local archetypeEntitiesArray = archetypeEntities[oldArchetype]
		local index = entityToArchetypeIndex[entity]

		if index then
			local lastEntity = archetypeEntitiesArray[entityCount]
			archetypeEntitiesArray[index] = lastEntity
			archetypeEntitiesArray[entityCount] = nil
			archetypeEntityCounts[oldArchetype] -= 1
			entityToArchetypeIndex[lastEntity] = index
		end
	end

	if newArchetype ~= 0 then
		archetypeEntities[newArchetype] = archetypeEntities[newArchetype] or {}
		local newCount = (archetypeEntityCounts[newArchetype] or 0) + 1
		archetypeEntities[newArchetype][newCount] = entity
		archetypeEntityCounts[newArchetype] = newCount
		entityToArchetypeIndex[entity] = newCount
	end

	entityArchetypes[entity] = newArchetype
	--queryCacheVersion += 1
	--queryCache = {}
end

function Alecs.SpawnEntity(): Entity
	local entity: Entity = table.remove(freeEntities) or nextEntityId
	if entity == nextEntityId then
		nextEntityId += 1
	end

	entityArchetypes[entity] = 0
	entityToArchetypeIndex[entity] = 0
	return entity
end

function Alecs.DespawnEntity(entity: Entity): ()
	local archetype: Archetype = entityArchetypes[entity]
	if archetype ~= 0 then
		local entityCount: number = archetypeEntityCounts[archetype]
		local archetypeEntitiesArray: {Entity} = archetypeEntities[archetype]
		local index: number = entityToArchetypeIndex[entity]

		if index then
			local lastEntity: Entity = archetypeEntitiesArray[entityCount]
			archetypeEntitiesArray[index] = lastEntity
			archetypeEntitiesArray[entityCount] = nil
			archetypeEntityCounts[archetype] -= 1
			entityToArchetypeIndex[lastEntity] = index
		end
	end

	entityArchetypes[entity] = 0
	entityToArchetypeIndex[entity] = 0

	for component, storage in componentStorage do
		storage[entity] = nil
	end

	table.insert(freeEntities, entity)
	--queryCacheVersion += 1
	--queryCache = {}
end

function Alecs.CreateComponent(): Component
	if nextComponentId >= lshift(0b1, componentBits) then
		componentBits *= 2
		COMPONENT_MASK = lshift(0b1, componentBits) - 0b1

		for component, _ in componentMaskCache do
			componentMaskCache[component] = lshift(0b1, component)
		end

		local newArchetypeBitmap: { [number]: Archetype } = {}
		for oldBitmask, archetypeId in archetypeBitmap do
			local newBitmask = band(oldBitmask, COMPONENT_MASK)
			newArchetypeBitmap[newBitmask] = archetypeId
		end
		archetypeBitmap = newArchetypeBitmap
		--queryCacheVersion += 1
		--queryCache = {}
	end
	local component: Component = nextComponentId
	nextComponentId += 1

	componentStorage[component] = {}
	componentMaskCache[component] = lshift(0b1, component)
	return component
end

function Alecs.SetComponent<T>(entity: Entity, component: Component, data: T): ()
	local oldArchetype: Archetype = entityArchetypes[entity]
	local newBitmask: number = bor(oldArchetype, componentMaskCache[component])
	local newArchetype: Archetype = archetypeBitmap[newBitmask]

	if not newArchetype then
		nextArchetypeId += 1
		newArchetype = nextArchetypeId
		archetypeBitmap[newBitmask] = newArchetype
		archetypeEntities[newArchetype] = {}
		archetypeEntityCounts[newArchetype] = 0
	end

	MoveArchetype(entity, oldArchetype, newArchetype)
	componentStorage[component][entity] = data
end

function Alecs.RemoveComponent(entity: Entity, component: Component): any
	local oldArchetype: Archetype = entityArchetypes[entity]
	local newBitmask: number = band(oldArchetype, bnot(componentMaskCache[component]))
	local newArchetype: Archetype = archetypeBitmap[newBitmask]

	if not newArchetype then
		nextArchetypeId += 1
		newArchetype = nextArchetypeId
		archetypeBitmap[newBitmask] = newArchetype
		archetypeEntities[newArchetype] = {}
		archetypeEntityCounts[newArchetype] = 0
	end
	MoveArchetype(entity, oldArchetype, newArchetype)

	local removedData = componentStorage[component][entity]
	componentStorage[component][entity] = nil
	return removedData
end

function Alecs.Query(components: { Component }, required: boolean?): () -> Entity?
	local queryBitmask: number = 0
	for i = 1, #components do
		queryBitmask = bor(queryBitmask, componentMaskCache[components[i]])
	end

	local matchingArchetypes = table.create(32)
	if required then
		for archetypeBitmask, archetypeId in archetypeBitmap do
			if band(archetypeBitmask, queryBitmask) == queryBitmask then
				table.insert(matchingArchetypes, archetypeId)
			end
		end
	else
		for archetypeBitmask, archetypeId in archetypeBitmap do
			if band(archetypeBitmask, queryBitmask) ~= 0 then
				table.insert(matchingArchetypes, archetypeId)
			end
		end
	end

	local currentArchetypeIndex = 1
	local currentEntityIndex = 1
	return function(): Entity?
		while currentArchetypeIndex <= #matchingArchetypes do
			local archetype = matchingArchetypes[currentArchetypeIndex]
			local archetypeEntitiesArray = archetypeEntities[archetype]
			local entityCount = archetypeEntityCounts[archetype]

			while currentEntityIndex <= entityCount do
				local entity = archetypeEntitiesArray[currentEntityIndex]
				currentEntityIndex += 1
				return entity
			end

			currentArchetypeIndex += 1
			currentEntityIndex = 1
		end
		return nil
	end
end

function Alecs.Has(entity: Entity, component: Component): any?
	if band(entityArchetypes[entity], componentMaskCache[component]) ~= 0b0 then
		return componentStorage[component][entity]
	end
	return nil
end

return Alecs
