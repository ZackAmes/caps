use caps::models::board::{BoardDefinition, PublishedBoard};
#[starknet::interface]
pub trait IBoards<T> {
    fn get_geometry(self: @T, layout: u8, board_id: u64) -> caps::logic::track::BoardGeometry;
    fn publish(ref self: T, definition: BoardDefinition) -> u64;
    fn get_board(self: @T, id: u64) -> Option<PublishedBoard>;
    fn get_board_count(self: @T) -> u64;
    fn get_publication(self: @T, transaction: felt252) -> u64;
}

/// Permissionless, append-only board registry. No update, moderation, or owner gate.
#[dojo::contract]
pub mod boards {
    use super::IBoards;
    use caps::models::board::{BoardDefinition, PublishedBoard, BoardRegistry, BoardDistances, BoardPublication};
    use dojo::model::ModelStorage;
    use starknet::get_caller_address;
    use core::num::traits::Zero;
    use core::dict::{Felt252Dict, Felt252DictTrait};

    #[abi(embed_v0)]
    impl BoardsImpl of IBoards<ContractState> {
        fn get_geometry(self: @ContractState, layout: u8, board_id: u64) -> caps::logic::track::BoardGeometry {
            if board_id == 0 { return caps::logic::track::legacy(layout); }
            let board = self.get_board(board_id).expect('Board not found');
            let data: BoardDistances = self.world(@"caps").read_model(board_id);
            caps::logic::track::published(@board,@data)
        }
        fn get_publication(self: @ContractState, transaction: felt252) -> u64 {
            let publication: BoardPublication = self.world(@"caps").read_model(transaction);
            publication.board_id
        }
        fn get_board_count(self: @ContractState) -> u64 {
            let registry: BoardRegistry = self.world(@"caps").read_model(0_u8);
            registry.count
        }
        fn get_board(self: @ContractState, id: u64) -> Option<PublishedBoard> {
            let board: PublishedBoard = self.world(@"caps").read_model(id);
            if board.creator.is_zero() { Option::None } else { Option::Some(board) }
        }
        fn publish(ref self: ContractState, definition: BoardDefinition) -> u64 {
            assert!(definition.name.len() > 0 && definition.name.len() <= 64, "Name must be 1 to 64 bytes");
            assert!(definition.width > 0 && definition.width <= 15 && definition.height > 0 && definition.height <= 15, "Grid must be 1 to 15");
            assert!(definition.view_width >= 1000 && definition.view_height >= 1000, "Visual extent too small");
            let n = definition.spots.len();
            assert!(n >= 2 && n <= 64 && definition.edges.len() <= 128, "Board resource limit");
            let mut occupied: Felt252Dict<bool> = Default::default();
            let mut visible: Felt252Dict<bool> = Default::default();
            let mut p1 = false;
            let mut p2 = false;
            assert!(definition.p1_goal != definition.p2_goal, "Goals must differ");
            for spot in definition.spots.span() {
                assert!(*spot.at.x < definition.width && *spot.at.y < definition.height, "Spot outside grid");
                assert!(*spot.position.x <= definition.view_width && *spot.position.y <= definition.view_height, "Spot outside visual extent");
                let cell: u16 = (*spot.at.y).into() * 15 + (*spot.at.x).into();
                assert!(!occupied.get(cell.into()), "Duplicate spot");
                occupied.insert(cell.into(), true);
                let visual: u64 = (*spot.position.x).into() * 65536 + (*spot.position.y).into();
                assert!(!visible.get(visual.into()), "Duplicate visual position");
                visible.insert(visual.into(), true);
                if *spot.at == definition.p1_goal { p1 = true; }
                if *spot.at == definition.p2_goal { p2 = true; }
            }
            assert!(p1 && p2, "Goals must be spots");
            let mut edges_seen: Felt252Dict<bool> = Default::default();
            for edge in definition.edges.span() {
                assert!((*edge.from).into() < n && (*edge.to).into() < n && *edge.from != *edge.to, "Invalid edge");
                assert!(edge.via.len() <= 8, "Too many waypoints");
                let (a,b) = if *edge.from < *edge.to { (*edge.from,*edge.to) } else { (*edge.to,*edge.from) };
                let key: u16 = a.into() * 64 + b.into();
                assert!(!edges_seen.get(key.into()), "Duplicate edge");
                edges_seen.insert(key.into(), true);
                for point in edge.via.span() {
                    assert!(*point.x <= definition.view_width && *point.y <= definition.view_height, "Waypoint outside extent");
                }
            }
            // BFS computes authoritative shortest paths; publishers cannot supply fake distances.
            let mut packed = array![];
            let mut word: u128 = 0;
            let mut factor: u128 = 1;
            let mut byte_count: u8 = 0;
            for source in 0..n {
                let mut distances: Felt252Dict<u8> = Default::default();
                distances.insert(source.into(), 1); // zero is unvisited
                let mut queue = array![source];
                while let Option::Some(current) = queue.pop_front() {
                    let next_distance = distances.get(current.into()) + 1;
                    for edge in definition.edges.span() {
                        let target = if (*edge.from).into() == current { (*edge.to).into() }
                            else if (*edge.to).into() == current { (*edge.from).into() } else { n };
                        if target < n && distances.get(target.into()) == 0 {
                            distances.insert(target.into(), next_distance);
                            queue.append(target);
                        }
                    }
                }
                for target in 0..n {
                    let d = distances.get(target.into());
                    assert!(d > 0, "Board must be connected");
                    word += (d - 1).into() * factor;
                    byte_count += 1;
                    if byte_count == 16 { packed.append(word); word = 0; factor = 1; byte_count = 0; }
                    else { factor *= 256; }
                }
            }
            if byte_count > 0 { packed.append(word); }
            let mut world = self.world(@"caps");
            let mut registry: BoardRegistry = world.read_model(0_u8);
            registry.count += 1;
            let id = registry.count;
            world.write_model(@registry);
            world.write_model(@BoardPublication { transaction: starknet::get_tx_info().unbox().transaction_hash, board_id: id });
            world.write_model(@BoardDistances { id, packed });
            world.write_model(@PublishedBoard { id, creator: get_caller_address(), definition });
            id
        }
    }
}
