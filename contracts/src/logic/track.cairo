use caps::logic::board_data::{dimensions, distance, distances, p1_base, p2_base};
use caps::models::game::Vec2;

pub const LAYOUT_PERIMETER_5X5: u8 = 0;
pub const LAYOUT_CROSS_5X5: u8 = 1;
pub const LAYOUT_DIAGONAL_X_5X5: u8 = 2;
pub const LAYOUT_DIAMOND_5X5: u8 = 3;
pub const LAYOUT_DUEL_7X9: u8 = 4;
pub const LAYOUT_DUEL_7X5: u8 = 5;
pub const MAX_BOARD_SIZE: u8 = 15;

pub fn get_board_dimensions(layout: u8) -> (u8, u8) {
    dimensions(layout)
}

/// Shortest number of explicit path edges. Occupancy does not change geometric range.
pub fn path_distance(layout: u8, from: Vec2, to: Vec2) -> Option<u8> {
    let (width, height) = dimensions(layout);
    if width == 0 || from.x >= width || from.y >= height || to.x >= width || to.y >= height {
        return Option::None;
    }
    let steps = distance(layout, from.y * width + from.x, to.y * width + to.x);
    if steps == 255 {
        Option::None
    } else {
        Option::Some(steps)
    }
}
pub fn is_walkable(layout: u8, pos: Vec2) -> bool {
    path_distance(layout, pos, pos).is_some()
}
pub fn is_valid_step(layout: u8, from: Vec2, to: Vec2) -> bool {
    path_distance(layout, from, to) == Option::Some(1)
}
pub fn within_range(layout: u8, from: Vec2, to: Vec2, range: u16) -> bool {
    match path_distance(layout, from, to) {
        Option::Some(n) => n.into() <= range,
        Option::None => false,
    }
}
pub fn get_p1_deploy_spot(layout: u8) -> Vec2 {
    p1_base(layout)
}
pub fn get_p2_deploy_spot(layout: u8) -> Vec2 {
    p2_base(layout)
}
pub fn get_walkable_neighbors(layout: u8, pos: Vec2) -> Array<Vec2> {
    let mut result = array![];
    let (width, height) = dimensions(layout);
    if width == 0 || pos.x >= width || pos.y >= height {
        return result;
    }
    let row = distances(layout, pos.y * width + pos.x);
    let mut id: u8 = 0;
    while id < width * height {
        if *row.at(id.into()) == 1 {
            result.append(Vec2 { x: id % width, y: id / width });
        }
        id += 1;
    }
    result
}
