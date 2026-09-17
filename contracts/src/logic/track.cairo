use caps::logic::board_data::{dimensions, packed_distances, p1_base, p2_base};
use caps::models::game::Vec2;
use caps::models::board::{BoardSpot, PublishedBoard, BoardDistances, VisualPoint};

pub const LAYOUT_PERIMETER_5X5: u8 = 0;
pub const LAYOUT_CROSS_5X5: u8 = 1;
pub const LAYOUT_DIAGONAL_X_5X5: u8 = 2;
pub const LAYOUT_DIAMOND_5X5: u8 = 3;
pub const LAYOUT_DUEL_7X9: u8 = 4;
pub const LAYOUT_DUEL_7X5: u8 = 5;
pub const MAX_BOARD_SIZE: u8 = 15;

/// Copyable, immutable geometry loaded once by the action system. Pure rules share it.
#[derive(Copy, Drop, Serde)]
pub struct BoardGeometry {
    pub legacy: u8,
    pub custom: bool,
    pub stride: u32,
    pub width: u8,
    pub height: u8,
    pub p1: Vec2,
    pub p2: Vec2,
    pub spots: Span<BoardSpot>,
    pub packed: Span<u128>,
}
pub fn legacy(layout: u8) -> BoardGeometry {
    let (width,height) = dimensions(layout);
    let n: u32 = width.into() * height.into();
    let stride = ((n + 15) / 16) * 16;
    let mut spots = array![];
    let mut packed = array![];
    for i in 0..n {
        let cell: u8 = i.try_into().unwrap();
        let at = Vec2 {x:cell % width,y:cell / width};
        spots.append(BoardSpot {at,position:VisualPoint {x:0,y:0},energy:caps::logic::board_data::energy_space(layout,at)});
        let row = packed_distances(layout,cell);
        for word in 0..(stride / 16) {
            packed.append(if word < row.len() { *row.at(word) } else { 340282366920938463463374607431768211455 });
        }
    }
    BoardGeometry { legacy: layout, custom: false, stride, width, height, p1: p1_base(layout), p2: p2_base(layout), spots: spots.span(), packed: packed.span() }
}
pub fn published(board: @PublishedBoard, data: @BoardDistances) -> BoardGeometry {
    BoardGeometry { legacy: 255, custom: true, stride: board.definition.spots.len(), width: *board.definition.width, height: *board.definition.height,
        p1: *board.definition.p1_goal, p2: *board.definition.p2_goal, spots: board.definition.spots.span(), packed: data.packed.span() }
}
pub fn get_board_dimensions(layout: BoardGeometry) -> (u8, u8) { (layout.width,layout.height) }

fn spot_index(layout: BoardGeometry, pos: Vec2) -> u32 {
    for i in 0..layout.spots.len() { if *layout.spots.at(i).at == pos { return i; } }
    layout.spots.len()
}
pub fn path_distance(layout: BoardGeometry, from: Vec2, to: Vec2) -> Option<u8> {
    let (width,height) = get_board_dimensions(layout);
    if width == 0 || from.x >= width || from.y >= height || to.x >= width || to.y >= height { return Option::None; }
    let steps: u8 = {
        let a = spot_index(layout,from);
        let b = spot_index(layout,to);
        let n = layout.spots.len();
        if a == n || b == n { return Option::None; }
        let index = a * layout.stride + b;
        let mut word = *layout.packed.at(index / 16);
        let mut offset = index % 16;
        while offset > 0 { word /= 256; offset -= 1; }
        (word % 256).try_into().unwrap()
    };
    if steps == 255 { Option::None } else { Option::Some(steps) }
}
pub fn is_walkable(layout: BoardGeometry, pos: Vec2) -> bool { path_distance(layout,pos,pos).is_some() }
pub fn is_valid_step(layout: BoardGeometry, from: Vec2, to: Vec2) -> bool { path_distance(layout,from,to) == Option::Some(1) }
pub fn within_range(layout: BoardGeometry, from: Vec2, to: Vec2, range: u16) -> bool {
    match path_distance(layout,from,to) { Option::Some(n) => n.into() <= range, Option::None => false }
}
pub fn get_p1_deploy_spot(layout: BoardGeometry) -> Vec2 { layout.p1 }
pub fn get_p2_deploy_spot(layout: BoardGeometry) -> Vec2 { layout.p2 }
pub fn energy_space(layout: BoardGeometry, pos: Vec2) -> bool {
    let index = spot_index(layout,pos);
    index < layout.spots.len() && *layout.spots.at(index).energy
}
pub fn get_walkable_neighbors(layout: BoardGeometry, pos: Vec2) -> Array<Vec2> {
    let mut result = array![];
    for spot in layout.spots { if is_valid_step(layout,pos,*spot.at) { result.append(*spot.at); } }
    result
}
