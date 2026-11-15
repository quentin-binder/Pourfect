/// Stars for finishing a level: 3 = optimal, 2 = within +3 moves, otherwise 1.
public enum StarRating {
    public static func stars(moves: Int, minMoves: Int) -> Int {
        if moves <= minMoves { return 3 }
        if moves <= minMoves + 3 { return 2 }
        return 1
    }
}
