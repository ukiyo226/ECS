--!native
--!optimize 2

type Archetype = number
type Component = number
type Entity = number

local band, bor, bnot, lshift = bit32.band, bit32.bor, bit32.bnot, bit32.lshift

local entityArchetypes: { [Entity]: number } = table.create(10000, 0)
local entityToArchetypeIndex: { [Entity]: number } = table.create(10000, 0)
local freeEntities: { Entity } = table.create(50)
local archetypeEntities: { [Archetype]: { Entity } } = {}
local archetypeEntityCounts: { [Archetype]: number } = {}
local componentEntities: { [Component]: { Entity } } = {}
local componentData: { [Component]: { any } } = {}
local componentEntityIndex: { [Component]: { [Entity]: number } } = {}
local archetypeBitmap: { [number]: Archetype } = {}

local nextEntityId: Entity = 1
local nextComponentId: Component = 1
local nextArchetypeId: Archetype = 1
local componentMaskCache: { [Component]: number } = {}
local componentBits: number = 0xFFFFF
local COMPONENT_MASK: number = lshift(0b1, componentBits) - 0b1

local queryCache: { [number]: { [Entity]: boolean } } = {}

local Alecs = {}

local function MoveArchetype(entity: Entity, oldArchetype: Archetype, newArchetype: Archetype): ()
	if oldArchetype == newArchetype then
		return
	end

	if oldArchetype ~= 0 then
		local entityCount: number = archetypeEntityCounts[oldArchetype]
		local archetypeEntitiesArray: {Entity} = archetypeEntities[oldArchetype]
		local index: number = entityToArchetypeIndex[entity]

		if index then
			local lastEntity: Entity = archetypeEntitiesArray[entityCount]
			archetypeEntitiesArray[index] = lastEntity
			archetypeEntitiesArray[entityCount] = nil
			archetypeEntityCounts[oldArchetype] -= 1
			entityToArchetypeIndex[lastEntity] = index
		end
	end

	if newArchetype ~= 0 then
		local newCount: number = (archetypeEntityCounts[newArchetype] or 0) + 1
		archetypeEntityCounts[newArchetype] = newCount
		archetypeEntities[newArchetype] = archetypeEntities[newArchetype] or {}
		archetypeEntities[newArchetype][newCount] = entity
		entityToArchetypeIndex[entity] = newCount
		entityArchetypes[entity] = newArchetype
	end
end

function Alecs.SpawnEntity(): Entity
	local entity: Entity = table.remove(freeEntities) or nextEntityId
	nextEntityId += 1
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

	for component, _ in componentData do
		componentEntityIndex[component][entity] = nil
	end

	table.insert(freeEntities, entity)
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
		queryCache = {}
	end
	local component: Component = nextComponentId
	nextComponentId += 1

	componentEntities[component] = {}
	componentData[component] = {}
	componentEntityIndex[component] = {}

	componentMaskCache[component] = lshift(0b1, component)
	return component
end

function Alecs.AddComponent<T>(entity: Entity, component: Component, data: T): ()
	local oldArchetype: Archetype = entityArchetypes[entity]
	local newBitmask: number = bor(entityArchetypes[entity], componentMaskCache[component])
	local newArchetype: Archetype = archetypeBitmap[newBitmask]

	if not newArchetype then
		nextArchetypeId += 1
		archetypeBitmap[newBitmask] = nextArchetypeId
		newArchetype = nextArchetypeId
		archetypeEntities[newArchetype] = {}
		archetypeEntityCounts[newArchetype] = 0
	end

	MoveArchetype(entity, oldArchetype, newArchetype)
	queryCache = {}

	local componentDataArray: { any } = componentData[component]
	local entityIndexArray: { [Entity]: number } = componentEntityIndex[component]
	local entitiesArray: { Entity } = componentEntities[component]

	local index: number = #entitiesArray + 1
	entitiesArray[index] = entity
	componentDataArray[index] = data
	entityIndexArray[entity] = index
end

function Alecs.RemoveComponent(entity: Entity, component: Component): any
	local oldArchetype: Archetype = entityArchetypes[entity]
	local newBitmask: number = band(entityArchetypes[entity], bnot(componentMaskCache[component]))
	local newArchetype: Archetype = archetypeBitmap[newBitmask]

	MoveArchetype(entity, oldArchetype, newArchetype)
	queryCache = {}

	local componentDataArray: { any } = componentData[component]
	local entityIndexArray: { [Entity]: number } = componentEntityIndex[component]
	local entitiesArray: {Entity} = componentEntities[component]

	local index: number = entityIndexArray[entity]
	local lastIndex: number = #entitiesArray
	local lastEntity: Entity = entitiesArray[lastIndex]

	entitiesArray[index] = lastEntity
	entitiesArray[lastIndex] = nil
	componentDataArray[index] = componentDataArray[lastIndex]
	componentDataArray[lastIndex] = nil
	entityIndexArray[lastEntity] = index
	entityIndexArray[entity] = nil

	return componentDataArray[index]
end

function Alecs.GetComponentData(entity: Entity, component: Component): any
	return componentData[component][componentEntityIndex[component][entity]]
end

function Alecs.Query(components: { Component }): () -> Entity?
	local uniqueComponents: { [Component]: boolean } = {}
	local queryBitmask: number = 0

	for _, component in ipairs(components) do
		if not uniqueComponents[component] then
			uniqueComponents[component] = true
			queryBitmask = bor(queryBitmask, componentMaskCache[component])
		end
	end
	local cachedEntities = queryCache[queryBitmask]
	if not cachedEntities then
		cachedEntities = {}
		queryCache[queryBitmask] = cachedEntities
	end

	local nextEntity = 1
	local entityCount = #entityArchetypes
	return function(): Entity?
		while nextEntity <= entityCount do
			local archetype = entityArchetypes[nextEntity]
			if cachedEntities[nextEntity] then
				local cached = nextEntity
				nextEntity += 1
				return cached
			elseif band(archetype, queryBitmask) == queryBitmask then
				cachedEntities[nextEntity] = true
				local result = nextEntity
				nextEntity += 1
				return result
			end
			nextEntity += 1
		end
		return nil
	end
end

function Alecs.Has(entity: Entity, component: Component): boolean
	return band(entityArchetypes[entity], componentMaskCache[component]) ~= 0b0
end

return Alecs
