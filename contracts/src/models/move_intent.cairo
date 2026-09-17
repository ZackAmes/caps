use starknet::ContractAddress;
/// Signed Torii messages only. Game rules never read this model.
#[derive(Drop, Serde, Introspect, DojoStore)]
#[dojo::model]
pub struct MoveIntent {
    #[key] pub identity: ContractAddress,
    #[key] pub game_id: u64,
    #[key] pub turn: u64,
    pub world: ContractAddress,
    pub timestamp: u64,
    pub tx_hash: felt252,
    /// 0 = submitted intent, 1 = broadcast transaction, 2 = cancelled/reverted, 3 = committed event.
    pub status: u8,
    pub actions: Array<felt252>,
}

/// Onchain acceptance of a submitted turn. The intent uses the same action encoding
/// as the signed offchain preview. Consumers must distinguish this event from a relay hint.
#[derive(Drop, Serde)]
#[dojo::event]
pub struct MoveCommitted {
    #[key] pub game_id: u64,
    #[key] pub turn: u64,
    pub intent: MoveIntent,
}
