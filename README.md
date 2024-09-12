# Alecs

## Purpose
School Project, nothing more. And to provide a basic implementation of an ECS in [Luau](https://luau.org/)

## Note
I just want this to be as fast as possible :)

## Features
- `::SpawnEntity() -> Entity` - Spawn an entity.
- `::DespawnEntity(entity: Entity) -> ()` - Despawns the specified entity, removing all associated components.
- `::CreateComponent() -> Component` - Creates a component.
- `::SetComponent<T>(entity: Entity, component: Component, data: T) -> ()` - Assigns a component to an entity, storing the component's data.
- `::RemoveComponent(entity: Entity, component: Component) -> any` - Removes the specified component from the entity.
- `::Query(components: {Component}, strict: boolean?) -> () -> Entity?` - Returns an iterator that lazily yields entities which have the specified components.
- `::Has(entity: Entity, component: Component) -> any?` - Checks if the specified entity has the given component and retrieves its data.

## Design & Optimization Techniques
- Data-Oriented Design (DOD)
- Struct of Arrays (SoA)
- Bitwise Operations
- Archetype-based ECS
- Lazy iterator with cached archetypes

## TBA
- An actually good cache management (current: `__mode = "v"`)