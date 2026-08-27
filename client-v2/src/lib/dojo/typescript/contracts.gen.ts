import { DojoProvider, type DojoCall } from "@dojoengine/core";
import { Account, AccountInterface, CairoOption, CairoCustomEnum } from "starknet";
import type { BigNumberish } from "starknet";
import type { Action } from "./models.gen";
import * as models from "./models.gen";

export function setupWorld(provider: DojoProvider) {

	const build_actions_createGame_calldata = (p2: string): DojoCall => {
		return {
			contractName: "actions",
			entrypoint: "create_game",
			calldata: [p2],
		};
	};

	const actions_createGame = async (snAccount: Account | AccountInterface, p2: string) => {
		try {
			return await provider.execute(
				snAccount,
				build_actions_createGame_calldata(p2),
				"caps",
			);
		} catch (error) {
			console.error(error);
			throw error;
		}
	};

	const build_actions_getGame_calldata = (gameId: BigNumberish): DojoCall => {
		return {
			contractName: "actions",
			entrypoint: "get_game",
			calldata: [gameId],
		};
	};

	const actions_getGame = async (gameId: BigNumberish) => {
		try {
			return await provider.call("caps", build_actions_getGame_calldata(gameId));
		} catch (error) {
			console.error(error);
			throw error;
		}
	};

	const build_actions_takeTurn_calldata = (gameId: BigNumberish, turn: Array<Action>): DojoCall => {
		return {
			contractName: "actions",
			entrypoint: "take_turn",
			calldata: [gameId, turn],
		};
	};

	const actions_takeTurn = async (snAccount: Account | AccountInterface, gameId: BigNumberish, turn: Array<Action>) => {
		try {
			return await provider.execute(
				snAccount,
				build_actions_takeTurn_calldata(gameId, turn),
				"caps",
			);
		} catch (error) {
			console.error(error);
			throw error;
		}
	};



	return {
		actions: {
			createGame: actions_createGame,
			buildCreateGameCalldata: build_actions_createGame_calldata,
			getGame: actions_getGame,
			buildGetGameCalldata: build_actions_getGame_calldata,
			takeTurn: actions_takeTurn,
			buildTakeTurnCalldata: build_actions_takeTurn_calldata,
		},
	};
}