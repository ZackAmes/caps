use caps::helpers::{clone_dicts, get_dicts_from_array};
use caps::models::effect::{Effect};
use caps::models::game::{Game, Vec2};
use caps::sets::set_zero::get_cap_type;

use core::dict::Felt252Dict;
use starknet::ContractAddress;

#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct Cap {
    #[key]
    pub id: u64,
    pub owner: felt252,
    pub location: Location,
    pub set_id: u64,
    pub cap_type: u16,
    pub dmg_taken: u16,
    pub shield_amt: u16,
}


#[generate_trait]
pub impl CapImpl of CapTrait {
    fn new(id: u64, owner: felt252, location: Location, set_id: u64, cap_type: u16) -> Cap {
        Cap { id, owner, location, set_id, cap_type, dmg_taken: 0, shield_amt: 0 }
    }

    fn get_new_index_from_dir(self: @Cap, direction: u8, amt: u8) -> felt252 {
        let mut new_position = Vec2 { x: 0, y: 0 };
        match self.location {
            Location::Board(vec) => {
                new_position = Vec2 { x: *vec.x, y: *vec.y };
            },
            _ => {
                panic!("Cap is not on the board");
            },
        }
        match direction {
            0 => if new_position.x + amt > 6 {
                panic!(
                    "Move out of bounds: would move to x: {} (start: {}, amt: {}) (get_new_index_from_dir)",
                    new_position.x + amt,
                    new_position.x,
                    amt,
                );
            } else {
                new_position.x += amt
            },
            1 => if amt > new_position.x {
                panic!(
                    "Move out of bounds: would move to x: -{} (start: {}, amt: {}) (get_new_index_from_dir)",
                    amt - new_position.x,
                    new_position.x,
                    amt,
                );
            } else {
                new_position.x -= amt
            },
            2 => if new_position.y + amt > 6 {
                panic!(
                    "Move out of bounds: would move to y: {} (start: {}, amt: {}) (get_new_index_from_dir)",
                    new_position.y + amt,
                    new_position.y,
                    amt,
                );
            } else {
                new_position.y += amt
            },
            3 => if amt > new_position.y {
                panic!(
                    "Move out of bounds: would move to y: -{} (start: {}, amt: {}) (get_new_index_from_dir)",
                    amt - new_position.y,
                    new_position.y,
                    amt,
                );
            } else {
                new_position.y -= amt
            },
            _ => panic!("Invalid direction"),
        };
        (new_position.x * 7 + new_position.y).into()
    }

    fn move(ref self: Cap, cap_type: CapType, direction: u8, amount: u8, bonus_range: u8) {
        let mut new_position = self.get_position();
        if new_position.is_none() {
            panic!("Cap is not on the board");
        }
        let mut new_position = new_position.unwrap();
        match direction {
            0 => {
                if new_position.x + amount > 6 {
                    panic!(
                        "Move out of bounds: would move to x: {} (start: {}, amt: {}) (Move)",
                        new_position.x + amount,
                        new_position.x,
                        amount,
                    );
                }
                if amount > cap_type.move_range.x + bonus_range {
                    panic!("Move out of range");
                }
                new_position.x += amount;
            },
            1 => {
                if amount > new_position.x {
                    panic!(
                        "Move out of bounds: would move to x: -{} (start: {}, amt: {}) (Move)",
                        amount - new_position.x,
                        new_position.x,
                        amount,
                    );
                }
                if amount > cap_type.move_range.x + bonus_range {
                    panic!("Move out of range");
                }
                new_position.x -= amount;
            },
            2 => {
                if new_position.y + amount > 6 {
                    panic!(
                        "Move out of bounds: would move to y: {} (start: {}, amt: {}) (Move)",
                        new_position.y + amount,
                        new_position.y,
                        amount,
                    );
                }
                if amount > cap_type.move_range.y + bonus_range {
                    panic!("Move out of range");
                }
                new_position.y += amount;
            },
            3 => {
                if amount > new_position.y {
                    panic!(
                        "Move out of bounds: would move to y: -{} (start: {}, amt: {}) (Move)",
                        amount - new_position.y,
                        new_position.y,
                        amount,
                    );
                }
                if amount > cap_type.move_range.y + bonus_range {
                    panic!("Move out of range");
                }
                new_position.y -= amount;
            },
            _ => (),
        };
        self.location = Location::Board(new_position);
    }

    fn check_in_range(self: @Cap, target: Vec2, range: @Array<Vec2>) -> bool {
        let mut valid = false;
        let mut i = 0;
        let mut position = Vec2 { x: 0, y: 0 };
        match self.location {
            Location::Board(vec) => {
                position = Vec2 { x: *vec.x, y: *vec.y };
            },
            _ => {
                panic!("Cap is not on the board");
            },
        }
        while i < range.len() {
            let to_check: Vec2 = *range[i];
            if target.x >= position.x && target.y >= position.y {
                if to_check.x + position.x > 6 {}
                if to_check.y + position.y > 6 {}
                if position.x
                    + to_check.x == target.x && position.y
                    + to_check.y == target.y {
                    valid = true;
                    break;
                } else {}
            } else if target.x <= position.x && target.y <= position.y {
                if to_check.x > position.x {}
                if to_check.y > position.y {}
                if position.x
                    - to_check.x == target.x && position.y
                    - to_check.y == target.y {
                    valid = true;
                    break;
                } else {}
            } else if target.x <= position.x && target.y >= position.y {
                if to_check.x > position.x {}
                if to_check.y + position.y > 6 {}
                if position.x
                    - to_check.x == target.x && position.y
                    + to_check.y == target.y {
                    valid = true;
                    break;
                } else {}
            } else if target.x >= position.x && target.y <= position.y {
                if to_check.x + position.x > 6 {}
                if to_check.y > position.y {}
                if position.x
                    + to_check.x == target.x && position.y
                    - to_check.y == target.y {
                    valid = true;
                    break;
                } else {}
            }
            i += 1;
        };
        valid
    }

    fn get_cap_type(self: @Cap) -> Option<CapType> {
        get_cap_type(*self.cap_type)
    }

    fn get_position(self: @Cap) -> Option<Vec2> {
        match self.location {
            Location::Board(vec) => {
                Option::Some(*vec)
            },
            _ => {
                Option::None
            },
        }
    }

    fn use_ability(
        ref self: Cap,
        target: Vec2,
        ref game: Game,
        ref locations: Felt252Dict<u64>,
        ref keys: Felt252Dict<Nullable<Cap>>,
    ) -> (Game, Array<Effect>, Felt252Dict<u64>, Felt252Dict<Nullable<Cap>>) {
        let mut caps_array: Array<Cap> = ArrayTrait::new();
        let mut i = 0;
        while i < game.caps_ids.len() {
            let cap = keys.get((*game.caps_ids[i]).into()).deref();
            caps_array.append(cap);
            i += 1;
        };
        let mut cap_type = get_cap_type(self.cap_type).unwrap();
        let (new_game, new_effects, new_caps) = caps::sets::set_zero::use_ability(
            ref self, ref cap_type, target, ref game, ref locations, ref keys,
        );
        let (new_locations, new_keys) = get_dicts_from_array(@new_caps);
        (new_game, new_effects, new_locations, new_keys)
    }
}


//This is never getting stored. It's just a model to generate the bindings
#[derive(Drop, Serde, Debug, Clone, Introspect)]
#[dojo::model]
pub struct CapType {
    #[key]
    pub id: u16,
    pub name: ByteArray,
    pub description: ByteArray,
    pub play_cost: u8,
    pub move_cost: u8,
    pub attack_cost: u8,
    // Attack range is the squares relative to the cap's position that can be attacked
    pub attack_range: Array<Vec2>,
    pub ability_range: Array<Vec2>,
    pub ability_description: ByteArray,
    // Move range is the x range, y range
    pub move_range: Vec2,
    pub attack_dmg: u16,
    pub base_health: u16,
    pub ability_target: TargetType,
    pub ability_cost: u8,
}


#[derive(Copy, Drop, Serde, Debug, PartialEq, DojoStore, Default, Introspect)]
pub enum TargetType {
    #[default]
    None,
    SelfCap,
    TeamCap,
    OpponentCap,
    AnyCap,
    AnySquare,
}

#[derive(Copy, Drop, Serde, Debug, PartialEq, DojoStore, Default, Introspect)]
pub enum Location {
    #[default]
    Bench,
    Board: Vec2,
    Hidden: felt252, // hash if hidden
    Dead
}

#[generate_trait]
pub impl TargetTypeImpl of TargetTypeTrait {
    fn is_valid(
        self: @TargetType,
        cap: @Cap,
        ref cap_type: CapType,
        target: Vec2,
        ref game: Game,
        ref locations: Felt252Dict<u64>,
        ref keys: Felt252Dict<Nullable<Cap>>,
    ) -> (bool, Game, Felt252Dict<u64>, Felt252Dict<Nullable<Cap>>) {
        let mut valid = false;

        match *self {
            TargetType::None => {},
            TargetType::SelfCap => { valid = true; },
            TargetType::TeamCap => {
                assert!(cap_type.ability_range.len() > 0, "Ability range is empty");
                let in_range = cap.check_in_range(target, @cap_type.ability_range);
                assert!(in_range, "Target not in range");
                let at_location_id = locations.get((target.x * 7 + target.y).into());
                let mut at_location = keys.get(at_location_id.into()).deref();
                assert!(at_location_id != 0, "No cap at location");
                //Must be player
                assert!(at_location.owner == *cap.owner, "Cap is not owned by player");
                if in_range && at_location.owner == *cap.owner {
                    valid = true;
                }
            },
            TargetType::OpponentCap => {
                assert!(cap_type.ability_range.len() > 0, "Ability range is empty");
                let in_range = cap.check_in_range(target, @cap_type.ability_range);
                assert!(in_range, "Target not in range");
                let at_location_id = locations.get((target.x * 7 + target.y).into());
                let mut at_location = keys.get(at_location_id.into()).deref();
                assert!(at_location_id != 0, "No cap at location");
                assert!(*cap.owner != 0, "Cap owner 0?");
                assert!(at_location.owner != *cap.owner, "Cap is owned by player");
                //Must be opponent
                if in_range && at_location.owner != *cap.owner {
                    valid = true;
                }
            },
            TargetType::AnyCap => {
                assert!(cap_type.ability_range.len() > 0, "Ability range is empty");
                let in_range = cap.check_in_range(target, @cap_type.ability_range);
                assert!(in_range, "Target not in range");
                let at_location_id = locations.get((target.x * 7 + target.y).into());
                let mut at_location = keys.get(at_location_id.into());
                assert!(at_location_id != 0, "No cap at location");
                if at_location.owner != *cap.owner && in_range {
                    valid = true;
                }
            },
            TargetType::AnySquare => {
                assert!(cap_type.ability_range.len() > 0, "Ability range is empty");
                valid = cap.check_in_range(target, @cap_type.ability_range);
            },
        }
        let (new_game, new_locations, new_keys) = clone_dicts(@game, ref locations, ref keys);
        (valid, new_game, new_locations, new_keys)
    }
}
