pub mod systems {
    pub mod boards;
    pub mod actions;
}

pub mod models {
    pub mod board;
    pub mod cap;
    pub mod effect;
    pub mod game;
    pub mod game_clock;
    pub mod set;
    pub mod set_data;
    pub mod stack;
    pub mod turn_record;
}

pub mod sets {
    pub mod set_zero;
}

pub mod logic {
    pub mod board_data;
    pub mod hand;
    pub mod ops;
    pub mod passives;
    pub mod rules;
    pub mod stack;
    pub mod track;
}

#[cfg(test)]
mod tests {
    mod board_test;
    mod clock_test;
    mod foundation_test;
    mod rules_test;
    mod stack_test;
}
