pub mod systems {
    pub mod actions;
}

pub mod models {
    pub mod cap;
    pub mod effect;
    pub mod game;
    pub mod set;
    pub mod set_data;
}

pub mod sets {
    pub mod set_zero;
}

pub mod logic {
    pub mod hand;
    pub mod ops;
    pub mod rules;
    pub mod track;
}

#[cfg(test)]
mod tests {
    mod rules_test;
}
