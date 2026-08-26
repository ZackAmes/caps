use starknet::{ContractAddress};
use dojo::model::{ModelStorage};
use dojo::world::WorldStorage;
use caps::models::effect::{Effect};
use caps::models::cap::{Cap, CapTrait};

#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct Global {
    #[key]
    pub key: u64,
    pub games_counter: u64,
    pub cap_counter: u64,
}

#[derive(Drop, Serde, Debug, Clone)]
#[dojo::model]
pub struct Game {
    #[key]
    pub id: u64,
    pub player1: ContractAddress,
    pub player2: ContractAddress,
    pub caps_ids: Array<u64>,
    pub turn_count: u64,
    pub over: bool,
    pub effect_ids: Array<u64>,
    pub last_action_timestamp: u64,
}

#[generate_trait]
pub impl GameImpl of GameTrait {
    fn new(id: u64, player1: ContractAddress, player2: ContractAddress) -> Game {
        Game {
            id,
            player1,
            player2,
            caps_ids: ArrayTrait::new(),
            turn_count: 0,
            over: false,
            effect_ids: ArrayTrait::new(),
            last_action_timestamp: 0,
        }
    }

    fn add_cap(ref self: Game, cap_id: u64) {
        self.caps_ids.append(cap_id);
    }

    fn remove_cap(ref self: Game, cap_id: u64) {
        let mut i = 0;
        let mut new_ids: Array<u64> = ArrayTrait::new();
        while i < self.caps_ids.len() {
            if *self.caps_ids[i] == cap_id {
                i += 1;
                continue;
            }
            new_ids.append(*self.caps_ids[i]);
            i += 1;
        };
        self.caps_ids = new_ids;
    }

    fn update_effects(
        ref self: Game,
        ref world: WorldStorage,
        ref start_of_turn_effects: Array<Effect>,
        ref move_step_effects: Array<Effect>,
        ref end_of_turn_effects: Array<Effect>,
    ) {
        let mut i = 0;
        let mut new_ids: Array<u64> = ArrayTrait::new();
        while i < start_of_turn_effects.len() {
            let mut effect = *start_of_turn_effects.at(i);
            if effect.remaining_triggers > 0 {
                new_ids.append(effect.effect_id);
                world.write_model(@effect);
            } else {
                world.erase_model(@effect);
            }
            i += 1;
        };
        let mut i = 0;
        while i < move_step_effects.len() {
            let mut effect = *move_step_effects.at(i);
            if effect.remaining_triggers > 0 {
                new_ids.append(effect.effect_id);
                world.write_model(@effect);
            } else {
                world.erase_model(@effect);
            }
            i += 1;
        };
        let mut i = 0;
        while i < end_of_turn_effects.len() {
            let mut effect = *end_of_turn_effects.at(i);
            if effect.remaining_triggers > 0 {
                new_ids.append(effect.effect_id);
                world.write_model(@effect);
            } else {
                world.erase_model(@effect);
            }
            i += 1;
        };
        self.effect_ids = new_ids;
    }

    fn check_over(self: @Game, world: @WorldStorage) -> (bool, ContractAddress) {
        let mut i = 0;
        let mut one_found = false;
        let mut two_found = false;
        let mut one_tower_found = false;
        let mut two_tower_found = false;
        while i < self.caps_ids.len() {
            let cap: Cap = world.read_model(*self.caps_ids[i]);
            let cap_type = cap.get_cap_type().unwrap();
            if cap.dmg_taken >= cap_type.base_health {
                i += 1;
                continue;
            }
            if cap.owner == (*self.player1).into() {
                one_found = true;
                //todo: better way to tell if it's a tower
                if cap.cap_type < 4 {
                    one_tower_found = true;
                }
            } else if cap.owner == (*self.player2).into() {
                two_found = true;
                if cap.cap_type < 4 {
                    two_tower_found = true;
                }
            }
            i += 1;
        };
        if !one_found || !one_tower_found {
            return (true, *self.player2);
        } else if !two_found || !two_tower_found {
            return (true, *self.player1);
        }
        (false, starknet::contract_address_const::<0>())
    }

    fn check_over_simulated(self: @Game, caps: @Array<Cap>) -> (bool, ContractAddress) {
        let mut i = 0;
        let mut one_found = false;
        let mut two_found = false;
        let mut winner = starknet::contract_address_const::<0>();
        while i < caps.len() {
            let cap: Cap = *caps.at(i);
            if cap.owner == (*self.player1).into() {
                one_found = true;
                winner = *self.player1;
                break;
            }
            if cap.owner == (*self.player2).into() {
                two_found = true;
                winner = *self.player2;
                break;
            }
            i += 1;
        };
        (one_found && two_found, winner)
    }
}


#[derive(Drop, Serde, Copy, Introspect)]
pub struct Action {
    pub cap_id: u64,
    pub action_type: ActionType,
}

#[derive(Drop, Serde, Copy, Introspect)]
pub enum ActionType {
    Play: Vec2,
    Move: Vec2,
    Attack: Vec2,
    Ability: Vec2,
}

#[derive(Copy, Drop, Serde, PartialEq, DojoStore, Debug, Introspect)]
pub struct Vec2 {
    pub x: u8,
    pub y: u8,
}


#[generate_trait]
impl Vec2Impl of Vec2Trait {
    fn is_zero(self: Vec2) -> bool {
        if self.x - self.y == 0 {
            return true;
        }
        false
    }

    fn is_equal(self: Vec2, b: Vec2) -> bool {
        self.x == b.x && self.y == b.y
    }
}

