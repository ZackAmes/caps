#[cfg(test)]
mod tests {
    use dojo_cairo_test::WorldStorageTestTrait;
    use dojo::model::{ModelStorage, ModelStorageTest};
    use dojo::world::WorldStorageTrait;
    use dojo_cairo_test::{
        spawn_test_world, NamespaceDef, TestResource, ContractDefTrait, ContractDef,
    };

    use caps::systems::actions::{actions, IActionsDispatcher, IActionsDispatcherTrait};
    use caps::models::cap::{Cap, m_Cap, CapType, m_CapType, TargetType};
    use caps::models::effect::{Effect, m_Effect, EffectType, EffectTarget, Timing};
    use caps::models::game::{Vec2, Game, m_Game, Action, ActionType, Global, m_Global};
    use caps::models::set::{Set, m_Set, ISetInterface};
    use caps::sets::set_zero::{set_zero};

    use starknet::testing::{set_contract_address};

    fn namespace_def() -> NamespaceDef {
        let ndef = NamespaceDef {
            namespace: "caps",
            resources: [
                TestResource::Model(m_Cap::TEST_CLASS_HASH),
                TestResource::Model(m_CapType::TEST_CLASS_HASH),
                TestResource::Model(m_Effect::TEST_CLASS_HASH),
                TestResource::Model(m_Game::TEST_CLASS_HASH),
                TestResource::Model(m_Global::TEST_CLASS_HASH),
                TestResource::Model(m_Set::TEST_CLASS_HASH),
                TestResource::Contract(actions::TEST_CLASS_HASH),
                TestResource::Contract(set_zero::TEST_CLASS_HASH),
                TestResource::Event(actions::e_Moved::TEST_CLASS_HASH),
            ]
                .span(),
        };

        ndef
    }

    fn contract_defs() -> Span<ContractDef> {
        [
            ContractDefTrait::new(@"caps", @"actions")
                .with_writer_of([dojo::utils::bytearray_hash(@"caps")].span()),
            ContractDefTrait::new(@"caps", @"set_zero")
                .with_writer_of([dojo::utils::bytearray_hash(@"caps")].span()),
        ]
            .span()
    }

    #[test]
    fn test_world_test_set() {
        // Initialize test environment
        let caller = 0.try_into().unwrap();
        let ndef = namespace_def();

        // Register the resources.
        let mut world = spawn_test_world([ndef].span());

        // Ensures permissions and initializations are synced.
        world.sync_perms_and_inits(contract_defs());
    }

    #[test]
    #[available_gas(30000000000)]
    fn test_move() {
        let ndef = namespace_def();
        let mut world = spawn_test_world([ndef].span());
        world.sync_perms_and_inits(contract_defs());

        let (contract_address, _) = world.dns(@"actions").unwrap();
        let actions_system = IActionsDispatcher { contract_address };

        let p1 = 1.try_into().unwrap();
        let p2 = 2.try_into().unwrap();

        let game_id = actions_system.create_game(p1, p2, 1, 1);

        let mut game: Game = world.read_model(game_id);
        game.turn_count = 2;
        world.write_model(@game);

        assert!(game.player1 == p1, "p1 is wrong");
        assert!(game.player2 == p2, "p2 is wrong");

        set_contract_address(p1);

        let turn: Array<Action> = array![
            Action { cap_id: 6, action_type: ActionType::Move(Vec2 { x: 0, y: 1 }) },
            Action { cap_id: 6, action_type: ActionType::Move(Vec2 { x: 0, y: 1 }) },
        ];

        actions_system.take_turn(game_id, turn);
    }
}
