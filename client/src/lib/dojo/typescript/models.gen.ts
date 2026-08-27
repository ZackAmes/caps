import type { SchemaType as ISchemaType } from "@dojoengine/sdk";

import { CairoCustomEnum } from 'starknet';
import type { BigNumberish } from 'starknet';

// Type definition for `caps::models::cap::Cap` struct
export interface Cap {
	id: BigNumberish;
	owner: BigNumberish;
	cap_type: BigNumberish;
	location: LocationEnum;
	health: BigNumberish;
}

// Type definition for `caps::models::game::Game` struct
export interface Game {
	id: BigNumberish;
	player1: BigNumberish;
	player2: BigNumberish;
	turn_count: BigNumberish;
	over: boolean;
	winner: BigNumberish;
	caps_ids: Array<BigNumberish>;
	last_action_timestamp: BigNumberish;
}

// Type definition for `caps::models::game::Global` struct
export interface Global {
	key: BigNumberish;
	games_counter: BigNumberish;
	cap_counter: BigNumberish;
}

// Type definition for `caps::models::game::Vec2` struct
export interface Vec2 {
	x: BigNumberish;
	y: BigNumberish;
}

// Type definition for `caps::models::game::Action` struct
export interface Action {
	cap_id: BigNumberish;
	action_type: ActionTypeEnum;
}

// Type definition for `caps::models::cap::Location` enum
export const location = [
	'Bench',
	'Board',
	'Dead',
] as const;
export type Location = { 
	Bench: string,
	Board: Vec2,
	Dead: string,
};
export type LocationEnum = CairoCustomEnum;

// Type definition for `caps::models::game::ActionType` enum
export const actionType = [
	'Play',
	'Move',
	'Attack',
] as const;
export type ActionType = { 
	Play: Vec2,
	Move: Vec2,
	Attack: Vec2,
};
export type ActionTypeEnum = CairoCustomEnum;

export interface SchemaType extends ISchemaType {
	caps: {
		Cap: Cap,
		Game: Game,
		Global: Global,
		Vec2: Vec2,
		Action: Action,
	},
}
export const schema: SchemaType = {
	caps: {
		Cap: {
			id: 0,
			owner: 0,
			cap_type: 0,
		location: new CairoCustomEnum({ 
					Bench: "",
				Board: undefined,
				Dead: undefined, }),
			health: 0,
		},
		Game: {
			id: 0,
			player1: 0,
			player2: 0,
			turn_count: 0,
			over: false,
			winner: 0,
			caps_ids: [0],
			last_action_timestamp: 0,
		},
		Global: {
			key: 0,
			games_counter: 0,
			cap_counter: 0,
		},
		Vec2: {
			x: 0,
			y: 0,
		},
		Action: {
			cap_id: 0,
		action_type: new CairoCustomEnum({ 
				Play: { x: 0, y: 0, },
				Move: undefined,
				Attack: undefined, }),
		},
	},
};
export enum ModelsMapping {
	Cap = 'caps-Cap',
	Location = 'caps-Location',
	Game = 'caps-Game',
	Global = 'caps-Global',
	Vec2 = 'caps-Vec2',
	Action = 'caps-Action',
	ActionType = 'caps-ActionType',
}