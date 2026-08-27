use caps::models::game::Vec2;

/// Layout identifiers
pub const LAYOUT_PERIMETER_5X5: u8 = 0;
pub const LAYOUT_CROSS_5X5: u8 = 1;
pub const LAYOUT_DIAGONAL_X_5X5: u8 = 2;
pub const LAYOUT_DIAMOND_5X5: u8 = 3;

/// Maximum dimensions supported across layouts
pub const MAX_BOARD_SIZE: u8 = 7;

/// Check if a position is within the bounds of a given layout
pub fn get_board_dimensions(layout: u8) -> (u8, u8) {
    (5, 5)
}

/// Check if a cell is an active/walkable tile in the layout
pub fn is_walkable(layout: u8, pos: Vec2) -> bool {
    let (w, h) = get_board_dimensions(layout);
    if pos.x >= w || pos.y >= h {
        return false;
    }

    if layout == LAYOUT_PERIMETER_5X5 {
        // Perimeter of 5x5 grid (edges only)
        pos.x == 0 || pos.x == 4 || pos.y == 0 || pos.y == 4
    } else if layout == LAYOUT_CROSS_5X5 {
        // Perimeter + center cross (x=2 or y=2)
        pos.x == 0 || pos.x == 4 || pos.y == 0 || pos.y == 4 || pos.x == 2 || pos.y == 2
    } else if layout == LAYOUT_DIAGONAL_X_5X5 {
        // Perimeter + diagonal X connecting opposite corners through center (2,2)
        pos.x == 0 || pos.x == 4 || pos.y == 0 || pos.y == 4 || pos.x == pos.y || (pos.x + pos.y == 4)
    } else if layout == LAYOUT_DIAMOND_5X5 {
        // Perimeter + inner diamond track: (2,1), (3,2), (2,3), (1,2)
        let is_perimeter = pos.x == 0 || pos.x == 4 || pos.y == 0 || pos.y == 4;
        let is_diamond = (pos.x == 2 && pos.y == 1) || (pos.x == 3 && pos.y == 2) ||
                         (pos.x == 2 && pos.y == 3) || (pos.x == 1 && pos.y == 2);
        is_perimeter || is_diamond
    } else {
        pos.x == 0 || pos.x == 4 || pos.y == 0 || pos.y == 4
    }
}

/// Get the deploy tile for Player 1 (bottom side center)
pub fn get_p1_deploy_spot(layout: u8) -> Vec2 {
    Vec2 { x: 2, y: 0 }
}

/// Get the deploy tile for Player 2 (top side center)
pub fn get_p2_deploy_spot(layout: u8) -> Vec2 {
    Vec2 { x: 2, y: 4 }
}

/// Check if `to` is a valid 1-step move from `from` (supports orthogonal & diagonal)
pub fn is_valid_step(layout: u8, from: Vec2, to: Vec2) -> bool {
    if !is_walkable(layout, from) || !is_walkable(layout, to) {
        return false;
    }

    if from.x == to.x && from.y == to.y {
        return false;
    }

    let dx = if from.x > to.x { from.x - to.x } else { to.x - from.x };
    let dy = if from.y > to.y { from.y - to.y } else { to.y - from.y };

    // Chebyshev distance == 1 means adjacent (orthogonal or diagonal)
    dx <= 1 && dy <= 1
}
