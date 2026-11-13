// The missions of GHOSTGRID, as data. A mission is a row of this table and the
// maps it names (maps.v); nothing else in the game is written for one mission
// in particular. To add one: draw a map, add a `RoomDef` for it and a
// `MissionDef` row below, and raise `mission_count` and the picker's pages if
// the list outgrows ten.
//
// What a mission is, and where the game finds it out:
//
//   rooms     the maps, in order; doors (`D` onward, `U` back) join them
//   guards    each guard's route as waypoint characters of the map, and which
//             way a guard that has one waypoint stands
//   cameras   a camera on the map's `A`, `B`, `C` pillar sweeps between two angles
//   chips     every `$` of the map: the exit is shut until they are all taken
//   limit     seconds on a countdown, or 0
//   ranks     the scores that earn S, A and B (score = seconds + 5 for each
//             time seen + 15 for each alert; lower is better)
//
// `kind` is only the name the briefing gives the mission: what it asks is
// decided by what its rooms hold.
module main

import jaggame

const mission_count = 10
const max_guards = 4
const max_cams = 3
const cam_steps = 16 // positions a camera's sweep can have
const cam_turn = 8 // the angle between two of them
const cam_range = 96 // pixels a camera's cone reaches: six tiles
const cam_half = 16 // angle units either side of where it looks: 22 degrees

// Kind is what a mission is called.
enum Kind {
	sneak
	collect
	timed
	rooms
}

// guide:gg_defs
// GuardDef is a guard: the waypoints of its route (characters of the map, a
// guard goes to and fro along them in order) and, for a guard with one, the
// angle it stands facing.
struct GuardDef {
	route string
	face  int = jaggame.angle_down
}

// CameraDef is a camera's sweep: the angles it turns between.
struct CameraDef {
	from int
	to   int
}

// RoomDef is a map and what is in it.
struct RoomDef {
	map     string
	guards  []GuardDef
	cameras []CameraDef
}

// MissionDef is a mission.
struct MissionDef {
	title string // at most 8 characters
	kind  Kind
	brief string
	rooms []RoomDef
	limit int
	ranks []int
}

// guide:end

fn (k Kind) label() string {
	return match k {
		.sneak { 'SNEAK' }
		.collect { 'COLLECT' }
		.timed { 'TIMED' }
		.rooms { 'ROOMS' }
	}
}

// missions is the table.
fn missions() []MissionDef {
	// guide:gg_missions
	return [
		MissionDef{
			title: 'DEPOT'
			kind:  .sneak
			brief: 'FOUR GUARDS WALK THE DEPOT. WAIT BEHIND COVER, CROUCH WITH B, AND REACH THE GREEN PAD UNSEEN.'
			rooms: [
				RoomDef{
					map:    map_depot
					guards: [GuardDef{
						route: '12'
					}, GuardDef{
						route: '46'
					}, GuardDef{
						route: '3'
						face:  jaggame.angle_up
					}, GuardDef{
						route: '5'
						face:  jaggame.angle_left
					}]
				},
			]
			ranks: [
				9,
				18,
				30,
			]
		},
		MissionDef{
			title: 'ARCHIVE'
			kind:  .collect
			brief: 'TAKE THE THREE DATA CHIPS. THE EXIT OPENS WHEN YOU HAVE ALL OF THEM.'
			rooms: [
				RoomDef{
					map:    map_archive
					guards: [GuardDef{
						route: '12'
					}, GuardDef{
						route: '3'
						face:  jaggame.angle_up
					}]
				},
			]
			ranks: [
				18,
				40,
				64,
			]
		},
		MissionDef{
			title: 'SPRINT'
			kind:  .timed
			brief: 'BEAT THE CLOCK: THE EXIT IN FORTY SECONDS. RUNNING IS FAST, BUT GUARDS HEAR IT.'
			rooms: [
				RoomDef{
					map:    map_sprint
					guards: [GuardDef{
						route: '12'
					}, GuardDef{
						route: '3'
						face:  jaggame.angle_down
					}]
				},
			]
			limit: 40
			ranks: [
				7,
				18,
				28,
			]
		},
		MissionDef{
			title: 'ANNEX'
			kind:  .rooms
			brief: 'TWO ROOMS JOINED BY A DOOR. WHEN YOU LEAVE A ROOM ITS GUARDS GO BACK TO THEIR POSTS.'
			rooms: [
				RoomDef{
					map:    map_annex_a
					guards: [GuardDef{
						route: '12'
					}]
				},
				RoomDef{
					map:    map_annex_b
					guards: [GuardDef{
						route: '34'
					}]
				},
			]
			ranks: [
				16,
				35,
				56,
			]
		},
		MissionDef{
			title: 'VAULT'
			kind:  .sneak
			brief: 'CAMERAS SWEEP THE VAULT. THEIR LIGHT IS WHAT SEES YOU, AND COVER DOES NOT HIDE YOU FROM THEM.'
			rooms: [
				RoomDef{
					map:     map_vault
					guards:  [GuardDef{
						route: '12'
					}]
					cameras: [CameraDef{16, 112}, CameraDef{16, 112}]
				},
			]
			ranks: [
				8,
				15,
				24,
			]
		},
		MissionDef{
			title: 'STACKS'
			kind:  .collect
			brief: 'FOUR CHIPS AMONG THE SHELVES, A CAMERA OVERHEAD AND TWO GUARDS ON THE AISLES.'
			rooms: [
				RoomDef{
					map:     map_stacks
					guards:  [GuardDef{
						route: '12'
					}]
					cameras: [CameraDef{16, 112}]
				},
			]
			ranks: [
				14,
				33,
				52,
			]
		},
		MissionDef{
			title: 'DASH'
			kind:  .timed
			brief: 'A LONG HALL, A CAMERA AND A GUARD. FIFTY SECONDS.'
			rooms: [
				RoomDef{
					map:     map_dash
					guards:  [GuardDef{
						route: '12'
					}, GuardDef{
						route: '3'
						face:  jaggame.angle_left
					}]
					cameras: [CameraDef{0, 96}]
				},
			]
			limit: 50
			ranks: [
				5,
				12,
				20,
			]
		},
		MissionDef{
			title: 'CROSSING'
			kind:  .rooms
			brief: 'THE SECOND ROOM IS WATCHED BY A CAMERA. GUARDS KEEP THEIR HABITS WHEN YOU COME BACK.'
			rooms: [
				RoomDef{
					map:    map_crossing_a
					guards: [GuardDef{
						route: '12'
					}]
				},
				RoomDef{
					map:     map_crossing_b
					guards:  [GuardDef{
						route: '34'
					}]
					cameras: [CameraDef{16, 112}]
				},
			]
			ranks: [
				16,
				35,
				56,
			]
		},
		MissionDef{
			title: 'FOUNDRY'
			kind:  .sneak
			brief: 'THREE GUARDS AND TWO CAMERAS. THE LIGHT OF A CAMERA MOVES, SO WAIT FOR IT TO TURN.'
			rooms: [
				RoomDef{
					map:     map_foundry
					guards:  [GuardDef{
						route: '12'
					}, GuardDef{
						route: '4'
						face:  jaggame.angle_right
					}, GuardDef{
						route: '56'
					}]
					cameras: [CameraDef{16, 112}, CameraDef{16, 112}]
				},
			]
			ranks: [
				8,
				18,
				28,
			]
		},
		MissionDef{
			title: 'GAUNTLET'
			kind:  .timed
			brief: 'THE LAST RUN: A LONG HALL, THREE GUARDS, A CAMERA. SIXTY SECONDS.'
			rooms: [
				RoomDef{
					map:     map_gauntlet
					guards:  [GuardDef{
						route: '12'
					}, GuardDef{
						route: '3'
						face:  jaggame.angle_left
					}]
					cameras: [CameraDef{0, 96}]
				},
			]
			limit: 60
			ranks: [
				5,
				10,
				18,
			]
		},
	]
	// guide:end
}
