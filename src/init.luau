--!native
--!optimize 2

export type Entity = number
export type Component = number
export type Archetype = number

local band, bor, bnot, lshift = bit32.band, bit32.bor, bit32.bnot, bit32.lshift

local entityArchetypes: { [Entity]: Archetype } = table.create(1000, 0)
local entityToArchetypeIndex: { [Entity]: number } = table.create(1000, 0)
local freeEntities: { Entity } = table.create(50)
local archetypeEntities: { [Archetype]: { Entity } } = {}
local archetypeEntityCounts: {[Archetype]: number} = {}
local archetypeColumns: { [Archetype]: { [Component]: { any } } } = {}
local archetypeBitmap: { number } = {}
local archetypeIds: { Archetype } = {}
local componentFrequency: { [Component]: number } = {}

local nextEntityId: Entity = 1
local nextComponentId: Component = 1
local nextArchetypeId: Archetype = 1
local componentMaskCache: { [Component]: number } = {}
local componentBits: number = 0xFFFFF
local COMPONENT_MASK: number = lshift(0b1, componentBits) - 0b1
local queryCache = setmetatable({}, { __mode = "v" }) :: typeof(setmetatable({ 1 }, { __mode = "v" }))

local Alecs = {}

function Alecs.SpawnEntity(): Entity
	local entity: Entity
	if #freeEntities > 0 then
		entity = table.remove(freeEntities) :: number
	else
		entity = nextEntityId
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
		local archetypeEntitiesArray: { Entity } = archetypeEntities[archetype]
		local index: number = entityToArchetypeIndex[entity]

		if index then
			local lastEntity = archetypeEntitiesArray[entityCount]
			archetypeEntitiesArray[index] = lastEntity
			archetypeEntitiesArray[entityCount] = nil
			archetypeEntityCounts[archetype] -= 1

			if index ~= entityCount then
				entityToArchetypeIndex[lastEntity] = index
			end

			for _, column in archetypeColumns[archetype] do
				if index ~= entityCount then
					column[index] = column[entityCount]
				end
				column[entityCount] = nil
			end
		end
	end

	entityArchetypes[entity] = 0
	entityToArchetypeIndex[entity] = 0

	table.insert(freeEntities, entity)
end

function Alecs.CreateComponent(): Component
	if nextComponentId >= lshift(0b1, componentBits) then
		componentBits *= 2
		COMPONENT_MASK = lshift(0b1, componentBits) - 0b1

		for component, _ in componentMaskCache do
			componentMaskCache[component] = lshift(0b1, component)
		end

		local newArchetypeBitmap: { number } = table.create(#archetypeBitmap)
		for i, oldBitmask in ipairs(archetypeBitmap) do
			newArchetypeBitmap[i] = band(oldBitmask, COMPONENT_MASK)
		end
		archetypeBitmap = newArchetypeBitmap
	end
	local component: Component = nextComponentId
	nextComponentId += 1

	componentMaskCache[component] = lshift(0b1, component)
	componentFrequency[component] = 0
	return component
end

function Alecs.SetComponent<T>(entity: Entity, component: Component, data: T): ()
	local oldArchetype: Archetype = entityArchetypes[entity]
	local oldBitmask = entityArchetypes[entity]
	local newBitmask: number = bor(oldBitmask, componentMaskCache[component])

	local newArchetype
	for i, mask in ipairs(archetypeBitmap) do
		if mask == newBitmask then
			newArchetype = archetypeIds[i]
			break
		end
	end
	if not newArchetype then
		newArchetype = nextArchetypeId
		nextArchetypeId += 1

		table.insert(archetypeBitmap, newBitmask)
		table.insert(archetypeIds, newArchetype)
		archetypeEntities[newArchetype] = {}
		archetypeEntityCounts[newArchetype] = 0
		archetypeColumns[newArchetype] = {}
	end

	if oldArchetype ~= newArchetype then
		local oldEntityCount = archetypeEntityCounts[oldArchetype]
		local oldIndex = entityToArchetypeIndex[entity]
		local newEntityCount = archetypeEntityCounts[newArchetype]
		archetypeEntities[newArchetype][newEntityCount + 1] = entity
		archetypeEntityCounts[newArchetype] += 1
		entityToArchetypeIndex[entity] = newEntityCount + 1
		entityArchetypes[entity] = newArchetype

		if oldArchetype ~= 0 then
			for comp, oldColumn in archetypeColumns[oldArchetype] do
				if not archetypeColumns[newArchetype][comp] then
					archetypeColumns[newArchetype][comp] = {}
				end
				local newColumn = archetypeColumns[newArchetype][comp]
				if comp ~= component then
					newColumn[newEntityCount + 1] = oldColumn[oldIndex]
				end

				if oldIndex < oldEntityCount then
					table.move(oldColumn, oldIndex + 1, oldEntityCount, oldIndex)
				end
				oldColumn[oldEntityCount] = nil
			end

			if oldIndex < oldEntityCount then
				local movedEntity = archetypeEntities[oldArchetype][oldEntityCount]
				archetypeEntities[oldArchetype][oldIndex] = movedEntity
				entityToArchetypeIndex[movedEntity] = oldIndex
			end
			archetypeEntities[oldArchetype][oldEntityCount] = nil
			archetypeEntityCounts[oldArchetype] -= 1
		end
	end

	if not archetypeColumns[newArchetype][component] then
		archetypeColumns[newArchetype][component] = {}
	end
	archetypeColumns[newArchetype][component][entityToArchetypeIndex[entity]] = data
end

function Alecs.RemoveComponent(entity: Entity, component: Component): any
	local oldArchetype: Archetype = entityArchetypes[entity]
	local oldBitmask = entityArchetypes[entity]
	local newBitmask: number = band(oldBitmask, bnot(componentMaskCache[component]))
	local newArchetype
	for i, mask in ipairs(archetypeBitmap) do
		if mask == newBitmask then
			newArchetype = archetypeIds[i]
			break
		end
	end
	if not newArchetype then
		newArchetype = nextArchetypeId
		nextArchetypeId += 1

		table.insert(archetypeBitmap, newBitmask)
		table.insert(archetypeIds, newArchetype)
		archetypeEntities[newArchetype] = {}
		archetypeEntityCounts[newArchetype] = 0
		archetypeColumns[newArchetype] = {}
	end

	local removedData = nil

	if oldArchetype ~= newArchetype then
		local oldEntityCount = archetypeEntityCounts[oldArchetype]
		local oldIndex = entityToArchetypeIndex[entity]
		local newEntityCount = archetypeEntityCounts[newArchetype]
		archetypeEntities[newArchetype][newEntityCount + 1] = entity
		archetypeEntityCounts[newArchetype] += 1
		entityToArchetypeIndex[entity] = newEntityCount + 1
		entityArchetypes[entity] = newArchetype

		for comp, oldColumn in archetypeColumns[oldArchetype] do
			if comp ~= component then
				if not archetypeColumns[newArchetype][comp] then
					archetypeColumns[newArchetype][comp] = {}
				end
				local newColumn = archetypeColumns[newArchetype][comp]
				newColumn[newEntityCount + 1] = oldColumn[oldIndex]
			else
				removedData = oldColumn[oldIndex]
			end

			if oldIndex < oldEntityCount then
				table.move(oldColumn, oldIndex + 1, oldEntityCount, oldIndex)
			end
			oldColumn[oldEntityCount] = nil
		end
		if oldIndex < oldEntityCount then
			local movedEntity = archetypeEntities[oldArchetype][oldEntityCount]
			archetypeEntities[oldArchetype][oldIndex] = movedEntity
			entityToArchetypeIndex[movedEntity] = oldIndex
		end
		archetypeEntities[oldArchetype][oldEntityCount] = nil
		archetypeEntityCounts[oldArchetype] -= 1
		componentFrequency[component] -= 1
	end

	return removedData
end

function Alecs.Query(components: { Component }, strict: boolean?): () -> (Entity, ...any)?
	local queryBitmask: number = 0
	for i = 1, #components do
		queryBitmask = bor(queryBitmask, componentMaskCache[components[i]])
	end
	if not queryCache[queryBitmask] then
		local matchingArchetypes = {}
		for i, archetypeBitmask in archetypeBitmap do
			if strict then
				if band(archetypeBitmask, queryBitmask) == queryBitmask then
					matchingArchetypes[#matchingArchetypes + 1] = archetypeIds[i]
				end
			else
				if band(archetypeBitmask, queryBitmask) ~= 0 then
					matchingArchetypes[#matchingArchetypes + 1] = archetypeIds[i]
				end
			end
		end
		queryCache[queryBitmask] = matchingArchetypes
	end

	local matchingArchetypes = queryCache[queryBitmask]
	local totalArchetypes = #matchingArchetypes
	local currentArchetypeIndex = 1
	local currentEntityIndex = 1
	
	return function(): () -> (Entity, ...any)?
		while currentArchetypeIndex <= totalArchetypes do
			local archetype = matchingArchetypes[currentArchetypeIndex]
			if currentEntityIndex <= archetypeEntityCounts[archetype] then
				local entityData = table.create(1, archetypeEntities[archetype][currentEntityIndex])
				local entity = entityData[1]
				for _, componentID in components do
					local column = archetypeColumns[entityArchetypes[entity]][componentID]
					local value = if column then column[entityToArchetypeIndex[entity]] else nil
					table.insert(entityData, value)
				end
				currentEntityIndex += 1
				return table.unpack(entityData)
			end
			currentArchetypeIndex += 1
			currentEntityIndex = 1
		end
		return nil
	end
end

function Alecs.Has(entity: Entity, component: Component): any
	local entityArchetypeIndex = entityToArchetypeIndex[entity]
	if entityArchetypeIndex == 0 then
		return nil
	end
	local column = archetypeColumns[entityArchetypeIndex][component]
	if not column then
		return nil
	end
	local index = entityToArchetypeIndex[entity]
	return column[index]
end

return Alecs