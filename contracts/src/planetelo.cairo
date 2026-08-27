use starknet::ContractAddress;

//planetelo 1on1 interface
#[starknet::interface]
pub trait IOneOnOne<TState> {
    fn create_match(
        ref self: TState, p1: ContractAddress, p2: ContractAddress, playlist_id: u128,
    ) -> u128;
    fn settle_match(ref self: TState, match_id: u128) -> Status;
}

#[derive(Drop, Serde)]
pub enum Status {
    None,
    Active,
    Draw,
    Winner: ContractAddress,
}

#[derive(Drop, Serde, Introspect)]
#[dojo::model]
pub struct GlobalStats {
    #[key]
    id: u8,
    games_played: u64,
    custom_game_counter: u128,
}

#[derive(Drop, Serde, Introspect)]
#[dojo::model]
pub struct AgentGames {
    #[key]
    id: u8,
    game_ids: Array<u128>,
    address: ContractAddress,
    wins: u8,
    losses: u8,
}

#[derive(Drop, Serde, Introspect)]
#[dojo::model]
pub struct Player {
    #[key]
    address: ContractAddress,
    in_game: bool,
    game_id: u128,
    agent_wins: u8,
    agent_losses: u8,
    team: u16,
    custom_game_ids: Array<u128>,
}

#[derive(Drop, Serde, Introspect)]
#[dojo::model]
pub struct CustomGames {
    #[key]
    id: u128,
    player1: ContractAddress,
    player2: ContractAddress,
    game_id: u128,
}

#[starknet::interface]
trait IPlanetelo<T> {
    fn get_result(self: @T, session_id: u32) -> (bool, ContractAddress);
    fn play_agent(ref self: T) -> u128;
    fn settle_agent_game(ref self: T);
    fn get_agent_games(self: @T) -> Array<u128>;
    fn get_player_game_id(self: @T, address: ContractAddress) -> u128;
    fn select_team(ref self: T, team: u16);
    fn invite(ref self: T, player2: ContractAddress);
    fn get_player_invites(self: @T, address: ContractAddress) -> Array<u128>;
    fn get_player_custom_games(self: @T, address: ContractAddress) -> Array<CustomGames>;
    fn accept_invite(ref self: T, invite_id: u128);
    fn decline_invite(ref self: T, invite_id: u128);
    fn settle_custom_game(ref self: T, game_id: u128);
    fn get_player_stats(self: @T, address: ContractAddress) -> (u8, u8);
    fn get_player_team(self: @T, address: ContractAddress) -> u16;
}

#[dojo::contract]
mod planetelo {
    use super::{IPlanetelo, Status, IOneOnOne, AgentGames, Player, GlobalStats, CustomGames};
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use dojo::world::{WorldStorage, WorldStorageTrait};
    use dojo::model::{ModelStorage};

    use caps::models::game::{Game, GameTrait};
    use caps::systems::actions::{IActionsDispatcher, IActionsDispatcherTrait};


    fn dojo_init(ref self: ContractState, address: ContractAddress) {
        let mut world = self.world(@"planetelo");
        let mut agent_games: AgentGames = world.read_model(0);
        agent_games.address = address;
        world.write_model(@agent_games);
    }


    #[abi(embed_v0)]
    impl PlaneteloInterfaceImpl of IPlanetelo<ContractState> {
        fn get_result(self: @ContractState, session_id: u32) -> (bool, ContractAddress) {
            let mut world: WorldStorage = self.world(@"caps");
            let game: Game = world.read_model(session_id);
            let (over, winner) = @game.check_over(@world);
            if *over {
                return (*over, *winner);
            }
            return (false, 0.try_into().unwrap());
        }

        fn play_agent(ref self: ContractState) -> u128 {
            let _caps_world = self.world(@"caps");
            let mut world = self.world(@"planetelo");
            let mut player: Player = world.read_model(get_caller_address());
            assert!(!player.in_game, "You are already in a game");
            let mut agent_games: AgentGames = world.read_model(0);
            let dispatcher: IActionsDispatcher = IActionsDispatcher {
                contract_address: _caps_world.dns_address(@"actions").unwrap(),
            };

            let mut agent_team = (get_block_timestamp() % 4).try_into().unwrap();
            if agent_team == player.team {
                agent_team = (agent_team + 1) % 4;
            }
            let player_team = player.team;
            let id: u128 = dispatcher
                .create_game(get_caller_address(), agent_games.address, player_team, agent_team)
                .into();

            agent_games.game_ids.append(id);
            world.write_model(@agent_games);
            player.in_game = true;
            player.game_id = id;
            world.write_model(@player);

            id
        }

        fn settle_agent_game(ref self: ContractState) {
            let caps_world = self.world(@"caps");
            let mut world = self.world(@"planetelo");

            let player_address = get_caller_address();
            let mut player: Player = world.read_model(player_address);

            let mut new_ids: Array<u128> = ArrayTrait::new();
            let mut found = false;

            let mut agent_games: AgentGames = world.read_model(0);
            let mut i = 0;
            while i < agent_games.game_ids.len() {
                let game_id = agent_games.game_ids.at(i);
                let game: Game = caps_world.read_model(*game_id);
                if player.game_id == *game_id && game.over {
                    found = true;
                    i += 1;
                    continue;
                } else {
                    new_ids.append(*game_id);
                }
                i += 1;
            };

            if found {
                let game: Game = caps_world.read_model(player.game_id);
                let (_over, winner) = @game.check_over(@caps_world);
                if *winner == player_address {
                    player.agent_wins += 1;
                    agent_games.losses += 1;
                } else if *winner == agent_games.address {
                    agent_games.wins += 1;
                    player.agent_losses += 1;
                } else {
                    panic!("Winner is neither player nor agent????");
                }
                agent_games.game_ids = new_ids;
                let mut global_stats: GlobalStats = world.read_model(0);
                global_stats.games_played += 1;
                world.write_model(@global_stats);
                world.write_model(@agent_games);
                player.in_game = false;
                player.game_id = 0;
                world.write_model(@player);
            } else {
                panic!("Game not found");
            }
        }

        fn get_agent_games(self: @ContractState) -> Array<u128> {
            let mut world = self.world(@"planetelo");
            let mut agent_games: AgentGames = world.read_model(0);
            agent_games.game_ids
        }

        fn get_player_game_id(self: @ContractState, address: ContractAddress) -> u128 {
            let mut world = self.world(@"planetelo");
            let mut player: Player = world.read_model(address);
            player.game_id
        }

        fn select_team(ref self: ContractState, team: u16) {
            let mut world = self.world(@"planetelo");
            let mut player: Player = world.read_model(get_caller_address());
            player.team = team;
            world.write_model(@player);
        }

        fn invite(ref self: ContractState, player2: ContractAddress) {
            let mut world = self.world(@"planetelo");
            let mut player: Player = world.read_model(get_caller_address());
            let mut p2: Player = world.read_model(player2);
            let mut global_stats: GlobalStats = world.read_model(0);
            let mut i = 0;
            while i < p2.custom_game_ids.len() {
                let custom_game: CustomGames = world.read_model(*p2.custom_game_ids.at(i));
                if custom_game.player1 == player.address || custom_game.player2 == player.address {
                    panic!("You are already in a custom game with this player");
                }
                i += 1;
            };
            let invite: CustomGames = CustomGames {
                id: global_stats.custom_game_counter,
                player1: player.address,
                player2: player2,
                game_id: 0,
            };
            global_stats.custom_game_counter += 1;
            world.write_model(@global_stats);
            p2.custom_game_ids.append(invite.id);
            player.custom_game_ids.append(invite.id);
            world.write_model(@player);
            world.write_model(@p2);
            world.write_model(@invite);
        }

        fn get_player_invites(self: @ContractState, address: ContractAddress) -> Array<u128> {
            let mut world = self.world(@"planetelo");
            let mut player: Player = world.read_model(address);
            let mut invites: Array<u128> = ArrayTrait::new();
            let mut i = 0;
            while i < player.custom_game_ids.len() {
                let custom_game: CustomGames = world.read_model(*player.custom_game_ids.at(i));
                if custom_game.game_id == 0 {
                    invites.append(custom_game.id);
                }
                i += 1;
            };
            invites
        }

        fn accept_invite(ref self: ContractState, invite_id: u128) {
            let mut world = self.world(@"caps");
            let mut invite: CustomGames = world.read_model(invite_id);
            if invite.player2 != get_caller_address() {
                panic!("You are not the recipient of this invite");
            }
            let mut p1: Player = world.read_model(invite.player1);
            let mut p2: Player = world.read_model(invite.player2);

            let mut dispatcher: IActionsDispatcher = IActionsDispatcher {
                contract_address: world.dns_address(@"actions").unwrap(),
            };
            let id: u128 = dispatcher.create_game(p1.address, p2.address, p1.team, p2.team).into();
            invite.game_id = id;
            world.write_model(@invite);
        }

        fn decline_invite(ref self: ContractState, invite_id: u128) {
            let mut world = self.world(@"planetelo");
            let mut invite: CustomGames = world.read_model(invite_id);
            if invite.player2 != get_caller_address() {
                panic!("You are not the recipient of this invite");
            }
            assert!(invite.game_id == 0, "Game has already started");
            let mut p1: Player = world.read_model(invite.player1);
            let mut p2: Player = world.read_model(invite.player2);
            let mut new_p1_ids: Array<u128> = ArrayTrait::new();
            let mut new_p2_ids: Array<u128> = ArrayTrait::new();
            let mut i = 0;
            while i < p1.custom_game_ids.len() {
                if *p1.custom_game_ids.at(i) == invite_id {
                    i += 1;
                    continue;
                }
                new_p1_ids.append(*p1.custom_game_ids.at(i));
                i += 1;
            };
            i = 0;
            while i < p2.custom_game_ids.len() {
                if *p2.custom_game_ids.at(i) == invite_id {
                    i += 1;
                    continue;
                }
                new_p2_ids.append(*p2.custom_game_ids.at(i));
                i += 1;
            };
            p1.custom_game_ids = new_p1_ids;
            p2.custom_game_ids = new_p2_ids;
            world.write_model(@p1);
            world.write_model(@p2);
        }

        fn settle_custom_game(ref self: ContractState, game_id: u128) {
            let mut world = self.world(@"caps");
            let game: Game = world.read_model(game_id);
            let (over, winner) = @game.check_over(@world);
            let mut res = Status::Active;
            if *over {
                if *winner == game.player1 {
                    res = Status::Winner(game.player1.into());
                } else if *winner == game.player2 {
                    res = Status::Winner(game.player2.into());
                } else {
                    res = Status::None;
                }
            }
            let mut p1: Player = world.read_model(game.player1);
            let mut p2: Player = world.read_model(game.player2);
            let mut i = 0;
            let mut new_p1_ids: Array<u128> = ArrayTrait::new();
            let mut new_p2_ids: Array<u128> = ArrayTrait::new();
            while i < p1.custom_game_ids.len() {
                if *p1.custom_game_ids.at(i) == game_id {
                    i += 1;
                    continue;
                }
                new_p1_ids.append(*p1.custom_game_ids.at(i));
                i += 1;
            };
            i = 0;
            while i < p2.custom_game_ids.len() {
                if *p2.custom_game_ids.at(i) == game_id {
                    i += 1;
                    continue;
                }
                new_p2_ids.append(*p2.custom_game_ids.at(i));
                i += 1;
            };
            p1.custom_game_ids = new_p1_ids;
            p2.custom_game_ids = new_p2_ids;
            world.write_model(@p1);
            world.write_model(@p2);
        }

        fn get_player_custom_games(
            self: @ContractState, address: ContractAddress,
        ) -> Array<CustomGames> {
            let mut world = self.world(@"planetelo");
            let mut player: Player = world.read_model(address);
            let mut custom_games: Array<CustomGames> = ArrayTrait::new();
            let mut i = 0;
            while i < player.custom_game_ids.len() {
                let custom_game: CustomGames = world.read_model(*player.custom_game_ids.at(i));
                custom_games.append(custom_game);
                i += 1;
            };
            custom_games
        }

        fn get_player_stats(self: @ContractState, address: ContractAddress) -> (u8, u8) {
            let mut world = self.world(@"planetelo");
            let mut player: Player = world.read_model(address);
            (player.agent_wins, player.agent_losses)
        }

        fn get_player_team(self: @ContractState, address: ContractAddress) -> u16 {
            let mut world = self.world(@"planetelo");
            let mut player: Player = world.read_model(address);
            player.team
        }
    }

    #[abi(embed_v0)]
    impl OneOnOneImpl of IOneOnOne<ContractState> {
        fn create_match(
            ref self: ContractState, p1: ContractAddress, p2: ContractAddress, playlist_id: u128,
        ) -> u128 {
            let mut world = self.world(@"caps");
            let dispatcher: IActionsDispatcher = IActionsDispatcher {
                contract_address: world.dns_address(@"actions").unwrap(),
            };

            let p1: Player = world.read_model(p1);
            let p2: Player = world.read_model(p2);
            let id: u128 = dispatcher.create_game(p1.address, p2.address, p1.team, p2.team).into();
            id
        }

        fn settle_match(ref self: ContractState, match_id: u128) -> Status {
            let mut world = self.world(@"caps");
            let game: Game = world.read_model(match_id);
            let (over, winner) = @game.check_over(@world);

            if !*over {
                return Status::Active;
            } else {
                if *winner == game.player1 {
                    return Status::Winner(game.player1.into());
                } else if *winner == game.player2 {
                    return Status::Winner(game.player2.into());
                } else {
                    return Status::None;
                }
            }
        }
    }
}

