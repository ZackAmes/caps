import { DojoProvider, DojoCall } from "@dojoengine/core";
import { Account, AccountInterface, BigNumberish, CairoOption, CairoCustomEnum } from "starknet";
import * as models from "./models.gen";

export function setupWorld(provider: DojoProvider) {

	const build_actions_createGame_calldata = (p1: string, p2: string, p1Team: BigNumberish, p2Team: BigNumberish): DojoCall => {
		return {
			contractName: "actions",
			entrypoint: "create_game",
			calldata: [p1, p2, p1Team, p2Team],
		};
	};

	const actions_createGame = async (snAccount: Account | AccountInterface, p1: string, p2: string, p1Team: BigNumberish, p2Team: BigNumberish) => {
		try {
			return await provider.execute(
				snAccount,
				build_actions_createGame_calldata(p1, p2, p1Team, p2Team),
				"caps",
			);
		} catch (error) {
			console.error(error);
			throw error;
		}
	};

	const build_actions_getCapData_calldata = (setId: BigNumberish, capType: BigNumberish): DojoCall => {
		return {
			contractName: "actions",
			entrypoint: "get_cap_data",
			calldata: [setId, capType],
		};
	};

	const actions_getCapData = async (setId: BigNumberish, capType: BigNumberish) => {
		try {
			return await provider.call("caps", build_actions_getCapData_calldata(setId, capType));
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

	const build_actions_simulateTurn_calldata = (game: models.Game, caps: Array<Cap>, effects: CairoOption<Array<Effect>>, turn: Array<Action>): DojoCall => {
		return {
			contractName: "actions",
			entrypoint: "simulate_turn",
			calldata: [game, caps, effects, turn],
		};
	};

	const actions_simulateTurn = async (game: models.Game, caps: Array<Cap>, effects: CairoOption<Array<Effect>>, turn: Array<Action>) => {
		try {
			return await provider.call("caps", build_actions_simulateTurn_calldata(game, caps, effects, turn));
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

	const build_planetelo_acceptInvite_calldata = (inviteId: BigNumberish): DojoCall => {
		return {
			contractName: "planetelo",
			entrypoint: "accept_invite",
			calldata: [inviteId],
		};
	};

	const planetelo_acceptInvite = async (snAccount: Account | AccountInterface, inviteId: BigNumberish) => {
		try {
			return await provider.execute(
				snAccount,
				build_planetelo_acceptInvite_calldata(inviteId),
				"planetelo",
			);
		} catch (error) {
			console.error(error);
			throw error;
		}
	};

	const build_planetelo_createMatch_calldata = (p1: string, p2: string, playlistId: BigNumberish): DojoCall => {
		return {
			contractName: "planetelo",
			entrypoint: "create_match",
			calldata: [p1, p2, playlistId],
		};
	};

	const planetelo_createMatch = async (snAccount: Account | AccountInterface, p1: string, p2: string, playlistId: BigNumberish) => {
		try {
			return await provider.execute(
				snAccount,
				build_planetelo_createMatch_calldata(p1, p2, playlistId),
				"planetelo",
			);
		} catch (error) {
			console.error(error);
			throw error;
		}
	};

	const build_planetelo_declineInvite_calldata = (inviteId: BigNumberish): DojoCall => {
		return {
			contractName: "planetelo",
			entrypoint: "decline_invite",
			calldata: [inviteId],
		};
	};

	const planetelo_declineInvite = async (snAccount: Account | AccountInterface, inviteId: BigNumberish) => {
		try {
			return await provider.execute(
				snAccount,
				build_planetelo_declineInvite_calldata(inviteId),
				"planetelo",
			);
		} catch (error) {
			console.error(error);
			throw error;
		}
	};

	const build_planetelo_getAgentGames_calldata = (): DojoCall => {
		return {
			contractName: "planetelo",
			entrypoint: "get_agent_games",
			calldata: [],
		};
	};

	const planetelo_getAgentGames = async () => {
		try {
			return await provider.call("planetelo", build_planetelo_getAgentGames_calldata());
		} catch (error) {
			console.error(error);
			throw error;
		}
	};

	const build_planetelo_getPlayerCustomGames_calldata = (address: string): DojoCall => {
		return {
			contractName: "planetelo",
			entrypoint: "get_player_custom_games",
			calldata: [address],
		};
	};

	const planetelo_getPlayerCustomGames = async (address: string) => {
		try {
			return await provider.call("planetelo", build_planetelo_getPlayerCustomGames_calldata(address));
		} catch (error) {
			console.error(error);
			throw error;
		}
	};

	const build_planetelo_getPlayerGameId_calldata = (address: string): DojoCall => {
		return {
			contractName: "planetelo",
			entrypoint: "get_player_game_id",
			calldata: [address],
		};
	};

	const planetelo_getPlayerGameId = async (address: string) => {
		try {
			return await provider.call("planetelo", build_planetelo_getPlayerGameId_calldata(address));
		} catch (error) {
			console.error(error);
			throw error;
		}
	};

	const build_planetelo_getPlayerInvites_calldata = (address: string): DojoCall => {
		return {
			contractName: "planetelo",
			entrypoint: "get_player_invites",
			calldata: [address],
		};
	};

	const planetelo_getPlayerInvites = async (address: string) => {
		try {
			return await provider.call("planetelo", build_planetelo_getPlayerInvites_calldata(address));
		} catch (error) {
			console.error(error);
			throw error;
		}
	};

	const build_planetelo_getPlayerStats_calldata = (address: string): DojoCall => {
		return {
			contractName: "planetelo",
			entrypoint: "get_player_stats",
			calldata: [address],
		};
	};

	const planetelo_getPlayerStats = async (address: string) => {
		try {
			return await provider.call("planetelo", build_planetelo_getPlayerStats_calldata(address));
		} catch (error) {
			console.error(error);
			throw error;
		}
	};

	const build_planetelo_getPlayerTeam_calldata = (address: string): DojoCall => {
		return {
			contractName: "planetelo",
			entrypoint: "get_player_team",
			calldata: [address],
		};
	};

	const planetelo_getPlayerTeam = async (address: string) => {
		try {
			return await provider.call("planetelo", build_planetelo_getPlayerTeam_calldata(address));
		} catch (error) {
			console.error(error);
			throw error;
		}
	};

	const build_planetelo_getResult_calldata = (sessionId: BigNumberish): DojoCall => {
		return {
			contractName: "planetelo",
			entrypoint: "get_result",
			calldata: [sessionId],
		};
	};

	const planetelo_getResult = async (sessionId: BigNumberish) => {
		try {
			return await provider.call("planetelo", build_planetelo_getResult_calldata(sessionId));
		} catch (error) {
			console.error(error);
			throw error;
		}
	};

	const build_planetelo_invite_calldata = (player2: string): DojoCall => {
		return {
			contractName: "planetelo",
			entrypoint: "invite",
			calldata: [player2],
		};
	};

	const planetelo_invite = async (snAccount: Account | AccountInterface, player2: string) => {
		try {
			return await provider.execute(
				snAccount,
				build_planetelo_invite_calldata(player2),
				"planetelo",
			);
		} catch (error) {
			console.error(error);
			throw error;
		}
	};

	const build_planetelo_playAgent_calldata = (): DojoCall => {
		return {
			contractName: "planetelo",
			entrypoint: "play_agent",
			calldata: [],
		};
	};

	const planetelo_playAgent = async (snAccount: Account | AccountInterface) => {
		try {
			return await provider.execute(
				snAccount,
				build_planetelo_playAgent_calldata(),
				"planetelo",
			);
		} catch (error) {
			console.error(error);
			throw error;
		}
	};

	const build_planetelo_selectTeam_calldata = (team: BigNumberish): DojoCall => {
		return {
			contractName: "planetelo",
			entrypoint: "select_team",
			calldata: [team],
		};
	};

	const planetelo_selectTeam = async (snAccount: Account | AccountInterface, team: BigNumberish) => {
		try {
			return await provider.execute(
				snAccount,
				build_planetelo_selectTeam_calldata(team),
				"planetelo",
			);
		} catch (error) {
			console.error(error);
			throw error;
		}
	};

	const build_planetelo_settleAgentGame_calldata = (): DojoCall => {
		return {
			contractName: "planetelo",
			entrypoint: "settle_agent_game",
			calldata: [],
		};
	};

	const planetelo_settleAgentGame = async (snAccount: Account | AccountInterface) => {
		try {
			return await provider.execute(
				snAccount,
				build_planetelo_settleAgentGame_calldata(),
				"planetelo",
			);
		} catch (error) {
			console.error(error);
			throw error;
		}
	};

	const build_planetelo_settleCustomGame_calldata = (gameId: BigNumberish): DojoCall => {
		return {
			contractName: "planetelo",
			entrypoint: "settle_custom_game",
			calldata: [gameId],
		};
	};

	const planetelo_settleCustomGame = async (snAccount: Account | AccountInterface, gameId: BigNumberish) => {
		try {
			return await provider.execute(
				snAccount,
				build_planetelo_settleCustomGame_calldata(gameId),
				"planetelo",
			);
		} catch (error) {
			console.error(error);
			throw error;
		}
	};

	const build_planetelo_settleMatch_calldata = (matchId: BigNumberish): DojoCall => {
		return {
			contractName: "planetelo",
			entrypoint: "settle_match",
			calldata: [matchId],
		};
	};

	const planetelo_settleMatch = async (snAccount: Account | AccountInterface, matchId: BigNumberish) => {
		try {
			return await provider.execute(
				snAccount,
				build_planetelo_settleMatch_calldata(matchId),
				"planetelo",
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
			getCapData: actions_getCapData,
			buildGetCapDataCalldata: build_actions_getCapData_calldata,
			getGame: actions_getGame,
			buildGetGameCalldata: build_actions_getGame_calldata,
			simulateTurn: actions_simulateTurn,
			buildSimulateTurnCalldata: build_actions_simulateTurn_calldata,
			takeTurn: actions_takeTurn,
			buildTakeTurnCalldata: build_actions_takeTurn_calldata,
		},
		planetelo: {
			acceptInvite: planetelo_acceptInvite,
			buildAcceptInviteCalldata: build_planetelo_acceptInvite_calldata,
			createMatch: planetelo_createMatch,
			buildCreateMatchCalldata: build_planetelo_createMatch_calldata,
			declineInvite: planetelo_declineInvite,
			buildDeclineInviteCalldata: build_planetelo_declineInvite_calldata,
			getAgentGames: planetelo_getAgentGames,
			buildGetAgentGamesCalldata: build_planetelo_getAgentGames_calldata,
			getPlayerCustomGames: planetelo_getPlayerCustomGames,
			buildGetPlayerCustomGamesCalldata: build_planetelo_getPlayerCustomGames_calldata,
			getPlayerGameId: planetelo_getPlayerGameId,
			buildGetPlayerGameIdCalldata: build_planetelo_getPlayerGameId_calldata,
			getPlayerInvites: planetelo_getPlayerInvites,
			buildGetPlayerInvitesCalldata: build_planetelo_getPlayerInvites_calldata,
			getPlayerStats: planetelo_getPlayerStats,
			buildGetPlayerStatsCalldata: build_planetelo_getPlayerStats_calldata,
			getPlayerTeam: planetelo_getPlayerTeam,
			buildGetPlayerTeamCalldata: build_planetelo_getPlayerTeam_calldata,
			getResult: planetelo_getResult,
			buildGetResultCalldata: build_planetelo_getResult_calldata,
			invite: planetelo_invite,
			buildInviteCalldata: build_planetelo_invite_calldata,
			playAgent: planetelo_playAgent,
			buildPlayAgentCalldata: build_planetelo_playAgent_calldata,
			selectTeam: planetelo_selectTeam,
			buildSelectTeamCalldata: build_planetelo_selectTeam_calldata,
			settleAgentGame: planetelo_settleAgentGame,
			buildSettleAgentGameCalldata: build_planetelo_settleAgentGame_calldata,
			settleCustomGame: planetelo_settleCustomGame,
			buildSettleCustomGameCalldata: build_planetelo_settleCustomGame_calldata,
			settleMatch: planetelo_settleMatch,
			buildSettleMatchCalldata: build_planetelo_settleMatch_calldata,
		},
	};
}